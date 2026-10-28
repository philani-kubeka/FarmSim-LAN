extends "res://tests/farm_sim_test.gd"
## Resizing the window must never cut anything off.
##
## Written after a play session where parts of the interface disappeared while
## the window was being dragged around. Two faults were behind it.
##
## The project stretched with aspect "expand", which keeps the design's aspect
## ratio but lets the viewport grow past 1280x720 on any window wider than 16:9 -
## an ultrawide monitor, or just a window dragged wide. The farm is laid out at
## fixed world coordinates for exactly 1280x720, so it stayed in the top-left
## while everything anchored to a viewport edge moved away from it.
##
## And the two player panels were positioned with a hard-coded 664 px split:
## panel 1 ran from the left edge to (width - 664) and panel 2 from 664 to the
## right edge. At the design width that is two 600 px panels with a gap. At
## anything wider they overlap, and one draws on top of the other.
##
## The fix was aspect "keep" - the whole design is always on screen, letterboxed
## if the window's shape does not match - and a container that splits the bottom
## band proportionally instead of at a fixed pixel.
##
## This case pins both: the project's stretch settings, and the HUD measured at a
## spread of layout sizes rather than only at the design size. The sizes below
## are what "expand" would have produced on a range of real windows, so the HUD
## stays honest even if someone changes the stretch mode later.

const HUD_SCENE := preload("res://scenes/ui/farm_hud.tscn")
const FarmHud := preload("res://scripts/ui/farm_hud.gd")

## A HUD label narrower than this has been squeezed to nothing.
const MIN_SENSIBLE_LABEL_WIDTH := 30.0

const SIZES := [
	Vector2(1280, 720),   # the design size
	Vector2(1280, 800),   # a 16:10 window under the old "expand"
	Vector2(1707, 720),   # an ultrawide window under the old "expand"
	Vector2(1920, 800),
	Vector2(1024, 576),   # smaller than the design size
]

const LONG_MESSAGE := \
	"This tile was already saturated - the extra water drained past the roots."


func _init() -> void:
	super()
	is_async = true


func run_async() -> void:
	_check_stretch_settings()

	var hud: CanvasLayer = HUD_SCENE.instantiate()
	add_child(hud)

	# Real content in every field, so nothing is measured empty.
	hud.set_scenario({"title": "Scenario 2 - Drought season", "crop": "maize"})
	hud.set_player(0, "planter", Config.Tool.WATER)
	hud.set_player(1, "monitor", Config.Tool.INSPECT)
	hud.update_clock(137.0, 200.0)
	hud.update_water(42.0, 140.0)
	hud.update_field({"planted": 8, "mature": 2, "harvested": 3, "stressed": 4,
		"infested_visible": 2})
	hud.show_player_message(0, LONG_MESSAGE, "warn")
	hud.show_player_message(1, "Pests treated early - very little damage done.", "good")

	var root: Control = hud.get_node("HudRoot")
	# Take the root out of its full-rect anchoring so the test can hand it an
	# explicit layout area. Everything inside is anchored to this node, so the
	# bands and panels lay out exactly as they would in a window of that size.
	root.set_anchors_preset(Control.PRESET_TOP_LEFT, true)

	for size in SIZES:
		root.size = size
		await _layout_frames()
		_check_at(hud, root, size)

	hud.queue_free()


# ---------------------------------------------------------- project settings --

func _check_stretch_settings() -> void:
	var mode := String(ProjectSettings.get_setting("display/window/stretch/mode", ""))
	var aspect := String(ProjectSettings.get_setting("display/window/stretch/aspect", ""))
	var width := int(ProjectSettings.get_setting("display/window/size/viewport_width", 0))
	var height := int(ProjectSettings.get_setting("display/window/size/viewport_height", 0))

	check_equal(mode, "canvas_items",
		"the project scales canvas items rather than the 2D viewport")
	check_equal(aspect, "keep",
		"the project keeps the design aspect ratio, so resizing the window can "
		+ "never show less of the farm than it was laid out for")
	check_equal(width, 1280, "the design width is the one the farm is laid out for")
	check_equal(height, 720, "the design height is the one the farm is laid out for")

	# The farm's world coordinates are fixed, so the design size has to contain
	# the whole walkable area or a player can walk off the edge of the picture.
	var design := Rect2(Vector2.ZERO, Vector2(width, height))
	check(design.encloses(Config.PLAY_AREA),
		"the design size contains the whole walkable area")

	check(Config.MINIMUM_WINDOW_SIZE.x > 0 and Config.MINIMUM_WINDOW_SIZE.y > 0,
		"a minimum window size is set, so the window cannot be dragged to nothing")
	var minimum_aspect := float(Config.MINIMUM_WINDOW_SIZE.x) / float(Config.MINIMUM_WINDOW_SIZE.y)
	check_near(minimum_aspect, float(width) / float(height), 0.01,
		"the minimum window size has the design's aspect ratio, so the smallest "
		+ "allowed window is not letterboxed")


# ------------------------------------------------------------- measurements --

func _check_at(hud: CanvasLayer, root: Control, size: Vector2) -> void:
	var label := "%dx%d" % [int(size.x), int(size.y)]
	var screen: Rect2 = root.get_global_rect()

	check_near(screen.size.x, size.x, 1.0,
		"%s: the interface lays out at the size it was given" % label)

	var top: Rect2 = (hud.top_bar as Control).get_global_rect()
	var water: Rect2 = (hud.water_band as Control).get_global_rect()

	check(screen.encloses(top), "%s: the top bar is fully on screen" % label)
	check(screen.encloses(water), "%s: the water band is fully on screen" % label)
	check(not top.intersects(water),
		"%s: the top bar and the water band do not overlap" % label)
	check(top.end.y <= FarmHud.TOP_RESERVED_HEIGHT,
		"%s: the top bar stays inside the reserved top band (ends at %.0f)"
			% [label, top.end.y])
	check(water.end.y <= FarmHud.TOP_RESERVED_HEIGHT,
		"%s: the water band stays inside the reserved top band (ends at %.0f)"
			% [label, water.end.y])

	# --- the bottom band: the fault this case exists for ---
	check_equal(hud.player_panels.size(), 2, "%s: there are two player panels" % label)
	if hud.player_panels.size() == 2:
		var first: Rect2 = (hud.player_panels[0] as Control).get_global_rect()
		var second: Rect2 = (hud.player_panels[1] as Control).get_global_rect()

		check(screen.encloses(first), "%s: player 1's panel is fully on screen" % label)
		check(screen.encloses(second), "%s: player 2's panel is fully on screen" % label)
		check(not first.intersects(second),
			"%s: the two player panels do not overlap (p1 ends at %.0f, p2 starts at %.0f)"
				% [label, first.end.x, second.position.x])
		check(first.position.y >= screen.end.y - FarmHud.BOTTOM_RESERVED_HEIGHT,
			"%s: player 1's panel stays inside the reserved bottom band" % label)
		check(second.end.y <= screen.end.y,
			"%s: player 2's panel is not cut off by the bottom of the window" % label)
		check(absf(first.size.x - second.size.x) <= 1.0,
			"%s: the two panels get the same width (%.0f and %.0f)"
				% [label, first.size.x, second.size.x])

	# --- nothing squeezed to nothing, nothing off the side ---
	var squeezed: Array[String] = []
	var offscreen: Array[String] = []
	for text_label in hud.all_labels():
		if text_label.text.strip_edges().is_empty() or not text_label.is_visible_in_tree():
			continue
		var rect: Rect2 = text_label.get_global_rect()
		if rect.size.x < MIN_SENSIBLE_LABEL_WIDTH:
			squeezed.append("'%s' (%.0f px wide)" % [text_label.text.left(20), rect.size.x])
		if rect.end.x > screen.end.x + 1.0 or rect.position.x < screen.position.x - 1.0:
			offscreen.append("'%s' (x %.0f..%.0f)"
				% [text_label.text.left(20), rect.position.x, rect.end.x])

	check(squeezed.is_empty(),
		"%s: no HUD label is squeezed to nothing %s" % [label, str(squeezed)])
	check(offscreen.is_empty(),
		"%s: no HUD label runs off the side of the window %s" % [label, str(offscreen)])


func _layout_frames() -> void:
	# Containers settle over a couple of frames, so measure after a few.
	for _index in range(6):
		await get_tree().process_frame
