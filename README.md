# Repentance Plus — native Nintendo Switch port

Экспериментальный нативный порт Repentance Plus для официальной Switch-версии
The Binding of Isaac: Repentance. Игра исполняется самой консолью: ПК-стриминг,
удалённый рендер и запуск PC-версии не используются.

## Совместимая версия

- Title ID: `010021C000B6A000`
- update `main` Build ID: `b6e5bdb9dc12e1d1a25cbfda17f4be24b4754ef5`
- `Repentance.nro` Build ID: `91c73fdd575061318d68886316afeac72388b2ab`
- требуется Atmosphère с LayeredFS

На другой версии игры инжектор намеренно откажется ставить хуки. Никакие
`prod.keys`, `title.keys`, NSZ/NCA или файлы установленной игры не нужны для
установки готового релиза.

## Быстрая установка

1. Скачайте ZIP из раздела **Releases**.
2. Распакуйте папку `atmosphere` из архива в корень microSD.
3. Не заменяйте `main.npdm`, `subsdk0` или `subsdk1` игры. Релиз их не содержит.
4. Полностью перезапустите игру через Atmosphère.

Итоговые пути должны начинаться так:

```text
sd:/atmosphere/contents/010021C000B6A000/
├── exefs/subsdk9
└── romfs/
    ├── mods/repentanceplus/
    └── rp_patch/resources/
```

Если другой мод уже использует `exefs/subsdk9`, два инжектора одновременно не
заработают: временно уберите конфликтующий `subsdk9` или объедините исходники.

## Текущий статус

Собраны и защищены проверками Build ID/сигнатур:

- late-init после загрузки `Repentance.nro`;
- ARM64 LuaJIT в interpreter-only режиме с рабочим FFI resolver;
- stock Lua API bootstrap, `RegisterMod` и реальный `MC_POST_UPDATE` smoke;
- все 53 Lua-файла Repentance Plus встроены и компилируются;
- ресурсы/XML мода упакованы в LayeredFS;
- штатные `ModManager::ListMods()` и `LoadConfigs()` вызываются на живом
  `g_Manager+0x36800`;
- прямой ARM64-мост RNG и нативные `Sprite()`/ANM2;
- lookup модовых item/trinket/card/pill/sound/challenge/entity ID после
  `LoadConfigs()`;
- реальный отложенный запуск `mods/repentanceplus/main.lua` с маркером
  `REPENTANCE_PLUS_READY` либо точной Lua-ошибкой в debug log.

Это **alpha/hardware bring-up**, а не обещание полностью пройденного мода:
полный Isaac ABI и все 43 используемых callback ещё восстанавливаются. Если
игра падает или мод не появляется, приложите Atmosphère crash report и строки
`[isaac-port]` из debug log к GitHub Issue.

Ожидаемая успешная последовательность маркеров:

```text
SAFE_INIT_READY
LATE_INIT ... signature=ok
ENGINE_HOOK_READY
LUA_SMOKE_READY result=42
MOD_MANAGER_SCAN_BEGIN
MOD_MANAGER_LIST_READY
MOD_MANAGER_CONFIG_READY
REPENTANCE_PLUS_READY
ENGINE_SMOKE_READY
```

## Сборка из исходников

Нужны Podman и официальный контейнер
`devkitpro/devkita64:20260219`. Оригинальные Lua-скрипты игры в Git не входят.
Извлеките из своей копии DLC RomFS каталог `resources/scripts_v2` в:

```text
reference/stock-lua/dlc/resources/scripts_v2/
```

Затем:

```sh
./runtime/vendor/luajit/build.sh
./runtime/build-container.sh
```

Готовое дерево появится в `runtime/out/atmosphere/`. Внутренний qlaunch
`main.npdm`, который временно генерирует exlaunch, намеренно не публикуется.

Подробности реализации: [runtime/README.md](runtime/README.md), план работ:
[ROADMAP.md](ROADMAP.md), сводка используемого API:
[analysis/api-usage/README.md](analysis/api-usage/README.md).

## Удаление

Удалите только каталог:

```text
sd:/atmosphere/contents/010021C000B6A000/
```

Если в нём были другие моды, удаляйте лишь добавленные этим релизом
`exefs/subsdk9`, `romfs/mods/repentanceplus` и `romfs/rp_patch/resources`.

Проект не содержит ключей, образов игры или расшифрованных Nintendo-бинарников.
