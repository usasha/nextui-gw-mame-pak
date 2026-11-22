#!/bin/sh
# =============================================================================
# package.sh — build the distributable GW_MAME.pakz (NextUI / Pak Store)
#
# A .pakz is a zip containing a full SD-card slice:
#
#   Emus/tg5040/GW_MAME.pak/             the pak (assemble.sh)
#   Roms/Game & Watch MAME (GW_MAME)/    empty ROM folder entry so the system
#                                        appears in NextUI right after install
#   Roms/.../.artwork/                    empty hidden artwork folder (created
#                                        so users just drop artwork zips in;
#                                        dot-prefixed => invisible in the
#                                        NextUI game list)
#
# The zip is deterministic: fixed member order and timestamps
# (SOURCE_DATE_EPOCH, default 2000-01-01), unix exec bits preserved. Reziping
# the same pak always produces the identical archive + sha256.
#
# Output: out/dist/GW_MAME.pakz + GW_MAME.pakz.sha256
#
# Usage: ./package.sh    (needs out/ from build.sh)
# =============================================================================
set -eu

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
. "${REPO_ROOT}/pins.env"

OUT_DIR="${REPO_ROOT}/out"
DIST_DIR="${OUT_DIR}/dist"
ZIP_PATH="${DIST_DIR}/${PAK_TAG}.pakz"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/gw_mame_pakz.XXXXXX")"
trap 'rm -rf "${STAGE}"' EXIT

log() { echo "[package] $*"; }
err() { echo "[package ERROR] $*" >&2; }

command -v python3 >/dev/null 2>&1 || { err "python3 not found"; exit 1; }

# --- Stage the SD-card slice ---------------------------------------------------
"${REPO_ROOT}/assemble.sh"

log "Staging SD-card slice..."
mkdir -p "${STAGE}/Emus/${PLATFORM}" "${STAGE}/Roms/${ROM_FOLDER}"
cp -R "${OUT_DIR}/${PAK_TAG}.pak" "${STAGE}/Emus/${PLATFORM}/"

# --- Deterministic zip -----------------------------------------------------------
log "Building ${ZIP_PATH}..."
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"

python3 - "${STAGE}" "${ZIP_PATH}" "${PAK_TAG}.pak" "${ROM_FOLDER}" "${PLATFORM}" <<'EOF'
import os, sys, time, zipfile

stage, zip_path, pak_name, rom_folder, platform = sys.argv[1:6]
pak_rel = "Emus/" + platform + "/" + pak_name
rom_rel = "Roms/" + rom_folder

# fixed timestamps (SOURCE_DATE_EPOCH, default 2000-01-01) => identical
# archives for identical inputs
epoch = int(os.environ.get("SOURCE_DATE_EPOCH", "946684800"))
dt = time.gmtime(epoch)[:6]

entries = []
pak_root = os.path.join(stage, pak_rel)
for root, dirs, files in os.walk(pak_root):
    dirs.sort()
    for name in sorted(files):
        p = os.path.join(root, name)
        entries.append((p, os.path.relpath(p, stage)))

with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
    # sorted member order (Emus/... before Roms)
    for p, arc in sorted(entries, key=lambda e: e[1]):
        zi = zipfile.ZipInfo.from_file(p, arc)
        zi.date_time = dt
        zi.compress_type = zipfile.ZIP_DEFLATED
        with open(p, "rb") as f:
            zf.writestr(zi, f.read())
    # empty ROM folder entry (directory bit, so unzip recreates it)
    zi = zipfile.ZipInfo(rom_rel + "/", date_time=dt)
    zi.external_attr = (0o755 << 16) | 0x10
    zf.writestr(zi, b"")
    # empty hidden artwork folder inside the ROM folder (same dir entry)
    zi = zipfile.ZipInfo(rom_rel + "/.artwork/", date_time=dt)
    zi.external_attr = (0o755 << 16) | 0x10
    zf.writestr(zi, b"")
EOF

# --- Verify ------------------------------------------------------------------------
log "Archive listing:"
unzip -l "${ZIP_PATH}"
max_glibc=$(strings "${STAGE}/Emus/${PLATFORM}/${PAK_TAG}.pak/mame" \
    | grep -o 'GLIBC_2\.[0-9]*' | sort -t. -k2 -n | tail -1)
log "Max GLIBC symbol required by mame: ${max_glibc} (device runtime >= 2.31)"

log "Checksum..."
(cd "${DIST_DIR}" && shasum -a 256 "${PAK_TAG}.pakz" > "${PAK_TAG}.pakz.sha256")

log ""
log "Done! Release artifacts in ${DIST_DIR}:"
ls -lh "${DIST_DIR}"
log "Manual install: unzip GW_MAME.pakz at the SD-card root (or copy via"
log "deploy.sh for SSH). Store submission (pak.json) is a separate later step."
