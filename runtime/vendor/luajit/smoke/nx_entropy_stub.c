#include <stddef.h>

/* Build-only placeholder. Replace with libnx CSRNG in the injected runtime. */
int luaJIT_nx_getentropy(void *buf, size_t len) {
  (void)buf;
  (void)len;
  return -1;
}
