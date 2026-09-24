# v0.2.0-alpha — запуск реального main.lua

Второй аппаратный alpha-пакет нативного Switch-порта Repentance Plus.

Установка:

1. Нужна легально установленная The Binding of Isaac: Repentance с Title ID
   `010021C000B6A000` и Build ID, указанными в README.
2. Распаковать архив в корень microSD с объединением папки `atmosphere`.
3. Запустить игру через Atmosphère.

Архив добавляет:

- `atmosphere/contents/010021C000B6A000/exefs/subsdk9` — runtime injector;
- `atmosphere/contents/010021C000B6A000/romfs/mods/repentanceplus` — Lua/XML/assets;
- `atmosphere/contents/010021C000B6A000/romfs/rp_patch/resources` — resource overlay.

Не добавляйте чужой `main.npdm`. Если уже установлен другой `subsdk9`, он
конфликтует с этим инжектором.

В v0.2 добавлены нативные RNG и Sprite/ANM2, lookup загруженных конфигов,
исправлена регистрация API-v1 callback и впервые выполняется реальный
`repentanceplus/main.lua` после `ModManager::LoadConfigs()`.

Текущая пересборка также исправляет ABI конструктора ANM2, lookup costume и
sound ID, Lua 5.3-совместимость исходников, наследование API-v1 окружения в
`include()`, priority callbacks и class hooks Custom Health API. Полный
host-bootstrap завершается маркерами `Custom Health API: v0.946 Loaded`
и `REPENTANCE_PLUS_HOST_BOOTSTRAP_READY`.

Статус: непроверенная на железе alpha. Полное покрытие 43 Isaac callback ещё в
работе. При сбое
приложите Atmosphère crash report и строки `[isaac-port]` к GitHub Issue.

NSP/NSZ игры, ключи и оригинальные Nintendo-бинарники в релиз не входят.
