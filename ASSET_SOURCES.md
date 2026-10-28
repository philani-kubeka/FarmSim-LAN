# Asset sources

Every visual asset used by FarmSim is recorded here, with its origin and licence.
Nothing in this file is assumed or inferred: if the provenance of an asset is not
known with certainty, it is not used.

## Sourcing decision

Free asset packs were **not** downloaded for this prototype. The build
environment for this project had no network access to asset hosts, so the licence
of any downloaded pack could not be verified at source. Recording an unverified
licence in an academic artefact is worse than having simpler graphics, so the
fallback in the project brief applies: the sprite pack was created specifically
for FarmSim.

## Origin and licence

| Asset group | Source | Licence | Attribution required |
| --- | --- | --- | --- |
| `icon.svg` | Supplied with the blank Godot project template (Godot Engine default icon) | MIT (Godot Engine) | No |
| `assets/fonts/fredoka_semibold.woff2` (headings and buttons) | Fredoka by the Fredoka Project Authors, via the `@fontsource/fredoka` npm package (5.3.0) | SIL Open Font License 1.1 (`assets/fonts/FREDOKA_OFL.txt`) | No (licence file kept with the font) |
| `assets/icons/` (app / launcher icon: flat 512 and 192 px, Android adaptive foreground, background and monochrome layers) | Created for this prototype by `tools/generate_assets.py` (app icon section), using the Player 1 sprite | Original work, part of this project | No |
| `assets/decor/` (20 sprites: trees, bushes, flowers, rocks, grass tufts, dirt path, garden toolbox, ground variation) | Created for this prototype by `tools/generate_assets.py` (decor section); the toolbox is drawn after a reference photo of a resin deck box, not copied from it | Original work, part of this project | No |
| Everything else under `assets/` (30 sprites; the fence is rail lengths plus one post sprite, laid out by `scripts/farm/fence_ring.gd`) | Created for this prototype by `tools/generate_assets.py` | Original work, part of this project | No |

The generator script is committed alongside the sprites it produces, so every
image can be regenerated and audited:

```
python tools/generate_assets.py
```

The only third-party dependency in that script is Pillow, which is used at
authoring time only. It is not shipped with the game and the game does not depend
on it.

## The pack

| File | Size | Used for |
| --- | --- | --- |
| `assets/environment/fence_horizontal.png` | 64x64 | Ground, well and fencing |
| `assets/environment/fence_vertical.png` | 64x64 | Ground, well and fencing |
| `assets/environment/grass.png` | 64x64 | Ground, well and fencing |
| `assets/environment/soil.png` | 64x64 | Ground, well and fencing |
| `assets/environment/tile_border.png` | 64x64 | Ground, well and fencing |
| `assets/environment/tilled.png` | 64x64 | Ground, well and fencing |
| `assets/environment/well.png` | 64x64 | Ground, well and fencing |
| `assets/crops/beans_1.png` | 64x64 | Crop growth stages |
| `assets/crops/beans_2.png` | 64x64 | Crop growth stages |
| `assets/crops/beans_3.png` | 64x64 | Crop growth stages |
| `assets/crops/beans_4.png` | 64x64 | Crop growth stages |
| `assets/crops/maize_1.png` | 64x64 | Crop growth stages |
| `assets/crops/maize_2.png` | 64x64 | Crop growth stages |
| `assets/crops/maize_3.png` | 64x64 | Crop growth stages |
| `assets/crops/maize_4.png` | 64x64 | Crop growth stages |
| `assets/crops/stubble.png` | 64x64 | Crop growth stages |
| `assets/characters/player_1.png` | 40x52 | The two players |
| `assets/characters/player_2.png` | 40x52 | The two players |
| `assets/tools/harvest.png` | 40x40 | Tool icons |
| `assets/tools/hoe.png` | 40x40 | Tool icons |
| `assets/tools/inspect.png` | 40x40 | Tool icons |
| `assets/tools/seed.png` | 40x40 | Tool icons |
| `assets/tools/treat.png` | 40x40 | Tool icons |
| `assets/tools/water.png` | 40x40 | Tool icons |
| `assets/effects/alert.png` | 40x40 | Indicators and event icons |
| `assets/effects/drop.png` | 40x40 | Indicators and event icons |
| `assets/effects/drought.png` | 40x40 | Indicators and event icons |
| `assets/effects/pest.png` | 40x40 | Indicators and event icons |
| `assets/effects/warning.png` | 40x40 | Indicators and event icons |

The automated test suite (`tests/cases/test_assets.gd`) checks that every one of
these files exists, imports, resolves to a real texture rather than a
placeholder, and that the ground tiles match the tile size the field is laid out
with.
