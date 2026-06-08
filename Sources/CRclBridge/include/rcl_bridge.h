//
// rcl_bridge.h
// C-FFI bridge for the real rcl + rmw_cyclonedds_cpp stack (CRos2Jazzy).
// Types use the "crcl_" prefix to avoid colliding with rcl types.
//
#ifndef CRCL_BRIDGE_H
#define CRCL_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct crcl_context_s crcl_context_t;
typedef struct crcl_node_s crcl_node_t;
typedef struct crcl_publisher_s crcl_publisher_t;

/// QoS mapped from Swift TransportQoS (primitives only — no rmw types leak).
typedef struct crcl_qos_s {
    int reliability;  // 0 = best_effort, 1 = reliable
    int durability;   // 0 = volatile,    1 = transient_local
    int history;      // 0 = keep_last,   1 = keep_all
    size_t depth;     // used when history == keep_last
} crcl_qos_t;

/// Lifecycle. Each create returns NULL on failure; call crcl_last_error().
crcl_context_t *crcl_context_create(size_t domain_id);
void crcl_context_destroy(crcl_context_t *ctx);

crcl_node_t *crcl_node_create(crcl_context_t *ctx, const char *name, const char *ns);
void crcl_node_destroy(crcl_node_t *node);

crcl_publisher_t *crcl_publisher_create(
    crcl_node_t *node, const char *ros_type_name, const char *topic, crcl_qos_t qos);
void crcl_publisher_destroy(crcl_publisher_t *pub);

/// Publish pre-serialized CDR bytes. Returns 0 on success, non-zero rcl_ret_t otherwise.
int crcl_publish_serialized(crcl_publisher_t *pub, const uint8_t *data, size_t len);

/// Serialize a sensor_msgs/msg/Imu from flat fields using the real ROS 2
/// introspection serializer (rmw_serialize) — no node/context/participant.
/// Each covariance pointer must reference exactly 9 doubles. On success writes
/// a malloc'd CDR buffer (incl. the 4-byte encapsulation header) to *out_buf
/// and its length to *out_len, and returns 0; the caller must crcl_free(*out_buf).
/// Returns a non-zero rmw_ret_t on failure (see crcl_last_error()).
int crcl_serialize_imu(
    int32_t stamp_sec, uint32_t stamp_nanosec, const char *frame_id,
    double orientation_x, double orientation_y, double orientation_z, double orientation_w,
    const double *orientation_covariance,
    double angular_velocity_x, double angular_velocity_y, double angular_velocity_z,
    const double *angular_velocity_covariance,
    double linear_acceleration_x, double linear_acceleration_y, double linear_acceleration_z,
    const double *linear_acceleration_covariance,
    uint8_t **out_buf, size_t *out_len);

/// Free a buffer returned by crcl_serialize_imu.
void crcl_free(uint8_t *buf);

/// Write the canonical RIHS01 type-hash string (e.g. "RIHS01_7d9a00ff…") for a
/// supported ROS type into `out` (NUL-terminated, truncated to `cap`). Returns 0
/// on success, non-zero on failure (unsupported type, or the handle carries no
/// type hash — see crcl_last_error()).
int crcl_type_hash(const char *ros_type_name, char *out, size_t cap);

/// Last error from the rcutils error stack; "" if none.
const char *crcl_last_error(void);

#ifdef __cplusplus
}
#endif
#endif  // CRCL_BRIDGE_H
