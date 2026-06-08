#include "rcl_bridge.h"

#include <rcl/rcl.h>
#include <rcl/publisher.h>
// rcl_error_string_t / rcl_get_error_string / rcl_reset_error (capture_error()).
// Included explicitly for the symbols this TU uses rather than relying on the
// CRos2Jazzy module re-exporting it: the modulemap declares CRos2Jazzy.h as a
// plain (non-umbrella) header, so `#include <rcl/...>` resolves textually and
// only brings what each header transitively pulls in.
#include <rcl/error_handling.h>
// rcl_serialized_message_t is typedef'd in <rcl/types.h>, pulled in by <rcl/rcl.h>.
// There is no standalone <rcl/serialized_message.h> in this distribution.
#include <rmw/qos_profiles.h>
#include <rmw/serialized_message.h>
#include <rcutils/allocator.h>
#include <rosidl_runtime_c/message_type_support_struct.h>
#include <rmw/rmw.h>                              // rmw_serialize
#include <rosidl_runtime_c/string_functions.h>   // rosidl_runtime_c__String__assign / __fini
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

#ifdef _Thread_local
#define CRCL_THREAD_LOCAL _Thread_local
#elif defined(__GNUC__) || defined(__clang__)
#define CRCL_THREAD_LOCAL __thread
#else
#define CRCL_THREAD_LOCAL
#endif
static CRCL_THREAD_LOCAL char g_err[1024] = {0};

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
        (void)rcl_init_options_fini(&c->opts);
        free(c);
        return NULL;
    }
    if (rcl_init(0, NULL, &c->opts, &c->ctx) != RCL_RET_OK) {
        capture_error();
        (void)rcl_init_options_fini(&c->opts);
        free(c);
        return NULL;
    }
    return c;
}

void crcl_context_destroy(crcl_context_t *c) {
    if (!c) return;
    if (rcl_context_is_valid(&c->ctx)) {
        (void)rcl_shutdown(&c->ctx);
    }
    (void)rcl_context_fini(&c->ctx);
    (void)rcl_init_options_fini(&c->opts);
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
    (void)rcl_node_fini(&n->node);
    free(n);
}

crcl_publisher_t *crcl_publisher_create(
    crcl_node_t *n, const char *ros_type_name, const char *topic, crcl_qos_t q) {
    if (!n) return NULL;
    const rosidl_message_type_support_t *ts = resolve_typesupport(ros_type_name);
    if (!ts) {
        // Not an rcl error — no rcl error state to clear; set g_err directly.
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
    (void)rcl_publisher_fini(&p->pub, p->node);
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

void crcl_free(uint8_t *buf) { free(buf); }

int crcl_serialize_imu(
    int32_t stamp_sec, uint32_t stamp_nanosec, const char *frame_id,
    double orientation_x, double orientation_y, double orientation_z, double orientation_w,
    const double *orientation_covariance,
    double angular_velocity_x, double angular_velocity_y, double angular_velocity_z,
    const double *angular_velocity_covariance,
    double linear_acceleration_x, double linear_acceleration_y, double linear_acceleration_z,
    const double *linear_acceleration_covariance,
    uint8_t **out_buf, size_t *out_len) {
    const rosidl_message_type_support_t *ts = resolve_typesupport("sensor_msgs/msg/Imu");
    if (!ts) {
        snprintf(g_err, sizeof(g_err), "unsupported type: sensor_msgs/msg/Imu");
        return -1;
    }

    // Zero-init on the stack; only header.frame_id needs heap (via __assign).
    sensor_msgs__msg__Imu msg;
    memset(&msg, 0, sizeof(msg));
    msg.header.stamp.sec = stamp_sec;
    msg.header.stamp.nanosec = stamp_nanosec;
    if (!rosidl_runtime_c__String__assign(&msg.header.frame_id, frame_id ? frame_id : "")) {
        snprintf(g_err, sizeof(g_err), "String__assign failed for frame_id");
        return -1;
    }
    msg.orientation.x = orientation_x;
    msg.orientation.y = orientation_y;
    msg.orientation.z = orientation_z;
    msg.orientation.w = orientation_w;
    memcpy(msg.orientation_covariance, orientation_covariance, 9 * sizeof(double));
    msg.angular_velocity.x = angular_velocity_x;
    msg.angular_velocity.y = angular_velocity_y;
    msg.angular_velocity.z = angular_velocity_z;
    memcpy(msg.angular_velocity_covariance, angular_velocity_covariance, 9 * sizeof(double));
    msg.linear_acceleration.x = linear_acceleration_x;
    msg.linear_acceleration.y = linear_acceleration_y;
    msg.linear_acceleration.z = linear_acceleration_z;
    memcpy(msg.linear_acceleration_covariance, linear_acceleration_covariance, 9 * sizeof(double));

    rcutils_allocator_t alloc = rcutils_get_default_allocator();
    rmw_serialized_message_t ser = rmw_get_zero_initialized_serialized_message();
    rmw_ret_t rc = rmw_serialized_message_init(&ser, 0u, &alloc);
    if (rc != RMW_RET_OK) {
        capture_error();
        rosidl_runtime_c__String__fini(&msg.header.frame_id);
        return (int)rc;
    }

    rc = rmw_serialize(&msg, ts, &ser);
    if (rc != RMW_RET_OK) {
        capture_error();
        (void)rmw_serialized_message_fini(&ser);
        rosidl_runtime_c__String__fini(&msg.header.frame_id);
        return (int)rc;
    }

    uint8_t *copy = malloc(ser.buffer_length);
    if (!copy) {
        snprintf(g_err, sizeof(g_err), "out-of-memory copying %zu serialized bytes", ser.buffer_length);
        (void)rmw_serialized_message_fini(&ser);
        rosidl_runtime_c__String__fini(&msg.header.frame_id);
        return -1;
    }
    memcpy(copy, ser.buffer, ser.buffer_length);
    *out_buf = copy;
    *out_len = ser.buffer_length;

    (void)rmw_serialized_message_fini(&ser);
    rosidl_runtime_c__String__fini(&msg.header.frame_id);
    return 0;
}
