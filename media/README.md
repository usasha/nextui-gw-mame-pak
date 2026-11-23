# Bundled NextUI menu artwork

56 PNGs for NextUI's per-ROM `.media` folder, covering the standard MAME
Game & Watch set (the same `gnw_*` names as the ROM zips).

- Trimmed to the device, resized to **300 px wide**.
- Transparent padding above and below. The padding is sized for NextUI's
  "Game art corner radius" mask (default `20`, i.e. `20 * FIXED_SCALE(3) = 60`
  display px on the Brick), so the rounded mask cuts only transparent pixels.
  This keeps the black card square while other systems keep their rounded
  corners. It also means tall multi-screen art is scaled down by NextUI; that
  is expected.
- File names match the ROM file names without `.zip`: `gnw_ball.png` is used
  for `gnw_ball.zip`.

## Source and credit

Base images: **"Nintendo Game & Watch Screenshot Game Play Pack"** by
**ci2own** (2023), published on the LaunchBox Community Forums and EmuMovies:

- https://forums.launchbox-app.com/files/file/4413-nintendo-game-watch-screenshot-game-play-pack/
- https://emumovies.com/files/file/5242-nintendo-game-watch-screenshot-game-play-pack/

Changes made for this pak: black borders trimmed, resized to 300 px wide,
transparent top/bottom padding added. No other edits.

## Licensing

The source pages do not state an explicit license. These are fan-made
composites that include Nintendo Game & Watch hardware artwork and game
screenshots; that imagery is Nintendo copyrighted material. The files are
included here with attribution for this free fan project and are **not**
covered by the GPL-2.0 license that applies to the MAME binary. If you are a
rights holder and want them removed, please open an issue in the project
repository.

## Regeneration parameters

The values used for the NextUI Brick:

- screen: 1024x768
- "Game art width": 45% (max 460x460 px)
- corner radius: 20 (60 display px)
- target transparent padding: 72 display px per side

The committed PNGs are the reproducible build inputs; the original 1920x1080
source pack is not vendored.
