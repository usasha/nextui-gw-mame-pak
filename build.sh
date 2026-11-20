#!/bin/bash
# =============================================================================
# build.sh — reproducible from-scratch build of native MAME 0.223
# (Game & Watch-only subset, aarch64) for the TrimUI Brick (tg5040).
#
# Everything is pinned in pins.env: MAME commit, Docker base digest, apt
# snapshot timestamp, SDL2 tarball sha256. The resolved toolchain and
# artifact hashes are recorded in out/BUILD-INFO.txt; the full compile log
# lands in out/build.log.
#
# Prerequisites: Docker running (arm64 containers), ~6 GB free disk,
# ~8 GB RAM recommended.
#
# Usage:
#   ./build.sh               # full build: docker image + MAME (from scratch)
#   ./build.sh --no-image    # reuse the existing docker image
#   ./build.sh --no-clone    # reuse the existing out/mame_src clone
#   ./build.sh --force       # recompile even if out/mame already exists
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${REPO_ROOT}/pins.env"

MAME_SRC="${REPO_ROOT}/out/mame_src"
OUT_DIR="${REPO_ROOT}/out"
IMAGE_NAME="brick-gw-mame:${MAME_TAG}"
BUILD_LOG="${OUT_DIR}/build.log"

log() { echo "[build] $*"; }
err() { echo "[build ERROR] $*" >&2; }

# --- Step 1: Docker image -----------------------------------------------------
build_image() {
    log "Building docker image ${IMAGE_NAME}"
    log "  base apt snapshot: ${APT_SNAPSHOT_DATE}"
    docker build --platform linux/arm64 \
        --build-arg DOCKER_BASE_IMAGE="${DOCKER_BASE_IMAGE}" \
        --build-arg APT_USE_SNAPSHOT="${APT_USE_SNAPSHOT}" \
        --build-arg APT_SNAPSHOT_DATE="${APT_SNAPSHOT_DATE}" \
        --build-arg SDL2_VERSION="${SDL2_VERSION}" \
        --build-arg SDL2_URL="${SDL2_URL}" \
        --build-arg SDL2_SHA256="${SDL2_SHA256}" \
        -t "${IMAGE_NAME}" "${REPO_ROOT}"
}

# --- Step 2: MAME source at the pinned commit --------------------------------
clone_mame() {
    if [ -d "${MAME_SRC}/.git" ] && [ "${REUSE_SRC}" = "1" ]; then
        log "Reusing MAME source at ${MAME_SRC}"
    elif [ -e "${MAME_SRC}" ]; then
        err "Source directory already exists: ${MAME_SRC}"
        err "Use --no-clone to reuse it, or move it aside for a clean build."
        exit 1
    else
        log "Cloning MAME at tag ${MAME_TAG} (shallow)..."
        git clone --depth 1 --branch "${MAME_TAG}" "${MAME_REPO}" "${MAME_SRC}"
    fi
    local actual
    actual="$(git -C "${MAME_SRC}" rev-parse HEAD)"
    if [ "${actual}" != "${MAME_COMMIT}" ]; then
        err "Tag ${MAME_TAG} does not resolve to the pinned commit:"
        err "  pinned  ${MAME_COMMIT}"
        err "  actual  ${actual}"
        err "If mamedev re-pointed the tag, amend MAME_COMMIT in pins.env consciously."
        exit 1
    fi
    log "MAME source @ ${actual} (pinned)"
}

# --- Step 3: apply + verify patches ---------------------------------------------
apply_patches() {
    log "Applying patches from patches/..."
    local py
    for py in "${REPO_ROOT}"/patches/*.py; do
        [ -e "$py" ] || continue
        python3 "$py" "${MAME_SRC}"
    done
    # fail the build if a patch silently missed its anchor
    grep -q "m_last_draw_bitmap" "${MAME_SRC}/src/emu/screen.cpp" \
        || { err "patch 0001 (svg skip-unchanged) did not land in screen.cpp"; exit 1; }
    grep -q "set_size(width / 2, height / 2)" "${MAME_SRC}/src/mame/drivers/hh_sm510.cpp" \
        || { err "patch 0002 (svg half-res) did not land in hh_sm510.cpp"; exit 1; }
    log "Patches verified."
}

# --- Step 4: compile inside the container --------------------------------------
build_mame() {
    # 0.223 ships a prebuilt x86_64 GENie; drop it so the makefile rebuilds
    # the arm64 one from the in-tree source (it has a rule for that).
    local genie_bin="${MAME_SRC}/3rdparty/genie/bin/linux/genie"
    if [ -f "${genie_bin}" ] && file "${genie_bin}" | grep -q "x86-64"; then
        log "Removing prebuilt x86_64 GENie (arm64 rebuild happens in-tree)"
        rm -f "${genie_bin}"
    fi

    # REGENIE only when projects are not generated yet: regenerating bumps
    # the Makefile mtimes and every object depends on $(MAKEFILE) — a full
    # rebuild would be triggered for no reason.
    local regenie=0
    [ -f "${MAME_SRC}/build/projects/sdl/mame/gmake-linux/Makefile" ] || regenie=1

    log "Compiling MAME subset (${MAME_SOURCES}), -j${BUILD_JOBS}, OPTIMIZE=${OPTIMIZE}"
    log "Log: ${BUILD_LOG}"
    if ! docker run --rm --platform linux/arm64 \
            -e REGENIE="${regenie}" \
            -e OPTIMIZE="${OPTIMIZE}" \
            -e BUILD_JOBS="${BUILD_JOBS}" \
            -e MAME_SOURCES="${MAME_SOURCES}" \
            -v "${MAME_SRC}":/src \
            -v "${OUT_DIR}":/out \
            -w /src \
            "${IMAGE_NAME}" \
            /bin/bash -c '
                set -e
                make linux \
                    REGENIE=$REGENIE \
                    SOURCES=$MAME_SOURCES \
                    PYTHON_EXECUTABLE=python3 \
                    OPTIMIZE=$OPTIMIZE \
                    NOWERROR=1 \
                    NO_X11=1 \
                    NO_OPENGL=1 \
                    NO_USE_PORTAUDIO=1 \
                    NO_USE_MIDI=1 \
                    USE_QTDEBUG=0 \
                    USE_TAPTUN=0 \
                    USE_PCAP=0 \
                    NO_USE_XINPUT=1 \
                    USE_LIBSDL=1 \
                    SDL_INSTALL_ROOT=/opt/sdl2 \
                    LDOPTS="-static-libstdc++ -static-libgcc -fuse-ld=lld" \
                    ARCHOPTS="-U_FORTIFY_SOURCE -DASMJIT_BUILD_X86=1 -UASMJIT_BUILD_HOST" \
                    -j$BUILD_JOBS
            ' 2>&1 | tee "${BUILD_LOG}"; then
        err "MAME compile failed — see ${BUILD_LOG}"
        exit 1
    fi

    # Age the rebuilt arm64 GENie so the makefile's regen rule (Makefile
    # depends on $(GENIE)) never re-triggers a project regeneration.
    if [ -f "${genie_bin}" ]; then
        if [ "$(uname)" = "Darwin" ]; then
            touch -t "$(date -v-2H +%Y%m%d%H%M.%S)" "${genie_bin}"
        else
            touch -d '2 hours ago' "${genie_bin}"
        fi
    fi
}

# --- Step 5: collect binary + runtime lib closure --------------------------------
collect_artifacts() {
    local bin="${MAME_SRC}/mame"
    [ -f "${bin}" ] || bin="${MAME_SRC}/build/projects/sdl/mame/gmake-linux/mame"
    [ -f "${bin}" ] || { err "built binary not found (tried ${MAME_SRC}/mame)"; exit 1; }

    rm -rf "${OUT_DIR}/lib"
    mkdir -p "${OUT_DIR}/lib"
    cp "${bin}" "${OUT_DIR}/mame"
    chmod 755 "${OUT_DIR}/mame"
    log "mame binary: $(ls -lh "${OUT_DIR}/mame" | awk '{print $5}')"

    # Bundle the full runtime closure (except glibc core and the device's
    # own libEGL) so nothing from the build machine is assumed. Only
    # libSDL2 ships in the pak (assemble.sh); the rest documents the
    # complete set the binary needs.
    docker run --rm --platform linux/arm64 \
        -v "${OUT_DIR}":/out \
        "${IMAGE_NAME}" \
        /bin/bash -c '
            set -e
            # glibc components stay with the device; libEGL also stays
            # (device has its own PowerVR libEGL.so.1 — do not shadow it)
            SKIP_RE="^(libc\.so|libm\.so|libdl\.so|libpthread\.so|librt\.so|libstdc\+\+|libgcc_s|libgcc\.so|ld-linux|libnss_|libresolv|libutil|libcrypt|libEGL)"
            needlibs() { readelf -d "$1" | grep NEEDED | sed -E "s/.*\[(.*)\].*/\1/"; }
            # prefer the minimal SDL2 we built (/opt/sdl2, fbcon-only) over
            # the distro one (which drags in X11/wayland/pulseaudio)
            findlib() { find /opt/sdl2/lib /lib /usr/lib -name "$1" 2>/dev/null | head -1; }
            needlibs /out/mame > /tmp/candidates.txt
            while :; do
                new=0
                while read -r lib; do
                    echo "$lib" | grep -qE "$SKIP_RE" && continue
                    [ -f "/out/lib/$lib" ] && continue
                    found=$(findlib "$lib")
                    if [ -n "$found" ]; then
                        cp -L "$found" /out/lib/
                        echo "[bundle] $lib <- $found"
                        new=1
                    else
                        echo "[bundle] WARNING: $lib not found in container"
                    fi
                done < /tmp/candidates.txt
                [ "$new" = "0" ] && break
                # transitive deps of everything bundled so far
                : > /tmp/candidates.txt
                for f in /out/lib/*.so*; do
                    [ -f "$f" ] || continue
                    needlibs "$f" >> /tmp/candidates.txt
                done
                sort -u /tmp/candidates.txt -o /tmp/candidates.txt
            done
        '
    log "Bundled libs:"
    ls -lh "${OUT_DIR}/lib/"
}

# --- Step 6: verify + record ---------------------------------------------------
verify_and_record() {
    local max_glibc toolchain
    max_glibc="$(strings "${OUT_DIR}/mame" | grep -o 'GLIBC_2\.[0-9]*' | sort -t. -k2 -n | tail -1)"
    toolchain="$(docker run --rm --platform linux/arm64 "${IMAGE_NAME}" sh -c 'gcc --version | head -1; ld.lld --version | head -1')"

    log "max GLIBC symbol required by mame: ${max_glibc} (device runtime >= 2.31)"
    log "remaining dynamic deps (must be in out/lib/ or device-provided):"
    docker run --rm --platform linux/arm64 \
        -v "${OUT_DIR}":/out "${IMAGE_NAME}" \
        readelf -d /out/mame | grep NEEDED | sed 's/^/  /'

    {
        echo "=== brick_gw_new build record ==="
        echo "generated: $(date -u '+%Y-%m-%d %H:%M:%SZ') (informational; not a pinned input)"
        echo
        echo "--- pins (pins.env) ---"
        grep -E '^[A-Z0-9_]+=' "${REPO_ROOT}/pins.env"
        echo
        echo "--- resolved ---"
        echo "mame_commit:     $(git -C "${MAME_SRC}" rev-parse HEAD)"
        echo "source_tag:      ${MAME_TAG}"
        echo "docker_image:    ${IMAGE_NAME} ($(docker images -q "${IMAGE_NAME}" | head -c 12))"
        echo "max_glibc:       ${max_glibc}"
        echo "toolchain:"
        echo "${toolchain}" | sed 's/^/  /'
        echo
        echo "--- artifacts (sha256) ---"
        (cd "${OUT_DIR}" && shasum -a 256 mame lib/*.so*)
    } > "${OUT_DIR}/BUILD-INFO.txt"
    log "build record: ${OUT_DIR}/BUILD-INFO.txt"
}

# --- Main ----------------------------------------------------------------------
REUSE_SRC=0
FORCE=0
SKIP_IMAGE=0
for a in "$@"; do
    case "$a" in
        --no-image) SKIP_IMAGE=1 ;;
        --no-clone) REUSE_SRC=1 ;;
        --force)    FORCE=1 ;;
        *) err "unknown option: $a"; exit 1 ;;
    esac
done

command -v docker >/dev/null 2>&1 || { err "docker not found"; exit 1; }
mkdir -p "${OUT_DIR}"

if [ "${SKIP_IMAGE}" = "1" ]; then
    log "Reusing docker image ${IMAGE_NAME} (--no-image)"
else
    build_image
fi

clone_mame
apply_patches

if [ -f "${OUT_DIR}/mame" ] && [ -f "${MAME_SRC}/mame" ] && [ "${FORCE}" = "0" ]; then
    log "out/mame exists — skipping compile (--force to rebuild)"
else
    build_mame
    collect_artifacts
fi

verify_and_record

log ""
log "Done! Artifacts in ${OUT_DIR}:"
ls -lh "${OUT_DIR}"
log "Next: ./deploy.sh (upload to device) or ./package.sh (make GW_MAME.pakz)"
