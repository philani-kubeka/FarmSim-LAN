extends Node
## Central tuning values for the FarmSim research prototype.
##
## Everything a researcher might reasonably want to adjust between study runs
## lives here (or in the JSON files under res://data/) rather than being
## scattered through gameplay code.

# ---------------------------------------------------------------- identity ---

const PROTOTYPE_NAME := "FarmSim"
const PROTOTYPE_VERSION := "0.1.0-lan"
const RESEARCH_CONTEXT := "ITRI671 Honours treatise artefact"

# ------------------------------------------------------------------- world ---

## Size of one soil tile in pixels.
const TILE_SIZE := 64
## Number of soil tiles across the plot.
const FIELD_COLUMNS := 10
## Number of soil tiles down the plot.
const FIELD_ROWS := 5
## Top-left pixel position of the soil grid inside the farm scene.
const FIELD_ORIGIN := Vector2(320, 216)
## Where the shared well stands.
const WELL_POSITION := Vector2(208, 300)
## Walkable area, in the same pixel space. Keeps both players on the farm, and
## deliberately starts below the HUD so nobody can stand behind a panel.
const PLAY_AREA := Rect2(Vector2(112, 184), Vector2(1056, 388))
## Where each player starts the season.
const PLAYER_SPAWNS := [Vector2(196, 470), Vector2(1084, 470)]

# ----------------------------------------------------------------- players ---

const PLAYER_SPEED := 210.0
## How far a player can reach to act on a tile, in pixels.
const PLAYER_REACH := 56.0

# ------------------------------------------------------------------- crops ---

enum CropType { NONE, MAIZE, BEANS }

## Seconds of well-watered growing time needed to reach maturity.
##
## Sized so that one crop occupies most of a 200-second season. That is what a
## season is, and it is also what makes over-committing costly: with several
## cycles per season, sowing too much ground banked early harvests before the
## reserve ran dry and beat farming within the water available, which is the
## opposite of the lesson the drought scenario exists to teach.
const CROP_GROWTH_SECONDS := {
	CropType.MAIZE: 140.0,
	CropType.BEANS: 120.0,
}

## Yield in "units" from one perfectly grown, perfectly healthy tile.
const CROP_BASE_YIELD := {
	CropType.MAIZE: 10.0,
	CropType.BEANS: 8.0,
}

## Fraction of the moisture bar lost per second under normal conditions.
const CROP_BASE_DRYING_RATE := {
	CropType.MAIZE: 0.025,
	CropType.BEANS: 0.020,
}

## Moisture below this value stresses the crop and damages health.
const MOISTURE_STRESS_THRESHOLD := 0.25
## Moisture at or above this value allows full-speed growth.
const MOISTURE_HEALTHY_THRESHOLD := 0.45
## Moisture above this value is wasteful (over-irrigation) but not damaging.
const MOISTURE_SATURATED_THRESHOLD := 0.95

## Health lost per second while a crop is below the stress threshold.
const STRESS_HEALTH_LOSS_PER_SECOND := 0.055
## Health lost per second per unit of pest pressure on a tile.
const PEST_HEALTH_LOSS_PER_SECOND := 0.075
## Health regained per second while a crop is comfortably watered and pest free.
const HEALTH_RECOVERY_PER_SECOND := 0.020

## Growth speed multiplier applied while a crop is water stressed.
const STRESSED_GROWTH_MULTIPLIER := 0.25

# ------------------------------------------------------------------- water ---

## Moisture added to one tile by a single watering action. One watering covers
## roughly 24 seconds of maize drying under normal conditions, which sets how
## often a tile has to be revisited and therefore how much ground two players
## can realistically keep alive.
const WATER_PER_ACTION_MOISTURE := 0.60
## Litres drawn from the shared reserve by a single watering action.
const WATER_COST_PER_ACTION := 3.0

# -------------------------------------------------------------------- pest ---

## Pest pressure added per second on an infested, untreated tile.
const PEST_GROWTH_PER_SECOND := 0.11
## Pest pressure removed by one treatment action.
const PEST_TREATMENT_STRENGTH := 1.0
## Chance per second that an untreated infested tile spreads to a neighbour.
const PEST_SPREAD_CHANCE_PER_SECOND := 0.05

# ------------------------------------------------------------------- tools ---

enum Tool { HOE, SEED, WATER, INSPECT, TREAT, HARVEST }

const TOOL_LABELS := {
	Tool.HOE: "Hoe",
	Tool.SEED: "Seed",
	Tool.WATER: "Watering can",
	Tool.INSPECT: "Scout",
	Tool.TREAT: "Pest treatment",
	Tool.HARVEST: "Sickle",
}

## Which tools each role may carry. Roles are complementary on purpose: a single
## player cannot complete a scenario alone, which is what makes the multiplayer
## requirement meaningful rather than cosmetic.
const ROLE_TOOLS := {
	"planter": [Tool.HOE, Tool.SEED, Tool.WATER, Tool.HARVEST],
	"monitor": [Tool.INSPECT, Tool.WATER, Tool.TREAT, Tool.HARVEST],
	# Single player: one farmer does both jobs. The planter's four tools come
	# first (the phone's diamond of buttons), then the monitor's two extras.
	"solo": [Tool.HOE, Tool.SEED, Tool.WATER, Tool.HARVEST, Tool.INSPECT, Tool.TREAT],
}

const ROLE_LABELS := {
	"planter": "Planter / Irrigator",
	"monitor": "Field Monitor",
	"solo": "Farmer (both roles)",
}

const ROLE_DESCRIPTIONS := {
	"planter": "Prepares soil, sows the crop and irrigates. Only this player can till and plant.",
	"monitor": "Scouts tiles to reveal moisture, condition and pests, irrigates, and is the only player who can treat a pest outbreak.",
	"solo": "Does both jobs alone: prepares the soil, sows, irrigates, scouts for pests, treats them and harvests.",
}

# ----------------------------------------------------------------- session ---

## Where session JSON is written when res:// is not writable (exported builds).
const USER_SESSION_DIR := "user://sessions"
## Preferred output directory while running from the project folder.
const PROJECT_SESSION_DIR := "res://data/sessions"

## Set true by the automated test runner so gameplay systems skip animations
## and wall-clock waits.
var headless_test_mode := false

# ------------------------------------------------------------------ window ---

## The smallest the window may be dragged to.
##
## Nothing is ever cut off below this - the project stretches with aspect "keep",
## so the whole 1280x720 design is always on screen whatever the window is doing,
## letterboxed if the shape does not match. This is only about legibility: below
## roughly this size the scenario title and the field counters are too small for
## two people sitting at one keyboard to read.
const MINIMUM_WINDOW_SIZE := Vector2i(960, 540)


# ------------------------------------------------------------------ mobile ---
#
# The phone build is the same project. On a phone (or on a computer started with
# `-- --mobile`, which is what run_mobile_preview.bat does) three things change:
#
# * The window fills the whole screen instead of letterboxing (aspect "expand"),
#   so a 20:9 phone gets its full width. The farm centres itself in it.
# * Menu screens are drawn larger, so text is readable at arm's length and every
#   button is a comfortable thumb target. The farm itself stays at 1:1 - its
#   world is laid out in 1280x720 pixels and has to fit the screen.
# * The farm adds BombSquad-style touch controls: a floating joystick on the
#   left, one big round button per tool on the right.
#
# Desktop is untouched: aspect "keep", scale 1, keyboard only.

## Menu scale on a phone-sized screen. 1.5 turns the 720-pixel-high design into
## a 480-pixel-high one, which puts body text at roughly the size phones use.
const MOBILE_MENU_SCALE := 1.5
## Menu scale on a tablet, where the screen is physically big enough already.
const TABLET_MENU_SCALE := 1.15
## Screens shorter than this many inches (in landscape) count as phones.
const PHONE_MAX_HEIGHT_INCHES := 3.6

## Tests and the screenshot tool can force the mobile layout on a computer.
var force_mobile := false
var _mobile := false
var _scaled_scene_id := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	refresh_platform()
	var window := get_window()
	if window != null and not _mobile:
		window.min_size = MINIMUM_WINDOW_SIZE


## True on a phone or tablet, or in the mobile preview on a computer.
func is_mobile() -> bool:
	return _mobile


## True when the mobile layout is running on something without a touchscreen
## (the preview on a computer), so the touch controls also answer the mouse.
func is_touch_preview() -> bool:
	return _mobile and not DisplayServer.is_touchscreen_available()


## Works out which platform this is and applies the window settings for it.
## Safe to call again (the screenshot tool and tests do).
func refresh_platform() -> void:
	_mobile = force_mobile or OS.has_feature("mobile") \
		or OS.get_cmdline_user_args().has("--mobile")
	var root := get_tree().root if is_inside_tree() else null
	if root == null:
		return
	if _mobile:
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		set_process(true)
		_scaled_scene_id = 0
		_apply_screen_scale()
	else:
		set_process(false)


func _process(_delta: float) -> void:
	# Each screen is a fresh scene; re-apply the scale when the scene changes.
	var scene := get_tree().current_scene
	var scene_id := scene.get_instance_id() if scene != null else 0
	if scene_id != _scaled_scene_id:
		_scaled_scene_id = scene_id
		_apply_screen_scale()
		_keyboard_lift = 0.0
	_fit_step()
	_lift_above_keyboard(_delta)


func _apply_screen_scale() -> void:
	var root := get_tree().root
	var scene := get_tree().current_scene
	# The farm is a 2D world laid out in fixed pixels: always 1:1.
	if scene is Node2D:
		root.content_scale_factor = 1.0
		_fitting = false
	else:
		root.content_scale_factor = menu_scale()
		# Only the farm moves the canvas; make sure nothing else inherits it.
		root.canvas_transform = Transform2D.IDENTITY
		_begin_fit(scene, true)


# ------------------------------------------------------- on-screen keyboard ---
#
# Android draws its keyboard over the bottom of the game rather than shrinking
# the window, so a text box low on the screen (Join by address, the farm name)
# disappears behind it. While a text box has focus and the keyboard is up, the
# whole screen slides up just far enough that the box (and a little space under
# it) sits above the keyboard, and slides back when the keyboard closes. Touches
# follow the slide because it is done with the canvas transform.

## Gap left between the bottom of the text box and the top of the keyboard.
const KEYBOARD_GAP := 24.0
## How quickly the screen slides (fraction of the remaining distance per frame at 60 fps).
const KEYBOARD_SLIDE_SPEED := 14.0
## Tests and the screenshot tool set this (in screen pixels) to stand in for a
## keyboard on a computer. Negative means "ask the device".
var simulated_keyboard_height := -1.0
var _keyboard_lift := 0.0


## Height of the on-screen keyboard in screen pixels (0 when it is closed).
func keyboard_height() -> float:
	if simulated_keyboard_height >= 0.0:
		return simulated_keyboard_height
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return 0.0
	return float(DisplayServer.virtual_keyboard_get_height())


## How far the current screen is slid up for the keyboard, in canvas units.
func keyboard_lift() -> float:
	return _keyboard_lift


func _lift_above_keyboard(delta: float) -> void:
	var scene := get_tree().current_scene
	if scene == null or scene is Node2D:
		return
	var viewport := get_viewport()
	var target := 0.0
	var focus := viewport.gui_get_focus_owner()
	var keyboard := keyboard_height()
	if keyboard > 0.0 and (focus is LineEdit or focus is TextEdit) and focus.is_visible_in_tree():
		var visible := viewport.get_visible_rect().size
		var window_height := float(DisplayServer.window_get_size().y)
		if simulated_keyboard_height >= 0.0 or window_height <= 0.0:
			window_height = visible.y * viewport.get_final_transform().get_scale().y
		var keyboard_canvas := keyboard * visible.y / maxf(window_height, 1.0)
		var keyboard_top := visible.y - keyboard_canvas
		var rect: Rect2 = (focus as Control).get_global_rect()
		# A screen can name a button to keep in view too (the box's Join button).
		var extra: Variant = focus.get_meta(&"keyboard_reveal", null)
		var with_extra := rect
		if extra is Control and (extra as Control).is_visible_in_tree():
			with_extra = rect.merge((extra as Control).get_global_rect())
		var bottom := with_extra.end.y + KEYBOARD_GAP
		if bottom - keyboard_top > rect.position.y - KEYBOARD_GAP:
			bottom = rect.end.y + KEYBOARD_GAP  # not enough room for both: the box wins
		if bottom > keyboard_top:
			# Never push the top of the box off the top of the screen.
			target = minf(bottom - keyboard_top, maxf(rect.position.y - KEYBOARD_GAP, 0.0))
	var weight := clampf(delta * KEYBOARD_SLIDE_SPEED, 0.0, 1.0)
	_keyboard_lift = lerpf(_keyboard_lift, target, weight)
	if absf(_keyboard_lift - target) < 0.5:
		_keyboard_lift = target
	viewport.canvas_transform = Transform2D(0.0, Vector2(0.0, -_keyboard_lift))


# ----------------------------------------------------------- fit to screen ---
#
# Phones differ in shape (16:9 up to 21:9) and size, so a fixed menu scale will
# fit one phone and spill off another. Every page screen is therefore fitted to
# the phone it is on: it starts at menu_scale() and is drawn a step smaller at a
# time until its content fits the height without scrolling, but never below
# MIN_FIT_SCALE, which keeps body text readable on a small phone. If a screen
# still does not fit at that size it scrolls, as it always could.
#
# Screens whose content changes (the next quiz question, say) call refit().
# The new screen is kept invisible for the few frames the first fit takes, so
# nobody sees it shrink.

## Smallest scale a page screen is drawn at on a phone.
const MIN_FIT_SCALE := 1.1
## How much the scale changes per step.
const FIT_STEP := 0.04
## Content must be this much shorter than the screen before the scale grows.
const FIT_GROW_SLACK := 18.0
## Give up hiding a screen after this many frames, whatever happens.
const FIT_MAX_HIDDEN_FRAMES := 40

var _fitting := false
var _fit_scene: Control = null
var _fit_cooldown := 0
var _fit_stable := 0
var _fit_frames := 0
var _fit_grow_locked := false


## Call when a screen's content changes size (a new question, a hand-over...).
func refit() -> void:
	if not _mobile:
		return
	var scene := get_tree().current_scene
	if scene is Control:
		_begin_fit(scene, false)


func _begin_fit(scene: Node, hide: bool) -> void:
	_fit_scene = scene as Control
	_fitting = _mobile and _fit_scene != null
	_fit_cooldown = 1
	_fit_stable = 0
	_fit_frames = 0
	_fit_grow_locked = false
	if _fitting and hide:
		_fit_scene.modulate.a = 0.0
		_widen_page(_fit_scene)


## Page screens keep wide side margins on a computer. A phone needs that width
## for text, so the margins shrink to a sliver.
static func _widen_page(scene: Node) -> void:
	var scroll := page_scroll(scene)
	if scroll == null or scroll.get_child_count() == 0:
		return
	var row := scroll.get_child(0)
	for gutter_name in ["GutterLeft", "GutterRight"]:
		var gutter := row.get_node_or_null(gutter_name) as Control
		if gutter != null:
			gutter.size_flags_stretch_ratio = 0.03


## The scroll container a page screen is built in, or null.
static func page_scroll(scene: Node) -> ScrollContainer:
	if scene == null:
		return null
	return scene.find_child("PageScroll", true, false) as ScrollContainer


## How tall a page screen's content is, against the height it has.
static func page_fit(scene: Node) -> Vector2:
	var scroll := page_scroll(scene)
	if scroll == null or scroll.get_child_count() == 0:
		return Vector2.ZERO
	var content := scroll.get_child(0) as Control
	return Vector2(content.get_combined_minimum_size().y, scroll.size.y)


func _fit_step() -> void:
	if not _fitting:
		return
	if _fit_scene == null or not is_instance_valid(_fit_scene) \
			or _fit_scene != get_tree().current_scene:
		_fitting = false
		return
	_fit_frames += 1
	# A scale change only shows up in the layout a frame later.
	if _fit_cooldown > 0:
		_fit_cooldown -= 1
		return
	var fit := page_fit(_fit_scene)
	var needed := fit.x
	var available := fit.y
	var root := get_tree().root
	var factor := root.content_scale_factor
	var target := factor
	if available <= 0.0:
		target = factor
	elif needed > available + 0.5 and factor > MIN_FIT_SCALE + 0.001:
		target = maxf(MIN_FIT_SCALE, factor - FIT_STEP)
		_fit_grow_locked = _fit_grow_locked or factor < menu_scale() - 0.001
	elif not _fit_grow_locked and factor < menu_scale() - 0.001 \
			and needed < available * factor / (factor + FIT_STEP) - FIT_GROW_SLACK:
		target = minf(menu_scale(), factor + FIT_STEP)
	if not is_equal_approx(target, factor):
		root.content_scale_factor = target
		_fit_cooldown = 1
		_fit_stable = 0
	else:
		_fit_stable += 1
	if _fit_stable >= 2 or _fit_frames > FIT_MAX_HIDDEN_FRAMES:
		_fit_scene.modulate.a = 1.0
		if _fit_stable >= 2:
			_fitting = false


## How much larger menu screens are drawn on this device.
func menu_scale() -> float:
	if not _mobile:
		return 1.0
	if not OS.has_feature("mobile"):
		return MOBILE_MENU_SCALE
	var dpi := float(DisplayServer.screen_get_dpi())
	var height := float(mini(DisplayServer.screen_get_size().x, DisplayServer.screen_get_size().y))
	if dpi <= 0.0 or height <= 0.0:
		return MOBILE_MENU_SCALE
	return MOBILE_MENU_SCALE if height / dpi < PHONE_MAX_HEIGHT_INCHES else TABLET_MENU_SCALE


## Android's back gesture / button: pause in the farm, "Back" everywhere else.
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST or not is_inside_tree():
		return
	if SessionController.exit_dialog_open():
		SessionController._hide_exit_dialog()
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var overlay: Variant = scene.get("pause_overlay")
	if overlay != null and is_instance_valid(overlay) and overlay.has_method("toggle"):
		overlay.toggle()
	elif scene.has_method("_on_back_pressed"):
		scene.call("_on_back_pressed")


## Litres needed to keep `tiles` of `crop` continuously out of water stress for
## `seconds`, at the given drying multiplier.
##
## This is what makes a scenario's reserve a deliberate number rather than a
## guess: the baseline is set comfortably above it and the drought deliberately
## below it, and the test suite asserts both.
func litres_to_sustain(crop: int, tiles: int, seconds: float,
		drying_multiplier: float = 1.0) -> float:
	var drying: float = float(CROP_BASE_DRYING_RATE.get(crop, 0.03)) * drying_multiplier
	if drying <= 0.0 or tiles <= 0:
		return 0.0
	var seconds_per_watering: float = WATER_PER_ACTION_MOISTURE / drying
	return tiles * (seconds / seconds_per_watering) * WATER_COST_PER_ACTION


func crop_id_from_name(crop_name_text: String) -> int:
	match crop_name_text.to_lower():
		"maize":
			return CropType.MAIZE
		"beans":
			return CropType.BEANS
		_:
			return CropType.NONE


func crop_name(crop: int) -> String:
	match crop:
		CropType.MAIZE:
			return "Maize"
		CropType.BEANS:
			return "Beans"
		_:
			return "None"


func tool_label(tool_id: int) -> String:
	return TOOL_LABELS.get(tool_id, "Unknown")


func role_label(role: String) -> String:
	return ROLE_LABELS.get(role, role)
