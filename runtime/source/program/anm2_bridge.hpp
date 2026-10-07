#pragma once

#include <cstddef>

namespace isaac_port::anm2 {

/* ANM2::IsPlaying is a const method with the ordinary AArch64 contract:
 * x0=this, x1=animation name, w0=bool.  Keep the call boundary small and
 * independently testable; the Switch wrapper supplies the mapping checks. */
using IsPlayingNative = bool (*)(void*, const char*);

inline bool InvokeIsPlaying(void* object, const char* animation,
                            IsPlayingNative native, bool object_mapped,
                            bool name_mapped) {
    if (!object || !native || !object_mapped || !name_mapped)
        return false;
    return native(object, animation ? animation : "");
}

} // namespace isaac_port::anm2
