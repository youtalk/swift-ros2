#include "rcl_bridge.h"

#include <rcl/rcl.h>
#include <rcl/publisher.h>
// rcl_serialized_message_t is typedef'd in <rcl/types.h>, pulled in by <rcl/rcl.h>.
// There is no standalone <rcl/serialized_message.h> in this distribution.
#include <rmw/qos_profiles.h>
#include <rmw/serialized_message.h>
#include <rcutils/allocator.h>
#include <rosidl_runtime_c/message_type_support_struct.h>
// Use the rosidl_typesupport_c symbol (T in the static lib).
// ROSIDL_GET_MSG_TYPE_SUPPORT expands to
//   rosidl_typesupport_c__get_message_type_support_handle__sensor_msgs__msg__Imu()
#include <sensor_msgs/msg/imu.h>

#include <stdlib.h>
#include <string.h>

struct crcl_context_s {
    rcl_context_t ctx;
    rcl_init_options_t opts;
};
struct crcl_node_s {
    rcl_node_t node;
};
struct crcl_publisher_s {
    rcl_publisher_t pub;
    rcl_node_t *node;  // borrowed; node must outlive the publisher
};

static char g_err[1024];

static void capture_error(void) {
    rcl_error_string_t s = rcl_get_error_string();
    strncpy(g_err, s.str, sizeof(g_err) - 1);
    g_err[sizeof(g_err) - 1] = '\0';
    rcl_reset_error();
}
const char *crcl_last_error(void) { return g_err; }

// Type-name -> typesupport table.
// rosidl_typesupport_c symbol is defined (T) in CRos2Jazzy; use
// ROSIDL_GET_MSG_TYPE_SUPPORT (from <sensor_msgs/msg/imu.h>) to obtain it.
static const rosidl_message_type_support_t *resolve_typesupport(const char *ros_type_name) {
    if (strcmp(ros_type_name, "sensor_msgs/msg/Imu") == 0) {
        return ROSIDL_GET_MSG_TYPE_SUPPORT(sensor_msgs, msg, Imu);
    }
    return NULL;
}

crcl_context_t *crcl_context_create(size_t domain_id) {
    crcl_context_t *c = calloc(1, sizeof(*c));
    if (!c) return NULL;
    c->opts = rcl_get_zero_initialized_init_options();
    c->ctx = rcl_get_zero_initialized_context();
    rcl_allocator_t alloc = rcl_get_default_allocator();
    if (rcl_init_options_init(&c->opts, alloc) != RCL_RET_OK) {
        capture_error();
        free(c);
        return NULL;
    }
    if (rcl_init_options_set_domain_id(&c->opts, domain_id) != RCL_RET_OK) {
        capture_error();
        rcl_init_options_fini(&c->opts);
        free(c);
        return NULL;
    }
    if (rcl_init(0, NULL, &c->opts, &c->ctx) != RCL_RET_OK) {
        capture_error();
        rcl_init_options_fini(&c->opts);
        free(c);
        return NULL;
    }
    return c;
}

void crcl_context_destroy(crcl_context_t *c) {
    if (!c) return;
    if (rcl_context_is_valid(&c->ctx)) {
        rcl_shutdown(&c->ctx);
    }
    rcl_context_fini(&c->ctx);
    rcl_init_options_fini(&c->opts);
    free(c);
}

crcl_node_t *crcl_node_create(crcl_context_t *c, const char *name, const char *ns) {
    if (!c) return NULL;
    crcl_node_t *n = calloc(1, sizeof(*n));
    if (!n) return NULL;
    n->node = rcl_get_zero_initialized_node();
    rcl_node_options_t nopts = rcl_node_get_default_options();
    if (rcl_node_init(&n->node, name, ns, &c->ctx, &nopts) != RCL_RET_OK) {
        capture_error();
        free(n);
        return NULL;
    }
    return n;
}

void crcl_node_destroy(crcl_node_t *n) {
    if (!n) return;
    rcl_node_fini(&n->node);
    free(n);
}

crcl_publisher_t *crcl_publisher_create(
    crcl_node_t *n, const char *ros_type_name, const char *topic, crcl_qos_t q) {
    if (!n) return NULL;
    const rosidl_message_type_support_t *ts = resolve_typesupport(ros_type_name);
    if (!ts) {
        snprintf(g_err, sizeof(g_err), "unsupported type: %s", ros_type_name);
        return NULL;
    }
    crcl_publisher_t *p = calloc(1, sizeof(*p));
    if (!p) return NULL;
    p->pub = rcl_get_zero_initialized_publisher();
    p->node = &n->node;
    rcl_publisher_options_t popts = rcl_publisher_get_default_options();
    popts.qos = rmw_qos_profile_default;
    popts.qos.reliability =
        q.reliability ? RMW_QOS_POLICY_RELIABILITY_RELIABLE : RMW_QOS_POLICY_RELIABILITY_BEST_EFFORT;
    popts.qos.durability =
        q.durability ? RMW_QOS_POLICY_DURABILITY_TRANSIENT_LOCAL : RMW_QOS_POLICY_DURABILITY_VOLATILE;
    popts.qos.history =
        q.history ? RMW_QOS_POLICY_HISTORY_KEEP_ALL : RMW_QOS_POLICY_HISTORY_KEEP_LAST;
    popts.qos.depth = q.depth;
    if (rcl_publisher_init(&p->pub, &n->node, ts, topic, &popts) != RCL_RET_OK) {
        capture_error();
        free(p);
        return NULL;
    }
    return p;
}

void crcl_publisher_destroy(crcl_publisher_t *p) {
    if (!p) return;
    rcl_publisher_fini(&p->pub, p->node);
    free(p);
}

int crcl_publish_serialized(crcl_publisher_t *p, const uint8_t *data, size_t len) {
    if (!p) return -1;
    rcl_serialized_message_t ser = rmw_get_zero_initialized_serialized_message();
    // Borrow the caller's buffer; rcl_publish_serialized_message only reads it.
    ser.buffer = (uint8_t *)data;
    ser.buffer_length = len;
    ser.buffer_capacity = len;
    ser.allocator = rcutils_get_default_allocator();
    rcl_ret_t ret = rcl_publish_serialized_message(&p->pub, &ser, NULL);
    if (ret != RCL_RET_OK) {
        capture_error();
        return (int)ret;
    }
    return 0;
}
