//
// crcl_action_registry.h
// Entry shape + lookup API for the generated RCL action typesupport
// registry (Generated/crcl_action_registry.c). Hand-written so the generated
// file only fills the table; the per-action surface stays minimal.
//
// rosidl typesupport handles are obtained through function calls
// (ROSIDL_GET_ACTION_TYPE_SUPPORT / ROSIDL_GET_MSG_TYPE_SUPPORT expand to
// getter-function invocations), not link-time constants — so the entry
// stores getter function pointers rather than raw typesupport pointers.
// That keeps the generated table statically initializable (`static const`)
// and thread-safe with zero lazy-init races. Call e.g.
// `entry->action_typesupport()` to resolve the handle.
//
#ifndef CRCL_ACTION_REGISTRY_H
#define CRCL_ACTION_REGISTRY_H

#include <rosidl_runtime_c/action_type_support_struct.h>
#include <rosidl_runtime_c/message_type_support_struct.h>

#ifdef __cplusplus
extern "C" {
#endif

/// One registered action type (M8 serialize-shim). The five wrapper message
/// roles are the rosidl-synthesized `<pkg>__action__<Type>_SendGoal_Request`
/// / `..._SendGoal_Response` / `..._GetResult_Request` / `..._GetResult_Response`
/// / `..._FeedbackMessage` C structs. Each `*_create` returns a
/// zero-initialized rosidl C struct allocated by the matching rosidl
/// `__create`; pass the pointer back to the matching `__destroy` wrapper
/// (NULL-tolerant, like rosidl itself) when done. The void pointers carry
/// the concrete wrapper struct — the generated wrappers cast back before
/// calling the typed rosidl functions.
typedef struct crcl_action_entry_s {
    /// Canonical ROS action type name, e.g. "example_interfaces/action/Fibonacci".
    const char *name;
    /// Action typesupport (ROSIDL_GET_ACTION_TYPE_SUPPORT) — for
    /// rcl_action_server_init / rcl_action_client_init.
    const rosidl_action_type_support_t *(*action_typesupport)(void);
    /// SendGoal request *message* typesupport (ROSIDL_GET_MSG_TYPE_SUPPORT
    /// with the action subfolder) — for rmw_serialize / rmw_deserialize.
    const rosidl_message_type_support_t *(*send_goal_request_typesupport)(void);
    /// <pkg>__action__<Type>_SendGoal_Request__create / __destroy.
    void *(*send_goal_request_create)(void);
    void (*send_goal_request_destroy)(void *message);
    /// SendGoal response *message* typesupport.
    const rosidl_message_type_support_t *(*send_goal_response_typesupport)(void);
    /// <pkg>__action__<Type>_SendGoal_Response__create / __destroy.
    void *(*send_goal_response_create)(void);
    void (*send_goal_response_destroy)(void *message);
    /// GetResult request *message* typesupport.
    const rosidl_message_type_support_t *(*get_result_request_typesupport)(void);
    /// <pkg>__action__<Type>_GetResult_Request__create / __destroy.
    void *(*get_result_request_create)(void);
    void (*get_result_request_destroy)(void *message);
    /// GetResult response *message* typesupport.
    const rosidl_message_type_support_t *(*get_result_response_typesupport)(void);
    /// <pkg>__action__<Type>_GetResult_Response__create / __destroy.
    void *(*get_result_response_create)(void);
    void (*get_result_response_destroy)(void *message);
    /// FeedbackMessage *message* typesupport.
    const rosidl_message_type_support_t *(*feedback_message_typesupport)(void);
    /// <pkg>__action__<Type>_FeedbackMessage__create / __destroy.
    void *(*feedback_message_create)(void);
    void (*feedback_message_destroy)(void *message);
} crcl_action_entry_t;

/// Resolve a canonical "pkg/action/Type" name to its registry entry. Returns
/// NULL when the name (or NULL) is not registered. The returned pointer has
/// static storage duration — never free it.
const crcl_action_entry_t *crcl_action_registry_lookup(const char *action_type_name);

#ifdef __cplusplus
}
#endif
#endif  // CRCL_ACTION_REGISTRY_H
