extends "res://tests/farm_sim_test.gd"
## Measures the interface after a real layout pass.
##
## Written after a play session where the shared-water panel rendered as a tall
## narrow column with "Shared water reserve" stacked one letter per line, sitting
## on top of the crop beds. Nothing in the suite could see it: every assertion
## was about data, and the geometry checks used the configured constants rather
## than the sizes the engine actually calculated.
##
## So this case waits for the engine to lay the HUD out and then measures it.

const Fixture := preload("res://tests/farm_fixture.gd")
const FarmHud := preload("res://scripts/ui/farm_hud.gd")

## A label wider than this is doing its job; anything narrower has been squeezed.
const MIN_SENSIBLE_LABEL_WIDTH := 30.0
## No HUD label should need more than this many lines.
const MAX_LABEL_LINES := 3


func _init() -> void:
	super()
	is_async = true


func run_async() -> void:
	var farm := Fixture.make(self, "drought")
	var hud: CanvasLayer = farm.hud
	check_not_null(hud, "the farm builds a HUD")
	if hud == null:
		return

	# Put real content in every field before measuring.
	hud.show_player_message(0,
		"This tile was already saturated - the extra water drained past the roots.", "warn")
	hud.show_player_message(1, "Pests treated early - very little damage done.", "good")
	hud.show_event("Drought",
		"The rains have failed. The soil is drying out much faster and there is no more "
		+ "water coming. Decide together what to keep alive.", "drought")
	farm.simulate(1.0)

	await _layout_frames()

	# Measure against the viewport the Controls were actually laid out in, not
	# against the configured window size: headless runs at a different root
	# viewport size, and bottom-anchored panels are positioned relative to it.
	var screen: Rect2 = get_tree().root.get_visible_rect()
	var viewport := screen.size
	check(viewport.x > 0.0 and viewport.y > 0.0,
		"the viewport has a real size (%.0f x %.0f)" % [viewport.x, viewport.y])
	var field_rect := Rect2(Config.FIELD_ORIGIN,
		Vector2(Config.FIELD_COLUMNS, Config.FIELD_ROWS) * float(Config.TILE_SIZE))

	# --- the three bands ---
	var top_rect: Rect2 = hud.top_bar.get_global_rect()
	var water_rect: Rect2 = hud.water_band.get_global_rect()

	_check_panel("top bar", top_rect, screen, field_rect)
	_check_panel("water band", water_rect, screen, field_rect)

	check(top_rect.end.y <= FarmHud.TOP_RESERVED_HEIGHT,
		"the top bar stays inside the reserved top band (ends at %.0f, limit %.0f)"
			% [top_rect.end.y, FarmHud.TOP_RESERVED_HEIGHT])
	check(water_rect.end.y <= FarmHud.TOP_RESERVED_HEIGHT,
		"the water band stays inside the reserved top band (ends at %.0f, limit %.0f)"
			% [water_rect.end.y, FarmHud.TOP_RESERVED_HEIGHT])
	check(not top_rect.intersects(water_rect), "the top bar and the water band do not overlap")

	# The water reserve has to be wide and shallow, not a narrow column.
	check(water_rect.size.x > 800.0,
		"the water band spans the screen (%.0f px wide)" % water_rect.size.x)
	check(water_rect.size.y < 100.0,
		"the water band is a band, not a column (%.0f px tall)" % water_rect.size.y)

	for index in range(hud.player_panels.size()):
		var panel_rect: Rect2 = (hud.player_panels[index] as Control).get_global_rect()
		_check_panel("player %d panel" % (index + 1), panel_rect, screen, field_rect)
		check(panel_rect.position.y >= viewport.y - FarmHud.BOTTOM_RESERVED_HEIGHT,
			"player %d's panel stays inside the reserved bottom band" % (index + 1))
		check(panel_rect.end.y <= viewport.y,
			"player %d's panel is not cut off by the bottom of the window" % (index + 1))
	if hud.player_panels.size() == 2:
		var first: Rect2 = (hud.player_panels[0] as Control).get_global_rect()
		var second: Rect2 = (hud.player_panels[1] as Control).get_global_rect()
		check(not first.intersects(second), "the two player panels do not overlap each other")

	# --- the banner, which only appears during an event ---
	check(hud.banner.visible, "an environmental event shows its banner")
	var banner_rect: Rect2 = (hud.banner as Control).get_global_rect()
	check(screen.encloses(banner_rect), "the event banner is fully on screen")
	check(banner_rect.size.x > 400.0,
		"the event banner is wide enough to read (%.0f px)" % banner_rect.size.x)

	# --- no label has been squeezed into a vertical column ---
	var labels: Array[Label] = hud.all_labels()
	check_greater(labels.size(), 8, "the HUD has labels to check (%d)" % labels.size())

	var squeezed: Array[String] = []
	var stacked: Array[String] = []
	for label in labels:
		if label.text.strip_edges().is_empty() or not label.is_visible_in_tree():
			continue
		var rect := label.get_global_rect()
		if rect.size.x < MIN_SENSIBLE_LABEL_WIDTH:
			squeezed.append("'%s' (%.0f px wide)" % [label.text.left(24), rect.size.x])
		if label.get_line_count() > MAX_LABEL_LINES:
			stacked.append("'%s' (%d lines)" % [label.text.left(24), label.get_line_count()])
		check(screen.encloses(rect) or rect.size.x <= 0.0,
			"label stays on screen: '%s'" % label.text.left(30))

	check(squeezed.is_empty(),
		"no HUD label is squeezed to nothing: %s" % str(squeezed))
	check(stacked.is_empty(),
		"no HUD label is stacked into a column of characters: %s" % str(stacked))

	# --- the numbers on screen match the farm underneath ---
	var text := _all_text(hud)
	check(text.contains("Shared water reserve"),
		"the shared reserve is named on screen, on one line")
	check(text.contains("%d / %d L" % [int(round(farm.water.remaining)),
		int(round(farm.water.capacity))]),
		"the water figure on screen matches the reserve")
	check(text.contains("Season time left"), "the season clock is on screen")
	check(text.contains("Planter / Irrigator"), "player 1's role is on screen")
	check(text.contains("Field Monitor"), "player 2's role is on screen")
	check(text.contains("Drought"), "the drought banner names the event")

	farm.queue_free()


func _check_panel(name: String, rect: Rect2, screen: Rect2, field_rect: Rect2) -> void:
	check(screen.encloses(rect),
		"%s is fully on screen (%s)" % [name, str(rect)])
	check(not rect.intersects(field_rect),
		"%s does not cover the crop beds (%s vs field %s)" % [name, str(rect), str(field_rect)])
	check(rect.size.x > 0.0 and rect.size.y > 0.0, "%s has a real size" % name)


func _all_text(node: Node) -> String:
	var parts: Array[String] = []
	_collect(node, parts)
	return "\n".join(parts)


func _collect(node: Node, parts: Array[String]) -> void:
	var label := node as Label
	if label != null and not label.text.is_empty():
		parts.append(label.text)
	for child in node.get_children():
		_collect(child, parts)


func _layout_frames() -> void:
	# Containers settle over a couple of frames, so measure after a few.
	for _index in range(6):
		await get_tree().process_frame
