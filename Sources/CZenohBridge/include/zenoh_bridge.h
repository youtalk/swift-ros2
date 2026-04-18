//
// zenoh_bridge.h
// C-FFI bridge for zenoh-pico to Swift
//
// Provides simplified C API wrapping zenoh-pico for use in Swift
//

#ifndef ZENOH_BRIDGE_H
#define ZENOH_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// Opaque handles for zenoh types (exposed as pointers to Swift)
// ============================================================================

typedef struct zenoh_session_t zenoh_session_t;
typedef struct zenoh_keyexpr_t zenoh_keyexpr_t;
typedef struct zenoh_subscriber_t zenoh_subscriber_t;
typedef struct zenoh_liveliness_token_t zenoh_liveliness_token_t;

// ============================================================================
// Error handling
// ============================================================================

// Returns 0 on success, negative error code on failure
typedef int8_t zenoh_result_t;

// Error codes
#define ZENOH_ERROR_SESSION_CLOSED -2

// ============================================================================
// Session management
// ============================================================================

/// Opens a zenoh session with the given locator string
/// @param locator Connection string (e.g., "tcp/127.0.0.1:7447")
/// @param out_session Output parameter for the created session handle
/// @return 0 on success, negative error code otherwise
zenoh_result_t zenoh_open_session(const char* locator, zenoh_session_t** out_session);

/// Closes a zenoh session and frees all associated resources
/// @param session Session handle to close (will be set to NULL)
/// @return 0 on success, negative error code otherwise
zenoh_result_t zenoh_close_session(zenoh_session_t** session);

/// Gets the session ID as a hex string
/// @param session The zenoh session
/// @param out_buffer Buffer to store the session ID (must be at least 33 bytes: 32 hex chars + null terminator)
/// @param buffer_size Size of the output buffer
/// @return 0 on success, negative error code otherwise
zenoh_result_t zenoh_get_session_id(zenoh_session_t* session, char* out_buffer, size_t buffer_size);

/// Checks if the session is healthy and can safely publish
/// This is more comprehensive than z_session_is_closed() - it verifies
/// the session is not in a stale/zombie state after sleep/wake cycles
/// @param session The zenoh session to check
/// @return true if session is healthy, false if stale or closed
bool zenoh_is_session_healthy(zenoh_session_t* session);

// ============================================================================
// Key expression management
// ============================================================================

/// Declares a key expression for efficient repeated use
/// @param session The zenoh session
/// @param keyexpr_str The key expression string
/// @param out_keyexpr Output parameter for the declared key expression handle
/// @return 0 on success, negative error code otherwise
zenoh_result_t zenoh_declare_keyexpr(zenoh_session_t* session,
                                      const char* keyexpr_str,
                                      zenoh_keyexpr_t** out_keyexpr);

/// Undeclares and frees a key expression
/// @param session The zenoh session
/// @param keyexpr Key expression handle to undeclare (will be set to NULL)
/// @return 0 on success, negative error code otherwise
zenoh_result_t zenoh_undeclare_keyexpr(zenoh_session_t* session,
                                        zenoh_keyexpr_t** keyexpr);

// ============================================================================
// Publishing
// ============================================================================

/// Puts data to a key expression with optional attachment
/// @param session The zenoh session
/// @param keyexpr The key expression to publish to
/// @param payload Pointer to the payload data
/// @param payload_len Length of the payload in bytes
/// @param attachment_data Pointer to attachment data (can be NULL)
/// @param attachment_len Length of attachment data in bytes (0 if no attachment)
/// @return 0 on success, negative error code otherwise
zenoh_result_t zenoh_put(zenoh_session_t* session,
                         zenoh_keyexpr_t* keyexpr,
                         const uint8_t* payload,
                         size_t payload_len,
                         const uint8_t* attachment_data,
                         size_t attachment_len);

/// Puts data to a key expression string (non-declared) with optional attachment
/// @param session The zenoh session
/// @param keyexpr_str The key expression string to publish to
/// @param payload Pointer to the payload data
/// @param payload_len Length of the payload in bytes
/// @param attachment_data Pointer to attachment data (can be NULL)
/// @param attachment_len Length of attachment data in bytes (0 if no attachment)
/// @return 0 on success, negative error code otherwise
zenoh_result_t zenoh_put_str(zenoh_session_t* session,
                             const char* keyexpr_str,
                             const uint8_t* payload,
                             size_t payload_len,
                             const uint8_t* attachment_data,
                             size_t attachment_len);

// ============================================================================
// Subscription (callback-based)
// ============================================================================

/// Callback function type for subscribers
/// @param keyexpr_str The key expression that matched
/// @param payload Pointer to received payload data
/// @param payload_len Length of received payload
/// @param attachment Pointer to received attachment data (can be NULL)
/// @param attachment_len Length of received attachment (0 if no attachment)
/// @param context User-provided context pointer
typedef void (*zenoh_subscriber_callback_t)(const char* keyexpr_str,
                                             const uint8_t* payload,
                                             size_t payload_len,
                                             const uint8_t* attachment,
                                             size_t attachment_len,
                                             void* context);

/// Declares a subscriber with a callback
/// @param session The zenoh session
/// @param keyexpr_str The key expression to subscribe to
/// @param callback The callback function to invoke on received samples
/// @param context User context pointer passed to callback
/// @param out_subscriber Output parameter for the subscriber handle
/// @return 0 on success, negative error code otherwise
zenoh_result_t zenoh_declare_subscriber(zenoh_session_t* session,
                                        const char* keyexpr_str,
                                        zenoh_subscriber_callback_t callback,
                                        void* context,
                                        zenoh_subscriber_t** out_subscriber);

/// Undeclares and frees a subscriber
/// @param session The zenoh session
/// @param subscriber Subscriber handle to undeclare (will be set to NULL)
/// @return 0 on success, negative error code otherwise
zenoh_result_t zenoh_undeclare_subscriber(zenoh_session_t* session,
                                          zenoh_subscriber_t** subscriber);

// ============================================================================
// Liveliness tokens (for ROS 2 discovery)
// ============================================================================

/// Declares a liveliness token for ROS 2 entity discovery
/// @param session The zenoh session
/// @param key_expr The liveliness token key expression (e.g., "@ros2_lv/0/...")
/// @param out_token Output parameter for the liveliness token handle
/// @return 0 on success, negative error code otherwise
zenoh_result_t zenoh_declare_liveliness_token(zenoh_session_t* session,
                                              const char* key_expr,
                                              zenoh_liveliness_token_t** out_token);

/// Undeclares and frees a liveliness token
/// @param session The zenoh session
/// @param token Liveliness token handle to undeclare (will be set to NULL)
/// @return 0 on success, negative error code otherwise
zenoh_result_t zenoh_undeclare_liveliness_token(zenoh_session_t* session,
                                                zenoh_liveliness_token_t** token);

// ============================================================================
// Utility functions
// ============================================================================

/// Gets a human-readable error message for a result code
/// @param result The result code
/// @return String description of the error
const char* zenoh_result_str(zenoh_result_t result);

#ifdef __cplusplus
}
#endif

#endif // ZENOH_BRIDGE_H
