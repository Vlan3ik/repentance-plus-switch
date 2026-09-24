# Repentance Plus → stock scripts_v2 native bridge

`cdefs.lua`: 544 unique declarations; stock binding references: 533; conservative closure required by the mod: **200** native functions.

## ABI family count

- `L_*`: 11
- `LC_*`: 123
- `LL_*`: 66

## What is directly covered

The closure is derived from `Isaac.*`, global constructors, and method names observed in the 53 Lua files, resolved against wrappers in `bindings.lua`/`main.lua`. Exact symbols and wrapper locations are in `native-bridge.json`.

## Exact public/global calls without a stock wrapper

- `Vector` (170)
- `AddCallback` (89)
- `Game` (88)
- `Sprite` (71)
- `EntityRef` (45)
- `SFXManager` (35)
- `Isaac.GetItemConfig` (29)
- `RNG` (10)
- `GetPtrHash` (6)
- `Isaac.GetRoomEntities` (6)
- `KColor` (5)
- `Font` (4)
- `Isaac.LoadModData` (3)
- `Isaac.SaveModData` (3)
- `Isaac.Explode` (2)
- `Isaac.GridSpawn` (2)

## Dynamic engine methods without a stock wrapper

- `*::GetData` (748)
- `*::addCollectible` (337)
- `*::addCard` (234)
- `*::GetEffects` (151)
- `*::GetOtherTwin` (150)
- `*::addTrinket` (126)
- `*::UpdateHealthMasks` (118)
- `*::GetSubPlayer` (88)
- `*::FindByType` (87)
- `*::GetInfoOfHealth` (81)
- `*::SetSeed` (74)
- `*::GetInfoOfKey` (70)
- `*::UpdateBasegameHealthState` (69)
- `*::PlayerIsIgnored` (63)
- `*::RandomInt` (56)
- `*::addEntity` (51)
- `*::GetCallbacks` (44)
- `*::addIcon` (40)
- `*::AddPriorityCallback` (39)
- `*::CheckHealthIsInitializedForPlayer` (39)
- `*::FromAngle` (39)
- `*::CheckSubPlayerInfoOfPlayer` (38)
- `*::CheckIfHealthOrderSet` (37)
- `*::CanPickKey` (36)
- `*::ResyncHealthOfPlayer` (34)
- `*::addCardMetadata` (33)
- `*::addPill` (33)
- `*::FindInRadius` (30)
- `*::GetItemConfig` (30)
- `*::GetItemPool` (29)
- `*::GetTotalMaxHP` (29)
- `*::Morph` (29)
- `*::FindFreePickupSpawnPosition` (28)
- `*::GetTotalKeys` (28)
- `*::GetTotalRedHP` (28)
- `*::Distance` (27)
- `*::AddPickup` (25)
- `*::GetCollectibleRNG` (25)
- `*::GetTotalSoulHP` (25)
- `*::GetLevel` (24)
- `*::GetTotalHP` (24)
- `*::ToPlayer` (24)
- `*::GetTotalBoneHP` (23)
- `*::AddIcon` (22)
- `*::CheckFamiliar` (22)
- `*::addGoldenTrinketMetadata` (22)
- `*::SaveSaveData` (20)
- `*::AddBasegameGoldenHealthWithoutModifiers` (17)
- `*::IsShopItem` (17)
- `*::IsFirstVisit` (16)
- `*::ToPickup` (16)
- `*::getDssSettings` (16)
- `*::GetAmountUnoccupiedContainers` (15)
- `*::GetHPOfKey` (15)
- `*::PlayerIsTheForgotten` (15)
- `*::GetRoomForOtherKeys` (13)
- `*::AnimateCollectible` (12)
- `*::GetBasegameBlackHeartsNum` (12)
- `*::GetPlayerIndex` (12)
- `*::AddBasegameEternalHealthWithoutModifiers` (11)
- `*::AddBoneHearts` (11)
- `*::ChangePlayerType` (11)
- `*::CheckIfRedShouldUseCustomLogic` (11)
- `*::GetGridEntity` (11)
- `*::IsCoopGhost` (11)
- `*::IsFoundSoul` (11)
- `*::PlayerIsTheSoul` (11)
- `*::RenderHealth` (11)
- `*::appendToDescription` (11)
- `*::FinishDamageDesync` (10)
- `*::IsMirrorWorld` (10)
- `*::IsTrinket` (10)
- `*::Lerp` (10)
- `*::RenderHolyMantle` (10)
- `*::AddBasegameRedHealthWithoutModifiers` (9)
- `*::AddHeartsKissesFix` (9)
- `*::GetGridSize` (9)
- `*::GetHealthSprite` (9)
- `*::GetTotalHPOfKey` (9)
- `*::HandleGoldenRoom` (9)
- `*::Length` (9)
- `*::AddBasegameSoulHealthWithoutModifiers` (8)
- `*::GetMenuKeybindSetting` (8)
- `*::GetMenusNotified` (8)
- `*::IsClear` (8)
- `*::RestrictBoneHearts` (8)
- `*::RestrictBrokenHearts` (8)
- `*::AddSoulHeartsKissesFix` (7)
- `*::CanPickRottenHearts` (7)
- `*::ChangeVariant` (7)
- `*::GetGamepadToggleSetting` (7)
- `*::GetPaletteSetting` (7)
- `*::HandleSodomAppleEffects` (7)
- `*::HealRedAnywhere` (7)
- `*::HealthHasTaintedMaggieProtection` (7)
- `*::RemoveTemporaryHP` (7)
- `*::RestrictRedHearts` (7)
- `*::RestrictSoulHearts` (7)
- `*::SaveMenuKeybindSetting` (7)
- `*::SaveMenusNotified` (7)

## Critical gaps

- `Entity:GetData()` is heavily used by Repentance Plus and is not a native cdef wrapper; it needs userdata-side persistent table storage.
- CustomHealthAPI's heart/container state, callback machinery, and overrides are not covered by the stock native ABI.
- DSS/EID/MinimapAPI/Encyclopedia/Sewn integration is Lua-level and needs compatibility shims or omission.
- `Sprite`/`ItemConfig`/many Repentance-only methods are not represented by the stock `scripts_v2` cdefs and remain unmapped.

Полный машинный результат: [`native-bridge.json`](native-bridge.json).
