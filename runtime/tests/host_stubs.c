#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

typedef struct { uint32_t seed, shift[3]; } LuaRng;

void L_DebugString(const char* message) { (void)message; }
void L_EnableCallback(unsigned int callback) { (void)callback; }
int LL_Isaac__GetFrameCount(void) { return 1; }

#define NAME_LOOKUP(symbol) int symbol(const char* name) { return name ? 1 : 0; }
NAME_LOOKUP(LL_Isaac__GetEntityTypeByName)
NAME_LOOKUP(LL_Isaac__GetEntityVariantByName)
NAME_LOOKUP(LL_Isaac__GetItemIdByName)
NAME_LOOKUP(LL_Isaac__GetPlayerTypeByName)
NAME_LOOKUP(LL_Isaac__GetCardIdByName)
NAME_LOOKUP(LL_Isaac__GetPillEffectByName)
NAME_LOOKUP(LL_Isaac__GetTrinketIdByName)
NAME_LOOKUP(LL_Isaac__GetChallengeIdByName)
NAME_LOOKUP(LL_Isaac__GetCostumeIdByPath)
NAME_LOOKUP(LL_Isaac__GetCurseIdByName)
NAME_LOOKUP(LL_Isaac__GetSoundIdByName)

void LC_RNG__SetSeed(LuaRng* rng, unsigned int seed, unsigned int shift) {
    if (rng) {
        rng->seed = seed;
        rng->shift[0] = shift;
        rng->shift[1] = 7;
        rng->shift[2] = 17;
    }
}
unsigned int LC_RNG__Next(LuaRng* rng) {
    if (!rng) return 0;
    rng->seed ^= rng->seed >> (rng->shift[0] & 31);
    rng->seed ^= rng->seed << (rng->shift[1] & 31);
    rng->seed ^= rng->seed >> (rng->shift[2] & 31);
    return rng->seed;
}
unsigned int LC_RNG__RandomInt(LuaRng* rng, unsigned int maximum) {
    const unsigned int value = LC_RNG__Next(rng);
    return maximum ? value % maximum : 0;
}
float LC_RNG__RandomFloat(LuaRng* rng) {
    return (float)LC_RNG__Next(rng) / 4294967295.0f;
}
