#include <stddef.h>
#include <stdint.h>
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

static int nx_answer(int value) {
  return value + 41;
}

/* Horizon resolver table: no dlopen/dlsym and no arbitrary libraries. */
void *luaJIT_nx_resolve(const char *name) {
  if (name[0] == 'n' && name[1] == 'x' && name[2] == '_' &&
      name[3] == 'a' && name[4] == 'n' && name[5] == 's' &&
      name[6] == 'w' && name[7] == 'e' && name[8] == 'r' &&
      name[9] == '\0')
    return (void *)&nx_answer;
  return 0;
}

int main(void) {
  lua_State *L = luaL_newstate();
  if (!L) return 1;
  luaL_openlibs(L);
  if (luaL_dostring(L,
      "local ffi = require('ffi')\n"
      "ffi.cdef[[int nx_answer(int);]]\n"
      "assert(ffi.C.nx_answer(1) == 42)\n") != 0) {
    lua_close(L);
    return 2;
  }
  lua_close(L);
  return 0;
}
