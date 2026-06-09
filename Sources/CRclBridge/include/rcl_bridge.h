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

// Generated per-type marshalling decls (crcl_serialize_<snake> /
// crcl_publish_<snake> / crcl_typesupport_<snake>) plus the typesupport
// resolver. Included after the crcl_publisher_t typedef the per-type headers
// reference. Surfaced to Swift through the modulemap's `export *`.
#include "crcl_marshal.h"

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

/// Free a buffer returned by a generated crcl_serialize_<type>.
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
