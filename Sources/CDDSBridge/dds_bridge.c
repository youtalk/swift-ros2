//
// dds_bridge.c
// C-FFI bridge for CycloneDDS
//
// Implementation of the DDS bridge that wraps CycloneDDS functionality
// for use from Swift via C-FFI.
//

#include "dds_bridge.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#include <dispatch/dispatch.h>

// Only compile CycloneDDS implementation when available
#ifdef DDS_AVAILABLE
#include <dds/dds.h>
#include <dds/ddsc/dds_opcodes.h>
#include "raw_cdr_sertype.h"
#endif

// =============================================================================
// MARK: - Thread-Local Error Storage
// =============================================================================

#ifdef _Thread_local
#define THREAD_LOCAL _Thread_local
#elif defined(__GNUC__) || defined(__clang__)
#define THREAD_LOCAL __thread
#else
#define THREAD_LOCAL
#endif

static THREAD_LOCAL char g_last_error[512] = {0};

static void set_error(const char* format, ...) {
    va_list args;
    va_start(args, format);
    vsnprintf(g_last_error, sizeof(g_last_error), format, args);
    va_end(args);
}

const char* dds_bridge_get_last_error(void) {
    return g_last_error;
}

void dds_bridge_clear_error(void) {
    g_last_error[0] = '\0';
}

// =============================================================================
// MARK: - Version and Availability
// =============================================================================

const char* dds_bridge_get_version(void) {
#ifdef DDS_AVAILABLE
    // CycloneDDS version is defined at build time
    return "0.10.5";  // Matches deps/cyclonedds tag
#else
    return "unavailable";
#endif
}

bool dds_bridge_is_available(void) {
#ifdef DDS_AVAILABLE
    return true;
#else
    return false;
#endif
}

// =============================================================================
// MARK: - Session Structure
// =============================================================================

struct bridge_dds_session_s {
#ifdef DDS_AVAILABLE
    dds_entity_t domain;
    dds_entity_t participant;
    dds_entity_t publisher;
#else
    int dummy_domain;
    int dummy_participant;
    int dummy_publisher;
#endif
    int32_t domain_id;
    char session_id[33];  // 32 hex chars + null terminator
    bool is_connected;
};

// =============================================================================
// MARK: - Writer Structure
// =============================================================================

struct bridge_dds_writer_s {
#ifdef DDS_AVAILABLE
    dds_entity_t writer;
    dds_entity_t topic;
    struct ddsi_sertype* raw_sertype;  // For raw CDR writers (NULL for standard writers)
#else
    int dummy_writer;
    int dummy_topic;
#endif
    bridge_dds_session_t* session;
    char topic_name[256];
    bool is_active;
    bool is_raw_cdr;  // True if using raw CDR sertype
};

// =============================================================================
// MARK: - Session Management Implementation
// =============================================================================

// Track whether a domain has been created for this process.
// CycloneDDS domains are shared per domain_id - once created, the config
// applies to all participants. Multiple sessions share the same domain.
#ifdef DDS_AVAILABLE
static bool g_domain_created = false;
static int32_t g_domain_id = -1;
#endif

#ifdef DDS_AVAILABLE
/// Build XML configuration string for CycloneDDS domain
/// Returns a malloc'd string that must be freed by the caller
static char* build_domain_config_xml(int32_t domain_id, const bridge_discovery_config_t* config) {
    // Buffer for XML configuration
    char* xml = malloc(8192);
    if (!xml) {
        return NULL;
    }

    // Start building XML
    int offset = 0;
    offset += snprintf(xml + offset, 8192 - offset,
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        "<CycloneDDS xmlns=\"https://cdds.io/config\">\n"
        "  <Domain id=\"%d\">\n",
        domain_id);

    // Add discovery configuration
    if (config && (config->unicast_peers && config->peer_count > 0)) {
        offset += snprintf(xml + offset, 8192 - offset,
            "    <Discovery>\n"
            "      <Peers>\n");

        // Add each peer
        for (int i = 0; i < config->peer_count; i++) {
            offset += snprintf(xml + offset, 8192 - offset,
                "        <Peer address=\"%s\"/>\n",
                config->unicast_peers[i]);
        }

        offset += snprintf(xml + offset, 8192 - offset,
            "      </Peers>\n");

        // Disable multicast SPDP if in unicast-only mode
        if (config->mode == BRIDGE_DISCOVERY_UNICAST) {
            offset += snprintf(xml + offset, 8192 - offset,
                "      <EnableTopicDiscoveryEndpoints>true</EnableTopicDiscoveryEndpoints>\n");
        }

        // Faster SPDP discovery for mobile devices (default is 30s)
        offset += snprintf(xml + offset, 8192 - offset,
            "      <SPDPInterval>1s</SPDPInterval>\n");

        offset += snprintf(xml + offset, 8192 - offset,
            "    </Discovery>\n");
    }

    // General configuration: network interface + large message support
    offset += snprintf(xml + offset, 8192 - offset,
        "    <General>\n");

    // Network interface binding
    if (config && config->network_interface && strlen(config->network_interface) > 0) {
        offset += snprintf(xml + offset, 8192 - offset,
            "      <Interfaces>\n"
            "        <NetworkInterface name=\"%s\"/>\n"
            "      </Interfaces>\n",
            config->network_interface);
    }

    // Keep default MaxMessageSize (14720B) and FragmentSize (1344B).
    // Large payloads like camera images are automatically fragmented at
    // the DDS level by CycloneDDS's RTPS fragmentation (DATA_FRAG).
    offset += snprintf(xml + offset, 8192 - offset,
        "    </General>\n");

    // Close XML
    snprintf(xml + offset, 8192 - offset,
        "  </Domain>\n"
        "</CycloneDDS>\n");

    return xml;
}
#endif

bridge_dds_session_t* dds_bridge_create_session(
    int32_t domain_id,
    const bridge_discovery_config_t* discovery_config
) {
    // Validate domain ID
    if (domain_id < 0 || domain_id > 232) {
        set_error("Invalid domain ID: %d (must be 0-232)", domain_id);
        return NULL;
    }

    // Allocate session structure
    bridge_dds_session_t* session = calloc(1, sizeof(bridge_dds_session_t));
    if (!session) {
        set_error("Failed to allocate session structure");
        return NULL;
    }

    session->domain_id = domain_id;
    session->is_connected = false;

#ifdef DDS_AVAILABLE
    // Build XML configuration for discovery peers
    char* config_xml = build_domain_config_xml(domain_id, discovery_config);
    if (config_xml) {
        // Create domain with XML configuration only if not yet created or domain ID changed.
        // CycloneDDS domains are shared: all participants with the same domain_id
        // use the same domain config. Only the first dds_create_domain() call applies
        // the config; subsequent calls for the same ID return an error (already exists).
        // This means domain config (NetworkInterface, MaxMessageSize, etc.) is fixed
        // for the lifetime of the process - changing it requires an app restart.
        if (!g_domain_created || g_domain_id != domain_id) {
            dds_entity_t domain = dds_create_domain(domain_id, config_xml);

            if (domain >= 0) {
                session->domain = domain;
                g_domain_created = true;
                g_domain_id = domain_id;
            }
        }

        free(config_xml);
    }

    // Create participant QoS with enclave USER_DATA (required by rmw_cyclonedds_cpp)
    dds_qos_t* ppant_qos = dds_create_qos();
    if (ppant_qos) {
        const char* enclave_data = "enclave=/;";
        dds_qset_userdata(ppant_qos, enclave_data, strlen(enclave_data));
    }

    // Create domain participant (will use the domain configuration we just set)
    session->participant = dds_create_participant(domain_id, ppant_qos, NULL);
    if (ppant_qos) {
        dds_delete_qos(ppant_qos);
    }
    if (session->participant < 0) {
        set_error("Failed to create participant: %s", dds_strretcode(session->participant));
        free(session);
        return NULL;
    }

    // Create publisher
    session->publisher = dds_create_publisher(session->participant, NULL, NULL);
    if (session->publisher < 0) {
        set_error("Failed to create publisher: %s", dds_strretcode(session->publisher));
        dds_delete(session->participant);
        free(session);
        return NULL;
    }

    // Get participant GUID for session ID
    dds_guid_t guid;
    if (dds_get_guid(session->participant, &guid) == 0) {
        // Convert GUID to hex string (first 16 bytes)
        for (int i = 0; i < 16; i++) {
            snprintf(session->session_id + (i * 2), 3, "%02x", guid.v[i]);
        }
    } else {
        // Fallback: generate random session ID
        for (int i = 0; i < 32; i++) {
            session->session_id[i] = "0123456789abcdef"[rand() % 16];
        }
    }
    session->session_id[32] = '\0';

    session->is_connected = true;
#else
    // Stub implementation for when CycloneDDS is not available
    (void)discovery_config;
    set_error("DDS not available - CycloneDDS not built");

    // Generate fake session ID for testing
    for (int i = 0; i < 32; i++) {
        session->session_id[i] = "0123456789abcdef"[rand() % 16];
    }
    session->session_id[32] = '\0';

    session->dummy_participant = 1;
    session->dummy_publisher = 1;
    session->is_connected = true;
#endif

    return session;
}

// Flag to control whether to skip participant deletion (workaround for hang issue)
// When true, participant is leaked but reconnection works
static bool g_skip_participant_delete = true;

void dds_bridge_destroy_session(bridge_dds_session_t* session) {
    if (!session) {
        return;
    }

#ifdef DDS_AVAILABLE
    // Delete publisher first
    if (session->publisher > 0) {
        dds_delete(session->publisher);
        session->publisher = 0;
    }

    // Participant deletion with timeout to avoid indefinite hang on iOS
    if (session->participant > 0) {
        if (g_skip_participant_delete) {
            session->participant = 0;
        } else {
            __block dds_return_t delete_result = -1;
            dds_entity_t participant_to_delete = session->participant;

            dispatch_semaphore_t sem = dispatch_semaphore_create(0);
            dispatch_queue_t dq = dispatch_queue_create(
                "com.conduit.dds.participant_delete", DISPATCH_QUEUE_SERIAL);

            dispatch_async(dq, ^{
                delete_result = dds_delete(participant_to_delete);
                dispatch_semaphore_signal(sem);
            });

            long timeout = dispatch_semaphore_wait(sem,
                dispatch_time(DISPATCH_TIME_NOW, 3LL * NSEC_PER_SEC));

            if (timeout != 0) {
                fprintf(stderr, "[DDS] WARNING: Participant deletion timed out, leaking entity %d\n",
                       (int)participant_to_delete);
                g_skip_participant_delete = true;
            }

            session->participant = 0;
        }
    }
#endif

    session->is_connected = false;
    free(session);
}

// API to control participant deletion behavior
void dds_bridge_set_skip_participant_delete(bool skip) {
    g_skip_participant_delete = skip;
}

bool dds_bridge_session_is_connected(const bridge_dds_session_t* session) {
    if (!session) {
        return false;
    }
    return session->is_connected;
}

int32_t dds_bridge_get_session_id(
    const bridge_dds_session_t* session,
    char* buffer,
    size_t buffer_size
) {
    if (!session || !buffer || buffer_size < 33) {
        set_error("Invalid parameters for dds_bridge_get_session_id");
        return -1;
    }

    strncpy(buffer, session->session_id, buffer_size - 1);
    buffer[buffer_size - 1] = '\0';
    return 0;
}

// =============================================================================
// MARK: - Writer Management Implementation
// =============================================================================

bridge_dds_writer_t* dds_bridge_create_writer(
    bridge_dds_session_t* session,
    const char* topic_name,
    const char* type_name,
    const bridge_qos_config_t* qos
) {
    if (!session || !topic_name || !type_name) {
        set_error("Invalid parameters for dds_bridge_create_writer");
        return NULL;
    }

    if (!session->is_connected) {
        set_error("Session is not connected");
        return NULL;
    }

    // Allocate writer structure
    bridge_dds_writer_t* writer = calloc(1, sizeof(bridge_dds_writer_t));
    if (!writer) {
        set_error("Failed to allocate writer structure");
        return NULL;
    }

    writer->session = session;
    strncpy(writer->topic_name, topic_name, sizeof(writer->topic_name) - 1);
    writer->is_active = false;
    writer->is_raw_cdr = false;

#ifdef DDS_AVAILABLE
    writer->raw_sertype = NULL;
    // Use default QoS if not specified
    const bridge_qos_config_t* effective_qos = qos ? qos : &BRIDGE_QOS_SENSOR_DATA;

    // Create topic descriptor for raw CDR data
    // We need a minimal valid ops array representing struct { octet data; }
    // Format: [ADR, TYPE_1BY, 0] [offset=0] [RTS]
    // DDS_OP_ADR = 0x01000000, DDS_OP_TYPE_1BY = 0x00010000
    static const uint32_t minimal_ops[] = {
        (0x01 << 24) | (0x01 << 16),  // DDS_OP_ADR | DDS_OP_TYPE_1BY
        0,                             // offset = 0
        0x00000000                     // DDS_OP_RTS
    };

    // Create descriptor with minimal valid ops
    // This represents struct { octet data; } - a single byte structure
    dds_topic_descriptor_t desc = {
        .m_size = 1,
        .m_align = 1,
        .m_flagset = DDS_TOPIC_NO_OPTIMIZE | DDS_TOPIC_FIXED_SIZE,
        .m_typename = type_name,
        .m_keys = NULL,
        .m_nkeys = 0,
        .m_ops = minimal_ops,
        .m_nops = 3
    };

    // Create topic
    writer->topic = dds_create_topic(
        session->participant,
        &desc,
        topic_name,
        NULL,
        NULL
    );

    if (writer->topic < 0) {
        set_error("Failed to create topic '%s': %s", topic_name, dds_strretcode(writer->topic));
        free(writer);
        return NULL;
    }

    // Create writer QoS
    dds_qos_t* writer_qos = dds_create_qos();
    if (!writer_qos) {
        set_error("Failed to create writer QoS");
        dds_delete(writer->topic);
        free(writer);
        return NULL;
    }

    // Set reliability
    if (effective_qos->reliability == BRIDGE_RELIABILITY_RELIABLE) {
        dds_qset_reliability(writer_qos, DDS_RELIABILITY_RELIABLE, DDS_MSECS(100));
    } else {
        dds_qset_reliability(writer_qos, DDS_RELIABILITY_BEST_EFFORT, 0);
    }

    // Set durability
    if (effective_qos->durability == BRIDGE_DURABILITY_TRANSIENT_LOCAL) {
        dds_qset_durability(writer_qos, DDS_DURABILITY_TRANSIENT_LOCAL);
    } else {
        dds_qset_durability(writer_qos, DDS_DURABILITY_VOLATILE);
    }

    // Set history
    if (effective_qos->history_kind == BRIDGE_HISTORY_KEEP_ALL) {
        dds_qset_history(writer_qos, DDS_HISTORY_KEEP_ALL, 0);
    } else {
        dds_qset_history(writer_qos, DDS_HISTORY_KEEP_LAST, effective_qos->history_depth);
    }

    // Create writer
    writer->writer = dds_create_writer(session->publisher, writer->topic, writer_qos, NULL);
    dds_delete_qos(writer_qos);

    if (writer->writer < 0) {
        set_error("Failed to create writer for topic '%s': %s",
                  topic_name, dds_strretcode(writer->writer));
        dds_delete(writer->topic);
        free(writer);
        return NULL;
    }

    writer->is_active = true;
#else
    // Stub implementation
    (void)qos;
    writer->dummy_writer = 1;
    writer->dummy_topic = 1;
    writer->is_active = true;
#endif

    return writer;
}

void dds_bridge_destroy_writer(bridge_dds_writer_t* writer) {
    if (!writer) {
        return;
    }

#ifdef DDS_AVAILABLE
    if (writer->writer > 0) {
        dds_delete(writer->writer);
        writer->writer = 0;
    }
    if (writer->topic > 0) {
        dds_delete(writer->topic);
        writer->topic = 0;
    }
    writer->raw_sertype = NULL;
#endif

    free(writer);
}

bool dds_bridge_writer_is_active(const bridge_dds_writer_t* writer) {
    if (!writer) {
        return false;
    }
    return writer->is_active;
}

// =============================================================================
// MARK: - Publishing Implementation
// =============================================================================

int32_t dds_bridge_write_cdr(
    bridge_dds_writer_t* writer,
    const uint8_t* cdr_data,
    size_t cdr_len,
    uint64_t timestamp_ns
) {
    if (!writer || !cdr_data || cdr_len == 0) {
        set_error("Invalid parameters for dds_bridge_write_cdr");
        return -1;
    }

    if (!writer->is_active) {
        set_error("Writer is not active");
        return -2;
    }

#ifdef DDS_AVAILABLE
    // Verify CDR data has encapsulation header
    if (cdr_len < 4) {
        set_error("CDR data too short (missing encapsulation header)");
        return -3;
    }

    // Write pre-serialized CDR data
    // Note: CycloneDDS requires using dds_write_ts for timestamped data
    // The timestamp is set via the source timestamp
    dds_time_t timestamp = (dds_time_t)timestamp_ns;

    // Set source timestamp
    // Note: This may require a custom serdata implementation for full control
    dds_return_t ret = dds_write_ts(writer->writer, cdr_data, timestamp);

    if (ret < 0) {
        set_error("Failed to write CDR data: %s", dds_strretcode(ret));
        return -4;
    }

    return 0;
#else
    // Stub implementation - just validate parameters
    (void)timestamp_ns;
    return 0;
#endif
}

// =============================================================================
// MARK: - Raw CDR Publishing Implementation
// =============================================================================

bridge_dds_writer_t* dds_bridge_create_raw_writer(
    bridge_dds_session_t* session,
    const char* topic_name,
    const char* type_name,
    const bridge_qos_config_t* qos,
    const char* user_data
) {
    if (!session || !topic_name || !type_name) {
        set_error("Invalid parameters for dds_bridge_create_raw_writer");
        return NULL;
    }

    if (!session->is_connected) {
        set_error("Session is not connected");
        return NULL;
    }

    // Allocate writer structure
    bridge_dds_writer_t* writer = calloc(1, sizeof(bridge_dds_writer_t));
    if (!writer) {
        set_error("Failed to allocate writer structure");
        return NULL;
    }

    writer->session = session;
    strncpy(writer->topic_name, topic_name, sizeof(writer->topic_name) - 1);
    writer->is_active = false;
    writer->is_raw_cdr = true;  // Mark as raw CDR writer

#ifdef DDS_AVAILABLE
    // Use default QoS if not specified
    const bridge_qos_config_t* effective_qos = qos ? qos : &BRIDGE_QOS_SENSOR_DATA;

    // Create raw CDR sertype
    writer->raw_sertype = raw_cdr_sertype_new(type_name);
    if (!writer->raw_sertype) {
        set_error("Failed to create raw CDR sertype for '%s'", type_name);
        free(writer);
        return NULL;
    }

    // Create topic using raw CDR sertype
    // Note: dds_create_topic_sertype takes ownership of sertype reference,
    // and may replace the sertype pointer with an existing compatible one.
    // We add a reference before calling, and after the call we need to use
    // the (possibly updated) sertype pointer.
    struct ddsi_sertype* sertype_for_topic = ddsi_sertype_ref(writer->raw_sertype);
    writer->topic = dds_create_topic_sertype(
        session->participant,
        topic_name,
        &sertype_for_topic,
        NULL,  // qos
        NULL,  // listener
        NULL   // sedp_plist
    );

    if (writer->topic < 0) {
        set_error("Failed to create raw CDR topic '%s': %s", topic_name, dds_strretcode(writer->topic));
        ddsi_sertype_unref(writer->raw_sertype);
        free(writer);
        return NULL;
    }

    // If dds_create_topic_sertype returned a different sertype (because a matching
    // one was already registered), we need to use that one for creating serdata.
    // Release our original reference and use the one from topic creation.
    if (sertype_for_topic != writer->raw_sertype) {
        ddsi_sertype_unref(writer->raw_sertype);
        writer->raw_sertype = ddsi_sertype_ref(sertype_for_topic);
    }

    // Create writer QoS
    dds_qos_t* writer_qos = dds_create_qos();
    if (!writer_qos) {
        set_error("Failed to create writer QoS");
        dds_delete(writer->topic);
        ddsi_sertype_unref(writer->raw_sertype);
        free(writer);
        return NULL;
    }

    // Set reliability
    if (effective_qos->reliability == BRIDGE_RELIABILITY_RELIABLE) {
        dds_qset_reliability(writer_qos, DDS_RELIABILITY_RELIABLE, DDS_MSECS(100));
    } else {
        dds_qset_reliability(writer_qos, DDS_RELIABILITY_BEST_EFFORT, 0);
    }

    // Set durability
    if (effective_qos->durability == BRIDGE_DURABILITY_TRANSIENT_LOCAL) {
        dds_qset_durability(writer_qos, DDS_DURABILITY_TRANSIENT_LOCAL);
    } else {
        dds_qset_durability(writer_qos, DDS_DURABILITY_VOLATILE);
    }

    // Set history
    if (effective_qos->history_kind == BRIDGE_HISTORY_KEEP_ALL) {
        dds_qset_history(writer_qos, DDS_HISTORY_KEEP_ALL, 0);
    } else {
        dds_qset_history(writer_qos, DDS_HISTORY_KEEP_LAST, effective_qos->history_depth);
    }

    // Set USER_DATA QoS (type hash for rmw_cyclonedds_cpp discovery)
    if (user_data && strlen(user_data) > 0) {
        dds_qset_userdata(writer_qos, user_data, strlen(user_data));
    }

    // Create writer
    writer->writer = dds_create_writer(session->publisher, writer->topic, writer_qos, NULL);
    dds_delete_qos(writer_qos);

    if (writer->writer < 0) {
        set_error("Failed to create raw CDR writer for topic '%s': %s",
                  topic_name, dds_strretcode(writer->writer));
        dds_delete(writer->topic);
        ddsi_sertype_unref(writer->raw_sertype);
        free(writer);
        return NULL;
    }

    writer->is_active = true;
#else
    // Stub implementation
    (void)qos;
    (void)user_data;
    writer->dummy_writer = 1;
    writer->dummy_topic = 1;
    writer->is_active = true;
#endif

    return writer;
}

int32_t dds_bridge_write_raw_cdr(
    bridge_dds_writer_t* writer,
    const uint8_t* cdr_data,
    size_t cdr_len,
    uint64_t timestamp_ns
) {
    if (!writer || !cdr_data || cdr_len == 0) {
        set_error("Invalid parameters for dds_bridge_write_raw_cdr");
        return -1;
    }

    if (!writer->is_active) {
        set_error("Writer is not active");
        return -2;
    }

    if (!writer->is_raw_cdr) {
        set_error("Writer was not created as raw CDR writer");
        return -3;
    }

#ifdef DDS_AVAILABLE
    // Verify CDR data has encapsulation header
    if (cdr_len < 4) {
        set_error("CDR data too short (missing encapsulation header)");
        return -4;
    }

    if (writer->raw_sertype == NULL) {
        set_error("raw_sertype is NULL");
        return -10;
    }

    // Create raw CDR serdata
    dds_time_t timestamp = (dds_time_t)timestamp_ns;
    struct ddsi_serdata* serdata = raw_cdr_serdata_new(
        writer->raw_sertype,
        cdr_data,
        cdr_len,
        timestamp
    );

    if (!serdata) {
        set_error("Failed to create raw CDR serdata");
        return -5;
    }

    // Write using dds_writecdr (this takes ownership of serdata reference)
    dds_return_t ret = dds_writecdr(writer->writer, serdata);

    if (ret < 0) {
        set_error("Failed to write raw CDR data: %s", dds_strretcode(ret));
        // Note: dds_writecdr may not consume the reference on error
        // but in practice we shouldn't double-unref
        return -6;
    }

    return 0;
#else
    // Stub implementation - just validate parameters
    (void)timestamp_ns;
    return 0;
#endif
}
