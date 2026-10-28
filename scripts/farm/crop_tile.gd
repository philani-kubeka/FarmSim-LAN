extends Node2D
## One tile of the field: its soil state, its crop, and everything that happens
## to that crop over a season.
##
## The visual parts - ground, crop sprite, selection border, moisture bar and
## the pest/stress marker - are real child nodes authored in crop_tile.tscn, so
## the tile can be opened, inspected and re-skinned in the editor. This script
## only swaps their textures, colours and sizes as the tile's state changes.
##
## The simulation runs through simulate(delta, context) rather than only inside
## _process, so a test can advance a whole season deterministically in
## milliseconds. Every player action returns a small result dictionary
## describing what happened and why, which is what the feedback system shows.

const AssetLibrary := preload("res://scripts/farm/asset_library.gd")

enum State { GRASS, TILLED, PLANTED, MATURE, HARVESTED, DEAD }

const STATE_NAMES := {
	State.GRASS: "grass",
	State.TILLED: "tilled",
	State.PLANTED: "planted",
	State.MATURE: "mature",
	State.HARVESTED: "harvested",
	State.DEAD: "failed",
}

## Pest damage becomes visible without scouting once it passes this level.
const PEST_VISIBLE_LEVEL := 0.45
## Moisture a tile is sown with, representing a watered seedbed.
const SEEDBED_MOISTURE := 0.5

# ------------------------------------------------------------------ state ---

var column := 0
var row := 0

var state: int = State.GRASS
var crop: int = Config.CropType.NONE
var growth := 0.0
var moisture := 0.0
var health := 1.0
var pest_level := 0.0
var infested := false
var scouted := false

# --- per-tile record, copied into the research data at the end of a season ---
var times_watered := 0
var water_used := 0.0
var seconds_stressed := 0.0
var seconds_infested := 0.0
var infested_at := -1.0
var treated_at := -1.0
var harvested_yield := 0.0
var tilled_by := -1
var planted_by := -1

# --- cumulative across every cycle this tile goes through in a season. These
# --- are never reset by tilling, so a re-used tile still reports everything it
# --- produced rather than only its last crop.
var ever_sown := false
var harvest_count := 0
var failed_cycles := 0
var lifetime_yield := 0.0
var lifetime_condition_sum := 0.0

# --------------------------------------------------------------- visuals ----
# All of these are nodes in crop_tile.tscn. Nothing here is created in code.

# get_node_or_null rather than $Ground, so that instantiating this script on its
# own - which the crop-model unit tests used to do - degrades to a silent, purely
# numerical tile instead of erroring on every missing child.
@onready var _ground: Sprite2D = get_node_or_null("Ground")
@onready var _crop_sprite: Sprite2D = get_node_or_null("Crop")
@onready var _border: Sprite2D = get_node_or_null("Border")
@onready var _highlight: ColorRect = get_node_or_null("Highlight")
@onready var _moisture_bg: ColorRect = get_node_or_null("MoistureTrack")
@onready var _moisture_fill: ColorRect = get_node_or_null("MoistureFill")
@onready var _marker: Sprite2D = get_node_or_null("Marker")


func _ready() -> void:
	refresh_visuals()


func setup(tile_column: int, tile_row: int) -> void:
	column = tile_column
	row = tile_row
	name = "Tile_%d_%d" % [tile_column, tile_row]


func coordinates() -> String:
	return "%d,%d" % [column, row]


# ----------------------------------------------------------------- queries --

func is_planted() -> bool:
	return state == State.PLANTED or state == State.MATURE


func is_stressed() -> bool:
	return is_planted() and moisture < Config.MOISTURE_STRESS_THRESHOLD


func pest_is_visible() -> bool:
	return infested and (scouted or pest_level >= PEST_VISIBLE_LEVEL)


func growth_stage() -> int:
	if growth < 0.25:
		return 1
	if growth < 0.55:
		return 2
	if growth < 0.9:
		return 3
	return 4


## Yield this tile would produce if harvested right now.
func potential_yield() -> float:
	if state != State.MATURE:
		return 0.0
	var base: float = Config.CROP_BASE_YIELD.get(crop, 0.0)
	return base * health


# ----------------------------------------------------------------- actions --

func can_till() -> bool:
	return state == State.GRASS or state == State.HARVESTED or state == State.DEAD


func till(player_index: int) -> Dictionary:
	if not can_till():
		return _result(false, "warn", "This ground is already prepared.")
	# Per-cycle state resets; the lifetime counters above deliberately do not.
	state = State.TILLED
	crop = Config.CropType.NONE
	growth = 0.0
	health = 1.0
	pest_level = 0.0
	infested = false
	scouted = false
	infested_at = -1.0
	treated_at = -1.0
	harvested_yield = 0.0
	tilled_by = player_index
	refresh_visuals()
	return _result(true, "good", "Seedbed prepared.")


func can_plant() -> bool:
	return state == State.TILLED


func plant(crop_type: int, player_index: int) -> Dictionary:
	if state == State.GRASS:
		return _result(false, "warn", "Seed needs a prepared seedbed. Till this ground first.")
	if not can_plant():
		return _result(false, "warn", "There is already a crop here.")
	state = State.PLANTED
	crop = crop_type
	growth = 0.0
	health = 1.0
	moisture = maxf(moisture, SEEDBED_MOISTURE)
	planted_by = player_index
	ever_sown = true
	refresh_visuals()
	return _result(true, "good", "%s sown." % Config.crop_name(crop_type))


func can_water() -> bool:
	return state == State.TILLED or is_planted()


## `litres` is the amount actually drawn from the shared reserve; the caller is
## responsible for taking it out of the reserve first.
func apply_water(litres: float) -> Dictionary:
	if not can_water():
		return _result(false, "warn", "There is nothing growing here to water.")
	var was_saturated := moisture >= Config.MOISTURE_SATURATED_THRESHOLD
	var before := moisture
	moisture = minf(1.0, moisture + Config.WATER_PER_ACTION_MOISTURE)
	times_watered += 1
	water_used += litres
	refresh_visuals()
	if was_saturated:
		return _result(true, "warn",
			"This tile was already saturated - the extra water drained past the roots.")
	if before < Config.MOISTURE_STRESS_THRESHOLD:
		return _result(true, "good", "Watered. This tile was under stress.")
	return _result(true, "good", "Watered.")


func scout() -> Dictionary:
	scouted = true
	refresh_visuals()
	if state == State.GRASS:
		return _result(true, "info", "Unprepared ground.")
	if state == State.TILLED:
		return _result(true, "info", "Prepared seedbed, nothing sown yet.")
	if state == State.HARVESTED:
		return _result(true, "info", "Already harvested.")
	if state == State.DEAD:
		return _result(true, "bad", "This crop failed.")

	var parts: Array[String] = []
	parts.append("%s, %d%% grown" % [Config.crop_name(crop), int(round(growth * 100.0))])
	if moisture < Config.MOISTURE_STRESS_THRESHOLD:
		parts.append("dry and under stress")
	elif moisture < Config.MOISTURE_HEALTHY_THRESHOLD:
		parts.append("drying out")
	else:
		parts.append("well watered")
	if infested:
		parts.append("PESTS PRESENT")
	parts.append("condition %d%%" % int(round(health * 100.0)))
	var kind := "bad" if (infested or moisture < Config.MOISTURE_STRESS_THRESHOLD) else "info"
	return _result(true, kind, ", ".join(parts))


func can_treat() -> bool:
	return infested


func treat(elapsed_seconds: float) -> Dictionary:
	if not infested:
		return _result(false, "info", "No pests on this tile.")
	var severity := pest_level
	if infested_at >= 0.0 and treated_at < 0.0:
		treated_at = elapsed_seconds
	infested = false
	pest_level = maxf(0.0, pest_level - Config.PEST_TREATMENT_STRENGTH)
	scouted = true
	refresh_visuals()
	if severity < 0.3:
		return _result(true, "good", "Pests treated early - very little damage done.")
	if severity < 0.7:
		return _result(true, "warn", "Pests treated, but they had already done some damage.")
	return _result(true, "bad", "Pests treated far too late. This tile lost a lot of condition.")


func can_harvest() -> bool:
	return state == State.MATURE or state == State.DEAD


func harvest() -> Dictionary:
	if state == State.PLANTED:
		return _result(false, "warn", "Not ready yet - this crop is still growing.")
	if state == State.DEAD:
		state = State.HARVESTED
		harvested_yield = 0.0
		failed_cycles += 1
		refresh_visuals()
		return _result(true, "bad", "Nothing to harvest here. This crop did not survive.")
	if state != State.MATURE:
		return _result(false, "warn", "There is nothing to harvest here.")
	harvested_yield = potential_yield()
	lifetime_yield += harvested_yield
	lifetime_condition_sum += health
	harvest_count += 1
	state = State.HARVESTED
	refresh_visuals()
	var kind := "good" if health > 0.75 else ("warn" if health > 0.4 else "bad")
	return _result(true, kind, "Harvested %.1f units (condition %d%%)."
		% [harvested_yield, int(round(health * 100.0))])


## Called by the environmental event system.
func infest(elapsed_seconds: float, starting_level: float = 0.12) -> bool:
	if not is_planted() or infested:
		return false
	infested = true
	pest_level = maxf(pest_level, starting_level)
	if infested_at < 0.0:
		infested_at = elapsed_seconds
	refresh_visuals()
	return true


# -------------------------------------------------------------- simulation --

## Advances this tile by `delta` seconds.
## context keys: drying_multiplier (float), elapsed (float).
func simulate(delta: float, context: Dictionary) -> void:
	if state == State.TILLED:
		# Bare prepared soil dries out too, just more slowly than a cropped tile.
		var bare_rate: float = 0.015 * float(context.get("drying_multiplier", 1.0))
		moisture = maxf(0.0, moisture - bare_rate * delta)
		return

	if not is_planted():
		return

	var drying: float = Config.CROP_BASE_DRYING_RATE.get(crop, 0.03) \
		* float(context.get("drying_multiplier", 1.0))
	moisture = maxf(0.0, moisture - drying * delta)

	if infested:
		pest_level = minf(1.0, pest_level + Config.PEST_GROWTH_PER_SECOND * delta)
		seconds_infested += delta

	var stressed := moisture < Config.MOISTURE_STRESS_THRESHOLD
	if stressed:
		seconds_stressed += delta
		health -= Config.STRESS_HEALTH_LOSS_PER_SECOND * delta
	if pest_level > 0.0:
		health -= Config.PEST_HEALTH_LOSS_PER_SECOND * pest_level * delta
	if not stressed and pest_level <= 0.01:
		health += Config.HEALTH_RECOVERY_PER_SECOND * delta
	health = clampf(health, 0.0, 1.0)

	if state == State.PLANTED:
		var seconds_to_maturity: float = Config.CROP_GROWTH_SECONDS.get(crop, 40.0)
		growth += (1.0 / seconds_to_maturity) * _growth_factor() * delta
		if growth >= 1.0:
			growth = 1.0
			state = State.MATURE

	if health <= 0.0:
		state = State.DEAD

	refresh_visuals()


## How fast this tile grows right now, as a fraction of its best rate.
func _growth_factor() -> float:
	if moisture >= Config.MOISTURE_HEALTHY_THRESHOLD:
		return 1.0
	if moisture >= Config.MOISTURE_STRESS_THRESHOLD:
		var span: float = Config.MOISTURE_HEALTHY_THRESHOLD - Config.MOISTURE_STRESS_THRESHOLD
		var position: float = (moisture - Config.MOISTURE_STRESS_THRESHOLD) / maxf(span, 0.0001)
		return lerpf(0.6, 1.0, position)
	return Config.STRESSED_GROWTH_MULTIPLIER


# ------------------------------------------------------------------ record --

## Everything about this tile that belongs in the research data.
func to_record() -> Dictionary:
	var record := {
		"tile": coordinates(),
		"state": STATE_NAMES.get(state, "unknown"),
		"crop": Config.crop_name(crop),
		"growth": snappedf(growth, 0.001),
		"health": snappedf(health, 0.001),
		"moisture": snappedf(moisture, 0.001),
		"times_watered": times_watered,
		"water_used_litres": snappedf(water_used, 0.01),
		"seconds_stressed": snappedf(seconds_stressed, 0.01),
		"seconds_infested": snappedf(seconds_infested, 0.01),
		"harvested_yield": snappedf(harvested_yield, 0.01),
		"harvests": harvest_count,
		"failed_cycles": failed_cycles,
		"total_yield": snappedf(lifetime_yield, 0.01),
		"tilled_by_player": tilled_by + 1 if tilled_by >= 0 else null,
		"planted_by_player": planted_by + 1 if planted_by >= 0 else null,
	}
	if infested_at >= 0.0:
		record["infested_at_seconds"] = snappedf(infested_at, 0.01)
		record["pest_response_seconds"] = (
			snappedf(treated_at - infested_at, 0.01) if treated_at >= 0.0 else null
		)
	return record


func _result(ok: bool, kind: String, message: String) -> Dictionary:
	return {"ok": ok, "kind": kind, "message": message, "tile": coordinates()}


# ----------------------------------------------------------------- visuals --

func refresh_visuals() -> void:
	if _ground == null:
		return

	match state:
		State.GRASS:
			_ground.texture = AssetLibrary.texture("grass")
		State.TILLED:
			_ground.texture = AssetLibrary.texture("tilled")
		State.HARVESTED:
			_ground.texture = AssetLibrary.texture("soil")
		_:
			_ground.texture = AssetLibrary.texture("tilled")

	if is_planted():
		_crop_sprite.texture = AssetLibrary.texture(AssetLibrary.crop_stage_key(crop, growth_stage()))
		_crop_sprite.visible = true
		# Condition is readable from the crop itself: healthy green through to
		# a dry, yellowed plant.
		_crop_sprite.modulate = Color(1.0, 1.0, 1.0).lerp(Color(0.85, 0.72, 0.36), 1.0 - health)
	elif state == State.DEAD:
		_crop_sprite.texture = AssetLibrary.texture(AssetLibrary.crop_stage_key(crop, growth_stage()))
		_crop_sprite.visible = true
		_crop_sprite.modulate = Color(0.55, 0.42, 0.28)
	elif state == State.HARVESTED:
		_crop_sprite.texture = AssetLibrary.texture("stubble")
		_crop_sprite.visible = true
		_crop_sprite.modulate = Color.WHITE
	else:
		_crop_sprite.visible = false

	var show_moisture := state == State.TILLED or is_planted()
	_moisture_bg.visible = show_moisture
	_moisture_fill.visible = show_moisture
	if show_moisture:
		var width := (float(Config.TILE_SIZE) - 12.0) * clampf(moisture, 0.0, 1.0)
		_moisture_fill.size = Vector2(width, 6.0)
		if moisture < Config.MOISTURE_STRESS_THRESHOLD:
			_moisture_fill.color = Color("d05a4a")
		elif moisture < Config.MOISTURE_HEALTHY_THRESHOLD:
			_moisture_fill.color = Color("e0a63c")
		else:
			_moisture_fill.color = Color("4a9fd0")

	if pest_is_visible():
		_marker.texture = AssetLibrary.texture("pest")
		_marker.visible = true
	elif is_stressed():
		_marker.texture = AssetLibrary.texture("warning")
		_marker.visible = true
	elif state == State.DEAD:
		_marker.texture = AssetLibrary.texture("alert")
		_marker.visible = true
	else:
		_marker.visible = false


func set_highlighted(highlighted: bool, colour: Color = Color(1, 1, 1, 0.18)) -> void:
	if _highlight == null:
		return
	_highlight.color = colour
	_highlight.visible = highlighted
