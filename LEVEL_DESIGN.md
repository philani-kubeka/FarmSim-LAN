# Designing the farm level

Everything decorative on the farm (trees, bushes, flowers, rocks, paths, the
garden toolbox) is an ordinary node in `scenes/farm/farm.tscn`. You place it by
hand in the Godot editor. None of it affects the game rules or the research
data, so you can move, add or delete anything freely.

## 1. Open the level

1. Open the project in Godot 4.7 (Project Manager > Import > `project.godot`).
2. In the **FileSystem** dock (bottom left), double-click
   `res://scenes/farm/farm.tscn`.
3. Click **2D** at the top of the window if the editor shows something else.

The **Scene** dock (top left) shows the farm's nodes. The three you design with
are the decoration layers:

| Layer | Put here | Drawn |
| --- | --- | --- |
| `DecorGround` | paths, rocks, grass tufts, the grass-variation overlay, flowers outside the fence | under everything, even the crop plot |
| `DecorLow` | flowers and small plants inside the fence | under the fence and the players |
| `DecorTall` | bushes, trees, the garden toolbox | over the fence, under the players |

Every piece is a `Sprite2D` inside one of them, with a readable name (`Tree1`,
`BerryBush2`, `Flowers7`, `GardenToolbox`, ...).

## 2. Move, copy, flip, delete

* **Move:** click a piece in the viewport (or in the Scene dock) and drag it.
  To pick something hidden behind another piece, hold **Alt** and right-click:
  Godot lists everything under the cursor.
* **Exact position:** Inspector > **Transform > Position**.
* **Copy:** select it and press **Ctrl+D**, then drag the copy away.
* **Mirror:** Inspector > **Offset > Flip H**. A flipped tree or flower patch
  looks like a different one.
* **Delete:** select it and press **Delete**.
* **Rename:** select it and press **F2**.
* **Line things up:** click the magnet icon in the viewport toolbar to turn on
  snapping. The three-dots menu next to it > **Configure Snap** sets the grid
  (8 px works well).

The "Garden toolbox" label is a child of `GardenToolbox`, so it moves with the
box. The well and its label are separate nodes (`Well`, `WellLabel`).

## 3. Add new pieces

1. In the Scene dock, click the layer you want (for example `DecorTall`).
2. In the FileSystem dock, open `res://assets/decor/`.
3. Drag a picture (for example `tree_pine.png`) into the viewport and drop it
   where you want it. Godot makes a `Sprite2D` for it.
4. If it landed under the wrong parent, drag it onto the right layer in the
   Scene dock. **Ctrl+S** saves.

Available pieces in `assets/decor/`:

| Trees | Bushes | Flowers | Ground |
| --- | --- | --- | --- |
| `tree_round`, `tree_round_2`, `tree_fruit`, `tree_pine` | `bush`, `bush_berries`, `bush_small` | `flowers_pink`, `_yellow`, `_white`, `_purple`, `_orange`, `_mixed` | `rock`, `grass_tuft_1..3`, `dirt_path`, `ground_variation` |

Plus `garden_toolbox`. Keep sprites at a whole-number scale (1, 2, 3) so the
pixel art stays crisp.

## 4. Where things show up

The farm is 1280 x 720 pixels. Some of it is covered on screen:

* **Top band (y 0-180):** the season bar and the water bar.
* **Bottom band (y 616-720):** the two player panels.
* **The field:** x 310-970, y 206-546. Keep it clear; that is where the game is
  played.
* **Where players walk:** inside the fence, x 112-1168, y 184-572. Scenery never
  blocks anyone, but a big tree in the middle of the farm will hide a player
  walking behind it.
* **Phones** show extra width at the sides: on a 20:9 phone about 160 px left
  of x = 0 and right of x = 1280. That is why a few trees sit at negative x or
  past 1280. On a computer they are simply off screen.
* **On phones**, the joystick sits over the bottom-left corner and the tool
  buttons over the bottom-right corner.

## 5. The fence

Select `Fences` and change **Top Left**, **Bottom Right** or **Post Spacing** in
the Inspector. The fence redraws itself with posts on every corner.

What actually stops the players is `Boundary` (four invisible walls) together
with `PLAY_AREA` in `scripts/autoload/config.gd`. If you move the fence a long
way, move those to match, or players will walk through it or stop short of it.

## 6. Try it

* **F6** (Run Current Scene) runs just the farm in a window.
* `run_mobile_preview.bat` shows it on a phone-shaped screen.
* `run_tests.bat` checks the layout is still sound. It fails if, say, a
  decoration layer is moved above the players or given a collision shape.

## 7. Making new art

The decoration pictures are drawn by `tools/generate_assets.py`, in the same
palette as the rest of the game (look for the `decor` section). Change a colour
or a shape there, then run:

```
pip install pillow
python tools/generate_assets.py
```

All sprites are regenerated; the existing ones come out identical. You can also
drop your own PNG into `assets/decor/`. If you do, record where it came from in
`ASSET_SOURCES.md`.
