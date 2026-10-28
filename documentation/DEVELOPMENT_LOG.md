# FarmSim development log

A record of what was actually built, actually tested, and what actually went
wrong. Written after the work, not before it. Entries describe events that
happened; anything not yet verified is marked as such.

Methodology: Design Science Research provides the overarching frame (problem
identification, design, development, demonstration, evaluation). Development
inside the design/development activity is run in short agile increments, each
with its own acceptance criteria. Agile does not replace DSR here; it is the
method used inside one DSR activity.

---

## 2026-09-09 — Stage 0: inspection and toolchain

**Task.** Inspect the supplied project, determine the Godot version, decide how
the project would be built, run and tested.

**What was found.**

- The project folder — then `C:\Github\farm-sim-ai-opus`, renamed to
  `C:\Github\FarmSim Research` on 14 September 2026 — was a blank Godot project:
  `project.godot`, `icon.svg`, `.gitignore`, `.gitattributes`, `.editorconfig`
  and a `.godot` cache directory. No scenes, scripts, assets or configuration
  beyond the defaults.
- Godot **4.7**, GL Compatibility renderer, Jolt physics, D3D12 on Windows.
- The `.godot` cache had been generated the same day, so the project had been
  opened in the editor at least once.

**Problem encountered.** The development environment could not execute Godot.
Three separate routes were tried and all three were unavailable:

1. The sandboxed Linux shell on the development machine failed to start
   ("Workspace unavailable"), so no commands could be run on that machine.
2. The cloud build container has no Godot, and its network allowlist blocks
   `godotengine.org` and GitHub release downloads, so the engine could not be
   installed there. The npm and PyPI registries are reachable but ship no Linux
   x86_64 Godot binary (`@ringozz/godot` publishes macOS, Windows and wasm
   builds only).
3. Direct control of the Godot editor was not available.

**Godot MCP.** Several Godot MCP servers exist on npm (`@yanhuifair/godot-mcp`,
`@coding-solo/godot-mcp`, `godot-mcp-runtime`, `breakpoint-mcp` and others). All
of them operate by launching the Godot executable on the host machine, so all of
them depend on the same missing capability. No MCP was installed. Nothing in
this project pretends otherwise.

**Solution adopted.** A file-based build/test loop:

- The project is authored in the build container and written into the project
  folder.
- The project ships its own automated test suite plus `run_tests.bat`, which
  locates Godot, runs the suite headlessly, and writes machine-readable results
  and full engine output into `test_out/`.
- Those output files are read back and drive the next debugging iteration.

This keeps the engine in the loop — every test assertion is executed by real
Godot — at the cost of one manual double-click per test cycle.

**Design consequences.** Two decisions follow directly from not being able to
open the editor, and both turned out to be good for a research artefact anyway:

- **Scenes are thin.** Each `.tscn` file is a root node plus a script; the
  contents are built in `_ready()`. Screen structure is therefore plain source
  that can be diffed, reviewed and asserted on by the test suite.
- **Simulation is tick-driven through an explicit entry point.** Gameplay
  systems expose `simulate(delta)` rather than doing their work only inside
  `_process`, so tests can advance a whole season deterministically in
  milliseconds instead of waiting on wall-clock time.

**Next.** Stage 1 — project foundation.

---

## 2026-09-09 — Stage 1: project foundation

**Task.** Establish the architecture, the singleton layer, the session flow
shell, and the automated test harness that every later stage depends on.

**Implemented.**

- `project.godot`: application name and description, 1280x720 viewport, main
  scene, and five autoloads.
- `Config` — every tunable value for the world, crops, water, pests, tools and
  roles in one place.
- `InputSetup` — the two-player control scheme, registered in `InputMap` at
  startup. Written in code with named `Key` constants rather than stored in
  `project.godot`, so the binding table is readable source and the test suite can
  assert against it.
- `GameState` — anonymous session id, roles, assessment scores, scenario
  results.
- `GameplayLogger` — timestamped event log and the session JSON writer. It
  writes to `data/sessions/` when that directory is writable and falls back to
  `user://sessions/` otherwise.
- `SessionController` — the whole session flow: menu, setup, pre-test, three
  scenarios, results, quizzes, post-test, final results. It knows nothing about
  how a crop grows, and the farm knows nothing about session flow.
- Screens: boot, main menu, instructions, player setup, and one reusable
  assessment screen driven entirely by JSON.
- Data: `data/scenarios.json` and five assessment instruments.
- `tests/` — the test framework, the runner, and six test cases.
- `run_tests.bat`, `run_game.bat`, `tools/run_farmsim.ps1`,
  `tools/validate_project.py`.

**Deliberately not implemented yet.** The farm itself. `scenes/farm/farm.tscn`
contains a placeholder that says so on screen and records no gameplay result.
The scenario-results and final-results screens do not exist yet either, and are
reported as "scheduled for a later stage" by the validator rather than being
silently broken.

**Tested (in the build container, before delivery).**

- `gdparse` (gdtoolkit 4.x) parsed all 16 GDScript files with no syntax errors.
- `tools/validate_project.py` passed: every `ext_resource`, autoload and
  `res://` reference resolves, every `load_steps` count matches, and all six JSON
  data files parse.

**Not yet tested.** Nothing in this stage has been executed by the Godot engine
yet. Parsing is not running: it catches syntax errors but not a wrong method
name, a wrong signature or a bad assumption about the API. The Stage 1
acceptance gate is the first run of `run_tests.bat`.

**Next.** Run `run_tests.bat`, fix whatever it reports, and only then start
Stage 2 (assets, farm environment, players).

---

## 2026-09-09 — Stage 1 acceptance gate: PASSED

`run_tests.bat` was executed on the development machine.

- Godot located automatically at
  `C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`,
  reporting `4.7.2.stable.steam.ed1daf0bf`.
- Import step completed, then the suite ran headlessly.
- **393 assertions passed, 0 failed.** `godot_stderr.log` was empty: no runtime
  errors and no warnings from the engine.

So the whole loop works end to end: build in the container, write to the project
folder, execute with the real engine, read the results back. Every claim from
here on rests on a real run.

**One defect found and fixed.** `runner.log` recorded blank exit codes for both
Godot invocations. `Process.WaitForExit(int)` in PowerShell can return before the
exit code is populated; the parameterless `WaitForExit()` has to be called
afterwards to flush it. Fixed in `tools/run_farmsim.ps1`.

---

## 2026-09-09 — Stage 2: assets, farm, players, farming, water, events

Bigger slice than the roadmap's Stage 2. That was a deliberate trade: each test
cycle costs a human double-click, so batching a coherent, fully testable chunk is
cheaper than five small ones. The chunk is still coherent - it is everything
needed to play one season - and every part of it has automated coverage.

**Assets.** `tools/generate_assets.py` produces the whole 29-sprite pack: ground,
tilled soil, well, fencing, four growth stages each for maize and beans, stubble,
two players, six tool icons, and the pest/drought/warning indicators. No pack was
downloaded, because the build environment could not reach an asset host to verify
a licence at source, and an unverified licence in an academic artefact is worse
than plain graphics. `ASSET_SOURCES.md` records all 29 files. The generator is
committed with them, so the pack can be regenerated and audited.

The first attempt at the tilled-soil tile read as wooden planking rather than
furrows. Redrawn with thinner furrow lines over a speckled base.

**Implemented.**

- `crop_tile.gd` - soil state, crop, growth, moisture, condition, pest pressure,
  and the per-tile record that ends up in the research data. Growth runs at full
  speed only above the healthy-moisture line, at a quarter speed under stress.
  Condition lost to stress or pests recovers only partially, which is what makes
  "keep it out of stress" a better strategy than "rescue it later".
- `field.gd` - the 8x5 grid, aggregate counts, neighbour lookup, and the
  "which tile am I standing on" query.
- `water_reserve.gd` - one reserve per farm. Draws larger than what is left are
  refused outright rather than partially served, so a shortfall is unambiguous
  both on screen and in the data.
- `environment_event.gd` - configurable events. Drought raises the drying rate
  from the moment it fires; the pest outbreak seeds a set number of tiles and
  then spreads from untreated ones to their neighbours.
- `player.gd` - movement, facing, tool carrying, and the tile underfoot. The
  player owns no farming rules; it emits `use_requested` and the farm decides.
- `farm.gd` - assembles the world, owns the season clock, resolves every action,
  and builds the season result including the causal explanations.
- `farm_hud.gd` - season clock, field counters, per-player panels, event banner,
  and the shared reserve given the most prominent position on screen because it
  is the thing the two players have to negotiate over.
- `scenario_results.gd` and `final_results.gd`.

**Design decisions.**

- A `HARVEST` tool was added to both roles. Harvesting is a shared outcome, so
  neither role owns it; the split stays where it matters (only the Planter tills
  and sows, only the Monitor scouts and treats).
- Role enforcement is in two places: a player can only select tools its role
  carries, and `farm.perform_action` refuses an out-of-role tool anyway. The
  second check is unreachable from the keyboard and exists so the split cannot be
  bypassed by a future caller.
- A fresh pest infestation is deliberately *not* visible from across the field.
  It becomes visible once damage passes a threshold, or immediately if the
  Monitor scouts the tile. Without that, scouting would be pointless and the
  early-detection idea would not be in the game.
- `average_condition` now includes already-harvested tiles. It previously
  averaged only standing crops, which meant a season where everything was brought
  in successfully reported 0% condition. Caught while writing the pest test.

**Retuning after doing the arithmetic.** The original reserves did not create the
decision they were supposed to. Maize needs roughly four waterings to reach
maturity, so twelve tiles cost about 130 litres; the baseline's 150 was tight
rather than comfortable, and the drought's 54 was not obviously distinguishable
from it. Now: baseline 220 litres (water is genuinely not the constraint),
drought 60 litres with a 2.6x drying multiplier once the event fires and a stated
target of 8 tiles (the reserve supports about three - so the scenario is a
question about how much ground to commit to), pest season 170 litres (water is
not meant to be the problem there).

**Tested.** Nine new automated cases, all executed by the engine:
`test_assets`, `test_crop_tile`, `test_water_reserve`, `test_farm_environment`,
`test_farming_loop`, `test_environment_events`, `test_scenario_playthrough`,
`test_session_flow`, `test_player_movement`.

Notable coverage: a full till-sow-water-grow-harvest loop through the same entry
point the keyboard uses; a watered tile compared against a neglected one; both
players drawing from one reserve; the reserve refusing draws when empty; the
drought changing the drying rate at the scripted moment and a protected tile
outliving an abandoned one; the pest outbreak infesting, hiding until scouted,
spreading, and being treatable; the same pest season played twice with identical
seeds where the only difference is whether the Monitor responds; all three
scenarios played to completion with a scripted strategy; the whole session flow
from setup to written JSON; and two players moving under real physics with real
key events fed through the input system.

**Not covered by automation, and stated as such.** How the game *feels* with two
people at one keyboard - reach, pace, whether the season length is right, whether
the HUD is readable at a glance. The playthrough tests call the farm's action
entry point directly rather than walking a character to a tile. That needs a real
play session.

**Next.** Run `run_tests.bat`, fix what it reports, then play it.

---

## 2026-09-09 — Stage 2 acceptance gate: FAILED, then fixed

`run_tests.bat` and `run_game.bat` were both run on the development machine.
The suite reported 696 passed, 67 failed, and the farm rendered as an empty
grey window during play.

**Root cause — one line.** `test_out/godot_import_stderr.log` had it:

```
SCRIPT ERROR: Parse Error: Cannot infer the type of "sown" variable because the
value doesn't have a set type.
   at: GDScript::reload (res://scripts/farm/farm.gd:387)
ERROR: Failed to load script "res://scripts/farm/farm.gd" with error "Parse error".
```

`build_result()` had `var sown := field.planted_count() + ...`. `field` is
declared `Node2D`, so its methods return Variant to the analyser and `:=` has
nothing to infer from. `farm.gd` therefore failed to compile, `farm.tscn` loaded
with no script attached, and the farm scene built nothing — hence the grey
window. The same mistake was in `tests/farm_fixture.gd`. Both now carry explicit
type annotations.

**Three process failures this exposed, all now closed.**

1. **The test suite reported four dead cases as passing.** `test_farm_environment`,
   `test_farming_loop`, `test_environment_events` and `test_player_movement` all
   recorded "0 passed, 0 failed" and were counted green. A GDScript runtime error
   aborts the running function without stopping the engine, so a case that died
   on its first line looked identical to a case with nothing to check. The runner
   now treats a case that produced no assertions as a failure.
2. **No test compiled the scripts.** Only scripts reachable from a scene that a
   test happened to instantiate were ever loaded. `test_scripts_compile.gd` now
   loads every `.gd` file under `scripts/` and `tests/` through the engine and
   checks each one compiles and resolves its base class.
3. **The launcher hid the evidence.** The import step wrote its stderr to a file
   nobody looked at, and logged a blank exit code. `run_farmsim.ps1` now starts
   Godot through `System.Diagnostics.Process` (which reports exit codes
   reliably, unlike `Start-Process -PassThru`) and echoes import errors into
   `runner.log` with an explicit warning that a script failing to compile shows
   up as a blank screen rather than a crash.

**Static checking improved too.** `gdparse` is a syntax parser and cannot see a
type-inference error. `tools/validate_project.py` now flags
`var x := <opaque>.method()` where the receiver is declared as `Node`, `Node2D`,
`Object`, `RefCounted` and similar — the exact shape that got through. The
checker was regression-tested against the original faulty line before being
kept.

**Other fixes in the same pass.**

- **Layout.** The shared-water panel occupied y 112–190 while the field started
  at y 176, so the panel sat over the top row of crops. The field moved to
  y 200 and the walkable area to y 196–600. The HUD now publishes its reserved
  bands as constants (`TOP_RESERVED_HEIGHT`, `BOTTOM_RESERVED_HEIGHT`) and
  `test_farm_environment` asserts the walkable area stays clear of both, so a
  player can never end up standing behind a panel.
- **Geometry assertions.** Since nobody can look at the window from the build
  environment, the next best thing: the field, the walkable area, both spawn
  points, the well and every tile are asserted to be inside the 1280x720
  viewport, and the field inside the walkable area.
- **A blank frame no longer looks like an engine error.** The default clear
  colour is now the game's own dark green, and the farm draws a solid green
  backdrop behind its tiled grass.
- **The farm prints what it built.** One line per run —
  `[farm] scenario=... tiles=40 players=2 hud=yes water=220L event=none` — so a
  graphical run leaves evidence in `godot_output.log` even with nobody watching.
- **New test: `test_results_screens.gd`.** Plays a real season, pushes the
  result through the session controller exactly as the farm does, instantiates
  the scenario-results and final-results screens, and reads the text they
  actually put on screen: the harvest figures, every causal explanation, the
  pre/post scores and the change between them. The scene-load test could not
  catch this join, because a results screen with nothing to show renders
  perfectly happily.

**Honest status.** These fixes are statically verified only — all 18 GDScript
files parse, the reference and type-inference checks pass. They have not been
executed yet. The next `run_tests.bat` is the gate.

---

## 2026-09-09 — Stage 2 acceptance gate: PASSED (1078/1079), plus a UI rebuild

`run_tests.bat`: **1078 assertions passed, 1 failed.** Every previously dead
case now runs and passes, exit codes are real, and `runner.log` carries the
`[farm]` build line:

```
Import exit code: 0
[farm] scenario=baseline crop=maize tiles=40 players=2 hud=yes water=220L event=none
FarmSim exit code: 0
```

**The one failure was a genuine data bug.** `test_farming_loop` reported
"refused waterings are counted (expected > 0, got 0)". `Farm._water_tile()`
checked `water.can_draw()` and returned early, so it never reached
`WaterReserve.draw()` — which is where refusals are counted. The drought
scenario's causal feedback reports that number, so every real session would have
said "irrigation was refused 0 times" no matter how often the reserve ran dry.
Now the farm simply asks `draw()` and branches on the answer.

### The interface

A play session showed the farm rendering correctly but the interface badly
wrong: the shared-water panel had become a tall narrow column with "Shared water
reserve" stacked one letter per line, sitting on top of the crop beds and
running off the bottom of the window. The player panels were clipped by the
window edge.

**Cause.** `UiKit.label()` set `AUTOWRAP_WORD_SMART` on every label it made. A
wrapping label reports a near-zero minimum width, so an `HBoxContainer` — which
hands out minimum widths to children that do not expand — squeezed it to one
character per line. Its minimum *height* then became twenty lines tall, and a
Control whose minimum size exceeds its anchored size grows to fit. The panel
inflated downwards over the field.

**Fix.** `label()`, `dim()`, `heading()` and `title()` are now single-line;
`paragraph()`, `body()` and `note()` wrap and set `SIZE_EXPAND_FILL`. Wrapping
is now something a caller opts into where a real width exists.

**And a rebuild of the layout, because it was cramped as well as broken.**

- The HUD is three bands: a top bar (8–104), a full-width water band under it
  (112–176), and two player panels along the bottom. The middle of the screen
  belongs entirely to the farm.
- The shared reserve is now a wide horizontal band — icon, caption, a bar that
  fills the remaining width, the litre figure, and the status note — rather than
  a floating box over the crops. It is still the most prominent element, which
  is the point, but it no longer competes with the field for space.
- The field counters became six small chips (sown / growing / ready / harvested
  / dry / pests) instead of one run-on line that wrapped.
- The briefing text was removed from the top bar. It was being truncated at 90
  characters mid-sentence; it belongs on the results and instruction screens.
- Feedback messages are capped at two lines with an ellipsis, and the scenario
  title trims with an ellipsis, so no label can ever inflate its panel again.
- The field went from 8x5 to **10x5 tiles** and moved to y 216. The old layout
  left large empty margins left and right while being vertically cramped; the
  wider plot uses the space and leaves room at both sides for the well and the
  players.
- The plot now reads as a plot: a dark earth border is drawn under the grid with
  a "Crop beds" caption, and the tile grid lines went from nearly invisible
  (alpha 46) to legible (alpha 120). Untilled tiles are grass, which was
  previously indistinguishable from the surrounding grass.

### New test: `test_hud_layout.gd`

The reason nothing caught the vertical-text panel is that every assertion was
about data, and the geometry checks used the configured constants rather than
the sizes the engine actually calculated. This case waits for a real layout
pass and then measures:

- each band's actual global rect is on screen, inside its reserved band, and
  does not intersect the crop beds;
- the water band is wide and shallow (>800 px across, <100 px tall) — a direct
  check that it has not become a column;
- the player panels do not overlap each other and are not cut off by the bottom
  of the window;
- **no label is narrower than 30 px, and none needs more than three lines** —
  which is precisely the failure that shipped;
- the figures on screen match the farm underneath.

**Honest status.** The layout arithmetic was verified numerically and rendered
as a schematic mock before delivery, but the rebuilt HUD has not yet been
executed. The next `run_tests.bat` is the gate, and the next `run_game.bat` is
the only thing that can confirm it looks right.

---

## 2026-09-11 — Stage 2 confirmed, and Stage 3: full-flow verification

`run_tests.bat`: **1132 passed, 10 failed.** The rebuilt HUD held up; the ten
failures were all in the new layout test, and both causes were worth finding.

**1. The layout test was measuring against the wrong rectangle.** It built its
screen rect from `display/window/size/viewport_*` (1280x720) but read Control
rects out of the live root viewport, which headless sizes differently. Bottom-
anchored panels sat at y 1144 and looked off screen. The test now measures
against `get_tree().root.get_visible_rect()` - the viewport the Controls were
actually laid out in.

**2. A real 2-pixel overflow underneath it.** The player panel's content needs
126 px and the band allowed 124, so the panel grew past its own bottom edge.
Band allowance raised; the panel now has 130 px for 126 px of content.

**3. `test_scripts_compile` crashed the GDScript VM.** stderr carried
`Internal script error! Opcode: 31 (please report)`. Forcing a fresh compile of
already-loaded, currently-executing scripts with `CACHE_MODE_IGNORE` and then
calling methods on the resulting GDScript object did it. The check is now a plain
`load()` and a type test - which is exactly the signal that caught `farm.gd`'s
parse error in the first place. Worth noting that the case had been silently
aborting partway through and still reporting green; the "no assertions means
failure" rule added last cycle did not catch it because it had already recorded
73 passes before dying. A case that stops early with some assertions still looks
healthy. Not solved, and recorded here as a known limitation of the harness.

### Stage 3: the things a session needs that it did not have

**Briefing screen** (`scenes/ui/scenario_briefing.tscn`). Each season now opens
with its own screen: title, crop, the scenario's briefing text, its objectives,
and both roles with their controls and tool sets. The clock starts only when the
players press through it. This is where the briefing text belongs - it was
previously truncated at 90 characters in a HUD bar, which is how nobody read it.

Flow changed accordingly: `start_next_scenario()` now opens the briefing and
`begin_scenario()` starts the season. `Phase.SCENARIO_BRIEFING` sits between the
pre-test and the first season.

**Pause screen** (`scripts/ui/pause_overlay.gd`). `Esc` freezes the tree. The
overlay runs on `PROCESS_MODE_ALWAYS` so it can still see the key and drive its
own buttons while everything else is stopped; the farm clock, the crops and both
players are on the default mode and stop dead. It shows both control sets, and
offers Resume or "Abandon and return to menu" - which writes a partial session
file rather than discarding the run.

Pauses are logged. A pair who stopped for two minutes mid-drought did not have
the same session as a pair who ran straight through, and the event log now says
so, with the duration.

**The farm always hands its result to the controller.** That call used to be
skipped in test mode, which meant the farm-to-controller join was the one seam
no test ever crossed. The controller's scene change is already a no-op under
test, so the guard bought nothing and hid something.

### New test: `test_full_session.gd`

The strongest automated version of "play it from start to finish". Nothing in it
is a stand-in:

- the pre-test is answered by pressing the option buttons on the real assessment
  screen, loaded from the real instrument, choosing three correct answers on
  purpose so the expected score is known;
- each briefing is opened, its objectives and both roles checked against the
  scenario definition, and its start button pressed;
- each season is played on the real farm scene until it ends on its own;
- the pause screen is opened mid-season and its effect on the tree verified;
- each results screen is checked for every causal explanation the season
  generated, then its continue button pressed;
- each quiz is answered the same way;
- the post-test is answered with seven correct, giving a known +50 point change.

Then it reads the session file that comes out and checks it against what
happened: three seasons in order with real tile records and real water figures,
the drought not out-yielding the settled season, both events recorded as fired,
five instruments completed, gameplay events attributed to a player and a role,
and no personal-data field anywhere. A copy is left at
`test_out/sample_session.json` for inspection and the synthetic run is deleted
out of `data/sessions/`.

**Still not covered, and it cannot be from here:** two people at one keyboard.
Walking, reach, pacing, whether a season is the right length, whether the HUD is
readable at a glance. Those need a real play session.

---

## 2026-09-12 — Stage 3 acceptance gate: PASSED, then two design faults found in the data

`run_tests.bat`: **1302 assertions passed, 0 failed**, `godot_stderr.log` empty.
`run_game.bat` played through and the log shows all three seasons reached:

```
[farm] scenario=baseline crop=maize tiles=50 players=2 hud=yes water=220L event=none
[farm] scenario=drought  crop=maize tiles=50 players=2 hud=yes water=60L  event=drought
[farm] scenario=pest     crop=beans tiles=50 players=2 hud=yes water=170L event=pest
```

Every case green, including the full end-to-end session. The produced session
file is well formed: 209 events, three seasons with per-tile records, five
instruments, a 3/8 to 7/8 pre/post change, no personal-data field anywhere.

**But reading the data rather than the assertions turned up two faults that
every test had passed over.**

### 1. Seasons were ending after a quarter of their length

Every season in the sample file ended at 46-56 seconds against a 200-second
duration, with `end_reason: field_complete`. `_field_is_finished()` ended the
season the moment the last worked tile was harvested - with forty untouched
tiles and two and a half minutes left on the clock.

For a game that would be a nuisance. For research it is worse: two pairs who
farm differently get different amounts of exposure, and the comparison between
them is weakened for a reason that has nothing to do with what they learned.
Seasons now always run their full length.

That change made a second bug visible. With a season long enough to work a tile
more than once, `harvested_yield` was overwritten by the next harvest, so a
re-used tile silently reported only its last crop. `CropTile` now carries
lifetime counters - `harvest_count`, `failed_cycles`, `lifetime_yield`,
`lifetime_condition_sum`, `ever_sown` - which survive re-tilling, and the
season result is built from those.

### 2. Over-committing during the drought was the winning strategy

With the early ending removed, a forward simulation of the scripted policy said
this:

```
drought  spread  2 -> harvests  8 | yield  80.0
drought  spread 12 -> harvests 12 | yield 120.0
```

Sowing twelve tiles during a drought **out-yielded** sowing two. The reason is
that maize matured in 42 seconds, so a 200-second season fitted four cycles:
twelve tiles banked twelve early harvests during the cheap pre-drought phase
before the reserve ran dry, and that beat two tiles farmed carefully throughout.

The scenario existed to teach the opposite. A season that grows four maize crops
is also not a season. **One crop now occupies most of a season** - maize 140
seconds, beans 120 - which fixes the agronomy and the incentive at once:

```
baseline spread 10 -> harvests 10 | yield 100.0 | cond 100% | failed  0 | refused   0
drought  spread  2 -> harvests  2 | yield  20.0 | cond 100% | failed  0 | refused   0
drought  spread 12 -> harvests  0 | yield   0.0 | cond   0% | failed 22 | refused 561
pest     spread 10 -> harvests 10 | yield  80.0 | cond 100% | failed  0 | refused   0
```

### The water economy is now a calculation, not a guess

`Config.litres_to_sustain(crop, tiles, seconds, drying_multiplier)` returns the
litres needed to keep an area continuously out of stress for a whole season.
Every reserve is set against it and the test suite asserts the relationship:

| Scenario | Target | Demand | Reserve | Ratio | Intent |
| --- | --- | --- | --- | --- | --- |
| Baseline | 10 tiles | 250 L | 380 L | 1.52 | water is not the constraint |
| Drought | 4 tiles | 260 L | 140 L | 0.54 | the reserve cannot cover the target |
| Pest | 10 tiles | 220 L | 300 L | 1.36 | the outbreak is the problem, not water |

Supporting changes: maize dries at 0.025/s and beans at 0.020/s, and one
watering delivers 0.60 moisture - about 24 seconds of maize drying - which is
what sets how much ground two people can realistically keep alive.

### A third fault, in the condition figure

Averaging condition over harvests alone meant a season that killed three tiles
scored the same as one that saved them, because dead crops were simply left out
of the average. A crop that died is an outcome, not an absence of one, and now
counts as zero.

**Honest status.** All of this is verified by arithmetic and by a forward
simulation of the policy, not yet by the engine. The next `run_tests.bat` is the
gate. And the tuning above is a starting point, not a finding: whether a
200-second season feels right, and whether the drought's 140 litres reads as a
hard decision or as an unfair one, is a judgement for play-testing, not for me.

---

## 2026-09-12 — The page screens had the same fault the HUD had

Screenshots from a play session: on the quiz, the question text and the option
buttons ran off the right-hand edge of the window; on the briefing, the "Start
the season" button was cut off by the bottom of it. Both are the same class of
fault the water panel had, and both had been sitting there through every run
because the HUD had a layout test and the page screens did not.

**Why the text ran off the side.** Killing autowrap everywhere fixed the HUD but
broke the page screens. The assessment question is built with `UiKit.heading()`,
and a non-wrapping Label reports its whole text width as its minimum - so an
80-character question demanded about 1400 px and dragged the column out past the
window with it. A `Button` does the same thing with its own text, which is what
happened to the four quiz options.

Headings and titles live inside page columns that have a real width, so they now
flow again; only the HUD's single-line captions stay fixed. Long-labelled buttons
get a new `UiKit.wide_button()`, which wraps where the engine supports it and
clips where it does not. Either way the text can no longer decide the layout.

**Why the button fell off the bottom.** Nothing scrolled. A screen taller than
the window simply lost whatever was at the bottom of it.

`UiKit.page_column()` was rebuilt around that:

- a `ScrollContainer` with horizontal scrolling disabled, so anything taller than
  the window can still be reached;
- the column takes a *share* of the window rather than a fixed number of pixels.
  `preferred_width` is now a preference: 900 becomes 70% of the window, which is
  866 px at 1280 and narrows with the window instead of running off it.

Vertical centring still works on the short screens - the scroll container hands
the row its full height when no scrollbar is needed, so `alignment` keeps doing
what the menu expects.

### New test: `test_screen_layout.gd`

The analogue of `test_hud_layout` for the seven page screens, and it would have
caught both faults. It gives each screen a hard case to render - a real drought
season played twelve tiles wide, so the results screens have to lay out the
longest explanations the prototype ever produces - waits for a real layout pass,
and then checks that:

- no visible label or button crosses either side of the window;
- every screen has a scroll container, so vertical overflow is always reachable;
- no button is cut off vertically while the content still fits the window;
- the column is narrower than the window and still usably wide.

### The type-inference checker earned its keep twice

Writing the new test tripped `tools/validate_project.py` twice. The first was a
false positive - `var x := node.method() as Control` does have a type - and the
checker now ignores a trailing cast. The second was real: `var column_rect :=
column.get_global_rect()` on a `Control`-typed variable, which is exactly the
fault that stopped `farm.gd` compiling and produced a blank grey screen. Caught
before delivery this time rather than after a play session.

**Honest status.** Statically verified: all 47 scripts parse, references and type
inference clean, and the column arithmetic checks out at 1280 (866 px column,
183 px gutters). Not yet executed - the next `run_tests.bat` is the gate, and the
screenshots after it are the real answer.

---

## 2026-09-14 — Project folder renamed

The project folder was renamed from `C:\Github\farm-sim-ai-opus` to
`C:\Github\FarmSim Research`. Recorded here so that earlier entries, and the
paths in `test_out/runner.log`, remain traceable to the same project.

Nothing in the project depends on the folder name: `tools/run_farmsim.ps1`
resolves the project root from its own location (`Split-Path -Parent
$PSScriptRoot`), and both batch files call through it, so `run_game.bat` and
`run_tests.bat` continue to work unchanged.

`test_out/runner.log` still names the old path. It is generated output from a run
that actually happened under that name and has deliberately not been edited; the
next `run_tests.bat` will overwrite it with the new one.

---

## 2026-09-14 — Rebuilt as scenes: real node hierarchies and six named systems

The Godot MCP was connected to the editor, and opening the project through it
made a design decision from the earliest entries visible as a problem: **every
scene in the project was a single root node with a script attached, and every
node the game actually used was created at run time.** `farm.tscn` was 178 bytes.
`main_menu.tscn` was 263. The grass, the plot, the fences, the well, the
collision boundary, the fifty crop tiles, both players, every HUD band and every
label on all seven screens existed only as `.new()` calls inside `_ready()`.

That was a reasonable choice when it was made - the build environment could not
run the editor, so a code-built interface was the only structure the automated
suite could inspect. It is the wrong choice now that the editor is available: a
scene tree that exists only at run time cannot be selected, moved, re-skinned or
even looked at, and "open the project in Godot and change the field layout" was
not a thing anyone could do.

### What changed

Everything the game shows is now an authored node.

| Scene | What it holds now |
| --- | --- |
| `scenes/farm/crop_tile.tscn` | Ground, Crop, Border, Highlight, MoistureTrack, MoistureFill, Marker |
| `scenes/farm/field.tscn` | 50 instances of the tile scene, named `Tile_<col>_<row>` |
| `scenes/farm/player.tscn` | CollisionShape2D, Body, Tag, ToolIcon |
| `scenes/farm/farm.tscn` | the whole environment, listed below |
| `scenes/ui/farm_hud.tscn` | the three HUD bands, both player panels, the event banner |
| `scenes/ui/pause_overlay.tscn` | the pause page |
| `scenes/ui/*.tscn` (7) | the seven screens, each a page column |
| `scenes/ui/components/*.tscn` | role card, stat card, quiz option - reused across screens |

The scripts kept their logic and lost their construction code: `crop_tile.gd`
swaps textures on nodes it no longer creates, `farm_hud.gd` puts numbers into
labels it no longer builds, and each screen script fills in the handful of things
that genuinely come from data - a scenario's objectives, a season's causal
explanations, a quiz's options.

`ui_kit.gd` is no longer a UI builder. What is left of it is the palette, the
font sizes, and five label helpers for those data-driven lists. Colours, font
sizes and panel styles now live in **`assets/ui/farm_sim_theme.tres`**, as named
type variations (`Title`, `Heading`, `Stat`, `Dim`, `Note`, `PanelLight`,
`HudPanel`, `WaterPanel`, `BannerPanel`, `ClockBar`, `WaterBar`) that are
selectable from the Inspector.

### The three named systems, and the three that were already implied

The farming rules used to sit in one `match` statement in `farm.gd`. They are now
six nodes under `Farm/Systems`, each with its own script:

```
Systems
├── PlantingSystem     hoe, seed                      FR-001
├── IrrigationSystem   watering can; the only thing that spends the reserve
├── HarvestingSystem   sickle; yield and average condition   FR-004, FR-005
├── ScoutingSystem     scout, pest treatment
├── GrowthSystem       time passing in the field
└── WeatherSystem      drought / pest outbreak        FR-002
```

They share a small base class, `scripts/systems/farm_system.gd`: a system
declares which tools it handles, and `farm.gd` asks whichever one claims the tool
that was used. **No system holds tile state.** The tiles remain the single source
of truth, which is what keeps two players, the scripted test harness and any
future tutorial farming through one set of rules rather than three. Adding a
seventh system is adding a node under `Systems`; `farm.gd` does not change.

`WeatherSystem` is the old `environment_event.gd` promoted from a `RefCounted`
to a node. `farm.event` still points at it, so the season record and the event
tests did not change. `scripts/farm/environment_event.gd` is now a one-line shim
and can be deleted.

### Acceptance gate

`run_tests.bat`, run headless: **1413 assertions passed, 0 failed**, and
`godot_stderr.log` empty - no runtime errors and no warnings anywhere in the run.

The suite was the reason this was worth doing rather than risky. Its public
surface was left alone on purpose - `farm.field`, `farm.water`, `farm.event`,
`farm.players`, `farm.simulate()`, `farm.perform_action()`, `farm.build_result()`
and the `Well` / `Fences` / `Boundary` / `WaterReserve` node names all still mean
what they meant - so 1409 of those assertions are the same assertions as before,
checking the same numbers against a completely different construction. Every
layout case passed unchanged: `test_hud_layout` 62, `test_screen_layout` 51,
`test_farm_environment` 61, `test_full_session` 176.

Only one test had to be updated for the rebuild: `test_crop_tile` built its
tiles with `CropTile.new()` and now instantiates `crop_tile.tscn`, because the
tile's ground and moisture bar are nodes rather than constructor output.

### Four failures that were waiting in the suite

The first run found four failures, all of them older than this rebuild. The
2026-09-13 entry ends "**Not yet executed** - the next `run_tests.bat` is the
gate", and the 12th's retuning of the reserves and the growth times had not been
through the suite since. All four trace to numbers in files this rebuild did not
touch:

1. **"the reserve can be spent completely"** expected the drought reserve to
   reach exactly zero. It holds 140 L and a watering costs 3 L, so the last 2 L
   can never be drawn - partial draws are refused on purpose, because a
   half-watered tile is a shortfall the players cannot see. Verified directly
   against the untouched `water_reserve.gd`: 140 L drawn in 3 L steps leaves
   2.0 L. The assertion now reads "spent down to less than one watering", and the
   loop stops at the first refusal instead of spinning 454 of them.
2. **"a crop with no condition left dies"** set `health = 0.0` on a well watered
   tile and expected it to die. A watered, pest-free tile recovers condition every
   tick, so it came back to 0.002 and stayed alive. That state is unreachable in
   play - condition only reaches zero by starving - so the test now leaves the
   tile dry as well, which is the case it meant to describe. (**The model was
   left alone**: whether a crop at exactly zero condition should be able to
   recover at all is a question for the supervisor, not a bug to fix quietly.)
3. **"the failed cycle is counted"** was downstream of 2.
4. **"over-committing during a drought ... irrigation gets refused"** asked the
   scripted policy to provoke a refusal it is written to avoid: it checks the
   reserve before watering, exactly as a pair who can read the water bar would.
   It does run the reserve dry, which is what that comparison is actually about,
   so the assertion now checks the reserve was emptied. The refusal itself - the
   message players get when the reserve cannot cover another watering - is
   covered directly in `test_farming_loop`.

Nothing in the simulation was retuned to make any of these pass. The crop model,
the water economy, the scenario definitions and the session logging are
byte-for-byte what they were.

---

## 2026-09-14 — The project goes under version control

Chapters 2 and 3 claim a GitHub repository. There is one -
`github.com/sulaimansulaman-dev/FarmSim-Research` - but it had been cloned one
folder too deep: the only `.git` in the tree sat in
`C:\Github\FarmSim Research\FarmSim Research\`, and it tracked GitHub's generated
README and nothing else. **No scene, script, asset or data file in this project
had ever been committed.** Every acceptance gate, every rebuild and every
retuning recorded above happened outside version control.

`init_git_history.bat` fixes it. It *moves* that `.git` up to the project root
rather than starting a new repository, so the existing `origin` remote and the
commit already on `origin/main` are kept and a later `git push` needs no force.
It then records the current tree as twenty-six commits - one per part of the
build, and one for each of the six farm systems - so the history reads as
something other than a single 200-file dump. It pushes nothing; it prints the
push command and stops.

### What these commits are, and what they are not

They are all dated today. They are an **import of the current state in readable
pieces**, not a reconstruction of when each part was written, and they must not
be presented as development dates. Anyone reading `git log` will see twenty-six
commits made within a minute of each other, which is exactly what happened.

This log is the chronology. It is contemporaneous, it records what each
acceptance gate actually found rather than what was intended, and it is what the
treatise should cite for when work happened. The repository from here on is a
real record; everything before this entry is not, and the honest thing is to say
so in the methodology rather than let a reader infer otherwise from commit
metadata.

### Also

A root `.gitattributes` now normalises line endings - LF for Godot's text
formats so a scene diff is readable on any machine, CRLF for the Windows batch
and PowerShell files so they still run, binary for the sprite pack.
`data/sessions/` is committed last and on its own, so the pilot session data is
easy to drop from the history if the ethics position on publishing it changes.

---

## 2026-09-14 — Resizing the window cut parts of the interface off

Reported from a play session: dragging the window around made parts of the
interface disappear. Two separate faults, and the second had been in the build
since the HUD was first written.

### 1. The stretch mode let the viewport grow past the design size

`display/window/stretch/aspect` was `expand`. That keeps the design's aspect
ratio and never shows *less* than 1280x720 - but on any window wider than 16:9
it makes the viewport **wider** than 1280 units. An ultrawide monitor, or just a
window dragged wide, and the viewport becomes 1707x720 or more.

The farm is laid out at fixed world coordinates for exactly 1280x720:
`FIELD_ORIGIN`, `WELL_POSITION`, `PLAY_AREA` and both player spawns are absolute
pixel positions. Everything anchored to a viewport edge - the HUD's top bar, the
water band, the two player panels - moved away from a farm that stayed in the
top-left corner.

`aspect` is now `keep`. The whole 1280x720 design is on screen at every window
size, scaled to fit and letterboxed when the window's shape does not match. For
a research artefact that is the right default for a second reason: every pair
sees an identically framed screen whatever machine the session runs on, so
framing is not a difference between participants.

### 2. The two player panels were split at a hard-coded pixel

Panel 1 ran from the left edge to `width - 664`; panel 2 from `664` to the right
edge. At 1280 that is two 600 px panels with a gap between them. At any viewport
wider than 1328 they **overlap**, and one draws on top of the other - which is
the interface "disappearing" that was actually reported.

They now share a single bottom-anchored `HBoxContainer` and split it evenly
whatever the width, with a 16 px gap. There is no arithmetic left to get wrong.

While in there: the scenario title and both player role labels now clip with an
ellipsis instead of reporting their full text width as a minimum. A long
scenario title used to push the six field counters off the right-hand end of the
top bar. The water band's caption and note also had minimum widths larger than
they needed (170 and 330), which left the band only 28 px of slack at a 1024-wide
layout; they are now 150 and 240.

### 3. A minimum window size

`Config.MINIMUM_WINDOW_SIZE` is 960x540 - the design's aspect ratio, so the
smallest allowed window is not letterboxed either. Nothing is cut below it; it is
about legibility, since below roughly that size two people at one keyboard cannot
read the field counters.

### New test: `test_window_scaling.gd`

The existing layout cases measured the interface once, at the design size, which
is exactly the size at which both faults are invisible. The new case lays the HUD
out at five sizes - the design size, a 16:10 window, an ultrawide window, a large
window and one smaller than the design - and at each one checks that the bands
stay inside their reserved strips, that the two player panels do not overlap and
get equal width, that nothing runs off the side, and that no label has been
squeezed to nothing. It also pins the project's stretch settings, so switching
back to `expand` fails the suite rather than quietly reintroducing fault 1.

**Status: not yet executed.** The Godot editor was wedged when this was written
(an `OS.execute` call from an editor script blocked its main thread), so this
change has been statically verified - references, load_steps and type inference
all clean - and nothing more. The next `run_tests.bat` is the gate.
