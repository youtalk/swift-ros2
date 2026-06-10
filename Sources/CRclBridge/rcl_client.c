#include "rcl_bridge.h"

#include <rcl/rcl.h>
#include <rcl/client.h>
#include <rcl/graph.h>  // rcl_service_server_is_available
#include <rcl/guard_condition.h>
#include <rcl/wait.h>
// rcl_reset_error for the wait-thread loop (rcl/rcutils error state is
// thread-local, so failures on the wait thread only need a reset there).
#include <rcl/error_handling.h>
#include <rmw/rmw.h>  // rmw_serialize / rmw_deserialize
#include <rmw/serialized_message.h>
#include <rmw/types.h>  // rmw_service_info_t
#include <rcutils/allocator.h>
// crcl_node_s body (stored rcl_context_t*) + crcl__set_error / crcl__capture_rcl_error.
#include "crcl_internal.h"

#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct crcl_client_s {
    rcl_client_t client;
    rcl_node_t *node;  // borrowed; node must outlive the client
    const crcl_srv_entry_t *entry;
    rcl_guard_condition_t stop_gc;
    rcl_wait_set_t wait_set;
    pthread_t thread;
    atomic_bool stop;
    crcl_response_callback_t cb;
    void *cb_ctx;
};

// Per-client wait thread: rcl_wait on {client, stop guard condition} with a
// 100 ms timeout, then drain every pending response via
// rcl_take_response_with_info into a registry-__create'd typed struct,
// rmw_serialize it through the response *message* typesupport, and hand the
// bytes plus rcl's sequence number to the callback (serialize-shim, spec
// §20.2). The wait set and client are touched by this thread only while it
// runs; crcl_client_destroy joins it before any fini, so there is no
// concurrent access to rcl entities (rcl_send_request is the documented
// exception — thread-safe with respect to take/wait).
static void *crcl__client_thread_main(void *arg) {
    crcl_client_t *c = arg;
    const int64_t timeout_ns = 100LL * 1000 * 1000;  // 100 ms
    while (!atomic_load(&c->stop)) {
        if (rcl_wait_set_clear(&c->wait_set) != RCL_RET_OK) {
            rcl_reset_error();
            break;  // wait set unusable — stop delivering rather than spin
        }
        if (rcl_wait_set_add_client(&c->wait_set, &c->client, NULL) != RCL_RET_OK) {
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
        // Drain: take until the middleware reports nothing pending, or a stop
        // request arrives — re-checking the flag per take bounds destroy
        // latency under sustained load (M4 pattern). Every taken response
        // struct is __destroy'd on every path, success or failure.
        while (!atomic_load(&c->stop)) {
            void *response = c->entry->response_create();
            if (!response) {
                break;  // allocation failure — back to waiting
            }
            rmw_service_info_t info;
            memset(&info, 0, sizeof(info));
            rcl_ret_t take = rcl_take_response_with_info(&c->client, &info, response);
            if (take != RCL_RET_OK) {
                c->entry->response_destroy(response);
                // RCL_RET_CLIENT_TAKE_FAILED == nothing pending (not an
                // error); anything else is a real failure — either way stop
                // draining and go back to waiting.
                rcl_reset_error();
                break;
            }
            rcl_serialized_message_t msg = rmw_get_zero_initialized_serialized_message();
            rcutils_allocator_t alloc = rcutils_get_default_allocator();
            if (rmw_serialized_message_init(&msg, 0, &alloc) == RMW_RET_OK) {
                if (rmw_serialize(response, c->entry->response_typesupport(), &msg) == RMW_RET_OK) {
                    c->cb(c->cb_ctx, info.request_id.sequence_number, msg.buffer, msg.buffer_length);
                } else {
                    rcl_reset_error();
                }
                (void)rmw_serialized_message_fini(&msg);
            } else {
                rcl_reset_error();
            }
            c->entry->response_destroy(response);
        }
    }
    return NULL;
}

crcl_client_t *crcl_client_create(
    crcl_node_t *n, const char *srv_type_name, const char *service_name, const crcl_qos_t *q,
    crcl_response_callback_t cb, void *ctx) {
    if (!n || !q || !cb) {
        crcl__set_error("crcl_client_create: NULL node/qos/callback");
        return NULL;
    }
    const crcl_srv_entry_t *entry = crcl_srv_registry_lookup(srv_type_name);
    if (!entry) {
        // Not an rcl error — no rcl error state to capture; set the message directly.
        char msg[256];
        snprintf(
            msg, sizeof(msg), "unsupported service type: %s",
            srv_type_name ? srv_type_name : "(null)");
        crcl__set_error(msg);
        return NULL;
    }
    crcl_client_t *c = calloc(1, sizeof(*c));
    if (!c) {
        crcl__set_error("crcl_client_create: out of memory");
        return NULL;
    }
    c->node = &n->node;
    c->entry = entry;
    c->cb = cb;
    c->cb_ctx = ctx;
    atomic_init(&c->stop, false);

    c->client = rcl_get_zero_initialized_client();
    rcl_client_options_t copts = rcl_client_get_default_options();
    // Base profile stays rmw_qos_profile_services_default (the rcl default);
    // only the four crcl_qos_t fields override it — same four assignments as
    // the publisher / subscription paths.
    copts.qos.reliability =
        q->reliability ? RMW_QOS_POLICY_RELIABILITY_RELIABLE : RMW_QOS_POLICY_RELIABILITY_BEST_EFFORT;
    copts.qos.durability =
        q->durability ? RMW_QOS_POLICY_DURABILITY_TRANSIENT_LOCAL : RMW_QOS_POLICY_DURABILITY_VOLATILE;
    copts.qos.history =
        q->history ? RMW_QOS_POLICY_HISTORY_KEEP_ALL : RMW_QOS_POLICY_HISTORY_KEEP_LAST;
    copts.qos.depth = q->depth;
    if (rcl_client_init(&c->client, &n->node, entry->service_typesupport(), service_name, &copts)
        != RCL_RET_OK) {
        crcl__capture_rcl_error();
        free(c);
        return NULL;
    }

    c->stop_gc = rcl_get_zero_initialized_guard_condition();
    if (rcl_guard_condition_init(&c->stop_gc, n->ctx, rcl_guard_condition_get_default_options())
        != RCL_RET_OK) {
        crcl__capture_rcl_error();
        (void)rcl_client_fini(&c->client, c->node);
        free(c);
        return NULL;
    }

    c->wait_set = rcl_get_zero_initialized_wait_set();
    if (rcl_wait_set_init(&c->wait_set, 0, 1, 0, 1, 0, 0, n->ctx, rcl_get_default_allocator())
        != RCL_RET_OK) {
        crcl__capture_rcl_error();
        (void)rcl_guard_condition_fini(&c->stop_gc);
        (void)rcl_client_fini(&c->client, c->node);
        free(c);
        return NULL;
    }

    if (pthread_create(&c->thread, NULL, crcl__client_thread_main, c) != 0) {
        crcl__set_error("crcl_client_create: pthread_create failed");
        (void)rcl_wait_set_fini(&c->wait_set);
        (void)rcl_guard_condition_fini(&c->stop_gc);
        (void)rcl_client_fini(&c->client, c->node);
        free(c);
        return NULL;
    }
    return c;
}

int crcl_client_send_request(
    crcl_client_t *c, const uint8_t *buf, size_t len, int64_t *out_sequence_number) {
    if (!c || (!buf && len > 0) || !out_sequence_number) {
        crcl__set_error("crcl_client_send_request: NULL client/buffer/out_sequence_number");
        return -1;
    }
    void *request = c->entry->request_create();
    if (!request) {
        crcl__set_error("crcl_client_send_request: request_create failed");
        return -1;
    }
    rcl_serialized_message_t ser = rmw_get_zero_initialized_serialized_message();
    // Borrow the caller's buffer; rmw_deserialize only reads it. No fini —
    // the buffer is not ours to free.
    ser.buffer = (uint8_t *)buf;
    ser.buffer_length = len;
    ser.buffer_capacity = len;
    ser.allocator = rcutils_get_default_allocator();
    if (rmw_deserialize(&ser, c->entry->request_typesupport(), request) != RMW_RET_OK) {
        crcl__capture_rcl_error();
        c->entry->request_destroy(request);
        return -1;
    }
    rcl_ret_t ret = rcl_send_request(&c->client, request, out_sequence_number);
    c->entry->request_destroy(request);
    if (ret != RCL_RET_OK) {
        crcl__capture_rcl_error();
        return (int)ret;
    }
    return 0;
}

int crcl_client_server_available(crcl_client_t *c) {
    if (!c) {
        crcl__set_error("crcl_client_server_available: NULL client");
        return -1;
    }
    bool available = false;
    if (rcl_service_server_is_available(c->node, &c->client, &available) != RCL_RET_OK) {
        crcl__capture_rcl_error();
        return -1;
    }
    return available ? 1 : 0;
}

int crcl_client_destroy(crcl_client_t *c) {
    if (!c) return 0;
    // Refuse a self-destroy from the take callback: pthread_join on the
    // calling thread cannot block on itself (Darwin/glibc return EDEADLK
    // immediately), so proceeding to fini/free would leave the wait thread
    // dereferencing freed memory the moment the callback returns. Leak the
    // client instead and surface an error — destroy must be called from
    // another thread.
    if (pthread_equal(pthread_self(), c->thread)) {
        crcl__set_error(
            "crcl_client_destroy called from the take callback; destroy from another thread");
        return -1;
    }
    // Join BEFORE any fini: rcl take / fini are not thread-safe, and the wait
    // thread reads `client` / `wait_set` until it exits. The guard condition
    // is the sanctioned cross-thread wakeup for rcl_wait, so the thread
    // observes the stop flag within one wakeup (or the 100 ms timeout).
    // Because the join happens first, this function blocks until any
    // in-flight callback has returned — the guarantee the Swift side relies
    // on before releasing the retained handler context.
    atomic_store(&c->stop, true);
    (void)rcl_trigger_guard_condition(&c->stop_gc);
    if (pthread_join(c->thread, NULL) != 0) {
        // The wait thread may still be running; fini/free now would race it.
        // Leak instead of crash.
        crcl__set_error("crcl_client_destroy: pthread_join failed");
        return -1;
    }
    int rc = 0;
    if (rcl_client_fini(&c->client, c->node) != RCL_RET_OK) {
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
