// LD_PRELOAD malloc counter (glibc): counts calls and requested bytes; read via mcount_get().
// Build: clang -O2 -shared -fPIC malloccount.c -o libmalloccount.so
#define _GNU_SOURCE
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
extern void *__libc_malloc(size_t), *__libc_calloc(size_t, size_t), *__libc_realloc(void *, size_t);
extern void *__libc_memalign(size_t, size_t);
extern void __libc_free(void *);
static uint64_t n_alloc, n_free, n_bytes;
void mcount_get(uint64_t out[3]) { out[0] = n_alloc; out[1] = n_free; out[2] = n_bytes; }
void *malloc(size_t n) { n_alloc++; n_bytes += n; return __libc_malloc(n); }
void *calloc(size_t a, size_t b) { n_alloc++; n_bytes += a * b; return __libc_calloc(a, b); }
void *realloc(void *p, size_t n) { n_alloc++; n_bytes += n; return __libc_realloc(p, n); }
void free(void *p) { if (p) n_free++; __libc_free(p); }
void *aligned_alloc(size_t al, size_t n) { n_alloc++; n_bytes += n; return __libc_memalign(al, n); }
void *memalign(size_t al, size_t n) { n_alloc++; n_bytes += n; return __libc_memalign(al, n); }
int posix_memalign(void **r, size_t al, size_t n) {
    n_alloc++; n_bytes += n; void *p = __libc_memalign(al, n); if (!p) return ENOMEM; *r = p; return 0;
}
