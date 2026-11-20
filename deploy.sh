#!/bin/sh
# =============================================================================
# deploy.sh — upload GW_MAME.pak to the TrimUI Brick over SSH (tar-over-ssh)
#
#   ./deploy.sh                     # assemble pak + upload
#   DEVICE_IP=x.x.x.x ./deploy.sh   # different device
#
# Writes to the device:
#   Emus/tg5040/GW_MAME.pak/             the pak
#   Roms/Game & Watch MAME (GW_MAME)/    ROM folder (created so the system
#                                        shows up in NextUI — copy your MAME
#                                        romset zips there)
#   .userdata/tg5040/mame/artwork/       case artwork zips (required by the
#                                        (artwork/*.zip, if present)
#
# cfg files ship inside the pak; nothing is seeded into .userdata.
# ROM zips themselves are never deployed — add them on the device.
#
# Prerequisites: sshpass; device reachable via SSH (dropbear).
# =============================================================================
set -eu

DEVICE_IP="${DEVICE_IP:-192.168.1.107}"
DEVICE_USER="${DEVICE_USER:-root}"
DEVICE_PASS="${DEVICE_PASS:-tina}"

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
. "${REPO_ROOT}/pins.env"

OUT_DIR="${REPO_ROOT}/out"
PAK_DIR="${OUT_DIR}/${PAK_TAG}.pak"
ARTWORK_SRC="${REPO_ROOT}/artwork"

# Device paths
DEVICE_SDCARD="/mnt/SDCARD"
DEVICE_EMUS="${DEVICE_SDCARD}/Emus/${PLATFORM}"
DEVICE_PAK="${DEVICE_EMUS}/${PAK_TAG}.pak"
DEVICE_ROMS="${DEVICE_SDCARD}/Roms/${ROM_FOLDER}"
DEVICE_ARTWORK="${DEVICE_SDCARD}/.userdata/${PLATFORM}/mame/artwork"

# Device SSH is slow (dropbear) — generous connect timeout
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=40"
SSH="sshpass -p ${DEVICE_PASS} ssh ${SSH_OPTS} ${DEVICE_USER}@${DEVICE_IP}"

log() { echo "[deploy] $*"; }
err() { echo "[deploy ERROR] $*" >&2; }

command -v sshpass >/dev/null 2>&1 || { err "sshpass not found"; exit 1; }

tar_to_remote() {
    local_dir="$1"; remote_dir="$2"
    ${SSH} "mkdir -p '${remote_dir}'"
    tar --exclude='._*' --exclude='.DS_Store' -C "${local_dir}" -cf - . \
        | ${SSH} "tar -C '${remote_dir}' -xf -"
}

# --- Assemble + connect ---------------------------------------------------------
"${REPO_ROOT}/assemble.sh"

log "Connecting to ${DEVICE_USER}@${DEVICE_IP}..."
${SSH} "true" || { err "device unreachable"; exit 1; }

# --- Pak -----------------------------------------------------------------------
log "Deploying pak (replaces ${DEVICE_PAK})..."
${SSH} "rm -rf '${DEVICE_PAK}'"
tar_to_remote "${PAK_DIR}" "${DEVICE_PAK}"

# ROM folder: create (with the tag) so NextUI lists the system
log "Ensuring ROM folder ${DEVICE_ROMS}..."
${SSH} "mkdir -p '${DEVICE_ROMS}'"

# --- Artwork (required by the emulator) ------------------------------------------------
if ls "${ARTWORK_SRC}"/*.zip > /dev/null 2>&1; then
    log "Uploading artwork zips..."
    ${SSH} "mkdir -p '${DEVICE_ARTWORK}'"
    tar --exclude='._*' --exclude='.DS_Store' -C "${ARTWORK_SRC}" -cf - . \
        | ${SSH} "tar -C '${DEVICE_ARTWORK}' -xf -"
else
    log "No artwork zips in artwork/ — skipping (NOTE: emulator requires"
    log "matching artwork per game; add them before release)"
fi

# --- Verify ------------------------------------------------------------------------
log "Verifying..."
${SSH} "ls -lh '${DEVICE_PAK}/' '${DEVICE_PAK}/lib/' && echo '--- roms:' && ls '${DEVICE_ROMS}/'"
log ""
log "Done. On the device: put romset zips (e.g. gnw_ball.zip) in"
log "  ${DEVICE_ROMS}/"
log "then launch \"Game & Watch MAME\" from NextUI."
log "Log: .userdata/${PLATFORM}/logs/${PAK_TAG}.txt"
log ""
log "Note: an older 'GW.pak' (previous iteration) may still be installed"
log "under ${DEVICE_EMUS}/GW.pak — remove it and its ROM folder once"
log "GW_MAME is verified, to avoid a duplicate system entry."
