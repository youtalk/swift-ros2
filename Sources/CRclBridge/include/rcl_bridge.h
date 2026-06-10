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
typedef struct crcl_subscription_s crcl_subscription_t;

// Generated per-type marshalling decls (crcl_serialize_<snake> /
// crcl_publish_<snake> / crcl_typesupport_<snake>) plus the typesupport
// resolver. Included after the crcl_publisher_t typedef the per-type headers
// reference. Surfaced to Swift through the modulemap's `export *`.
#include "crcl_marshal.h"

// Service typesupport registry (M7 serialize-shim): crcl_srv_entry_t +
// crcl_srv_registry_lookup. The table itself is generated into
// Generated/crcl_srv_registry.c.
#include "crcl_srv_registry.h"

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

/// Invoked from the subscription's dedicated wait thread once per taken
/// message. `buf` points at the raw CDR bytes (incl. the 4-byte encapsulation
/// header) and is valid only for the duration of the call — copy if needed.
/// `source_timestamp_ns` is rmw's publisher-side timestamp; 0 when the
/// middleware reports none (or an invalid/negative value).
typedef void (*crcl_take_callback_t)(
    void *ctx, const uint8_t *buf, size_t len, int64_t source_timestamp_ns);

/// Create a subscription on `node` and spawn its wait thread. `cb` fires on
/// that thread for every message until crcl_subscription_destroy. Returns
/// NULL on failure; call crcl_last_error().
crcl_subscription_t *crcl_subscription_create(
    crcl_node_t *node, const char *ros_type_name, const char *topic, const crcl_qos_t *qos,
    crcl_take_callback_t cb, void *ctx);

/// Destroy a subscription. Blocks until the wait thread has exited — and thus
/// until any in-flight callback has returned — before finalizing the rcl
/// entities. MUST NOT be called from the take callback (i.e. from the
/// subscription's own wait thread): the join would be a self-join, so the
/// call fails and the subscription is intentionally leaked rather than freed
/// under the running thread. Returns 0 on success; positive if a fini failed
/// (resources are still freed and the callback will never fire again);
/// negative if the subscription could NOT be destroyed (self-call from the
/// take callback, or the join failed) — the wait thread may still be running,
/// the subscription leaks, and the caller MUST NOT free `ctx`. See
/// crcl_last_error() for non-zero returns.
int crcl_subscription_destroy(crcl_subscription_t *sub);

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
