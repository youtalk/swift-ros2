#include "rcl_bridge.h"

#include <rcl/rcl.h>
#include <rcl/subscription.h>
#include <rcl/guard_condition.h>
#include <rcl/wait.h>
// rcl_reset_error for the wait-thread loop (rcl/rcutils error state is
// thread-local, so failures on the wait thread only need a reset there).
#include <rcl/error_handling.h>
#include <rmw/qos_profiles.h>
#include <rmw/serialized_message.h>
#include <rmw/types.h>
#include <rcutils/allocator.h>
#include <rosidl_runtime_c/message_type_support_struct.h>
// crcl_node_s body (stored rcl_context_t*) + crcl__set_error / crcl__capture_rcl_error.
#include "crcl_internal.h"

#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct crcl_subscription_s {
    rcl_subscription_t sub;
    rcl_node_t *node;  // borrowed; node must outlive the subscription
    rcl_guard_condition_t stop_gc;
    rcl_wait_set_t wait_set;
    pthread_t thread;
    atomic_bool stop;
    crcl_take_callback_t cb;
    void *cb_ctx;
};

// Per-subscription wait thread: rcl_wait on {subscription, stop guard
// condition} with a 100 ms timeout, then drain every pending message via
// rcl_take_serialized_message. The wait set and subscription are touched by
// this thread only while it runs; crcl_subscription_destroy joins it before
// any fini, so there is no concurrent access to rcl entities.
static void *crcl__sub_thread_main(void *arg) {
    crcl_subscription_t *s = arg;
    const int64_t timeout_ns = 100LL * 1000 * 1000;  // 100 ms
    while (!atomic_load(&s->stop)) {
        if (rcl_wait_set_clear(&s->wait_set) != RCL_RET_OK) {
            rcl_reset_error();
            break;  // wait set unusable — stop delivering rather than spin
        }
        if (rcl_wait_set_add_subscription(&s->wait_set, &s->sub, NULL) != RCL_RET_OK) {
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
        // latency under sustained load (a fast publisher could otherwise keep
        // this loop busy indefinitely). A fresh zero-capacity serialized
        // message per take is acceptable (M4 plan);
        // rcl_take_serialized_message grows it as needed.
        while (!atomic_load(&s->stop)) {
            rcl_serialized_message_t msg = rmw_get_zero_initialized_serialized_message();
            rcutils_allocator_t alloc = rcutils_get_default_allocator();
            if (rmw_serialized_message_init(&msg, 0, &alloc) != RMW_RET_OK) {
                rcl_reset_error();
                break;
            }
            rmw_message_info_t info = rmw_get_zero_initialized_message_info();
            rcl_ret_t take = rcl_take_serialized_message(&s->sub, &msg, &info, NULL);
            if (take == RCL_RET_OK) {
                int64_t ts = info.source_timestamp > 0 ? (int64_t)info.source_timestamp : 0;
                s->cb(s->cb_ctx, msg.buffer, msg.buffer_length, ts);
                (void)rmw_serialized_message_fini(&msg);
                continue;
            }
            (void)rmw_serialized_message_fini(&msg);
            // RCL_RET_SUBSCRIPTION_TAKE_FAILED == nothing pending (not an
            // error); anything else is a real failure — either way stop
            // draining and go back to waiting.
            rcl_reset_error();
            break;
        }
    }
    return NULL;
}

crcl_subscription_t *crcl_subscription_create(
    crcl_node_t *n, const char *ros_type_name, const char *topic, const crcl_qos_t *q,
    crcl_take_callback_t cb, void *ctx) {
    if (!n || !q || !cb) {
        crcl__set_error("crcl_subscription_create: NULL node/qos/callback");
        return NULL;
    }
    const rosidl_message_type_support_t *ts = crcl_marshal_resolve_typesupport(ros_type_name);
    if (!ts) {
        // Not an rcl error — no rcl error state to capture; set the message directly.
        char msg[256];
        snprintf(msg, sizeof(msg), "unsupported type: %s", ros_type_name ? ros_type_name : "(null)");
        crcl__set_error(msg);
        return NULL;
    }
    crcl_subscription_t *s = calloc(1, sizeof(*s));
    if (!s) {
        crcl__set_error("crcl_subscription_create: out of memory");
        return NULL;
    }
    s->node = &n->node;
    s->cb = cb;
    s->cb_ctx = ctx;
    atomic_init(&s->stop, false);

    s->sub = rcl_get_zero_initialized_subscription();
    rcl_subscription_options_t sopts = rcl_subscription_get_default_options();
    sopts.qos = rmw_qos_profile_default;
    sopts.qos.reliability =
        q->reliability ? RMW_QOS_POLICY_RELIABILITY_RELIABLE : RMW_QOS_POLICY_RELIABILITY_BEST_EFFORT;
    sopts.qos.durability =
        q->durability ? RMW_QOS_POLICY_DURABILITY_TRANSIENT_LOCAL : RMW_QOS_POLICY_DURABILITY_VOLATILE;
    sopts.qos.history =
        q->history ? RMW_QOS_POLICY_HISTORY_KEEP_ALL : RMW_QOS_POLICY_HISTORY_KEEP_LAST;
    sopts.qos.depth = q->depth;
    if (rcl_subscription_init(&s->sub, &n->node, ts, topic, &sopts) != RCL_RET_OK) {
        crcl__capture_rcl_error();
        free(s);
        return NULL;
    }

    s->stop_gc = rcl_get_zero_initialized_guard_condition();
    if (rcl_guard_condition_init(&s->stop_gc, n->ctx, rcl_guard_condition_get_default_options())
        != RCL_RET_OK) {
        crcl__capture_rcl_error();
        (void)rcl_subscription_fini(&s->sub, s->node);
        free(s);
        return NULL;
    }

    s->wait_set = rcl_get_zero_initialized_wait_set();
    if (rcl_wait_set_init(&s->wait_set, 1, 1, 0, 0, 0, 0, n->ctx, rcl_get_default_allocator())
        != RCL_RET_OK) {
        crcl__capture_rcl_error();
        (void)rcl_guard_condition_fini(&s->stop_gc);
        (void)rcl_subscription_fini(&s->sub, s->node);
        free(s);
        return NULL;
    }

    if (pthread_create(&s->thread, NULL, crcl__sub_thread_main, s) != 0) {
        crcl__set_error("crcl_subscription_create: pthread_create failed");
        (void)rcl_wait_set_fini(&s->wait_set);
        (void)rcl_guard_condition_fini(&s->stop_gc);
        (void)rcl_subscription_fini(&s->sub, s->node);
        free(s);
        return NULL;
    }
    return s;
}

int crcl_subscription_destroy(crcl_subscription_t *s) {
    if (!s) return 0;
    // Refuse a self-destroy from the take callback: pthread_join on the
    // calling thread cannot block on itself (Darwin/glibc return EDEADLK
    // immediately), so proceeding to fini/free would leave the wait thread
    // dereferencing freed memory the moment the callback returns. Leak the
    // subscription instead and surface an error — destroy must be called
    // from another thread.
    if (pthread_equal(pthread_self(), s->thread)) {
        crcl__set_error(
            "crcl_subscription_destroy called from the take callback; destroy from another thread");
        return -1;
    }
    // Join BEFORE any fini: rcl take / fini are not thread-safe, and the wait
    // thread reads `sub` / `wait_set` until it exits. The guard condition is
    // the sanctioned cross-thread wakeup for rcl_wait, so the thread observes
    // the stop flag within one wakeup (or the 100 ms timeout). Because the
    // join happens first, this function blocks until any in-flight callback
    // has returned — the guarantee the Swift side relies on before releasing
    // the retained handler context.
    atomic_store(&s->stop, true);
    (void)rcl_trigger_guard_condition(&s->stop_gc);
    if (pthread_join(s->thread, NULL) != 0) {
        // The wait thread may still be running; fini/free now would race it.
        // Leak instead of crash.
        crcl__set_error("crcl_subscription_destroy: pthread_join failed");
        return -1;
    }
    int rc = 0;
    if (rcl_subscription_fini(&s->sub, s->node) != RCL_RET_OK) {
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
