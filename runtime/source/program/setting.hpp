#pragma once

#include "common.hpp"

#define EXL_MODULE_NAME "isaac-port"

#define EXL_DEBUG
#define EXL_USE_FAKEHEAP

namespace exl::setting {
    /* LuaJIT's Horizon allocator needs more than exlaunch's tiny demo heap. */
    constexpr size_t HeapSize = 0x400000;
    constexpr size_t JitSize = 0x1000;
    constexpr size_t InlinePoolSize = 0x1000;
    constexpr size_t LogBufferSize = 512;

    static_assert(ALIGN_UP(JitSize, PAGE_SIZE) == JitSize, "");
    static_assert(ALIGN_UP(InlinePoolSize, PAGE_SIZE) == InlinePoolSize, "");
}
