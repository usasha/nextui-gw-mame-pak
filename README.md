# brick_gw_new — Game & Watch (MAME) for TrimUI Brick, reproducible build & pak

Standalone **native MAME 0.223** (G&W-only source subset, aarch64) packaged
as the NextUI emulator pak **`GW_MAME.pak`** (platform `tg5040`), with SVG
LCD-rendering performance patches.

Clean-room rewrite of the previous `brick_gw` iteration: same implementation
(same MAME, same patches, same build flags, same launcher), restructured as
a minimal, fully pinned, build-from-scratch project.

## Quick start

```sh
./build.sh      # Docker build: image + MAME subset binary → out/ (~30-90 min)
./deploy.sh     # assemble out/GW_MAME.pak, upload to the Brick via SSH
./package.sh    # assemble + out/dist/GW_MAME.pakz (distributable zip)
```

Deploy defaults to `root@192.168.1.107` (password `tina`); override with
`DEVICE_IP=…` (also `DEVICE_USER`, `DEVICE_PASS`).

Then on the device: copy your MAME Game & Watch romset zips
(`gnw_ball.zip`, …) into `Roms/Game & Watch MAME (GW_MAME)/` and the
matching MAME case-artwork zips into `Roms/Game & Watch MAME (GW_MAME)/.artwork/`
(hidden folder; both are required user inputs), then launch the
"Game & Watch MAME" system in NextUI.

The `.pakz` also installs 56 NextUI menu covers into the hidden `.media/`
folder and a `map.txt` with readable display names; both are generated from
the files in `media/` and `roms/`.

## Repo layout

```
pins.env        single source of truth: every pinned version/digest/checksum
Dockerfile      build env: digest-pinned ubuntu:20.04 (arm64), snapshot apt,
                sha256-verified SDL2 2.0.20
build.sh        docker image + shallow MAME clone (commit-verified) + patches
                + subset compile + artifact collection + out/BUILD-INFO.txt
assemble.sh     out/ + pak/ → out/GW_MAME.pak (staging step)
deploy.sh       assemble + tar-over-ssh upload (pak, bundled menu art,
                map.txt, optional MAME artwork zips)
package.sh      assemble + deterministic GW_MAME.pakz + sha256
patches/        the two MAME performance patches (idempotent, fail-hard)
pak/            payload shipped inside the .pak:
                  launch.sh   launcher (env, LD_LIBRARY_PATH, mame flags)
                  cfg/        control scheme (MAME cfg_directory → here)
                  README.md   user-facing notes
                  LICENSE     GPL-2.0 (MAME redistribution)
media/          56 NextUI menu covers (300 px, padded) + attribution notes
roms/map.txt    display-name aliases for the gnw_*.zip ROMs
pak.json        NextUI Pak Store metadata (for the eventual store release)
artwork/        MAME case-artwork zips, required by the emulator (gitignored;
                deploy-only)
out/            all artifacts (gitignored): mame_src/, mame, lib/,
                GW_MAME.pak/, dist/, build.log, BUILD-INFO.txt
```

## Reproducibility

Every input is pinned in `pins.env`, and the build re-verifies the critical
ones:

| Pin | Value | Where enforced |
|---|---|---|
| MAME | tag `mame0223` = commit `c55a261d…` | verified after shallow clone |
| Base image | `ubuntu:20.04` arm64 manifest digest `sha256:722ea796…` | `FROM` in Dockerfile |
| apt packages | `snapshot.ubuntu.com` @ `20261101T000000Z` | replaces `/etc/apt/sources.list` |
| SDL2 | 2.0.20 tarball, sha256 `c56aba1d…` | `sha256sum -c` in Dockerfile |
| Patches | `patches/*.py`, anchors grep-verified | build fails if a patch missed |

The resolved toolchain (gcc/lld versions), MAME commit, and artifact
hashes are recorded in `out/BUILD-INFO.txt` after every build.

Notes and limits:

- apt-over-https needs a CA bundle, but the bare base image ships none:
  `ca-certificates` is bootstrapped from the base image's stock http
  sources, then the sources are swapped to the frozen snapshot and every
  toolchain package (gcc/g++/lld/-dev libs) installs from it. ca-certificates
  is transport-only (never linked into the build) and SDL2 is sha256-checked,
  This bootstrap and its dependencies are not pinned, so a fully frozen
  build environment is not yet guaranteed.
- glibc of the base image (2.31) is the oldest the device runtime supports;
  the binary's max required symbol is checked and recorded (target ≈ 2.29).
- The zip produced by `package.sh` is deterministic (fixed member order and
  timestamps via `SOURCE_DATE_EPOCH`, default 2000-01-01) — the same pak
  always zips to the identical archive.
- Bit-for-bit reproducibility of the MAME binary has not been verified with
  a second clean build. The generated build record helps compare builds.
- To reuse the existing source tree, run `./build.sh --no-clone`; for a
  fresh clone, move `out/mame_src` aside first.

## Build details

- Native `linux/arm64` containers (Apple Silicon runs them at full speed; no
  cross toolchain).
- Subset: `SOURCES=src/mame/drivers/hh_sm510.cpp` — one G&W driver and its
  auto-detected deps; ~50 MB binary instead of ~700 MB.
- `ARCHOPTS="-DASMJIT_BUILD_X86=1 -UASMJIT_BUILD_HOST"` — the vendored asmjit
  only ships an x86 backend; without this aarch64 would try to include the
  missing arm.h.
- `LDOPTS="-static-libstdc++ -static-libgcc -fuse-ld=lld"` — static C++
  runtime; lld keeps the final link inside the 8 GB VM.
- `NO_X11=1 NO_OPENGL=1 NO_USE_PORTAUDIO=1 NO_USE_MIDI=1 USE_QTDEBUG=0
  USE_TAPTUN=0 USE_PCAP=0 NO_USE_XINPUT=1 USE_LIBSDL=1` — no desktop deps.
- SDL2 2.0.20 built from source is a **build-time** dep. At runtime the pak
  puts `/usr/trimui/lib` (the device's stock SDL2 with the `mali` fbdev
  video driver) first on `LD_LIBRARY_PATH`; the bundled fbcon build is only
  a self-contained fallback.
- `OPTIMIZE=2`, `BUILD_JOBS=4` — cc1plus memory safety for the Docker VM;
  G&W games are trivial to emulate, no performance impact.

## Performance patches

`build.sh` applies every script in `patches/` to the MAME source before
compiling and verifies the edits landed (the build fails otherwise). All
patches are idempotent.

- `0001_svg_skip_unchanged.py` (`src/emu/screen.cpp`) — the G&W SVG screen
  re-rendered every frame even when no segment changed (full-screen ~7.2 MB
  memcpy + scalar blits of every lit segment, 60×/s). The patch returns
  `UPDATE_HAS_NOT_CHANGED` when nothing changed since the last committed
  draw; commit-tracking via `screen.m_curbitmap` keeps it correct with
  frameskip. Upstream tried the same idea (PR #8791) and reverted it 2 days
  later due to input lag on tight games — this version adds the missing
  commit-tracking guard; check here first if controls ever feel laggy.
- `0002_svg_half_res.py` (`src/mame/drivers/hh_sm510.cpp`) — halves the SVG
  screen size (1671×1080 → 835×540), cutting every resolution-scaled cost
  4×. LCD segments are large flat shapes — invisible once scaled to the
  1024×768 panel.

With both patches + `-frameskip 4` in the launcher, gnw_ball runs at ~90%
of full speed (~46% before).

## Launcher & controls

`pak/launch.sh` (tag-independent — it derives `EMU_TAG` from the pak folder
name):

- `LD_LIBRARY_PATH=/usr/trimui/lib:<pak>/lib` (device SDL2 wins),
  `SDL_VIDEODRIVER=mali`, `SDL_AUDIODRIVER=alsa`
- `HOME=$USERDATA_PATH/mame` (nvram etc.), artwork read from the hidden
  `.artwork/` subfolder of the system's ROM folder (created by the pakz
  install; invisible in the NextUI game list)
- MAME `cfg_directory` → the pak's own `cfg/`; menu changes reset on pak
  update (deliberate)
- `-video accel -view "Background Only (No Shadow)" -sound sdl …` — default
  view pinned via a CLI flag; per-game cfgs (MAME menu saves) beat it, and
  games whose artwork names the view differently silently fall back to
  their own default view; log →
  `$LOGS_PATH/GW_MAME.txt` (`.userdata/tg5040/logs/`)
- brightness/volume restored via `syncsettings.elf`
- dev modes (both opt-in by marker files, unchanged from the previous
  iteration): `$USERDATA_PATH/mame/bench_seconds` → timed headless run
  printing "Average speed" to the log; `$USERDATA_PATH/mame/inputtest` →
  `-verbose` 30 s run for input debugging

Controls (global scheme in `pak/cfg/default.cfg`):

| Brick button | Action |
|---|---|
| D-pad | movement (JOYSTICK_*: hat remap) |
| A | action button (if the game has one) |
| Y | Game A |
| B | Game B |
| Select | Time |
| X | quit back to NextUI (UI Cancel) |
| Start | MAME in-game menu (UI Configure) |

In the MAME menu: D-pad navigates, A confirms, X goes back / quits. Device
button → SDL order: `0=B 1=A 2=Y 3=X 6=Select 7=Start`.

## Pak & store artifacts

- `Emus/tg5040/GW_MAME.pak/` — `mame`, `lib/libSDL2-2.0.so.0`, `launch.sh`,
  `cfg/`, `README.md`, `LICENSE` (GPL-2.0; MAME redistribution terms).
- `out/dist/GW_MAME.pakz` + `.sha256` — zip slice of the SD card root:
  `Emus/…`, `Roms/Game & Watch MAME (GW_MAME)/` with the bundled `.media/`
  menu covers (56 PNGs) and `map.txt` display names, plus the empty hidden
  `.artwork/` folder for user-supplied MAME case art. Deterministic; the Pak
  Store installs `.pakz` archives as-is (unzip to the SD card root).
- `pak.json` — Pak Store metadata; store submission is a deliberate later
  step (this iteration stops at the ready-to-submit artifacts).

## Credits

The bundled menu covers are based on the **"Nintendo Game & Watch Screenshot
Game Play Pack"** by **ci2own** (2023), published on LaunchBox Community
Forums and EmuMovies; see [`CREDITS.md`](CREDITS.md) and
[`media/README.md`](media/README.md) for links and licensing notes. The
source pack states no explicit license, and the images include Nintendo
copyrighted device artwork/game screenshots; they are included with
attribution for this free fan project and are not covered by the GPL-2.0
license of the MAME binary. Nintendo Game & Watch is a trademark of Nintendo;
this project is not affiliated with Nintendo.

## Caveats

- Standalone pak: no NextUI resume/quicksave/in-game-menu integration (the
  MAME menu opens with **Start** instead).
- The `mali` SDL video driver can wedge the display if MAME is killed
  abruptly (SIGKILL) — reboot the device if the screen stays black.
- NextUI auto-sleep can kick in during long idle sessions.
- An older `GW.pak` (previous iteration) may exist on the device alongside
  this one — remove it and its ROM folder after verifying GW_MAME to avoid
  a duplicate system entry.
