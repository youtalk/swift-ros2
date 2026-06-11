//
// crcl_srv_registry.h
// Entry shape + lookup API for the generated RCL service typesupport
// registry (Generated/crcl_srv_registry.c). Hand-written so the generated
// file only fills the table; the per-service surface stays minimal.
//
// rosidl typesupport handles are obtained through function calls
// (ROSIDL_GET_SRV_TYPE_SUPPORT / ROSIDL_GET_MSG_TYPE_SUPPORT expand to
// getter-function invocations), not link-time constants — so the entry
// stores getter function pointers rather than raw typesupport pointers.
// That keeps the generated table statically initializable (`static const`)
// and thread-safe with zero lazy-init races. Call e.g.
// `entry->service_typesupport()` to resolve the handle.
//
#ifndef CRCL_SRV_REGISTRY_H
#define CRCL_SRV_REGISTRY_H

#include <rosidl_runtime_c/message_type_support_struct.h>
#include <rosidl_runtime_c/service_type_support_struct.h>

#ifdef __cplusplus
extern "C" {
#endif

/// One registered service type. `request_create` / `response_create` return
/// a zero-initialized rosidl C struct allocated by the matching rosidl
/// `__create`; pass the pointer back to the matching `__destroy` wrapper
/// (NULL-tolerant, like rosidl itself) when done. The void pointers carry
/// the concrete `<pkg>__srv__<Type>_Request` / `..._Response` struct — the
/// generated wrappers cast back before calling the typed rosidl functions.
typedef struct crcl_srv_entry_s {
    /// Canonical ROS service type name, e.g. "example_interfaces/srv/AddTwoInts".
    const char *name;
    /// Service typesupport (ROSIDL_GET_SRV_TYPE_SUPPORT) — for rcl_service_init /
    /// rcl_client_init.
    const rosidl_service_type_support_t *(*service_typesupport)(void);
    /// Request *message* typesupport (ROSIDL_GET_MSG_TYPE_SUPPORT with the srv
    /// subfolder) — for rmw_serialize / rmw_deserialize of the request half.
    const rosidl_message_type_support_t *(*request_typesupport)(void);
    /// Response *message* typesupport — for rmw_serialize / rmw_deserialize of
    /// the response half.
    const rosidl_message_type_support_t *(*response_typesupport)(void);
    /// <pkg>__srv__<Type>_Request__create / __destroy.
    void *(*request_create)(void);
    void (*request_destroy)(void *request);
    /// <pkg>__srv__<Type>_Response__create / __destroy.
    void *(*response_create)(void);
    void (*response_destroy)(void *response);
} crcl_srv_entry_t;

/// Resolve a canonical "pkg/srv/Type" name to its registry entry. Returns
/// NULL when the name (or NULL) is not registered. The returned pointer has
/// static storage duration — never free it.
const crcl_srv_entry_t *crcl_srv_registry_lookup(const char *srv_type_name);

#ifdef __cplusplus
}
#endif
#endif  // CRCL_SRV_REGISTRY_H
