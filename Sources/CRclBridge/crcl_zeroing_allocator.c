// crcl_zeroing_allocator.c
// A zero-filling rcutils allocator for rmw_serialized_message buffers (#162).
//
// rmw serializers skip interior CDR alignment padding without writing it, so
// a malloc-backed buffer leaks uninitialized heap bytes into the message and
// makes the serialized bytes non-deterministic. Every byte this allocator
// hands out — including the tail added by reallocate — is zero. A 16-byte
// size header in front of each block lets reallocate zero exactly the grown
// region without platform-specific malloc_size()/malloc_usable_size().

#include "crcl_internal.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    size_t size;
    size_t reserved;  // keeps the user pointer 16-byte aligned
} crcl_zalloc_header_t;

static void *crcl__zalloc_allocate(size_t size, void *state) {
    (void)state;
    crcl_zalloc_header_t *h = calloc(1, sizeof(*h) + size);
    if (!h) {
        return NULL;
    }
    h->size = size;
    return h + 1;
}

static void crcl__zalloc_deallocate(void *pointer, void *state) {
    (void)state;
    if (pointer) {
        free((crcl_zalloc_header_t *)pointer - 1);
    }
}

static void *crcl__zalloc_reallocate(void *pointer, size_t size, void *state) {
    if (!pointer) {
        return crcl__zalloc_allocate(size, state);
    }
    crcl_zalloc_header_t *old = (crcl_zalloc_header_t *)pointer - 1;
    size_t old_size = old->size;
    crcl_zalloc_header_t *h = realloc(old, sizeof(*h) + size);
    if (!h) {
        return NULL;
    }
    if (size > old_size) {
        memset((uint8_t *)(h + 1) + old_size, 0, size - old_size);
    }
    h->size = size;
    return h + 1;
}

static void *crcl__zalloc_zero_allocate(size_t count, size_t size, void *state) {
    if (size != 0 && count > SIZE_MAX / size) {
        return NULL;
    }
    return crcl__zalloc_allocate(count * size, state);
}

rcutils_allocator_t crcl__zeroing_allocator(void) {
    rcutils_allocator_t a = rcutils_get_zero_initialized_allocator();
    a.allocate = crcl__zalloc_allocate;
    a.deallocate = crcl__zalloc_deallocate;
    a.reallocate = crcl__zalloc_reallocate;
    a.zero_allocate = crcl__zalloc_zero_allocate;
    a.state = NULL;
    return a;
}
