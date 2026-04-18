//
// raw_cdr_regression_bridge.c
// Thin wrappers that expose raw_cdr_sertype/serdata to Swift regression
// tests without leaking CycloneDDS ddsi internal headers (which clash with
// Foundation.Data).
//

#include "raw_cdr_regression_bridge.h"

#ifdef DDS_AVAILABLE

#include "raw_cdr_sertype.h"
#include <dds/ddsi/ddsi_sertype.h>
#include <dds/ddsi/ddsi_serdata.h>

raw_cdr_regression_sertype_t *raw_cdr_regression_sertype_new(const char *type_name)
{
    return (raw_cdr_regression_sertype_t *)raw_cdr_sertype_new(type_name);
}

void raw_cdr_regression_sertype_unref(raw_cdr_regression_sertype_t *sertype)
{
    if (sertype != NULL) {
        ddsi_sertype_unref((struct ddsi_sertype *)sertype);
    }
}

raw_cdr_regression_serdata_t *raw_cdr_regression_serdata_new(
    raw_cdr_regression_sertype_t *sertype,
    const uint8_t *cdr_data,
    size_t cdr_len,
    int64_t timestamp)
{
    if (sertype == NULL) {
        return NULL;
    }
    return (raw_cdr_regression_serdata_t *)raw_cdr_serdata_new(
        (const struct ddsi_sertype *)sertype,
        cdr_data,
        cdr_len,
        (dds_time_t)timestamp);
}

void raw_cdr_regression_serdata_unref(raw_cdr_regression_serdata_t *serdata)
{
    if (serdata != NULL) {
        ddsi_serdata_unref((struct ddsi_serdata *)serdata);
    }
}

#endif // DDS_AVAILABLE
