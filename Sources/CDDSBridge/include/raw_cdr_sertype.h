//
// raw_cdr_sertype.h
// Custom sertype/serdata for raw CDR data publishing
//
// This implementation allows publishing pre-serialized CDR data directly
// via CycloneDDS without requiring a schema-based topic descriptor.
// It implements the ddsi_sertype and ddsi_serdata interfaces.
//

#ifndef RAW_CDR_SERTYPE_H
#define RAW_CDR_SERTYPE_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef DDS_AVAILABLE

#include <dds/dds.h>
#include <dds/ddsi/ddsi_sertype.h>
#include <dds/ddsi/ddsi_serdata.h>

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// MARK: - Raw CDR Sertype
// =============================================================================

/// Custom sertype for raw CDR data
/// Extends ddsi_sertype with no additional fields (type name is stored in base)
struct raw_cdr_sertype {
    struct ddsi_sertype c;  // Base sertype (must be first member)
};

// =============================================================================
// MARK: - Raw CDR Serdata
// =============================================================================

/// Custom serdata for raw CDR data
/// Contains the pre-serialized CDR data including the 4-byte encapsulation header
struct raw_cdr_serdata {
    struct ddsi_serdata c;   // Base serdata (must be first member)
    size_t cdr_size;         // Size of CDR data including 4-byte header
    uint8_t cdr_data[];      // Flexible array member for CDR data
};

// =============================================================================
// MARK: - Sertype Operations
// =============================================================================

/// Operations table for raw CDR sertype
extern const struct ddsi_sertype_ops raw_cdr_sertype_ops;

/// Operations table for raw CDR serdata
extern const struct ddsi_serdata_ops raw_cdr_serdata_ops;

// =============================================================================
// MARK: - Factory Functions
// =============================================================================

/// Create a new raw CDR sertype
///
/// @param type_name The DDS type name (e.g., "sensor_msgs::msg::dds_::Imu_")
/// @return Newly allocated sertype, or NULL on failure
///         Caller is responsible for calling ddsi_sertype_unref when done
struct ddsi_sertype *raw_cdr_sertype_new(const char *type_name);

/// Create a new raw CDR serdata from pre-serialized CDR data
///
/// @param type The sertype this serdata belongs to
/// @param cdr_data Pre-serialized CDR data (must include 4-byte encapsulation header)
/// @param cdr_len Length of CDR data in bytes
/// @param timestamp Timestamp in nanoseconds since Unix epoch
/// @return Newly allocated serdata with refcount=1, or NULL on failure
///         Caller is responsible for calling ddsi_serdata_unref when done
struct ddsi_serdata *raw_cdr_serdata_new(
    const struct ddsi_sertype *type,
    const uint8_t *cdr_data,
    size_t cdr_len,
    dds_time_t timestamp
);

/// Initialize a raw CDR sertype (for use when sertype is embedded in another struct)
///
/// @param st Pointer to sertype structure to initialize
/// @param type_name The DDS type name
/// @return true on success, false on failure
bool raw_cdr_sertype_init(struct raw_cdr_sertype *st, const char *type_name);

/// Finalize a raw CDR sertype (for use when sertype is embedded in another struct)
///
/// @param st Pointer to sertype structure to finalize
void raw_cdr_sertype_fini(struct raw_cdr_sertype *st);

#ifdef __cplusplus
}
#endif

#endif // DDS_AVAILABLE

#endif // RAW_CDR_SERTYPE_H
