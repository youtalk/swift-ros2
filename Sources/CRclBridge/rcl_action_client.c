#include "rcl_bridge.h"

#include <rcl/rcl.h>
#include <rcl/guard_condition.h>
#include <rcl/wait.h>
// rcl_reset_error for the wait-thread loop (rcl/rcutils error state is
// thread-local, so failures on the wait thread only need a reset there).
#include <rcl/error_handling.h>
#include <rcl_action/action_client.h>
#include <rcl_action/types.h>  // action_msgs typedefs (GoalStatusArray et al.)
#include <rcl_action/wait.h>
#include <rmw/rmw.h>  // rmw_serialize / rmw_deserialize
#include <rmw/serialized_message.h>
#include <rmw/types.h>  // rmw_request_id_t
#include <rcutils/allocator.h>
// crcl_node_s body (stored rcl_context_t*) + crcl__set_error / crcl__capture_rcl_error.
#include "crcl_internal.h"

#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct crcl_action_client_s {
    rcl_action_client_t client;
    rcl_node_t *node;  // borrowed; node must outlive the action client
    const crcl_action_entry_t *entry;
    // action_msgs/srv/CancelGoal — the cancel half rides the M7 srv registry.
    const crcl_srv_entry_t *cancel_entry;
    rcl_guard_condition_t stop_gc;
    rcl_wait_set_t wait_set;
    pthread_t thread;
    atomic_bool stop;
    // Serializes the wait thread's takes against every caller-thread
    // rcl_action_* call (sends + rcl_action_server_is_available) — rcl_action
    // documents none of those pairings as thread-safe. Held only across the
    // rcl call, never across rcl_wait or the callback (M7 doctrine).
    pthread_mutex_t io_mutex;
    crcl_action_client_callback_t cb;
    void *cb_ctx;
};

// One drained take for a correlated response role (goal / cancel / result):
// allocate everything BEFORE the take (M4 pattern), take under io_mutex,
// rmw_serialize, and hand bytes + rcl's sequence number to the callback.
// Returns false when the drain loop for this role should stop.
static bool crcl__action_client_take_response(
    crcl_action_client_t *c, int role,
    void *(*create_fn)(void), void (*destroy_fn)(void *),
    const rosidl_message_type_support_t *(*ts_fn)(void),
    rcl_ret_t (*take_fn)(const rcl_action_client_t *, rmw_request_id_t *, void *)) {
    rcl_serialized_message_t msg = rmw_get_zero_initialized_serialized_message();
    rcutils_allocator_t alloc = rcutils_get_default_allocator();
    if (rmw_serialized_message_init(&msg, 0, &alloc) != RMW_RET_OK) {
        rcl_reset_error();
        return false;
    }
    void *response = create_fn();
    if (!response) {
        (void)rmw_serialized_message_fini(&msg);
        return false;  // allocation failure — back to waiting
    }
    rmw_request_id_t header;
    memset(&header, 0, sizeof(header));
    pthread_mutex_lock(&c->io_mutex);
    rcl_ret_t take = take_fn(&c->client, &header, response);
    pthread_mutex_unlock(&c->io_mutex);
    if (take != RCL_RET_OK) {
        destroy_fn(response);
        (void)rmw_serialized_message_fini(&msg);
        // RCL_RET_ACTION_CLIENT_TAKE_FAILED == nothing pending (not an
        // error); anything else is a real failure — either way stop draining
        // this role and go back to waiting.
        rcl_reset_error();
        return false;
    }
    if (rmw_serialize(response, ts_fn(), &msg) == RMW_RET_OK) {
        c->cb(c->cb_ctx, role, header.sequence_number, msg.buffer, msg.buffer_length);
    } else {
        rcl_reset_error();
    }
    (void)rmw_serialized_message_fini(&msg);
    destroy_fn(response);
    return true;
}

// One drained feedback take: typed FeedbackMessage -> rmw_serialize -> bytes.
static bool crcl__action_client_take_feedback(crcl_action_client_t *c) {
    rcl_serialized_message_t msg = rmw_get_zero_initialized_serialized_message();
    rcutils_allocator_t alloc = rcutils_get_default_allocator();
    if (rmw_serialized_message_init(&msg, 0, &alloc) != RMW_RET_OK) {
        rcl_reset_error();
        return false;
    }
    void *feedback = c->entry->feedback_message_create();
    if (!feedback) {
        (void)rmw_serialized_message_fini(&msg);
        return false;
    }
    pthread_mutex_lock(&c->io_mutex);
    rcl_ret_t take = rcl_action_take_feedback(&c->client, feedback);
    pthread_mutex_unlock(&c->io_mutex);
    if (take != RCL_RET_OK) {
        c->entry->feedback_message_destroy(feedback);
        (void)rmw_serialized_message_fini(&msg);
        rcl_reset_error();
        return false;
    }
    if (rmw_serialize(feedback, c->entry->feedback_message_typesupport(), &msg) == RMW_RET_OK) {
        c->cb(c->cb_ctx, CRCL_ACTION_CLIENT_FEEDBACK, 0, msg.buffer, msg.buffer_length);
    } else {
        rcl_reset_error();
    }
    (void)rmw_serialized_message_fini(&msg);
    c->entry->feedback_message_destroy(feedback);
    return true;
}

// One drained status take. The GoalStatusArray is flattened into fixed
// CRCL_GOAL_STATUS_RECORD_SIZE records (uuid[16] + sec i32 LE + nanosec
// u32 LE + status i8) instead of rmw_serialized — the type is not in the
// message registry and a fixed record stride keeps the FFI parse trivial.
static bool crcl__action_client_take_status(crcl_action_client_t *c) {
    action_msgs__msg__GoalStatusArray *arr = action_msgs__msg__GoalStatusArray__create();
    if (!arr) {
        return false;
    }
    pthread_mutex_lock(&c->io_mutex);
    rcl_ret_t take = rcl_action_take_status(&c->client, arr);
    pthread_mutex_unlock(&c->io_mutex);
    if (take != RCL_RET_OK) {
        action_msgs__msg__GoalStatusArray__destroy(arr);
        rcl_reset_error();
        return false;
    }
    size_t count = arr->status_list.size;
    size_t buflen = count * CRCL_GOAL_STATUS_RECORD_SIZE;
    uint8_t *flat = malloc(buflen > 0 ? buflen : 1);
    if (!flat) {
        action_msgs__msg__GoalStatusArray__destroy(arr);
        return false;
    }
    for (size_t i = 0; i < count; i++) {
        const action_msgs__msg__GoalStatus *st = &arr->status_list.data[i];
        uint8_t *rec = flat + i * CRCL_GOAL_STATUS_RECORD_SIZE;
        memcpy(rec, st->goal_info.goal_id.uuid, 16);
        uint32_t sec = (uint32_t)st->goal_info.stamp.sec;
        uint32_t nsec = st->goal_info.stamp.nanosec;
        for (int b = 0; b < 4; b++) {
            rec[16 + b] = (uint8_t)(sec >> (8 * b));
            rec[20 + b] = (uint8_t)(nsec >> (8 * b));
        }
        rec[24] = (uint8_t)st->status;
    }
    c->cb(c->cb_ctx, CRCL_ACTION_CLIENT_STATUS, 0, flat, buflen);
    free(flat);
    action_msgs__msg__GoalStatusArray__destroy(arr);
    return true;
}

// Per-action-client wait thread: rcl_wait on {3 service clients + 2
// subscriptions via rcl_action_wait_set_add_action_client, stop guard
// condition} with a 100 ms timeout, then drain every ready role
// (serialize-shim, spec §20.6). Teardown / locking contract identical to the
// M7 client thread.
static void *crcl__action_client_thread_main(void *arg) {
    crcl_action_client_t *c = arg;
    const int64_t timeout_ns = 100LL * 1000 * 1000;  // 100 ms
    while (!atomic_load(&c->stop)) {
        if (rcl_wait_set_clear(&c->wait_set) != RCL_RET_OK) {
            rcl_reset_error();
            break;  // wait set unusable — stop delivering rather than spin
        }
        if (rcl_action_wait_set_add_action_client(&c->wait_set, &c->client, NULL, NULL)
            != RCL_RET_OK) {
            rcl_reset_error();
            break;
        }
        if (rcl_wait_set_add_guard_condition(&c->wait_set, &c->stop_gc, NULL) != RCL_RET_OK) {
            rcl_reset_error();
            break;
        }
        rcl_ret_t ret = rcl_wait(&c->wait_set, timeout_ns);
        if (ret == RCL_RET_TIMEOUT) continue;
        if (ret != RCL_RET_OK) {
            rcl_reset_error();
            continue;
        }
        if (atomic_load(&c->stop)) break;
        bool feedback_ready = false;
        bool status_ready = false;
        bool goal_response_ready = false;
        bool cancel_response_ready = false;
        bool result_response_ready = false;
        if (rcl_action_client_wait_set_get_entities_ready(
                &c->wait_set, &c->client, &feedback_ready, &status_ready, &goal_response_ready,
                &cancel_response_ready, &result_response_ready)
            != RCL_RET_OK) {
            rcl_reset_error();
            continue;
        }
        // Drain each ready role until the middleware reports nothing pending,
        // re-checking the stop flag per take (M4 pattern).
        if (goal_response_ready) {
            while (!atomic_load(&c->stop)
                   && crcl__action_client_take_response(
                       c, CRCL_ACTION_CLIENT_GOAL_RESPONSE,
                       c->entry->send_goal_response_create, c->entry->send_goal_response_destroy,
                       c->entry->send_goal_response_typesupport, rcl_action_take_goal_response)) {
            }
        }
        if (cancel_response_ready) {
            while (!atomic_load(&c->stop)
                   && crcl__action_client_take_response(
                       c, CRCL_ACTION_CLIENT_CANCEL_RESPONSE,
                       c->cancel_entry->response_create, c->cancel_entry->response_destroy,
                       c->cancel_entry->response_typesupport, rcl_action_take_cancel_response)) {
            }
        }
        if (result_response_ready) {
            while (!atomic_load(&c->stop)
                   && crcl__action_client_take_response(
                       c, CRCL_ACTION_CLIENT_RESULT_RESPONSE,
                       c->entry->get_result_response_create, c->entry->get_result_response_destroy,
                       c->entry->get_result_response_typesupport,
                       rcl_action_take_result_response)) {
            }
        }
        if (feedback_ready) {
            while (!atomic_load(&c->stop) && crcl__action_client_take_feedback(c)) {
            }
        }
        if (status_ready) {
            while (!atomic_load(&c->stop) && crcl__action_client_take_status(c)) {
            }
        }
    }
    return NULL;
}

crcl_action_client_t *crcl_action_client_create(
    crcl_node_t *n, const char *action_type_name, const char *action_name,
    const crcl_qos_t *q, crcl_action_client_callback_t cb, void *ctx) {
    if (!n || !q || !cb) {
        crcl__set_error("crcl_action_client_create: NULL node/qos/callback");
        return NULL;
    }
    const crcl_action_entry_t *entry = crcl_action_registry_lookup(action_type_name);
    if (!entry) {
        // Not an rcl error — no rcl error state to capture; set the message directly.
        char msg[256];
        snprintf(
            msg, sizeof(msg), "unsupported action type: %s",
            action_type_name ? action_type_name : "(null)");
        crcl__set_error(msg);
        return NULL;
    }
    const crcl_srv_entry_t *cancel_entry = crcl_srv_registry_lookup("action_msgs/srv/CancelGoal");
    if (!cancel_entry) {
        crcl__set_error("crcl_action_client_create: action_msgs/srv/CancelGoal missing from srv registry");
        return NULL;
    }
    crcl_action_client_t *c = calloc(1, sizeof(*c));
    if (!c) {
        crcl__set_error("crcl_action_client_create: out of memory");
        return NULL;
    }
    c->node = &n->node;
    c->entry = entry;
    c->cancel_entry = cancel_entry;
    c->cb = cb;
    c->cb_ctx = ctx;
    atomic_init(&c->stop, false);

    c->client = rcl_action_get_zero_initialized_client();
    rcl_action_client_options_t copts = rcl_action_client_get_default_options();
    // Same QoS mapping as the server side: the four crcl_qos_t fields
    // override the three service profiles and the feedback topic; the status
    // topic keeps rcl's status default (transient_local, keep_last 1).
    rmw_qos_profile_t *profiles[] = {
        &copts.goal_service_qos, &copts.cancel_service_qos, &copts.result_service_qos,
        &copts.feedback_topic_qos,
    };
    for (size_t i = 0; i < sizeof(profiles) / sizeof(profiles[0]); i++) {
        profiles[i]->reliability = q->reliability ? RMW_QOS_POLICY_RELIABILITY_RELIABLE
                                                  : RMW_QOS_POLICY_RELIABILITY_BEST_EFFORT;
        profiles[i]->durability = q->durability ? RMW_QOS_POLICY_DURABILITY_TRANSIENT_LOCAL
                                                : RMW_QOS_POLICY_DURABILITY_VOLATILE;
        profiles[i]->history =
            q->history ? RMW_QOS_POLICY_HISTORY_KEEP_ALL : RMW_QOS_POLICY_HISTORY_KEEP_LAST;
        profiles[i]->depth = q->depth;
    }
    if (rcl_action_client_init(
            &c->client, &n->node, entry->action_typesupport(), action_name, &copts)
        != RCL_RET_OK) {
        crcl__capture_rcl_error();
        free(c);
        return NULL;
    }

    c->stop_gc = rcl_get_zero_initialized_guard_condition();
    if (rcl_guard_condition_init(&c->stop_gc, n->ctx, rcl_guard_condition_get_default_options())
        != RCL_RET_OK) {
        crcl__capture_rcl_error();
        (void)rcl_action_client_fini(&c->client, c->node);
        free(c);
        return NULL;
    }

    // Size the wait set from rcl_action's own entity counts (2 subscriptions
    // + 3 service clients on Jazzy) plus the stop guard condition.
    size_t num_subs = 0, num_gcs = 0, num_timers = 0, num_clients = 0, num_services = 0;
    if (rcl_action_client_wait_set_get_num_entities(
            &c->client, &num_subs, &num_gcs, &num_timers, &num_clients, &num_services)
        != RCL_RET_OK) {
        crcl__capture_rcl_error();
        (void)rcl_guard_condition_fini(&c->stop_gc);
        (void)rcl_action_client_fini(&c->client, c->node);
        free(c);
        return NULL;
    }
    c->wait_set = rcl_get_zero_initialized_wait_set();
    if (rcl_wait_set_init(
            &c->wait_set, num_subs, num_gcs + 1, num_timers, num_clients, num_services, 0, n->ctx,
            rcl_get_default_allocator())
        != RCL_RET_OK) {
        crcl__capture_rcl_error();
        (void)rcl_guard_condition_fini(&c->stop_gc);
        (void)rcl_action_client_fini(&c->client, c->node);
        free(c);
        return NULL;
    }

    if (pthread_mutex_init(&c->io_mutex, NULL) != 0) {
        crcl__set_error("crcl_action_client_create: pthread_mutex_init failed");
        (void)rcl_wait_set_fini(&c->wait_set);
        (void)rcl_guard_condition_fini(&c->stop_gc);
        (void)rcl_action_client_fini(&c->client, c->node);
        free(c);
        return NULL;
    }

    if (pthread_create(&c->thread, NULL, crcl__action_client_thread_main, c) != 0) {
        crcl__set_error("crcl_action_client_create: pthread_create failed");
        (void)pthread_mutex_destroy(&c->io_mutex);
        (void)rcl_wait_set_fini(&c->wait_set);
        (void)rcl_guard_condition_fini(&c->stop_gc);
        (void)rcl_action_client_fini(&c->client, c->node);
        free(c);
        return NULL;
    }
    return c;
}

// Shared deserialize-and-send body for the three request roles. `buf` is
// borrowed (rmw_deserialize only reads it); the typed struct is __destroy'd
// on every path.
static int crcl__action_client_send(
    crcl_action_client_t *c, const uint8_t *buf, size_t len, int64_t *out_sequence_number,
    const char *what,
    void *(*create_fn)(void), void (*destroy_fn)(void *),
    const rosidl_message_type_support_t *(*ts_fn)(void),
    rcl_ret_t (*send_fn)(const rcl_action_client_t *, const void *, int64_t *)) {
    if (!c || !out_sequence_number) {
        crcl__set_error("crcl_action_client send: NULL client/out_sequence_number");
        return -1;
    }
    // Valid CDR is at least the 4-byte encapsulation header — mirror the
    // Swift-side check instead of feeding a short buffer to rmw_deserialize.
    if (!buf || len < 4) {
        char msg[128];
        snprintf(msg, sizeof(msg), "%s: buffer missing 4-byte CDR encapsulation header", what);
        crcl__set_error(msg);
        return -1;
    }
    void *request = create_fn();
    if (!request) {
        char msg[128];
        snprintf(msg, sizeof(msg), "%s: request create failed", what);
        crcl__set_error(msg);
        return -1;
    }
    rcl_serialized_message_t ser = rmw_get_zero_initialized_serialized_message();
    ser.buffer = (uint8_t *)buf;
    ser.buffer_length = len;
    ser.buffer_capacity = len;
    ser.allocator = rcutils_get_default_allocator();
    if (rmw_deserialize(&ser, ts_fn(), request) != RMW_RET_OK) {
        crcl__capture_rcl_error();
        destroy_fn(request);
        return -1;
    }
    pthread_mutex_lock(&c->io_mutex);
    rcl_ret_t ret = send_fn(&c->client, request, out_sequence_number);
    pthread_mutex_unlock(&c->io_mutex);
    destroy_fn(request);
    if (ret != RCL_RET_OK) {
        crcl__capture_rcl_error();
        return (int)ret;
    }
    return 0;
}

int crcl_action_client_send_goal_request(
    crcl_action_client_t *c, const uint8_t *buf, size_t len, int64_t *out_sequence_number) {
    if (!c) {
        crcl__set_error("crcl_action_client_send_goal_request: NULL client");
        return -1;
    }
    return crcl__action_client_send(
        c, buf, len, out_sequence_number, "crcl_action_client_send_goal_request",
        c->entry->send_goal_request_create, c->entry->send_goal_request_destroy,
        c->entry->send_goal_request_typesupport, rcl_action_send_goal_request);
}

int crcl_action_client_send_cancel_request(
    crcl_action_client_t *c, const uint8_t *buf, size_t len, int64_t *out_sequence_number) {
    if (!c) {
        crcl__set_error("crcl_action_client_send_cancel_request: NULL client");
        return -1;
    }
    return crcl__action_client_send(
        c, buf, len, out_sequence_number, "crcl_action_client_send_cancel_request",
        c->cancel_entry->request_create, c->cancel_entry->request_destroy,
        c->cancel_entry->request_typesupport, rcl_action_send_cancel_request);
}

int crcl_action_client_send_result_request(
    crcl_action_client_t *c, const uint8_t *buf, size_t len, int64_t *out_sequence_number) {
    if (!c) {
        crcl__set_error("crcl_action_client_send_result_request: NULL client");
        return -1;
    }
    return crcl__action_client_send(
        c, buf, len, out_sequence_number, "crcl_action_client_send_result_request",
        c->entry->get_result_request_create, c->entry->get_result_request_destroy,
        c->entry->get_result_request_typesupport, rcl_action_send_result_request);
}

int crcl_action_client_server_available(crcl_action_client_t *c) {
    if (!c) {
        crcl__set_error("crcl_action_client_server_available: NULL client");
        return -1;
    }
    bool available = false;
    pthread_mutex_lock(&c->io_mutex);
    rcl_ret_t ret = rcl_action_server_is_available(c->node, &c->client, &available);
    pthread_mutex_unlock(&c->io_mutex);
    if (ret != RCL_RET_OK) {
        crcl__capture_rcl_error();
        return -1;
    }
    return available ? 1 : 0;
}

int crcl_action_client_destroy(crcl_action_client_t *c) {
    if (!c) return 0;
    // Refuse a self-destroy from the take callback (same M7 contract).
    if (pthread_equal(pthread_self(), c->thread)) {
        crcl__set_error(
            "crcl_action_client_destroy called from the take callback; destroy from another thread");
        return -1;
    }
    // Join BEFORE any fini (M4/M7 teardown): guarantees any in-flight
    // callback has returned before the Swift side releases its context.
    atomic_store(&c->stop, true);
    (void)rcl_trigger_guard_condition(&c->stop_gc);
    if (pthread_join(c->thread, NULL) != 0) {
        crcl__set_error("crcl_action_client_destroy: pthread_join failed");
        return -1;
    }
    (void)pthread_mutex_destroy(&c->io_mutex);
    int rc = 0;
    if (rcl_action_client_fini(&c->client, c->node) != RCL_RET_OK) {
        crcl__capture_rcl_error();
        rc = 1;
    }
    if (rcl_guard_condition_fini(&c->stop_gc) != RCL_RET_OK) {
        crcl__capture_rcl_error();
        rc = 1;
    }
    if (rcl_wait_set_fini(&c->wait_set) != RCL_RET_OK) {
        crcl__capture_rcl_error();
        rc = 1;
    }
    free(c);
    return rc;
}
