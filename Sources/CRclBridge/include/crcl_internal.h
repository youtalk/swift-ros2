//
// crcl_internal.h
// Internal (non-public-API) surface shared between the bridge C sources
// (rcl_bridge.c, rcl_subscription.c) and the generated marshaller C sources:
// the node / publisher struct bodies and the error helpers. The typedefs
// themselves stay in rcl_bridge.h; this header only supplies the struct
// *bodies* so the other TUs can dereference them without re-declaring the
// typedefs.
//
#ifndef CRCL_INTERNAL_H
#define CRCL_INTERNAL_H

#include <rcl/publisher.h>
#include <rcl/rcl.h>

#ifdef __cplusplus
extern "C" {
#endif

// The crcl_publisher_t / crcl_node_t typedefs are also declared in
// rcl_bridge.h. Repeating an identical typedef of an incomplete struct is
// legal in C11, and the generated marshaller headers reach the typedefs
// through this header (they never include rcl_bridge.h).
typedef struct crcl_publisher_s crcl_publisher_t;
struct crcl_publisher_s {
    rcl_publisher_t pub;
    rcl_node_t *node;  // borrowed; node must outlive the publisher
};

// Stored `ctx` exists because Jazzy's rcl has no rcl_node_get_context();
// rcl_subscription.c needs the owning context to init its guard condition and
// wait set, so crcl_node_create records it here at node-create time.
typedef struct crcl_node_s crcl_node_t;
struct crcl_node_s {
    rcl_node_t node;
    rcl_context_t *ctx;  // borrowed; context must outlive the node
};

/// Copy `msg` into the thread-local error buffer surfaced by crcl_last_error().
void crcl__set_error(const char *msg);

/// Capture the current rcutils error stack into the thread-local error buffer
/// and reset it (used after a failing rcl/rmw call).
void crcl__capture_rcl_error(void);

#ifdef __cplusplus
}
#endif
#endif  // CRCL_INTERNAL_H
