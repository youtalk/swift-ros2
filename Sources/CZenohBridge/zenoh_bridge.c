//
// zenoh_bridge.c
// C-FFI bridge implementation for zenoh-pico
//

#include "zenoh_bridge.h"
#include <zenoh-pico.h>
#include <zenoh-pico/api/liveliness.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>

#ifdef __APPLE__
  #include <os/log.h>
#else
  /* Non-Apple platforms: stub out Apple's unified logging to stderr. */
  typedef int os_log_t;
  #define os_log_create(subsystem, category) 0
  #define os_log_info(log, fmt, ...)  \
      fprintf(stderr, "[info]  " fmt "\n", ##__VA_ARGS__)
  #define os_log_error(log, fmt, ...) \
      fprintf(stderr, "[error] " fmt "\n", ##__VA_ARGS__)
  #define os_log_debug(log, fmt, ...) \
      fprintf(stderr, "[debug] " fmt "\n", ##__VA_ARGS__)
  #define os_log(log, fmt, ...)       \
      fprintf(stderr, fmt "\n", ##__VA_ARGS__)
#endif

// ============================================================================
// Internal structures
// ============================================================================

struct zenoh_session_t {
    z_owned_session_t session;
};

struct zenoh_keyexpr_t {
    z_owned_keyexpr_t keyexpr;
};

struct zenoh_subscriber_t {
    z_owned_subscriber_t subscriber;
    zenoh_subscriber_callback_t callback;
    void* context;
};

struct zenoh_liveliness_token_t {
    z_owned_liveliness_token_t token;
};

// ============================================================================
// Session management
// ============================================================================

zenoh_result_t zenoh_open_session(const char* locator, zenoh_session_t** out_session) {
    os_log_t log = os_log_create("com.youtalk.swift-ros2", "zenoh");

    if (!locator || !out_session) {
        os_log_error(log, "[zenoh_bridge] ERROR: Invalid parameters");
        return -1;
    }

    os_log_info(log, "[zenoh_bridge] Opening session with locator: %s", locator);

    // Allocate session wrapper
    zenoh_session_t* session = (zenoh_session_t*)malloc(sizeof(zenoh_session_t));
    if (!session) {
        os_log_error(log, "[zenoh_bridge] ERROR: Failed to allocate session");
        return -1;
    }

    // Create config
    z_owned_config_t config;
    int ret = z_config_default(&config);
    os_log_info(log, "[zenoh_bridge] z_config_default returned: %d", ret);
    if (ret < 0) {
        free(session);
        return -1;
    }

    // Set the connect mode and locator
    ret = zp_config_insert(z_loan_mut(config), Z_CONFIG_CONNECT_KEY, locator);
    os_log_info(log, "[zenoh_bridge] zp_config_insert returned: %d", ret);
    if (ret < 0) {
        z_drop(z_move(config));
        free(session);
        return -1;
    }

    // Open the session
    z_open_options_t options;
    options.__dummy = 0;

    os_log_info(log, "[zenoh_bridge] Calling z_open...");
    os_log_info(log, "[zenoh_bridge] Using locator: %s", locator);

    ret = z_open(&session->session, z_move(config), &options);
    os_log_info(log, "[zenoh_bridge] z_open returned: %d", ret);
    if (ret < 0) {
        os_log_error(log, "[zenoh_bridge] ERROR: z_open failed with code %d", ret);
        os_log_error(log, "[zenoh_bridge] Possible causes: network unreachable, router not running, or firewall blocking");
        os_log_error(log, "[zenoh_bridge] errno: %d (%s)", errno, strerror(errno));
        free(session);
        return -1;
    }

    // Start read and lease tasks for background processing (required for pico)
    os_log_info(log, "[zenoh_bridge] Starting read and lease tasks...");
    zp_start_read_task(z_loan_mut(session->session), NULL);
    zp_start_lease_task(z_loan_mut(session->session), NULL);

    os_log_info(log, "[zenoh_bridge] Session opened successfully");
    *out_session = session;
    return 0;
}

zenoh_result_t zenoh_close_session(zenoh_session_t** session) {
    if (!session || !*session) {
        return -1;
    }

    zenoh_session_t* s = *session;

    // Stop background tasks
    zp_stop_read_task(z_loan_mut(s->session));
    zp_stop_lease_task(z_loan_mut(s->session));

    // Close the session
    z_close_options_t options;
    options.__dummy = 0;
    z_close(z_loan_mut(s->session), &options);

    // Drop the session
    z_drop(z_move(s->session));

    free(s);
    *session = NULL;

    return 0;
}

zenoh_result_t zenoh_get_session_id(zenoh_session_t* session, char* out_buffer, size_t buffer_size) {
    if (!session || !out_buffer || buffer_size < 33) {
        return -1;
    }

    // Get the session ID
    z_id_t id = z_info_zid(z_loan(session->session));

    // Convert to hex string (16 bytes = 32 hex chars + null terminator)
    for (size_t i = 0; i < 16; i++) {
        snprintf(out_buffer + (i * 2), 3, "%02x", id.id[i]);
    }
    out_buffer[32] = '\0';

    return 0;
}

bool zenoh_is_session_healthy(zenoh_session_t* session) {
    os_log_t log = os_log_create("com.youtalk.swift-ros2", "zenoh");

    if (!session) {
        os_log_error(log, "[zenoh_bridge] is_session_healthy: session is NULL");
        return false;
    }

    // Check 1: Session is not explicitly closed
    if (z_session_is_closed(z_loan(session->session))) {
        os_log_info(log, "[zenoh_bridge] Session is closed");
        return false;
    }

    // Check 2: Try to get session ID - this validates internal state
    // If the session is in a zombie state, this may fail or return zero ID
    z_id_t id = z_info_zid(z_loan(session->session));

    // A valid session should have a non-zero ID
    bool has_valid_id = false;
    for (size_t i = 0; i < 16; i++) {
        if (id.id[i] != 0) {
            has_valid_id = true;
            break;
        }
    }

    if (!has_valid_id) {
        os_log_info(log, "[zenoh_bridge] Session has invalid/zero ID - likely stale");
        return false;
    }

    os_log_info(log, "[zenoh_bridge] Session health check passed");
    return true;
}

// ============================================================================
// Key expression management
// ============================================================================

zenoh_result_t zenoh_declare_keyexpr(zenoh_session_t* session,
                                      const char* keyexpr_str,
                                      zenoh_keyexpr_t** out_keyexpr) {
    os_log_t log = os_log_create("com.youtalk.swift-ros2", "zenoh");

    if (!session || !keyexpr_str || !out_keyexpr) {
        os_log_error(log, "[zenoh_bridge] declare_keyexpr: Invalid parameters");
        return -1;
    }

    os_log_info(log, "[zenoh_bridge] Declaring keyexpr: %s", keyexpr_str);

    zenoh_keyexpr_t* kexpr = (zenoh_keyexpr_t*)malloc(sizeof(zenoh_keyexpr_t));
    if (!kexpr) {
        os_log_error(log, "[zenoh_bridge] Failed to allocate keyexpr");
        return -1;
    }

    // Create a view keyexpr from string
    os_log_info(log, "[zenoh_bridge] Creating view keyexpr...");
    z_view_keyexpr_t view_ke;
    int ret = z_view_keyexpr_from_str(&view_ke, keyexpr_str);
    os_log_info(log, "[zenoh_bridge] z_view_keyexpr_from_str returned: %d", ret);
    if (ret < 0) {
        free(kexpr);
        return -1;
    }

    // Declare the keyexpr
    os_log_info(log, "[zenoh_bridge] Calling z_declare_keyexpr...");
    ret = z_declare_keyexpr(z_loan(session->session), &kexpr->keyexpr, z_loan(view_ke));
    os_log_info(log, "[zenoh_bridge] z_declare_keyexpr returned: %d", ret);
    if (ret < 0) {
        os_log_error(log, "[zenoh_bridge] z_declare_keyexpr failed with code: %d", ret);
        free(kexpr);
        return -1;
    }

    os_log_info(log, "[zenoh_bridge] Keyexpr declared successfully");
    *out_keyexpr = kexpr;
    return 0;
}

zenoh_result_t zenoh_undeclare_keyexpr(zenoh_session_t* session,
                                        zenoh_keyexpr_t** keyexpr) {
    if (!session || !keyexpr || !*keyexpr) {
        return -1;
    }

    zenoh_keyexpr_t* ke = *keyexpr;

    // Undeclare the keyexpr
    z_undeclare_keyexpr(z_loan(session->session), z_move(ke->keyexpr));

    free(ke);
    *keyexpr = NULL;

    return 0;
}

// ============================================================================
// Publishing
// ============================================================================

zenoh_result_t zenoh_put(zenoh_session_t* session,
                         zenoh_keyexpr_t* keyexpr,
                         const uint8_t* payload,
                         size_t payload_len,
                         const uint8_t* attachment_data,
                         size_t attachment_len) {
    if (!session || !keyexpr || !payload) {
        return -1;
    }

    // Check if session is closed (router disconnected)
    if (z_session_is_closed(z_loan(session->session))) {
        return ZENOH_ERROR_SESSION_CLOSED;
    }

    // Create bytes for payload
    z_owned_bytes_t bytes;
    if (z_bytes_from_buf(&bytes, (uint8_t*)payload, payload_len, NULL, NULL) < 0) {
        return -1;
    }

    // Prepare put options
    z_put_options_t options;
    z_put_options_default(&options);

    // Add attachment if provided
    z_owned_bytes_t attachment;
    if (attachment_data && attachment_len > 0) {
        if (z_bytes_from_buf(&attachment, (uint8_t*)attachment_data, attachment_len, NULL, NULL) < 0) {
            z_drop(z_move(bytes));
            return -1;
        }
        options.attachment = z_move(attachment);
    }

    // Perform the put
    int result = z_put(z_loan(session->session), z_loan(keyexpr->keyexpr),
                       z_move(bytes), &options);

    return (zenoh_result_t)result;
}

zenoh_result_t zenoh_put_str(zenoh_session_t* session,
                             const char* keyexpr_str,
                             const uint8_t* payload,
                             size_t payload_len,
                             const uint8_t* attachment_data,
                             size_t attachment_len) {
    if (!session || !keyexpr_str || !payload) {
        return -1;
    }

    // Check if session is closed (router disconnected)
    if (z_session_is_closed(z_loan(session->session))) {
        return ZENOH_ERROR_SESSION_CLOSED;
    }

    // Create a view keyexpr from string
    z_view_keyexpr_t view_ke;
    if (z_view_keyexpr_from_str(&view_ke, keyexpr_str) < 0) {
        return -1;
    }

    // Create bytes for payload
    z_owned_bytes_t bytes;
    if (z_bytes_from_buf(&bytes, (uint8_t*)payload, payload_len, NULL, NULL) < 0) {
        return -1;
    }

    // Prepare put options
    z_put_options_t options;
    z_put_options_default(&options);

    // Add attachment if provided
    z_owned_bytes_t attachment;
    if (attachment_data && attachment_len > 0) {
        if (z_bytes_from_buf(&attachment, (uint8_t*)attachment_data, attachment_len, NULL, NULL) < 0) {
            z_drop(z_move(bytes));
            return -1;
        }
        options.attachment = z_move(attachment);
    }

    // Perform the put
    int result = z_put(z_loan(session->session), z_loan(view_ke),
                       z_move(bytes), &options);

    return (zenoh_result_t)result;
}

// ============================================================================
// Subscription
// ============================================================================

// Internal callback wrapper that converts zenoh sample to our callback format
static void zenoh_sample_handler(z_loaned_sample_t* sample, void* context) {
    zenoh_subscriber_t* sub = (zenoh_subscriber_t*)context;
    if (!sub || !sub->callback) {
        return;
    }

    // Extract keyexpr as string
    const z_loaned_keyexpr_t* keyexpr = z_sample_keyexpr(sample);
    z_view_string_t keyexpr_str;
    z_keyexpr_as_view_string(keyexpr, &keyexpr_str);
    const char* ke_cstr = z_string_data(z_loan(keyexpr_str));

    // Extract payload
    const z_loaned_bytes_t* payload_bytes = z_sample_payload(sample);
    z_bytes_reader_t reader = z_bytes_get_reader(payload_bytes);

    // Get payload length and data
    size_t payload_len = z_bytes_len(payload_bytes);
    uint8_t* payload_data = NULL;

    if (payload_len > 0) {
        payload_data = (uint8_t*)malloc(payload_len);
        if (!payload_data) {
            // Memory allocation failed, skip callback
            return;
        }
        z_bytes_reader_read(&reader, payload_data, payload_len);
    }

    // Extract attachment if present
    const z_loaned_bytes_t* attachment_bytes = z_sample_attachment(sample);
    uint8_t* attachment_data = NULL;
    size_t attachment_len = 0;

    if (attachment_bytes) {
        attachment_len = z_bytes_len(attachment_bytes);
        if (attachment_len > 0) {
            attachment_data = (uint8_t*)malloc(attachment_len);
            if (!attachment_data) {
                // Attachment malloc failed, but we can still invoke callback without attachment
                attachment_len = 0;
            } else {
                z_bytes_reader_t att_reader = z_bytes_get_reader(attachment_bytes);
                z_bytes_reader_read(&att_reader, attachment_data, attachment_len);
            }
        }
    }

    // Invoke user callback
    sub->callback(ke_cstr, payload_data, payload_len,
                  attachment_data, attachment_len, sub->context);

    // Cleanup
    if (payload_data) free(payload_data);
    if (attachment_data) free(attachment_data);
}

zenoh_result_t zenoh_declare_subscriber(zenoh_session_t* session,
                                        const char* keyexpr_str,
                                        zenoh_subscriber_callback_t callback,
                                        void* context,
                                        zenoh_subscriber_t** out_subscriber) {
    if (!session || !keyexpr_str || !callback || !out_subscriber) {
        return -1;
    }

    zenoh_subscriber_t* sub = (zenoh_subscriber_t*)malloc(sizeof(zenoh_subscriber_t));
    if (!sub) {
        return -1;
    }

    sub->callback = callback;
    sub->context = context;

    // Create a view keyexpr from string
    z_view_keyexpr_t view_ke;
    if (z_view_keyexpr_from_str(&view_ke, keyexpr_str) < 0) {
        free(sub);
        return -1;
    }

    // Create closure for the callback
    z_owned_closure_sample_t closure;
    z_closure(&closure, zenoh_sample_handler, NULL, sub);

    // Declare subscriber
    z_subscriber_options_t options;
    z_subscriber_options_default(&options);

    if (z_declare_subscriber(z_loan(session->session), &sub->subscriber,
                             z_loan(view_ke), z_move(closure), &options) < 0) {
        free(sub);
        return -1;
    }

    *out_subscriber = sub;
    return 0;
}

zenoh_result_t zenoh_undeclare_subscriber(zenoh_session_t* session,
                                          zenoh_subscriber_t** subscriber) {
    if (!session || !subscriber || !*subscriber) {
        return -1;
    }

    zenoh_subscriber_t* sub = *subscriber;

    // Undeclare the subscriber
    z_undeclare_subscriber(z_move(sub->subscriber));

    free(sub);
    *subscriber = NULL;

    return 0;
}

// ============================================================================
// Liveliness tokens (for ROS 2 discovery)
// ============================================================================

zenoh_result_t zenoh_declare_liveliness_token(zenoh_session_t* session,
                                              const char* key_expr,
                                              zenoh_liveliness_token_t** out_token) {
    os_log_t log = os_log_create("com.youtalk.swift-ros2", "zenoh");

    if (!session || !key_expr || !out_token) {
        os_log_error(log, "[zenoh_bridge] declare_liveliness_token: Invalid parameters");
        return -1;
    }

    os_log_info(log, "[zenoh_bridge] Declaring liveliness token: %s", key_expr);

    // Allocate token wrapper
    zenoh_liveliness_token_t* token = (zenoh_liveliness_token_t*)malloc(sizeof(zenoh_liveliness_token_t));
    if (!token) {
        os_log_error(log, "[zenoh_bridge] ERROR: Failed to allocate liveliness token");
        return -1;
    }

    // Create key expression view
    z_view_keyexpr_t view_ke;
    int ret = z_view_keyexpr_from_str(&view_ke, key_expr);
    if (ret < 0) {
        os_log_error(log, "[zenoh_bridge] ERROR: Invalid key expression, ret=%d", ret);
        free(token);
        return -1;
    }

    // Declare liveliness token using proper API
    z_liveliness_token_options_t options;
    z_liveliness_token_options_default(&options);

    ret = z_liveliness_declare_token(
        z_loan(session->session),
        &token->token,
        z_loan(view_ke),
        &options
    );

    if (ret < 0) {
        os_log_error(log, "[zenoh_bridge] ERROR: Failed to declare liveliness token, ret=%d", ret);
        free(token);
        return -1;
    }

    os_log_info(log, "[zenoh_bridge] Liveliness token declared successfully");
    *out_token = token;
    return 0;
}

zenoh_result_t zenoh_undeclare_liveliness_token(zenoh_session_t* session,
                                                zenoh_liveliness_token_t** token) {
    if (!session || !token || !*token) {
        return -1;
    }

    zenoh_liveliness_token_t* t = *token;

    // Undeclare the liveliness token
    z_liveliness_undeclare_token(z_move(t->token));

    free(t);
    *token = NULL;

    return 0;
}

// ============================================================================
// Utility functions
// ============================================================================

const char* zenoh_result_str(zenoh_result_t result) {
    if (result == 0) {
        return "Success";
    } else if (result == -1) {
        return "Generic error";
    } else {
        return "Unknown error";
    }
}
