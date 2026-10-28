extends Node2D
## The farm: one reusable environment shared by all three crop-management
## scenarios.
##
## Everything in the world is a node authored in farm.tscn - the grass, the plot,
## the fences, the well, the boundary, the shared water reserve, the two players,
## the HUD and the pause overlay. This script builds none of it. It reads the
## scenario definition, dresses those nodes for it, owns the season clock, and
## routes every player action to the system responsible for the tool that was
## used.
##
## The scene tree, in the order it appears in the editor:
##
##     Farm
##     |-- Background/            grass and the clear colour, on layer -1
##     |-- DecorGround            level design: paths, rocks, grass detail
##     |-- PlotBackdrop
##     |-- DecorLow               level design: flowers inside the fence
##     |-- Field                  the grid of crop tiles (field.tscn)
##     |-- Fences, Well, WellLabel
##     |-- DecorTall              level design: bushes, trees, garden toolbox
##     |-- Boundary               the four walls that keep players on the farm
##     |-- WaterReserve           the season's shared litres
##     |-- Systems
##     |   |-- PlantingSystem     hoe, seed
##     |   |-- IrrigationSystem   watering can, spends WaterReserve
##     |   |-- HarvestingSystem   sickle
##     |   |-- ScoutingSystem     scout, pest treatment
##     |   |-- GrowthSystem       time passing in the field
##     |   +-- WeatherSystem      drought / pest outbreak
##     |-- Player1, Player2
##     |-- HUD
##     +-- PauseOverlay
##
## simulate(delta) is the single entry point for time passing, so the automated
## tests can play an entire season deterministically without waiting on frames.

signal season_finished(result: Dictionary)

const UiKit := preload("res://scripts/ui/ui_kit.gd")

const CROP_IDS := {
	"maize": Config.CropType.MAIZE,
	"beans": Config.CropType.BEANS,
}

var definition := {}
var crop_type: int = Config.CropType.MAIZE
var duration := 200.0
var target_tiles := 12
var elapsed := 0.0
var running := false

# --- authored nodes, wired here so the rest of the script (and the tests) can
# --- keep talking about farm.field, farm.water and farm.event.
@onready var field: Node2D = $Field
@onready var water: Node = $WaterReserve
@onready var hud: CanvasLayer = $HUD
@onready var pause_overlay: CanvasLayer = $PauseOverlay

@onready var systems: Node = $Systems
@onready var planting: Node = $Systems/PlantingSystem
@onready var irrigation: Node = $Systems/IrrigationSystem
@onready var harvesting: Node = $Systems/HarvestingSystem
@onready var scouting: Node = $Systems/ScoutingSystem
@onready var growth: Node = $Systems/GrowthSystem
## The weather / environmental event system. Still called `event` because that is
## what the season record and the test suite know it as.
@onready var event: Node = $Systems/WeatherSystem

var players: Array = []

var _finished := false
var _action_log: Array = [{}, {}]

## LAN port: the host sends the field to the client this often.
const SNAPSHOT_INTERVAL := 0.1
## Bytes per tile in a snapshot: state, crop, growth, moisture, health, pests,
## flags (1 = infested, 2 = scouted).
const SNAPSHOT_STRIDE := 7
var _snapshot_timer := 0.0
var _applying_remote_tool := false


func _ready() -> void:
	definition = SessionController.pending_scenario
	if definition.is_empty():
		definition = SessionController.scenario_definition(0)
	_apply_definition()
	_prepare_world()
	_bind_systems()
	_prepare_players()
	_prepare_hud()
	if Config.is_mobile():
		_prepare_mobile()
	_start_season()
	if Net.is_online():
		Net.set_handler(self)
		pause_overlay.paused_changed.connect(_on_local_pause_changed)
	_print_build_summary()


func _exit_tree() -> void:
	Net.clear_handler(self)
	if Config.is_mobile() and is_inside_tree():
		get_viewport().canvas_transform = Transform2D.IDENTITY


# ----------------------------------------------------------------- mobile ---

const TOUCH_CONTROLS_SCENE := preload("res://scenes/ui/touch_controls.tscn")
## The size the farm's world is laid out for. On a phone the screen is usually
## wider than this; the world is centred and the spare width on each side is
## where the thumbs go.
const DESIGN_SIZE := Vector2(1280, 720)

## The phone build's joystick and tool buttons, or null on a computer.
var touch_controls: CanvasLayer = null


## Phone / tablet: touch controls for this device's player, the HUD's phone
## layout, and the world centred on whatever shape the screen is.
func _prepare_mobile() -> void:
	# The world is laid out in fixed pixels, so it is never drawn scaled up.
	get_tree().root.content_scale_factor = 1.0
	var local_index := Net.local_player_index if Net.is_online() else 0
	touch_controls = TOUCH_CONTROLS_SCENE.instantiate()
	add_child(touch_controls)
	touch_controls.bind(players[local_index])
	touch_controls.pause_pressed.connect(pause_overlay.toggle)
	hud.apply_mobile_layout(local_index if Net.is_online() else -1)
	for index in range(players.size()):
		hud.set_player(index, players[index].role, players[index].current_tool())
	get_viewport().size_changed.connect(_fit_world_to_screen)
	_fit_world_to_screen()


## Centres the 1280x720 world in the visible area. Only the world moves: the
## HUD, the controls and the pause screen are CanvasLayers and keep using the
## whole screen.
func _fit_world_to_screen() -> void:
	if not is_inside_tree():
		return
	var visible := get_viewport().get_visible_rect().size
	var offset := ((visible - DESIGN_SIZE) * 0.5).max(Vector2.ZERO).floor()
	get_viewport().canvas_transform = Transform2D(0.0, offset)


## Printed on every run so that godot_output.log shows what the farm actually
## assembled. Cheap, and it is the only visibility into a graphical run when
## nobody is watching the window.
func _print_build_summary() -> void:
	print("[farm] scenario=%s crop=%s tiles=%d players=%d systems=%d hud=%s water=%.0fL event=%s" % [
		definition.get("id", "?"),
		definition.get("crop", "?"),
		field.tiles.size() if field != null else -1,
		players.size(),
		systems.get_child_count() if systems != null else -1,
		"yes" if hud != null else "NO",
		water.capacity if water != null else -1.0,
		event.event_id if event != null else "?",
	])


func _apply_definition() -> void:
	crop_type = CROP_IDS.get(String(definition.get("crop", "maize")), Config.CropType.MAIZE)
	duration = float(definition.get("duration_seconds", 200.0))
	target_tiles = int(definition.get("target_tiles", 12))


# ------------------------------------------------------------------ setup ---

## Names the authored tiles by their grid coordinate and fills the reserve and
## the weather system from the scenario definition.
func _prepare_world() -> void:
	field.build()

	water.configure(
		float(definition.get("water_reserve_litres", 120.0)),
		float(definition.get("water_refill_per_second", 0.0)))

	# A fixed seed while testing keeps the pest outbreak reproducible.
	event.configure(definition, 20260909 if Config.headless_test_mode else 0)
	# On the client the weather never runs: the host decides where pests land.
	event.triggered.connect(_on_event_triggered)


## Hands every system under Systems a reference to this farm. A system added in
## the editor later is picked up here without touching this script.
func _bind_systems() -> void:
	for system in systems.get_children():
		system.bind(self)


func _prepare_players() -> void:
	players.clear()
	var count := GameState.player_count() if not Net.is_online() else 2
	if count < 2:
		# Single player: there is no second farmer on the field.
		var second := get_node_or_null("Player2")
		if second != null:
			remove_child(second)
			second.queue_free()
	for index in range(count):
		var player: CharacterBody2D = get_node("Player%d" % (index + 1))
		player.setup(index, GameState.role_for_player(index),
			UiKit.COL_PLAYER_1 if index == 0 else UiKit.COL_PLAYER_2)
		player.field = field
		if Net.is_online():
			player.net_mode = index == Net.local_player_index
			player.controlled = index == Net.local_player_index
		elif count == 1:
			# One person at the keyboard: WASD or the arrow keys, E or Space,
			# Q or Shift - the same bindings a LAN player uses.
			player.net_mode = true
		player.use_requested.connect(_on_use_requested)
		player.tool_changed.connect(_on_tool_changed)
		players.append(player)
		_action_log[index] = {}
	_apply_resume()


# ------------------------------------------------------------- reconnecting --

## True on a client that has just reconnected into a season already under way.
var resumed := false


## Where both players are and what they are holding. The host sends this along
## with the farm scene when Player 2 reconnects mid-season.
func resume_state() -> Dictionary:
	var out: Array = []
	for player in players:
		out.append({
			"position": player.global_position,
			"tool": player.current_tool(),
			"facing": player.facing,
		})
	return {"players": out, "elapsed": elapsed}


## Client: put both players back where they were before the link dropped. The
## field, the clock and the water arrive with the host's next snapshot.
func _apply_resume() -> void:
	var resume: Dictionary = SessionController.farm_resume
	SessionController.farm_resume = {}
	if resume.is_empty() or not Net.is_client():
		return
	resumed = true
	elapsed = float(resume.get("elapsed", 0.0))
	var saved: Array = resume.get("players", [])
	for index in range(mini(saved.size(), players.size())):
		var entry: Dictionary = saved[index]
		var player: Node = players[index]
		player.global_position = entry.get("position", player.global_position)
		player.facing = entry.get("facing", player.facing)
		var tool_index: int = (player.tools as Array).find(int(entry.get("tool", -1)))
		if tool_index >= 0:
			player.tool_index = tool_index
			player._refresh_tool_icon()


func _prepare_hud() -> void:
	hud.set_scenario(definition)
	for index in range(players.size()):
		hud.set_player(index, players[index].role, players[index].current_tool())
	_update_hud()


# ----------------------------------------------------------------- season ---

func _start_season() -> void:
	running = true
	_finished = false
	if resumed:
		# Rejoining a season that is already running: nothing new has started.
		return
	elapsed = 0.0
	GameplayLogger.log_scenario("season_started", {
		"scenario_id": definition.get("id", ""),
		"crop": definition.get("crop", ""),
		"duration_seconds": duration,
		"water_reserve_litres": water.capacity,
	})


func _process(delta: float) -> void:
	# Tests drive simulate() themselves so a season can be played instantly.
	if Config.headless_test_mode:
		return
	if Net.is_client():
		# The host owns the season. The client only draws snapshots of it.
		return
	simulate(delta)
	if Net.is_host():
		_snapshot_timer -= delta
		if _snapshot_timer <= 0.0:
			_snapshot_timer = SNAPSHOT_INTERVAL
			Net.send_snapshot(build_snapshot())


## Advances the whole scenario by `delta` seconds, one system at a time: the
## weather decides the conditions, growth applies them to every tile, and the
## reserve recovers if the scenario allows it to.
func simulate(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	event.simulate(delta, elapsed)
	growth.simulate(delta, {
		"drying_multiplier": event.drying_multiplier(),
		"elapsed": elapsed,
	})
	irrigation.simulate(delta)
	_update_hud()

	if elapsed >= duration:
		finish_season("time")


func finish_season(reason: String = "time") -> void:
	if _finished:
		return
	_finished = true
	running = false
	var result := build_result(reason)
	GameplayLogger.log_scenario("season_finished", {
		"scenario_id": result.get("scenario_id", ""),
		"reason": reason,
		"total_yield": result.get("total_yield", 0.0),
		"tiles_harvested": result.get("tiles_harvested", 0),
	})
	season_finished.emit(result)
	SessionController.finish_scenario(result)


# ---------------------------------------------------------------- actions ---

func _on_tool_changed(player: Node, tool_id: int) -> void:
	if hud != null:
		hud.set_player(player.player_index, player.role, tool_id)
	if _applying_remote_tool:
		# Already logged on the computer where the key was pressed.
		return
	if Net.is_online():
		Net.send_tool(player.player_index, tool_id)
	GameplayLogger.log_player_action(player.player_index, "tool_changed", {
		"tool": Config.tool_label(tool_id),
	})


func _on_use_requested(player: Node, tool_id: int, tile: Node) -> void:
	if Net.is_client():
		# Every farming rule runs on the host. Tell it which tile we meant.
		if tile == null:
			Net.send_use(tool_id, -1, -1)
		else:
			Net.send_use(tool_id, tile.column, tile.row)
		return
	perform_action(player, tool_id, tile)


## The system responsible for a tool, or null if no system claims it.
func system_for(tool_id: int) -> Node:
	for system in systems.get_children():
		if system.handles(tool_id):
			return system
	return null


## Resolves one player action. Returns the result dictionary so tests can assert
## on exactly what the player would have been told.
func perform_action(player: Node, tool_id: int, tile: Node) -> Dictionary:
	if not running:
		return {"ok": false, "kind": "warn", "message": "The season is over."}
	if not (tool_id in player.tools):
		# Defence in depth: a player can only select tools its role carries, so
		# this should be unreachable from the keyboard. It exists so the role
		# split cannot be bypassed by a future caller.
		var wrong_role := {"ok": false, "kind": "warn",
			"message": "%s does not carry the %s."
				% [Config.role_label(player.role), Config.tool_label(tool_id).to_lower()]}
		_report(player, tool_id, tile, wrong_role)
		return wrong_role
	if tile == null:
		var no_tile := {"ok": false, "kind": "warn",
			"message": "Stand on a soil tile to use that tool."}
		_report(player, tool_id, null, no_tile)
		return no_tile

	var system: Node = system_for(tool_id)
	var result: Dictionary
	if system == null:
		result = {"ok": false, "kind": "warn", "message": "Nothing happens."}
	else:
		result = system.apply(player, tool_id, tile)

	_report(player, tool_id, tile, result)
	return result


func _report(player: Node, tool_id: int, tile: Node, result: Dictionary) -> void:
	# Deterministic key, e.g. "watering_can_ok" - used in the research data.
	var action_name := "%s_%s" % [
		Config.tool_label(tool_id).to_lower().replace(" ", "_"),
		"ok" if bool(result.get("ok", false)) else "refused"]
	var counts: Dictionary = _action_log[player.player_index]
	counts[action_name] = int(counts.get(action_name, 0)) + 1

	var details := {
		"tool": Config.tool_label(tool_id),
		"tile": tile.coordinates() if tile != null else "",
		"ok": result.get("ok", false),
		"outcome": result.get("message", ""),
		"scenario_seconds": snappedf(elapsed, 0.01),
	}
	if tile != null and tile.is_planted():
		details["crop"] = Config.crop_name(tile.crop)
		details["moisture"] = snappedf(tile.moisture, 0.001)
		details["condition"] = snappedf(tile.health, 0.001)
	if tool_id == Config.Tool.WATER and bool(result.get("ok", false)):
		details["water_remaining_litres"] = snappedf(water.remaining, 0.01)
		if hud != null:
			hud.update_water(water.remaining, water.capacity)
	GameplayLogger.log_player_action(player.player_index, action_name, details)

	if hud != null:
		hud.show_player_message(player.player_index,
			String(result.get("message", "")), String(result.get("kind", "info")))
	Net.send_player_message(player.player_index,
		String(result.get("message", "")), String(result.get("kind", "info")))


func _on_event_triggered(event_id: String, title: String, body: String, icon_key: String) -> void:
	GameplayLogger.log_scenario("event_triggered", {
		"event": event_id,
		"scenario_seconds": snappedf(elapsed, 0.01),
	})
	if hud != null:
		hud.show_event(title, body, icon_key)
	Net.send_event(title, body, icon_key)


# -------------------------------------------------------------------- hud ---

func _update_hud() -> void:
	if hud == null:
		return
	hud.update_clock(maxf(0.0, duration - elapsed), duration)
	hud.update_water(water.remaining, water.capacity)
	var counts: Dictionary = growth.field_counts()
	counts["infested_visible"] = scouting.visible_outbreaks()
	hud.update_field(counts)


# ----------------------------------------------------------------- result ---

func build_result(reason: String = "time") -> Dictionary:
	# Explicitly typed: `field` is a Node2D, so its methods return Variant and
	# `:=` cannot infer an int from them.
	var sown: int = field.sown_tiles()
	var result := {
		"scenario_id": definition.get("id", ""),
		"title": definition.get("title", ""),
		"crop": Config.crop_name(crop_type),
		"end_reason": reason,
		"duration_seconds": duration,
		"elapsed_seconds": snappedf(elapsed, 0.01),
		"target_tiles": target_tiles,
		"tiles_sown": sown,
		"tiles_matured": field.mature_count() + field.total_harvests(),
		"tiles_harvested": field.total_harvests(),
		"tiles_failed": field.dead_count() + field.total_failed_cycles(),
		"tiles_still_growing": field.planted_count(),
		"average_condition": snappedf(field.average_condition_at_harvest(), 0.001),
		"total_yield": snappedf(field.total_yield(), 0.01),
		"water": water.to_record(),
		"event": event.to_record(),
		"players": _player_records(),
		"tiles": field.records(),
	}
	result["causes"] = build_causal_notes(result)
	return result


func _player_records() -> Array:
	var out: Array = []
	for index in range(players.size()):
		out.append({
			"player": index + 1,
			"role": players[index].role,
			"actions": _action_log[index],
		})
	return out


## Plain-language explanations of why the season turned out the way it did.
## Every line is derived from a number that was actually recorded, so nothing
## here is a generic tip.
func build_causal_notes(result: Dictionary) -> Array:
	var notes: Array = []

	var sown := int(result.get("tiles_sown", 0))
	var harvested := int(result.get("tiles_harvested", 0))
	var still_growing := int(result.get("tiles_still_growing", 0))
	var failed := int(result.get("tiles_failed", 0))
	var condition := float(result.get("average_condition", 0.0))
	var water_record: Dictionary = result.get("water", {})
	var event_record: Dictionary = result.get("event", {})

	var stressed_seconds := 0.0
	var infested_seconds := 0.0
	var response_times: Array = []
	var untreated := 0
	for record in (result.get("tiles", []) as Array):
		var tile_record := record as Dictionary
		stressed_seconds += float(tile_record.get("seconds_stressed", 0.0))
		infested_seconds += float(tile_record.get("seconds_infested", 0.0))
		if tile_record.has("infested_at_seconds"):
			if tile_record.get("pest_response_seconds") == null:
				untreated += 1
			else:
				response_times.append(float(tile_record.get("pest_response_seconds")))

	if sown == 0:
		notes.append("Nothing was sown this season, so there was nothing to harvest. "
			+ ("Till a tile with the hoe before seed will go into it." if GameState.single_player
				else "The Planter has to till a tile before seed will go into it."))
		return notes

	notes.append("You sowed %d tiles and brought in %d harvests." % [sown, harvested])

	if still_growing > 0:
		notes.append("%d tiles were still growing when the season ended. A crop that does not "
			% still_growing
			+ "reach maturity yields nothing, so sowing more ground than you can keep watered "
			+ "costs you rather than gains you.")

	if failed > 0:
		notes.append("%d tiles failed completely. A crop that loses all of its condition - "
			% failed
			+ "from being left dry, from untreated pests, or both - produces nothing at all.")

	if stressed_seconds > 5.0:
		notes.append("Your crops spent about %d seconds in total below the stress line. "
			% int(round(stressed_seconds))
			+ "Time spent dry both slows growth and permanently costs condition, and condition "
			+ "is what the final yield is multiplied by.")
	elif harvested > 0:
		notes.append("Your crops were almost never left under water stress, which is why the "
			+ "harvested tiles came in at high condition.")

	if condition > 0.0:
		notes.append("Average crop condition at the end of the season was %d%%."
			% int(round(condition * 100.0)))

	# --- water ---
	var used := float(water_record.get("used_litres", 0.0))
	var capacity := float(water_record.get("capacity_litres", 0.0))
	var refused := int(water_record.get("refused_draws", 0))
	if capacity > 0.0:
		notes.append("You used %d of the %d litres in the shared reserve."
			% [int(round(used)), int(round(capacity))])
	if refused > 0:
		notes.append("Irrigation was refused %d times because the shared reserve was empty. "
			% refused
			+ "Once it is gone it is gone - the decision about where the last of the water goes "
			+ "has to be made before that point, not after it.")

	# --- events ---
	var event_id := String(event_record.get("event", "none"))
	if event_id == "drought" and bool(event_record.get("triggered", false)):
		notes.append(("The drought kept getting worse: by the end the soil was drying out "
			+ "%.1f times faster than normal. With a fixed reserve that turns irrigation into a "
			+ "choice about which part of the field to protect, rather than how often to water "
			+ "everything.") % float(event_record.get("drying_multiplier_at_end",
				event_record.get("peak_drying_multiplier", 2.0))))
	if event_id == "pest" and bool(event_record.get("triggered", false)):
		var infested := int(event_record.get("tiles_infested", 0))
		var spread := int(event_record.get("tiles_infested_by_spread", 0))
		var arrived := int(event_record.get("tiles_infested_by_new_arrivals", 0))
		var parts: Array[String] = []
		if arrived > 0:
			parts.append("%d from new pests arriving as the season went on" % arrived)
		if spread > 0:
			parts.append("%d by spreading from an untreated neighbour" % spread)
		var spread_clause := "" if parts.is_empty() else " (%s)" % ", ".join(parts)
		notes.append("The outbreak reached %d tiles%s." % [infested, spread_clause])
		if not response_times.is_empty():
			var total := 0.0
			for value in response_times:
				total += value
			notes.append("Average time from a tile becoming infested to it being treated was "
				+ "%d seconds. The longer that gap, the more condition the tile lost."
				% int(round(total / response_times.size())))
		if untreated > 0:
			notes.append("%d infested tiles were never treated at all, and kept losing "
				% untreated
				+ "condition for the rest of the season.")

	# --- cooperation ---
	# One player holding every tool has nobody to share the work with.
	if GameState.single_player:
		return notes
	var planter_actions := 0
	var monitor_actions := 0
	for record in (result.get("players", []) as Array):
		var player_record := record as Dictionary
		var total := 0
		for key in (player_record.get("actions", {}) as Dictionary).keys():
			total += int((player_record["actions"] as Dictionary)[key])
		if String(player_record.get("role", "")) == "planter":
			planter_actions += total
		else:
			monitor_actions += total
	if planter_actions > 0 and monitor_actions > 0:
		notes.append("Player workload: %d actions by the Planter / Irrigator and %d by the "
			% [planter_actions, monitor_actions]
			+ "Field Monitor.")
	elif monitor_actions == 0:
		notes.append("The Field Monitor took no actions this season. Scouting and pest "
			+ "treatment are things only that player can do, so the field was working with "
			+ "half its tools.")
	elif planter_actions == 0:
		notes.append("The Planter / Irrigator took no actions this season. Only that player "
			+ "can till and sow, so nothing new could be established.")

	return notes


# -------------------------------------------------------------- LAN port ----
# Handlers called by the Net autoload. The host runs the farm exactly as the
# one-keyboard version does; the client mirrors it.

## Host: the whole visible state of the season, packed into a few hundred
## bytes so it fits in one network packet ten times a second. Fractions are
## sent as 0-255; the client only draws them, so that precision is plenty.
## Every number that ends up in the research data stays on the host.
func build_snapshot() -> Dictionary:
	var values := PackedByteArray()
	values.resize(field.tiles.size() * SNAPSHOT_STRIDE)
	var i := 0
	for tile in field.tiles:
		values[i] = tile.state
		values[i + 1] = tile.crop
		values[i + 2] = _to_byte(tile.growth)
		values[i + 3] = _to_byte(tile.moisture)
		values[i + 4] = _to_byte(tile.health)
		values[i + 5] = _to_byte(tile.pest_level)
		values[i + 6] = (1 if tile.infested else 0) | (2 if tile.scouted else 0)
		i += SNAPSHOT_STRIDE
	return {
		"elapsed": elapsed,
		"water": [water.remaining, water.capacity],
		"tiles": values,
	}


static func _to_byte(value: float) -> int:
	return int(round(clampf(value, 0.0, 1.0) * 255.0))


## Client: draw the host's season.
func on_snapshot(snapshot: Dictionary) -> void:
	if not Net.is_client():
		return
	elapsed = float(snapshot.get("elapsed", elapsed))
	var water_values: Array = snapshot.get("water", [])
	if water_values.size() == 2:
		water.remaining = float(water_values[0])
		water.capacity = float(water_values[1])
	var values: PackedByteArray = snapshot.get("tiles", PackedByteArray())
	var count: int = mini(field.tiles.size(), values.size() / SNAPSHOT_STRIDE)
	for index in range(count):
		var tile: Node = field.tiles[index]
		var i := index * SNAPSHOT_STRIDE
		tile.state = values[i]
		tile.crop = values[i + 1]
		tile.growth = values[i + 2] / 255.0
		tile.moisture = values[i + 3] / 255.0
		tile.health = values[i + 4] / 255.0
		tile.pest_level = values[i + 5] / 255.0
		tile.infested = (values[i + 6] & 1) != 0
		tile.scouted = (values[i + 6] & 2) != 0
		tile.refresh_visuals()
	_update_hud()


func on_remote_transform(remote_position: Vector2, remote_facing: Vector2, flip: bool) -> void:
	var remote_index := 1 - Net.local_player_index
	if remote_index < players.size():
		players[remote_index].apply_remote_transform(remote_position, remote_facing, flip)


## Host: Player 2 pressed use on the client.
func on_remote_use(tool_id: int, tile_column: int, tile_row: int) -> void:
	if not Net.is_host() or players.size() < 2:
		return
	var tile: Node = null
	if tile_column >= 0 and tile_row >= 0:
		tile = field.tile_at(tile_column, tile_row)
	perform_action(players[1], tool_id, tile)


## The other computer's player changed tool.
func on_remote_tool(player_index: int, tool_id: int) -> void:
	if player_index < 0 or player_index >= players.size():
		return
	if player_index == Net.local_player_index:
		return
	_applying_remote_tool = true
	players[player_index].select_tool(tool_id)
	_applying_remote_tool = false


## Client: what the host told a player after an action.
func on_remote_player_message(player_index: int, message: String, kind: String) -> void:
	if hud != null:
		hud.show_player_message(player_index, message, kind)


func on_remote_event(title: String, body: String, icon_key: String) -> void:
	if hud != null:
		hud.show_event(title, body, icon_key)


func on_remote_pause(paused: bool) -> void:
	pause_overlay.set_paused(paused, true)


func _on_local_pause_changed(paused: bool, from_remote: bool) -> void:
	if not from_remote:
		Net.send_pause(paused)
