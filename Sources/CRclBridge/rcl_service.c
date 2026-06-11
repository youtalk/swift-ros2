#include "rcl_bridge.h"

#include <rcl/rcl.h>
#include <rcl/service.h>
#include <rcl/guard_condition.h>
#include <rcl/wait.h>
// rcl_reset_error for the wait-thread loop (rcl/rcutils error state is
// thread-local, so failures on the wait thread only need a reset there).
#include <rcl/error_handling.h>
#include <rmw/rmw.h>  // rmw_serialize / rmw_deserialize
#include <rmw/serialized_message.h>
#include <rmw/types.h>  // rmw_request_id_t / rmw_service_info_t
#include <rcutils/allocator.h>
// crcl_node_s body (stored rcl_context_t*) + crcl__set_error / crcl__capture_rcl_error.
#include "crcl_internal.h"

#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct crcl_service_s {
    rcl_service_t service;
    rcl_node_t *node;  // borrowed; node must outlive the service
    const crcl_srv_entry_t *entry;
    rcl_guard_condition_t stop_gc;
    rcl_wait_set_t wait_set;
    pthread_t thread;
    atomic_bool stop;
    // Serializes rcl_take_request_with_info (wait thread) against
    // rcl_send_response (caller threads) — see crcl__service_thread_main.
    pthread_mutex_t io_mutex;
    crcl_request_callback_t cb;
    void *cb_ctx;
};

// Pack an rmw_request_id_t into the opaque FFI blob: 16-byte writer GUID
// followed by the int64 sequence number in little-endian byte order. Swift
// never interprets the blob; the explicit LE packing just makes the layout
// deterministic regardless of host endianness.
static void crcl__pack_request_id(const rmw_request_id_t *id, uint8_t out[CRCL_REQUEST_ID_SIZE]) {
    memcpy(out, id->writer_guid, 16);
    uint64_t seq = (uint64_t)id->sequence_number;
    for (int i = 0; i < 8; i++) {
        out[16 + i] = (uint8_t)(seq >> (8 * i));
    }
}

static void crcl__unpack_request_id(const uint8_t in[CRCL_REQUEST_ID_SIZE], rmw_request_id_t *id) {
    memset(id, 0, sizeof(*id));
    memcpy(id->writer_guid, in, 16);
    uint64_t seq = 0;
    for (int i = 0; i < 8; i++) {
        seq |= ((uint64_t)in[16 + i]) << (8 * i);
    }
    id->sequence_number = (int64_t)seq;
}

// Per-service wait thread: rcl_wait on {service, stop guard condition} with a
// 100 ms timeout, then drain every pending request via
// rcl_take_request_with_info into a registry-__create'd typed struct,
// rmw_serialize it through the request *message* typesupport, and hand the
// bytes plus the packed request id to the callback (serialize-shim, spec
// §20.2). The wait set and service are touched by this thread only while it
// runs; crcl_service_destroy joins it before any fini, so there is no
// concurrent access to rcl entities — with one exception: rcl_send_response
// runs on caller threads while this thread takes. rcl does NOT document that
// pairing as safe (rcl_take_request_with_info is "Thread-Safe: No", and
// rcl_send_response's "Yes [1]" note forbids concurrency with non-thread-safe
// service functions); current rmw implementations only tolerate it by
// accident. The bridge makes the safety contractual instead: io_mutex
// serializes the take below against crcl_service_send_response. It is held
// only across the take — never across rcl_wait or the callback — so the cost
// is bounded (worst case the take stalls behind one in-flight send, e.g.
// rmw_cyclonedds's ~100 ms send-side match poll).
static void *crcl__service_thread_main(void *arg) {
    crcl_service_t *s = arg;
    const int64_t timeout_ns = 100LL * 1000 * 1000;  // 100 ms
    while (!atomic_load(&s->stop)) {
        if (rcl_wait_set_clear(&s->wait_set) != RCL_RET_OK) {
            rcl_reset_error();
            break;  // wait set unusable — stop delivering rather than spin
        }
        if (rcl_wait_set_add_service(&s->wait_set, &s->service, NULL) != RCL_RET_OK) {
            rcl_reset_error();
            break;
        }
        if (rcl_wait_set_add_guard_condition(&s->wait_set, &s->stop_gc, NULL) != RCL_RET_OK) {
            rcl_reset_error();
            break;
        }
        rcl_ret_t ret = rcl_wait(&s->wait_set, timeout_ns);
        if (ret == RCL_RET_TIMEOUT) continue;
        if (ret != RCL_RET_OK) {
            rcl_reset_error();
            continue;
        }
        if (atomic_load(&s->stop)) break;
        // Drain: take until the middleware reports nothing pending, or a stop
        // request arrives — re-checking the flag per take bounds destroy
        // latency under sustained load (M4 pattern). Every taken request
        // struct is __destroy'd on every path, success or failure.
        while (!atomic_load(&s->stop)) {
            // Allocate everything BEFORE the take (M4 pattern,
            // rcl_subscription.c): an allocation failure here leaves the
            // request queued in the middleware instead of silently dropping
            // an already-consumed one.
            rcl_serialized_message_t msg = rmw_get_zero_initialized_serialized_message();
            rcutils_allocator_t alloc = rcutils_get_default_allocator();
            if (rmw_serialized_message_init(&msg, 0, &alloc) != RMW_RET_OK) {
                rcl_reset_error();
                break;
            }
            void *request = s->entry->request_create();
            if (!request) {
                (void)rmw_serialized_message_fini(&msg);
                break;  // allocation failure — back to waiting
            }
            rmw_service_info_t info;
            memset(&info, 0, sizeof(info));
            pthread_mutex_lock(&s->io_mutex);
            rcl_ret_t take = rcl_take_request_with_info(&s->service, &info, request);
            pthread_mutex_unlock(&s->io_mutex);
            if (take != RCL_RET_OK) {
                s->entry->request_destroy(request);
                (void)rmw_serialized_message_fini(&msg);
                // RCL_RET_SERVICE_TAKE_FAILED == nothing pending (not an
                // error); anything else is a real failure — either way stop
                // draining and go back to waiting.
                rcl_reset_error();
                break;
            }
            if (rmw_serialize(request, s->entry->request_typesupport(), &msg) == RMW_RET_OK) {
                uint8_t blob[CRCL_REQUEST_ID_SIZE];
                crcl__pack_request_id(&info.request_id, blob);
                s->cb(s->cb_ctx, blob, msg.buffer, msg.buffer_length);
            } else {
                rcl_reset_error();
            }
            (void)rmw_serialized_message_fini(&msg);
            s->entry->request_destroy(request);
        }
    }
    return NULL;
}

crcl_service_t *crcl_service_create(
    crcl_node_t *n, const char *srv_type_name, const char *service_name, const crcl_qos_t *q,
    crcl_request_callback_t cb, void *ctx) {
    if (!n || !q || !cb) {
        crcl__set_error("crcl_service_create: NULL node/qos/callback");
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
    crcl_service_t *s = calloc(1, sizeof(*s));
    if (!s) {
        crcl__set_error("crcl_service_create: out of memory");
        return NULL;
    }
    s->node = &n->node;
    s->entry = entry;
    s->cb = cb;
    s->cb_ctx = ctx;
    atomic_init(&s->stop, false);

    s->service = rcl_get_zero_initialized_service();
    rcl_service_options_t sopts = rcl_service_get_default_options();
    // Base profile stays rmw_qos_profile_services_default (the rcl default);
    // only the four crcl_qos_t fields override it — same four assignments as
    // the publisher / subscription paths.
    sopts.qos.reliability =
        q->reliability ? RMW_QOS_POLICY_RELIABILITY_RELIABLE : RMW_QOS_POLICY_RELIABILITY_BEST_EFFORT;
    sopts.qos.durability =
        q->durability ? RMW_QOS_POLICY_DURABILITY_TRANSIENT_LOCAL : RMW_QOS_POLICY_DURABILITY_VOLATILE;
    sopts.qos.history =
        q->history ? RMW_QOS_POLICY_HISTORY_KEEP_ALL : RMW_QOS_POLICY_HISTORY_KEEP_LAST;
    sopts.qos.depth = q->depth;
    if (rcl_service_init(&s->service, &n->node, entry->service_typesupport(), service_name, &sopts)
        != RCL_RET_OK) {
        crcl__capture_rcl_error();
        free(s);
        return NULL;
    }

    s->stop_gc = rcl_get_zero_initialized_guard_condition();
    if (rcl_guard_condition_init(&s->stop_gc, n->ctx, rcl_guard_condition_get_default_options())
        != RCL_RET_OK) {
        crcl__capture_rcl_error();
        (void)rcl_service_fini(&s->service, s->node);
        free(s);
        return NULL;
    }

    s->wait_set = rcl_get_zero_initialized_wait_set();
    if (rcl_wait_set_init(&s->wait_set, 0, 1, 0, 0, 1, 0, n->ctx, rcl_get_default_allocator())
        != RCL_RET_OK) {
        crcl__capture_rcl_error();
        (void)rcl_guard_condition_fini(&s->stop_gc);
        (void)rcl_service_fini(&s->service, s->node);
        free(s);
        return NULL;
    }

    if (pthread_mutex_init(&s->io_mutex, NULL) != 0) {
        crcl__set_error("crcl_service_create: pthread_mutex_init failed");
        (void)rcl_wait_set_fini(&s->wait_set);
        (void)rcl_guard_condition_fini(&s->stop_gc);
        (void)rcl_service_fini(&s->service, s->node);
        free(s);
        return NULL;
    }

    if (pthread_create(&s->thread, NULL, crcl__service_thread_main, s) != 0) {
        crcl__set_error("crcl_service_create: pthread_create failed");
        (void)pthread_mutex_destroy(&s->io_mutex);
        (void)rcl_wait_set_fini(&s->wait_set);
        (void)rcl_guard_condition_fini(&s->stop_gc);
        (void)rcl_service_fini(&s->service, s->node);
        free(s);
        return NULL;
    }
    return s;
}

int crcl_service_send_response(
    crcl_service_t *s, const uint8_t *request_id, const uint8_t *buf, size_t len) {
    if (!s || !request_id) {
        crcl__set_error("crcl_service_send_response: NULL service/request_id");
        return -1;
    }
    // Valid CDR is at least the 4-byte encapsulation header — mirror the
    // Swift-side check instead of feeding a short buffer to rmw_deserialize.
    if (!buf || len < 4) {
        crcl__set_error("crcl_service_send_response: buffer missing 4-byte CDR encapsulation header");
        return -1;
    }
    void *response = s->entry->response_create();
    if (!response) {
        crcl__set_error("crcl_service_send_response: response_create failed");
        return -1;
    }
    rcl_serialized_message_t ser = rmw_get_zero_initialized_serialized_message();
    // Borrow the caller's buffer; rmw_deserialize only reads it. No fini —
    // the buffer is not ours to free.
    ser.buffer = (uint8_t *)buf;
    ser.buffer_length = len;
    ser.buffer_capacity = len;
    ser.allocator = rcutils_get_default_allocator();
    if (rmw_deserialize(&ser, s->entry->response_typesupport(), response) != RMW_RET_OK) {
        crcl__capture_rcl_error();
        s->entry->response_destroy(response);
        return -1;
    }
    rmw_request_id_t id;
    crcl__unpack_request_id(request_id, &id);
    // io_mutex: rcl does not document rcl_send_response as safe against a
    // concurrent rcl_take_request_with_info — serialize against the wait
    // thread's take (see crcl__service_thread_main).
    pthread_mutex_lock(&s->io_mutex);
    rcl_ret_t ret = rcl_send_response(&s->service, &id, response);
    pthread_mutex_unlock(&s->io_mutex);
    s->entry->response_destroy(response);
    if (ret != RCL_RET_OK) {
        crcl__capture_rcl_error();
        return (int)ret;
    }
    return 0;
}

int crcl_service_destroy(crcl_service_t *s) {
    if (!s) return 0;
    // Refuse a self-destroy from the take callback: pthread_join on the
    // calling thread cannot block on itself (Darwin/glibc return EDEADLK
    // immediately), so proceeding to fini/free would leave the wait thread
    // dereferencing freed memory the moment the callback returns. Leak the
    // service instead and surface an error — destroy must be called from
    // another thread.
    if (pthread_equal(pthread_self(), s->thread)) {
        crcl__set_error(
            "crcl_service_destroy called from the take callback; destroy from another thread");
        return -1;
    }
    // Join BEFORE any fini: rcl take / fini are not thread-safe, and the wait
    // thread reads `service` / `wait_set` until it exits. The guard condition
    // is the sanctioned cross-thread wakeup for rcl_wait, so the thread
    // observes the stop flag within one wakeup (or the 100 ms timeout).
    // Because the join happens first, this function blocks until any
    // in-flight callback has returned — the guarantee the Swift side relies
    // on before releasing the retained handler context.
    atomic_store(&s->stop, true);
    (void)rcl_trigger_guard_condition(&s->stop_gc);
    if (pthread_join(s->thread, NULL) != 0) {
        // The wait thread may still be running; fini/free now would race it.
        // Leak instead of crash.
        crcl__set_error("crcl_service_destroy: pthread_join failed");
        return -1;
    }
    // After the join no other crcl entry point may run (Swift drops the
    // handle before destroy), so the mutex is free; destroy before the finis.
    (void)pthread_mutex_destroy(&s->io_mutex);
    int rc = 0;
    if (rcl_service_fini(&s->service, s->node) != RCL_RET_OK) {
        crcl__capture_rcl_error();
        rc = 1;
    }
    if (rcl_guard_condition_fini(&s->stop_gc) != RCL_RET_OK) {
        crcl__capture_rcl_error();
        rc = 1;
    }
    if (rcl_wait_set_fini(&s->wait_set) != RCL_RET_OK) {
        crcl__capture_rcl_error();
        rc = 1;
    }
    free(s);
    return rc;
}
