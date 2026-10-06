# Persistence hardware acceptance

This is the acceptance test for the first Repentance Plus Switch blocker:
`Isaac.SaveModData`, `Isaac.HasModData`, `Isaac.LoadModData`, and
`Isaac.RemoveModData`.  The test is **hardware-only**.  The host persistence
smoke tests exercise a fake library and cannot prove that data survives a
real game restart.

## Prepare the Atmosphere tree

Build the runtime with the normal Switch toolchain, or use an existing
`runtime/out/atmosphere/` tree.  Put the acceptance mod into that exact tree
before copying it to the SD card:

```sh
cd /home/krl/Документы/isaac/repentance-plus-switch
install -D runtime/tests/hardware/persistence_acceptance.lua \
  runtime/out/atmosphere/contents/010021C000B6A000/romfs/mods/rplus-persistence-acceptance/main.lua
```

Copy `runtime/out/atmosphere/` to the SD-card root, merging the existing
`atmosphere/` directory.  Keep the title ID directory, `subsdk0`, `subsdk1`,
and the original title NPDM intact.  This test does not need `prod.keys`, a
title-key dump, or any console credential.

Enable `rplus-persistence-acceptance` in the game's mod menu if the title
requires explicit mod activation.  Launch the game and start/enter a run.

## Capture and validate

Capture the Atmosphere/debug output using the user's normal console logging
workflow.  The capture may contain unrelated lines; save the combined output
from both launches as a UTF-8 text file.  No IP address is assumed or
hard-coded by this test.

On the first launch the mod must emit, in order:

```text
RPLUS_PERSISTENCE_ACCEPTANCE BEGIN
RPLUS_PERSISTENCE_ACCEPTANCE INITIAL_STATE has=false
RPLUS_PERSISTENCE_ACCEPTANCE SAVE_OK
RPLUS_PERSISTENCE_ACCEPTANCE RESTART_REQUIRED exit_game_and_launch_again
```

Exit the game completely, wait for the title process to terminate, and launch
it again.  Start/enter another run.  The second launch must then emit:

```text
RPLUS_PERSISTENCE_ACCEPTANCE BEGIN
RPLUS_PERSISTENCE_ACCEPTANCE INITIAL_STATE has=true
RPLUS_PERSISTENCE_ACCEPTANCE LOAD_AFTER_RESTART_OK
RPLUS_PERSISTENCE_ACCEPTANCE REMOVE_OK
RPLUS_PERSISTENCE_ACCEPTANCE COMPLETE
```

Validate the combined capture locally:

```sh
python3 runtime/tests/hardware/validate_persistence_log.py /path/to/capture.log
```

Only `PERSISTENCE_ACCEPTANCE_VALIDATED` is an acceptance result.  A
`FAIL ...` marker, missing second launch, different marker order, or a
different initial state is a failure and must not be converted into a
host-only success.  After a successful run, `REMOVE_OK` also verifies that
the test cleaned up its own marker.

The fixture validator is intentionally separate from host regression and can
be checked without a console:

```sh
./runtime/tests/hardware/test-validate-persistence-log.sh
```
