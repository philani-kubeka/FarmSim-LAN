extends "res://tests/farm_sim_test.gd"
## The farm environment itself: the grid, the well, the boundary, the two
## players and the interface, all built from the real scene.

const Fixture := preload("res://tests/farm_fixture.gd")
const CropTile := preload("res://scripts/farm/crop_tile.gd")
const FarmHud := preload("res://scripts/ui/farm_hud.gd")


func run() -> void:
	var farm := Fixture.make(self, "baseline")

	# --- the field ---
	check_not_null(farm.field, "the farm builds a field")
	check_equal(farm.field.columns, Config.FIELD_COLUMNS, "the field is the configured width")
	check_equal(farm.field.rows, Config.FIELD_ROWS, "the field is the configured height")
	check_equal(farm.field.tiles.size(), Config.FIELD_COLUMNS * Config.FIELD_ROWS,
		"every grid position has a tile")

	var first: Node2D = farm.field.tile_at(0, 0)
	var last: Node2D = farm.field.tile_at(Config.FIELD_COLUMNS - 1, Config.FIELD_ROWS - 1)
	check_not_null(first, "the top-left tile exists")
	check_not_null(last, "the bottom-right tile exists")
	check(farm.field.tile_at(-1, 0) == null, "asking for a tile off the grid returns nothing")
	check(farm.field.tile_at(Config.FIELD_COLUMNS, 0) == null,
		"asking past the right-hand edge returns nothing")

	var half := float(Config.TILE_SIZE) / 2.0
	check_near(first.position.x, half, 0.01, "the first tile sits half a tile in from the origin")
	check_near(last.position.x, (Config.FIELD_COLUMNS - 0.5) * Config.TILE_SIZE, 0.01,
		"tiles are laid out one tile-width apart")

	var all_grass := true
	for tile in farm.field.tiles:
		if tile.state != CropTile.State.GRASS:
			all_grass = false
	check(all_grass, "a new season starts with unprepared ground")

	# --- reaching a tile ---
	var target: Node2D = farm.field.tile_at(3, 2)
	check_equal(farm.field.tile_near(target.global_position, Config.PLAYER_REACH), target,
		"standing on a tile targets that tile")
	check(farm.field.tile_near(target.global_position + Vector2(600, 600),
		Config.PLAYER_REACH) == null, "standing far from the field targets nothing")

	# --- the rest of the environment ---
	check_not_null(farm.get_node_or_null("Well"), "the shared well is in the scene")
	check_not_null(farm.get_node_or_null("Fences"), "the farm is fenced")
	# Level design layers (LEVEL_DESIGN.md). Decoration is drawn in the right
	# order whatever is placed in it: ground detail under the plot, flowers under
	# the fence, tall things over the fence but always under the players.
	var ground := farm.get_node_or_null("DecorGround")
	var low := farm.get_node_or_null("DecorLow")
	var tall := farm.get_node_or_null("DecorTall")
	if check(ground != null and low != null and tall != null, "the three decoration layers exist"):
		check(ground.get_index() < farm.get_node("PlotBackdrop").get_index(),
			"ground decoration is drawn under the crop plot")
		check(low.get_index() < farm.get_node("Fences").get_index(),
			"flowers are drawn under the fence")
		check(tall.get_index() > farm.get_node("Fences").get_index()
			and tall.get_index() < farm.get_node("Player1").get_index(),
			"trees and the toolbox are drawn over the fence and under the players")
		for layer in [ground, low, tall]:
			for child in layer.get_children():
				check(not (child is CollisionObject2D),
					"decoration '%s' does not block anyone - it is scenery only" % child.name)
	var boundary: Node = farm.get_node_or_null("Boundary")
	check_not_null(boundary, "there is a collision boundary")
	if boundary != null:
		check_equal(boundary.get_child_count(), 4, "the boundary closes all four sides")
	check_not_null(farm.get_node_or_null("WaterReserve"), "the farm has a water reserve")
	check_not_null(farm.hud, "the farm builds its interface")

	var well: Node2D = farm.get_node_or_null("Well")
	if well != null:
		check(Config.PLAY_AREA.has_point(well.position),
			"the well is inside the walkable area, so players can reach it")

	# --- the two players ---
	check_equal(farm.players.size(), 2, "there are exactly two players")
	var planter := Fixture.player_with_role(farm, "planter")
	var monitor := Fixture.player_with_role(farm, "monitor")
	check_not_null(planter, "one player is the Planter / Irrigator")
	check_not_null(monitor, "the other player is the Field Monitor")

	for index in range(farm.players.size()):
		var player: Node = farm.players[index]
		check_equal(player.player_index, index, "player %d knows its own index" % (index + 1))
		check(Config.PLAY_AREA.has_point(player.position),
			"player %d spawns inside the walkable area" % (index + 1))
		check(player.field == farm.field, "player %d can reach the field" % (index + 1))
		check(player.get_child_count() > 0, "player %d has a body" % (index + 1))
	check(farm.players[0].position.distance_to(farm.players[1].position) > 100.0,
		"the two players do not spawn on top of each other")

	# The roles have to carry different tools, or the multiplayer is decorative.
	check(planter.tools != monitor.tools, "the two roles carry different tools")
	check(Config.Tool.SEED in planter.tools, "only the planter carries seed")
	check(not (Config.Tool.SEED in monitor.tools), "the monitor cannot sow")
	check(Config.Tool.TREAT in monitor.tools, "only the monitor carries pest treatment")
	check(not (Config.Tool.TREAT in planter.tools), "the planter cannot treat pests")
	check(Config.Tool.WATER in planter.tools and Config.Tool.WATER in monitor.tools,
		"both players can irrigate from the shared reserve")

	# Cycling wraps around the role's own tool set and never leaves it.
	var seen: Array[int] = []
	for _step in range(planter.tools.size() + 1):
		seen.append(planter.current_tool())
		planter.cycle_tool()
	for tool_id in seen:
		check(tool_id in planter.tools, "cycling never hands the planter a tool it does not carry")
	check_equal(seen[0], seen[seen.size() - 1], "cycling wraps back to the first tool")

	# --- the season ---
	check(farm.running, "the season starts running")
	check_near(farm.elapsed, 0.0, 0.001, "the season clock starts at zero")
	check_near(farm.duration, float(farm.definition.get("duration_seconds", 0.0)), 0.001,
		"the season length comes from the scenario definition")
	check_equal(farm.crop_type, Config.CropType.MAIZE, "the baseline scenario sows maize")
	check_near(farm.water.capacity, float(farm.definition.get("water_reserve_litres", 0.0)), 0.001,
		"the reserve is filled from the scenario definition")

	_check_layout(farm)
	farm.queue_free()


## Geometry checks. Nobody can look at the window from here, so the next best
## thing is to assert that everything the player needs is inside it and that
## nothing is hidden behind the interface. Written after a run where the farm
## rendered as an empty grey window.
func _check_layout(farm: Node2D) -> void:
	var viewport := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 720)))
	var screen := Rect2(Vector2.ZERO, viewport)

	var field_rect := Rect2(Config.FIELD_ORIGIN,
		Vector2(Config.FIELD_COLUMNS, Config.FIELD_ROWS) * float(Config.TILE_SIZE))
	check(screen.encloses(field_rect), "the whole field is inside the window")
	check(screen.encloses(Config.PLAY_AREA), "the whole walkable area is inside the window")
	check(Config.PLAY_AREA.encloses(field_rect),
		"every tile can be reached without leaving the walkable area")

	# The HUD reserves a band at the top and one at the bottom. A player who can
	# walk into either of them disappears behind a panel.
	check(Config.PLAY_AREA.position.y >= FarmHud.TOP_RESERVED_HEIGHT,
		"the walkable area starts below the HUD's top band")
	check(Config.PLAY_AREA.end.y <= viewport.y - FarmHud.BOTTOM_RESERVED_HEIGHT,
		"the walkable area ends above the HUD's bottom band")
	# The bottom fence (its posts and their shadows reach 12 px below the rail
	# line) must not disappear under the player panels.
	var fences: Node = farm.get_node_or_null("Fences")
	if fences != null and "bottom_right" in fences:
		check(float(fences.bottom_right.y) + 12.0 <= viewport.y - FarmHud.BOTTOM_RESERVED_HEIGHT,
			"the bottom fence is fully visible above the player panels")

	for index in range(farm.players.size()):
		var player: Node2D = farm.players[index]
		check(screen.has_point(player.position),
			"player %d spawns somewhere visible" % (index + 1))
		check(not field_rect.has_point(player.position),
			"player %d does not spawn on top of the crop" % (index + 1))

	var well: Node2D = farm.get_node_or_null("Well")
	if well != null:
		check(screen.has_point(well.position), "the well is on screen")
		check(not field_rect.has_point(well.position), "the well does not sit on the field")

	# Every tile has to be somewhere a player could actually stand.
	var off_screen := 0
	for tile in farm.field.tiles:
		if not screen.has_point(tile.global_position):
			off_screen += 1
	check_equal(off_screen, 0, "no tile is drawn off screen")
