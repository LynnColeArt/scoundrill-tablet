#ifndef ZIGGIFY_H
#define ZIGGIFY_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
#define ZIGGIFY_ABI_VERSION 1
#define ZIGGIFY_MAX_BYTES (16u * 1024u * 1024u)
enum ziggify_status { ZIGGIFY_OK=0, ZIGGIFY_INVALID_INPUT=1, ZIGGIFY_DOMAIN_ERROR=2, ZIGGIFY_OOM=3, ZIGGIFY_CANCELED=4, ZIGGIFY_TOO_LARGE=5, ZIGGIFY_INVALID_HANDLE=6, ZIGGIFY_UNPORTED=7 };
/* Initialize with {0}; exclusively own each returned result until release.
   data is borrowed and valid only until release. Never free it with libc.
   release uses the registered owner ID, never the caller's pointer or length.
   A repeated release on the same cleared struct is a no-op. Stale owner IDs are
   rejected. All pointers passed into this C ABI must address valid live memory. */
typedef struct { const uint8_t *data; size_t len; uint64_t owner; } ziggify_result;
uint32_t ziggify_abi_version(void);
uint32_t ziggify_call(const uint8_t *input, size_t length, uint64_t cancellation, ziggify_result *output);
uint32_t ziggify_release(ziggify_result *output);
uint64_t ziggify_cancel_new(void);
uint32_t ziggify_cancel(uint64_t handle);
uint32_t ziggify_cancel_free(uint64_t handle);
size_t ziggify_live_allocations(void);
#ifdef __cplusplus
}
#endif
#endif
