extends "res://tests/farm_sim_test.gd"
## The crop model, exercised directly and deterministically: the lifecycle, what
## water stress actually costs, what pests actually cost, and whether the numbers
## that end up in the research data match what happened.

const CropTile := preload("res://scripts/farm/crop_tile.gd")
const TILE_SCENE := preload("res://scenes/farm/crop_tile.tscn")

const NORMAL := {"drying_multiplier": 1.0}


func run() -> void:
	_test_lifecycle()
	_test_tilling_is_required()
	_test_water_stress_costs_condition()
	_test_over_watering_is_flagged()
	_test_pests()
	_test_reworking_a_tile()
	_test_record()


## The real tile scene, not a bare script instance: the ground, crop sprite,
## moisture bar and marker are nodes in crop_tile.tscn now, and the model should
## be tested with them attached exactly as a season uses them.
func _new_tile() -> Node2D:
	var tile: Node2D = TILE_SCENE.instantiate()
	tile.setup(2, 3)
	add_child(tile)
	return tile


## Runs the tile forward, watering it whenever it would otherwise go into stress.
func _grow_well(tile: Node2D, seconds: float, step: float = 0.25) -> void:
	var remaining := seconds
	while remaining > 0.0:
		if tile.moisture < Config.MOISTURE_HEALTHY_THRESHOLD + 0.05:
			tile.apply_water(Config.WATER_COST_PER_ACTION)
		tile.simulate(step, NORMAL)
		remaining -= step


func _test_lifecycle() -> void:
	var tile := _new_tile()
	check_equal(tile.state, CropTile.State.GRASS, "a new tile starts as grass")
	check_equal(tile.coordinates(), "2,3", "a tile knows its grid position")

	var till_result: Dictionary = tile.till(0)
	check(bool(till_result["ok"]), "grass can be tilled")
	check_equal(tile.state, CropTile.State.TILLED, "tilling produces a seedbed")

	var plant_result: Dictionary = tile.plant(Config.CropType.MAIZE, 0)
	check(bool(plant_result["ok"]), "a seedbed can be sown")
	check_equal(tile.state, CropTile.State.PLANTED, "sowing produces a growing crop")
	check_equal(tile.crop, Config.CropType.MAIZE, "the sown crop is recorded")
	check_near(tile.growth, 0.0, 0.001, "a new crop starts at zero growth")
	check_near(tile.health, 1.0, 0.001, "a new crop starts in full condition")

	check(not bool((tile.harvest() as Dictionary)["ok"]), "an immature crop cannot be harvested")

	var growth_seconds: float = Config.CROP_GROWTH_SECONDS[Config.CropType.MAIZE]
	_grow_well(tile, growth_seconds + 4.0)
	check_equal(tile.state, CropTile.State.MATURE, "a well watered crop reaches maturity")
	check_near(tile.growth, 1.0, 0.001, "growth stops at 1.0")
	check_greater(tile.health, 0.9, "a well watered crop keeps its condition")
	check_equal(tile.growth_stage(), 4, "a mature crop shows its final sprite stage")

	var expected_yield: float = Config.CROP_BASE_YIELD[Config.CropType.MAIZE] * tile.health
	var harvest_result: Dictionary = tile.harvest()
	check(bool(harvest_result["ok"]), "a mature crop can be harvested")
	check_near(tile.harvested_yield, expected_yield, 0.01,
		"yield is the crop's base yield scaled by its condition")
	check_equal(tile.state, CropTile.State.HARVESTED, "harvesting clears the tile")
	tile.queue_free()


func _test_tilling_is_required() -> void:
	var tile := _new_tile()
	var result: Dictionary = tile.plant(Config.CropType.MAIZE, 0)
	check(not bool(result["ok"]), "seed cannot go into unprepared ground")
	check(String(result["message"]).to_lower().contains("till"),
		"refusing to sow explains that the ground has to be tilled")
	check_equal(tile.state, CropTile.State.GRASS, "a refused sowing changes nothing")
	tile.queue_free()


func _test_water_stress_costs_condition() -> void:
	# Two identical tiles. One is kept watered, the other is left alone.
	var watered := _new_tile()
	watered.till(0)
	watered.plant(Config.CropType.MAIZE, 0)
	var neglected := _new_tile()
	neglected.till(0)
	neglected.plant(Config.CropType.MAIZE, 0)

	_grow_well(watered, 40.0)
	# 15 seconds untended: long enough to fall into stress and lose condition,
	# short enough that the crop has not died outright.
	for _step in range(60):
		neglected.simulate(0.25, NORMAL)

	check_less(neglected.moisture, Config.MOISTURE_STRESS_THRESHOLD,
		"an unwatered tile falls into water stress")
	check(neglected.is_stressed(), "the tile reports itself as stressed")
	check_greater(neglected.seconds_stressed, 0.0, "time spent in stress is recorded")
	check_less(neglected.health, watered.health,
		"the neglected tile is in worse condition than the watered one")
	check_less(neglected.growth, watered.growth,
		"water stress slows growth as well as damaging condition")

	# Recovery is partial: watering it now does not undo the damage.
	var damaged_health: float = neglected.health
	_grow_well(neglected, 10.0)
	check_greater(neglected.health, damaged_health, "watering lets condition recover a little")
	check_less(neglected.health, 1.0,
		"condition lost to stress is not fully recovered by watering later")

	watered.queue_free()
	neglected.queue_free()


func _test_over_watering_is_flagged() -> void:
	var tile := _new_tile()
	tile.till(0)
	tile.plant(Config.CropType.MAIZE, 0)
	tile.apply_water(Config.WATER_COST_PER_ACTION)
	tile.apply_water(Config.WATER_COST_PER_ACTION)
	check_near(tile.moisture, 1.0, 0.001, "moisture is capped at full")
	var result: Dictionary = tile.apply_water(Config.WATER_COST_PER_ACTION)
	check(bool(result["ok"]), "watering a saturated tile still uses the water")
	check_equal(result["kind"], "warn", "watering a saturated tile is flagged as wasteful")
	check(String(result["message"]).to_lower().contains("drained"),
		"the player is told the extra water drained past the roots")
	tile.queue_free()


func _test_pests() -> void:
	var tile := _new_tile()
	tile.till(0)
	tile.plant(Config.CropType.BEANS, 1)
	_grow_well(tile, 6.0)

	check(not tile.can_treat(), "a healthy tile has nothing to treat")
	check(not bool((tile.treat(10.0) as Dictionary)["ok"]), "treating a clean tile does nothing")

	check(tile.infest(12.0), "a growing tile can become infested")
	check(tile.infested, "the tile records the infestation")
	check_near(tile.infested_at, 12.0, 0.001, "the time of infestation is recorded")
	check(not tile.pest_is_visible(),
		"a fresh, unscouted infestation is not yet obvious from a distance")

	var health_before: float = tile.health
	for _step in range(40):
		if tile.moisture < Config.MOISTURE_HEALTHY_THRESHOLD:
			tile.apply_water(Config.WATER_COST_PER_ACTION)
		tile.simulate(0.25, NORMAL)
	check_less(tile.health, health_before,
		"an untreated infestation costs condition even on a well watered tile")
	check_greater(tile.pest_level, 0.4, "pest pressure builds up while it is left alone")
	check(tile.pest_is_visible(), "a bad enough infestation becomes visible without scouting")
	check_greater(tile.seconds_infested, 0.0, "time spent infested is recorded")

	var treat_result: Dictionary = tile.treat(24.0)
	check(bool(treat_result["ok"]), "an infested tile can be treated")
	check(not tile.infested, "treatment clears the infestation")
	check_near(tile.pest_level, 0.0, 0.001, "treatment removes the pest pressure")
	check_near(tile.treated_at, 24.0, 0.001, "the time of treatment is recorded")
	check_equal(treat_result["kind"], "bad", "treating a severe outbreak is reported as too late")

	# Scouting a tile reveals what is on it.
	var scout_result: Dictionary = tile.scout()
	check(bool(scout_result["ok"]), "a tile can be scouted")
	check(tile.scouted, "scouting marks the tile as inspected")
	check(String(scout_result["message"]).contains("condition"),
		"scouting reports the crop's condition")
	tile.queue_free()


## A season runs to the clock now, so a tile can be worked more than once. The
## cumulative figures have to survive re-tilling, or the research data quietly
## loses everything but the last crop.
func _test_reworking_a_tile() -> void:
	var tile := _new_tile()
	var growth_seconds: float = Config.CROP_GROWTH_SECONDS[Config.CropType.MAIZE]

	for cycle in range(2):
		tile.till(0)
		tile.plant(Config.CropType.MAIZE, 0)
		_grow_well(tile, growth_seconds + 4.0)
		check_equal(tile.state, CropTile.State.MATURE, "cycle %d reaches maturity" % (cycle + 1))
		tile.harvest()

	check_equal(tile.harvest_count, 2, "both harvests are counted")
	check(tile.ever_sown, "the tile is marked as having been sown")
	check_greater(tile.lifetime_yield, tile.harvested_yield,
		"lifetime yield is more than the last crop alone")
	check_near(tile.lifetime_yield, tile.harvested_yield * 2.0, 0.01,
		"lifetime yield is the sum of both harvests")
	check_greater(tile.times_watered, 2, "waterings accumulate across cycles")

	var record: Dictionary = tile.to_record()
	check_equal(record["harvests"], 2, "the record reports both harvests")
	check_near(float(record["total_yield"]), tile.lifetime_yield, 0.01,
		"the record reports the lifetime yield, not just the last crop")

	# A crop that dies and is cleared counts as a failed cycle, not a harvest.
	#
	# The tile is left dry as well as condition-less, because that is the only way
	# a crop ever reaches zero condition: a well watered, pest-free tile recovers
	# condition every tick, so setting health to zero on one and expecting it to
	# die was testing an impossible state.
	tile.till(0)
	tile.plant(Config.CropType.MAIZE, 0)
	tile.health = 0.0
	tile.moisture = 0.0
	tile.simulate(0.1, NORMAL)
	check_equal(tile.state, CropTile.State.DEAD, "a starved crop with no condition left dies")
	tile.harvest()
	check_equal(tile.failed_cycles, 1, "the failed cycle is counted")
	check_equal(tile.harvest_count, 2, "a failed cycle is not counted as a harvest")
	tile.queue_free()


func _test_record() -> void:
	var tile := _new_tile()
	tile.till(0)
	tile.plant(Config.CropType.MAIZE, 1)
	tile.apply_water(Config.WATER_COST_PER_ACTION)
	tile.infest(5.0)
	tile.simulate(1.0, NORMAL)
	tile.treat(9.0)

	var record: Dictionary = tile.to_record()
	for key in ["tile", "state", "crop", "growth", "health", "moisture", "times_watered",
			"water_used_litres", "seconds_stressed", "seconds_infested", "harvested_yield"]:
		check(record.has(key), "the tile record contains '%s'" % key)
	check_equal(record["tile"], "2,3", "the record identifies the tile")
	check_equal(record["crop"], "Maize", "the record names the crop")
	check_equal(record["times_watered"], 1, "the record counts waterings")
	check_equal(record["tilled_by_player"], 1, "the record credits the player who tilled")
	check_equal(record["planted_by_player"], 2, "the record credits the player who sowed")
	check_near(float(record["pest_response_seconds"]), 4.0, 0.001,
		"the record holds how long the pest response took")

	# The record has to survive JSON, because that is where it ends up.
	var json := JSON.stringify(record)
	var parser := JSON.new()
	check_equal(parser.parse(json), OK, "the tile record serialises to valid JSON")
	tile.queue_free()
