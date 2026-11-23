# GW_MAME.pak — Game & Watch on TrimUI (native MAME)

Game & Watch for NextUI via a **standalone native MAME 0.223** binary
(G&W-only source subset, aarch64, with SVG-rendering performance patches).
Not a libretro core — no NextUI resume/quicksave integration (quit with X).

## Install

1. Copy/extract the `.pakz` at the root of your SD card. It creates
   `Emus/tg5040/GW_MAME.pak/`, the system folder
   `Roms/Game & Watch MAME (GW_MAME)/`, its hidden `.media/` folder with the
   bundled menu covers (56 games), `map.txt` with display names, and an empty
   hidden `.artwork/` folder. Or install via the NextUI **Pak Store**.
2. Put your MAME Game & Watch romset zips in
   `Roms/Game & Watch MAME (GW_MAME)/` (e.g. `gnw_ball.zip`, `gnw_mariocm.zip`).
3. Put the matching MAME **case artwork** zips (same `gnw_*.zip` names) into
   `Roms/Game & Watch MAME (GW_MAME)/.artwork/` — the emulator needs them.
   `.artwork` is a hidden folder: invisible in the NextUI game list (to keep
   the list clean), shown like any folder on Windows; on macOS press
   `Cmd+Shift+.` in Finder to reveal it.
4. Reinsert the SD card; "Game & Watch MAME" appears once at least one rom
   is in the folder.

## Menu artwork and display names

- `.media/` ships with 300 px menu covers for the 56 games emulated by this
  MAME build. NextUI uses `<rom name>.png`, e.g. `gnw_ball.zip` →
  `gnw_ball.png`.
- The covers have transparent top/bottom padding so NextUI's rounded-corner
  mask cuts only invisible pixels. Other systems keep their rounded corners.
  Tall multi-screen covers are scaled down by NextUI to fit its height limit.
- `map.txt` maps the MAME short names to readable titles
  (`gnw_mariocm.zip` → `Mario's Cement Factory (New Wide Screen)`). Edit or
  delete it to show the raw file names instead.
- Missing cover for a new ROM? Drop a PNG with the same basename into
  `.media/`.
- To remove rounding for **all** game art: **Settings → Appearance → Game art
  corner radius → 0**.

## Workarounds and caveats

- Brightness/volume are restored by NextUI's `syncsettings.elf` on launch.
- If the screen stays black after MAME is killed abruptly, reboot the device
  (mali fbdev video driver quirk).
- Standalone pak: no resume, quicksave or in-game menu integration; the MAME
  menu opens with **Start** instead.

## Controls (global scheme, all G&W games)

| Brick button | Action                            |
|--------------|-----------------------------------|
| D-pad        | movement                          |
| A            | action button (if the game has one) |
| Y            | Game A                            |
| B            | Game B                            |
| Select       | Time                              |
| X            | quit back to NextUI               |
| Start        | MAME in-game menu                 |

In the MAME menu: D-pad navigates, A confirms, X goes back / quits.

Settings changed in the MAME menu are stored in this pak's `cfg/` and reset
when the pak is updated or reinstalled.

## MAME case artwork (required, just like the ROMs)

The emulator still needs the **MAME artwork zips** (`gnw_ball.zip`, ...) in
the `.artwork/` folder inside the system folder
(`Roms/Game & Watch MAME (GW_MAME)/.artwork/`), using the same file names as
the ROM zips. These are the case/bezel layers MAME renders around the LCD;
they are separate from the NextUI menu covers in `.media/`.

## Credits

Menu artwork is based on the **"Nintendo Game & Watch Screenshot Game Play
Pack"** by **ci2own** (2023), published on LaunchBox Community Forums and
EmuMovies. It was trimmed, resized to 300 px wide, and given transparent
padding for this pak. Source links and licensing notes:
https://github.com/usasha/nextui-gw-mame-pak (`CREDITS.md`).

Nintendo Game & Watch is a trademark of Nintendo; device artwork and game
screenshots are © Nintendo. This pak is not affiliated with Nintendo.

MAME is GPL-2.0 — see `LICENSE`.
