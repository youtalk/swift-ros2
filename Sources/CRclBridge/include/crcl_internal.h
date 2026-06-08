//
// crcl_internal.h
// Internal (non-public-API) surface shared between rcl_bridge.c and the
// generated marshaller C sources: the publisher struct body and the error
// helpers. The `crcl_publisher_t` typedef itself stays in rcl_bridge.h; this
// header only supplies the struct *body* so generated code can dereference
// `pub->pub` without re-declaring the typedef.
//
#ifndef CRCL_INTERNAL_H
#define CRCL_INTERNAL_H

#include <rcl/publisher.h>
#include <rcl/rcl.h>

#ifdef __cplusplus
extern "C" {
#endif

// The crcl_publisher_t typedef is also declared in rcl_bridge.h. Repeating an
// identical typedef of an incomplete struct is legal in C11, and the generated
// marshaller headers reach the typedef through this header (they never include
// rcl_bridge.h).
typedef struct crcl_publisher_s crcl_publisher_t;
struct crcl_publisher_s {
    rcl_publisher_t pub;
    rcl_node_t *node;  // borrowed; node must outlive the publisher
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
