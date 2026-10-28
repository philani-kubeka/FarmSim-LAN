extends "res://scripts/systems/farm_system.gd"
## Weather System - the environmental event that turns a farming loop into a
## crop-management decision.
##
## One event is configured per scenario from its entry in data/scenarios.json:
## none for the baseline season, a drought that keeps getting worse until the soil
## dries more than twice as fast, or a pest outbreak that keeps building that starts in a few tiles and spreads from any it
## is left untreated in. Covers FR-002.
##
## Adding another kind of event means adding a branch here and a value in
## scenarios.json; no other system needs to change.

signal triggered(event_id: String, title: String, body: String, icon_key: String)

const NONE := "none"
const DROUGHT := "drought"
const PEST := "pest"

var event_id := NONE
var start_seconds := 0.0
var active := false
var finished := false

## drought
var base_drying_multiplier := 1.0
## The worst the drought gets.
var event_drying_multiplier := 1.0
## How long the drought takes to build from base_drying_multiplier up to
## event_drying_multiplier. 0 means it is at full strength immediately.
var ramp_seconds := 0.0
var _elapsed := 0.0

## pest
var initial_tiles := 3
var spread_chance_per_second := Config.PEST_SPREAD_CHANCE_PER_SECOND
## New pests keep arriving after the first wave, and the outbreak builds up like
## the drought does: the arrival rate climbs in a straight line from
## arrivals_start to arrivals_peak (new infestations per minute) over
## arrival_ramp_seconds, then stays at the peak.
var arrivals_start := 0.0
var arrivals_peak := 0.0
var arrival_ramp_seconds := 0.0
var arrived_total := 0
var _arrival_budget := 0.0

var _rng := RandomNumberGenerator.new()
var _pending_infestations := 0
var triggered_at := -1.0
var infested_total := 0
var spread_total := 0


func configure(definition: Dictionary, seed_value: int = 0) -> void:
	event_id = String(definition.get("event", NONE))
	start_seconds = float(definition.get("event_start_seconds", 0.0))
	base_drying_multiplier = float(definition.get("drying_multiplier", 1.0))
	event_drying_multiplier = float(definition.get("event_drying_multiplier", base_drying_multiplier))
	ramp_seconds = maxf(float(definition.get("event_ramp_seconds", 0.0)), 0.0)
	_elapsed = 0.0
	initial_tiles = int(definition.get("pest_initial_tiles", 3))
	spread_chance_per_second = float(
		definition.get("pest_spread_chance_per_second", Config.PEST_SPREAD_CHANCE_PER_SECOND))
	arrivals_start = maxf(float(definition.get("pest_arrivals_per_minute_start", 0.0)), 0.0)
	arrivals_peak = maxf(float(definition.get("pest_arrivals_per_minute_peak", arrivals_start)), 0.0)
	arrival_ramp_seconds = maxf(float(definition.get("pest_arrival_ramp_seconds", 0.0)), 0.0)
	arrived_total = 0
	_arrival_budget = 0.0
	active = false
	finished = false
	triggered_at = -1.0
	infested_total = 0
	spread_total = 0
	_pending_infestations = 0
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


## Drying multiplier that applies to the field right now. A drought builds up:
## from the moment it starts, the multiplier rises in a straight line from the
## season's normal value to its maximum over ramp_seconds, then stays there.
func drying_multiplier() -> float:
	if not active:
		return base_drying_multiplier
	return multiplier_at(_elapsed - triggered_at)


## New pest arrivals per minute, `seconds_into_event` after the outbreak began.
func arrivals_per_minute_at(seconds_into_event: float) -> float:
	if arrival_ramp_seconds <= 0.0:
		return arrivals_peak
	var progress := clampf(seconds_into_event / arrival_ramp_seconds, 0.0, 1.0)
	return lerpf(arrivals_start, arrivals_peak, progress)


## The multiplier `seconds_into_event` after the event started.
func multiplier_at(seconds_into_event: float) -> float:
	if ramp_seconds <= 0.0 or event_id != DROUGHT:
		return event_drying_multiplier
	var progress := clampf(seconds_into_event / ramp_seconds, 0.0, 1.0)
	return lerpf(base_drying_multiplier, event_drying_multiplier, progress)


## How strong the drought is right now, 0 (just started) to 1 (full strength).
func intensity() -> float:
	if not active:
		return 0.0
	if ramp_seconds <= 0.0:
		return 1.0
	return clampf((_elapsed - triggered_at) / ramp_seconds, 0.0, 1.0)


## The average drying multiplier over a whole season of `definition` - what the
## water a scenario needs is actually sized against. Used by the test suite to
## check each reserve poses the question it is meant to.
static func season_average_multiplier(definition: Dictionary) -> float:
	var duration := float(definition.get("duration_seconds", 200.0))
	var base := float(definition.get("drying_multiplier", 1.0))
	if String(definition.get("event", NONE)) != DROUGHT or duration <= 0.0:
		return base
	var peak := float(definition.get("event_drying_multiplier", base))
	var start := clampf(float(definition.get("event_start_seconds", 0.0)), 0.0, duration)
	var ramp := maxf(float(definition.get("event_ramp_seconds", 0.0)), 0.0)
	var ramp_end := minf(start + ramp, duration)
	var ramp_len := ramp_end - start
	var ramp_reached := lerpf(base, peak, ramp_len / ramp) if ramp > 0.0 else peak
	var total := base * start
	total += (base + ramp_reached) * 0.5 * ramp_len
	total += peak * (duration - ramp_end)
	return total / duration


func simulate(delta: float, elapsed: float) -> void:
	_elapsed = elapsed
	if event_id == NONE:
		return

	if not active and not finished and elapsed >= start_seconds:
		_trigger(elapsed)

	if not active:
		return

	if event_id == PEST:
		_simulate_pest(delta, elapsed)


func _trigger(elapsed: float) -> void:
	active = true
	triggered_at = elapsed
	match event_id:
		DROUGHT:
			triggered.emit(DROUGHT, "Drought",
				"The rains have failed and it is getting worse: the soil will dry out faster "
				+ "and faster, and there is no more water coming. Decide together what to "
				+ "keep alive.", "drought")
		PEST:
			_pending_infestations = initial_tiles
			triggered.emit(PEST, "Pest outbreak",
				"Pests have been reported in the area. Somewhere in this field plants are "
				+ "being attacked, and more will keep arriving as the season goes on - scout "
				+ "the tiles and treat what you find.", "pest")
		_:
			triggered.emit(event_id, "Event", "", "warning")


func _simulate_pest(delta: float, elapsed: float) -> void:
	# Seed the outbreak. If nothing is sown yet, keep trying until something is.
	if _pending_infestations > 0:
		var targets: Array = field.plantable_targets()
		while _pending_infestations > 0 and not targets.is_empty():
			var index := _rng.randi_range(0, targets.size() - 1)
			var tile: Node = targets[index]
			targets.remove_at(index)
			if tile.infest(elapsed):
				infested_total += 1
				_pending_infestations -= 1

	# More pests keep arriving, faster as the season goes on. Each arrival lands
	# on a sown tile that is not already infested; if there is none, it waits.
	var rate := arrivals_per_minute_at(elapsed - triggered_at) / 60.0
	if rate > 0.0:
		_arrival_budget += rate * delta
		while _arrival_budget >= 1.0:
			var candidates: Array = []
			for tile in field.tiles:
				if tile.is_planted() and not tile.infested:
					candidates.append(tile)
			if candidates.is_empty():
				break
			var target: Node = candidates[_rng.randi_range(0, candidates.size() - 1)]
			if target.infest(elapsed):
				infested_total += 1
				arrived_total += 1
			_arrival_budget -= 1.0

	# Untreated infestations spread to neighbouring tiles.
	if spread_chance_per_second <= 0.0:
		return
	var spreaders: Array = []
	for tile in field.tiles:
		if tile.infested and tile.pest_level > 0.4:
			spreaders.append(tile)
	for tile in spreaders:
		if _rng.randf() > spread_chance_per_second * delta:
			continue
		var neighbours: Array = field.neighbours_of(tile)
		for neighbour in neighbours:
			if neighbour.is_planted() and not neighbour.infested:
				if neighbour.infest(elapsed, 0.08):
					infested_total += 1
					spread_total += 1
				break


func to_record() -> Dictionary:
	return {
		"event": event_id,
		"triggered": active,
		"triggered_at_seconds": (snappedf(triggered_at, 0.01) if triggered_at >= 0.0 else null),
		"tiles_infested": infested_total,
		"tiles_infested_by_spread": spread_total,
		"tiles_infested_by_new_arrivals": arrived_total,
		"ramp_seconds": ramp_seconds,
		"peak_drying_multiplier": event_drying_multiplier,
		"drying_multiplier_at_end": snappedf(drying_multiplier(), 0.01),
	}
