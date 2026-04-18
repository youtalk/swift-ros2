//
// raw_cdr_regression_bridge.h
// Opaque Swift-visible wrappers for raw_cdr_sertype/serdata regression tests.
//
// The underlying raw_cdr_sertype.h pulls in CycloneDDS ddsi internals that
// collide with Foundation types (notably ddsi's `Data` struct), so Swift
// test code goes through these opaque wrappers instead.
//

#ifndef RAW_CDR_REGRESSION_BRIDGE_H
#define RAW_CDR_REGRESSION_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef DDS_AVAILABLE

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque handle for a raw_cdr sertype (wraps struct ddsi_sertype *).
typedef struct raw_cdr_regression_sertype_s raw_cdr_regression_sertype_t;

/// Opaque handle for a raw_cdr serdata (wraps struct ddsi_serdata *).
typedef struct raw_cdr_regression_serdata_s raw_cdr_regression_serdata_t;

/// Create a raw CDR sertype for regression tests. Returns NULL on failure.
raw_cdr_regression_sertype_t *raw_cdr_regression_sertype_new(const char *type_name);

/// Release a sertype reference obtained via raw_cdr_regression_sertype_new.
void raw_cdr_regression_sertype_unref(raw_cdr_regression_sertype_t *sertype);

/// Create a raw CDR serdata. Returns NULL on failure or too-small cdr_len.
raw_cdr_regression_serdata_t *raw_cdr_regression_serdata_new(
    raw_cdr_regression_sertype_t *sertype,
    const uint8_t *cdr_data,
    size_t cdr_len,
    int64_t timestamp
);

/// Release a serdata reference obtained via raw_cdr_regression_serdata_new.
void raw_cdr_regression_serdata_unref(raw_cdr_regression_serdata_t *serdata);

#ifdef __cplusplus
}
#endif

#endif // DDS_AVAILABLE

#endif // RAW_CDR_REGRESSION_BRIDGE_H
