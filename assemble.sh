#!/bin/sh
# =============================================================================
# assemble.sh — stage the NextUI emulator pak: out/GW_MAME.pak
#
# Pak layout (tag GW_MAME, platform tg5040):
#   GW_MAME.pak/
#     mame               built binary              (build.sh -> out/)
#     lib/libSDL2-2.0.so.0  bundled fallback SDL2  (build.sh -> out/lib/)
#     launch.sh          launcher                  (pak/)
#     cfg/default.cfg    control scheme — MAME's cfg_directory points here,
#                        so menu changes live inside the pak and reset on
#                        pak update                (pak/cfg/)
#     README.md          user-facing notes         (pak/)
#     LICENSE            GPL-2.0 (MAME redistribution)
#
# The bundled libSDL2 is only a fallback: at runtime the device's own SDL2
# from /usr/trimui/lib (mali fbdev driver) takes precedence — see launch.sh.
#
# Usage: ./assemble.sh    (run by deploy.sh / package.sh; needs out/ from build.sh)
# =============================================================================
set -eu

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
. "${REPO_ROOT}/pins.env"

OUT_DIR="${REPO_ROOT}/out"
PAK_SRC="${REPO_ROOT}/pak"
PAK_DIR="${OUT_DIR}/${PAK_TAG}.pak"

log() { echo "[assemble] $*"; }
err() { echo "[assemble ERROR] $*" >&2; }

[ -f "${OUT_DIR}/mame" ] || { err "out/mame missing — run ./build.sh first"; exit 1; }
[ -f "${OUT_DIR}/lib/libSDL2-2.0.so.0" ] || { err "out/lib/libSDL2-2.0.so.0 missing — run ./build.sh first"; exit 1; }

file "${OUT_DIR}/mame" | grep -q "ARM aarch64" \
    || { err "out/mame is not an aarch64 binary — wrong build?"; exit 1; }

log "Staging ${PAK_DIR}..."
rm -rf "${PAK_DIR}"
mkdir -p "${PAK_DIR}/lib" "${PAK_DIR}/cfg"

cp "${OUT_DIR}/mame" "${PAK_DIR}/mame"
cp "${OUT_DIR}/lib/libSDL2-2.0.so.0" "${PAK_DIR}/lib/"
cp "${PAK_SRC}/launch.sh" "${PAK_DIR}/launch.sh"
cp "${PAK_SRC}/cfg/default.cfg" "${PAK_DIR}/cfg/"
cp "${PAK_SRC}/README.md" "${PAK_DIR}/README.md"
cp "${PAK_SRC}/LICENSE" "${PAK_DIR}/LICENSE"

chmod 755 "${PAK_DIR}/mame" "${PAK_DIR}/launch.sh"

log "Pak contents:"
find "${PAK_DIR}" -type f | sort | while read -r f; do
    ls -lh "$f" | awk '{printf "  %-52s %s\n", $NF, $5}'
done
