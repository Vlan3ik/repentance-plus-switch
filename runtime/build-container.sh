#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
IMAGE=${DEVKITPRO_IMAGE:-devkitpro/devkita64:20260219}

podman run --rm \
    -e DEVKITPRO=/opt/devkitpro \
    -v "$ROOT_DIR:/work:Z" \
    -v "$(cd "$ROOT_DIR/../reference" && pwd):/reference:ro,Z" \
    -v "$(cd "$ROOT_DIR/../repentanceplus" && pwd):/repentanceplus:ro,Z" \
    -w /work \
    "$IMAGE" \
    bash -lc 'export PATH="$DEVKITPRO/devkitA64/bin:$DEVKITPRO/tools/bin:$PATH"; ./build.sh'
