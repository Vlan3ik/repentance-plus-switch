#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

typedef struct { uint32_t seed, shift[3]; } LuaRng;

/* Stable fake handles used by the focused Lua compatibility smoke.  They
 * intentionally exercise the same borrowed-pointer and resolver ABI as the
 * Switch compatibility chunk, without pretending to model a live engine. */
static unsigned char g_host_player[64] __attribute__((aligned(16)));
static unsigned char g_host_effects[48] __attribute__((aligned(16)));

void* LL_Isaac__GetPlayer(int id) {
    (void)id;
    return g_host_player;
}
int LC_Entity__GetType(void* entity) {
    return entity == g_host_player ? 1 : 0;
}
int LC_Entity__GetRef(void* entity) {
    (void)entity;
    return 0;
}
void LC_Entity__SetRef(void* entity, int ref) {
    (void)entity;
    (void)ref;
}
void* LC_Entity_Player__GetEffects(void* player) {
    return player == g_host_player ? g_host_effects : NULL;
}
bool LC_TemporaryEffects__HasCollectibleEffect(void* effects,
                                                unsigned int collectible) {
    return effects == g_host_effects && collectible == 42u;
}
unsigned int LC_TemporaryEffects__GetCollectibleEffectNum(
    void* effects, unsigned int collectible) {
    return effects == g_host_effects && collectible == 42u ? 3u : 0u;
}

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
