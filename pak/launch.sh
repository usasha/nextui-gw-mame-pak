#!/bin/sh
# =============================================================================
# GW_MAME.pak launcher: native MAME 0.223 standalone emulator for Game & Watch
#
# Standalone pak - no NextUI in-game menu / resume / quicksave integration.
# Quit back to NextUI with the X button (UI Cancel binding in cfg files).
# Brightness/volume restored by syncsettings.elf.
#
# Expects NextUI env: $ROM $PLATFORM $SDCARD_PATH $USERDATA_PATH $LOGS_PATH
#
# Benchmark support (dev): if $USERDATA_PATH/mame/bench_seconds exists,
# mame runs headless-style for that many seconds and prints Average speed
# to the log. Useful for UI-launched performance testing.
# =============================================================================

EMU_TAG=$(basename "$(dirname "$0")" .pak)
PAK_DIR=$(dirname "$0")
ROM="$1"
ROM_DIR=$(dirname "$ROM")
GAME=$(basename "$ROM" .zip)
ARTWORK_DIR="$ROM_DIR/.artwork"

# Bundled libs (SDL2_ttf/fontconfig chain) + the device's own SDL2 from the
# stock firmware (/usr/trimui/lib) which has the "mali" fbdev video driver.
# The device SDL2 must come FIRST so its libSDL2-2.0.so.0 wins.
export LD_LIBRARY_PATH="/usr/trimui/lib:$PAK_DIR/lib:$LD_LIBRARY_PATH"
export SDL_VIDEODRIVER=mali
export SDL_AUDIODRIVER=alsa

# MAME HOME + per-user data on the SD card (nvram). The cfg files
# (control scheme + view presets) ship INSIDE the pak under cfg/ - no seeding
# into userdata; a pak update restores factory settings.
# Artwork lives next to the roms, in the hidden ".artwork" subfolder of the
# system's ROM folder (created by the .pakz install) - invisible in NextUI's
# game list (dot-prefixed), one location for everything game-related.
export HOME="$USERDATA_PATH/mame"
mkdir -p "$HOME"

# Restore NextUI brightness/volume around the standalone binary
if [ -f "$SDCARD_PATH/.system/$PLATFORM/bin/syncsettings.elf" ]; then
    "$SDCARD_PATH/.system/$PLATFORM/bin/syncsettings.elf" &
fi

cd "$PAK_DIR"

BENCH=""
if [ -f "$USERDATA_PATH/mame/bench_seconds" ]; then
    BENCH="-str $(cat "$USERDATA_PATH/mame/bench_seconds") -artpath /nonexistent"
fi

# Input debug mode (dev): if this file exists, run mame with -verbose so the
# INPDEBUG event logging (see input_sdl.cpp) shows what MAME receives.
if [ -f "$USERDATA_PATH/mame/inputtest" ]; then
    ./mame "$GAME" \
        -rompath "$ROM_DIR" \
        -artpath /nonexistent \
        -cfg_directory "$PAK_DIR/cfg" \
        -video accel \
        -sound none \
        -skip_gameinfo \
        -verbose \
        -str 30 \
        > "$LOGS_PATH/$EMU_TAG.txt" 2>&1
    exit 0
fi

# Screen view: default to the flat "Background Only (No Shadow)" layout.
# Per-game cfgs (saved from the MAME menu) beat this flag, and games whose
# artwork names the view differently silently fall back to their own
# default view (verified on device).
./mame "$GAME" \
    -rompath "$ROM_DIR" \
    -artpath "$ARTWORK_DIR" \
    -cfg_directory "$PAK_DIR/cfg" \
    -video accel \
    -view "Background Only (No Shadow)" \
    -sound sdl \
    -skip_gameinfo \
    -autosave \
    -sleep \
    -frameskip 4 \
    $BENCH \
    > "$LOGS_PATH/$EMU_TAG.txt" 2>&1
