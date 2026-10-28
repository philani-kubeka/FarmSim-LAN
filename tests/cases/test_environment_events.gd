extends "res://tests/farm_sim_test.gd"
## Drought and pest outbreak: that they fire when the scenario says, that they
## actually change how the farm behaves, and that responding to them matters.

const Fixture := preload("res://tests/farm_fixture.gd")
const CropTile := preload("res://scripts/farm/crop_tile.gd")

const STEP := 0.25


func run() -> void:
	_test_no_event_in_baseline()
	_test_drought()
	_test_pest_outbreak()
	_test_pest_keeps_coming()
	_test_pest_response_matters()


## Advances the season in small steps, watering the listed tiles whenever they
## would otherwise drop into stress. Time has to move in small steps: a single
## huge delta would take a crop from healthy to dead in one call and would not
## resemble anything that happens during play.
func _advance(farm: Node2D, seconds: float, watered_tiles: Array) -> void:
	var planter := Fixture.player_with_role(farm, "planter")
	var remaining := seconds
	while remaining > 0.0 and farm.running:
		for tile in watered_tiles:
			if tile.moisture < Config.MOISTURE_HEALTHY_THRESHOLD \
					and farm.water.can_draw(Config.WATER_COST_PER_ACTION):
				farm.perform_action(planter, Config.Tool.WATER, tile)
		farm.simulate(STEP)
		remaining -= STEP


func _sow(farm: Node2D, tile: Node2D) -> void:
	var planter := Fixture.player_with_role(farm, "planter")
	farm.perform_action(planter, Config.Tool.HOE, tile)
	farm.perform_action(planter, Config.Tool.SEED, tile)


func _test_no_event_in_baseline() -> void:
	var farm := Fixture.make(self, "baseline")
	check_equal(farm.event.event_id, "none", "the baseline season runs no event")
	var tile: Node2D = farm.field.tile_at(1, 1)
	_sow(farm, tile)
	_advance(farm, 60.0, [tile])
	check(not farm.event.active, "nothing is triggered during a settled season")
	check_near(farm.event.drying_multiplier(), 1.0, 0.001,
		"the baseline season dries the soil at the normal rate")
	check_greater(tile.health, 0.9,
		"a settled season lets a tended crop stay in full condition")
	farm.queue_free()


func _test_drought() -> void:
	var farm := Fixture.make(self, "drought")
	check_equal(farm.event.event_id, "drought", "the drought scenario carries a drought event")
	var start: float = farm.event.start_seconds
	check_greater(start, 0.0, "the drought starts partway through the season, not at the whistle")

	var announced := [""]
	farm.event.triggered.connect(
		func(id: String, _t: String, _b: String, _i: String) -> void: announced[0] = id)

	var base_multiplier: float = farm.event.drying_multiplier()

	# Two identical tiles, both tended until the drought arrives.
	var protected: Node2D = farm.field.tile_at(0, 0)
	var abandoned: Node2D = farm.field.tile_at(7, 4)
	_sow(farm, protected)
	_sow(farm, abandoned)

	_advance(farm, start - 2.0, [protected, abandoned])
	check(not farm.event.active, "the drought has not started yet")
	check_equal(announced[0], "", "nothing has been announced yet")
	check_near(protected.health, abandoned.health, 0.05,
		"before the drought the two tiles are in the same condition")

	_advance(farm, 3.0, [protected, abandoned])
	check(farm.event.active, "the drought starts at the time the scenario says")
	check_equal(announced[0], "drought", "the drought is announced to the players")
	check_greater(farm.event.drying_multiplier(), base_multiplier,
		"the drought makes the soil dry out faster than before")
	check_greater(farm.event.triggered_at, 0.0, "the time the drought started is recorded")

	# The drought builds up: it starts gently, gets steadily worse and tops out at
	# the scenario's maximum, then stays there.
	var peak: float = farm.event.event_drying_multiplier
	var ramp: float = farm.event.ramp_seconds
	check_greater(ramp, 0.0, "the drought builds up over time rather than all at once")
	check_less(farm.event.drying_multiplier(), peak,
		"just after it starts the drought is not yet at full strength")
	check_near(farm.event.multiplier_at(0.0), farm.event.base_drying_multiplier, 0.001,
		"the drought starts from the season's normal drying rate")
	check_greater(farm.event.multiplier_at(ramp * 0.5), farm.event.multiplier_at(ramp * 0.25),
		"the soil dries faster as the drought goes on")
	check_near(farm.event.multiplier_at(ramp), peak, 0.001,
		"the drought reaches the scenario's maximum")
	check_near(farm.event.multiplier_at(ramp * 3.0), peak, 0.001,
		"and never goes past it")

	# From here the players can only afford to protect one of the two tiles.
	_advance(farm, 45.0, [protected])

	check_greater(protected.health, abandoned.health,
		"the tile that kept getting water is in better condition than the one that did not")
	check_greater(protected.growth, abandoned.growth,
		"the abandoned tile also fell behind on growth")
	check_greater(abandoned.seconds_stressed, 1.0,
		"the abandoned tile spent real time under water stress")
	check_less(protected.seconds_stressed, abandoned.seconds_stressed,
		"the protected tile spent less time in stress")

	var record: Dictionary = farm.event.to_record()
	check_equal(record["event"], "drought", "the event record names the event")
	check(bool(record["triggered"]), "the event record shows it fired")
	check(record["triggered_at_seconds"] != null, "the event record holds when it fired")
	farm.queue_free()


func _test_pest_outbreak() -> void:
	var farm := Fixture.make(self, "pest")
	check_equal(farm.event.event_id, "pest", "the pest scenario carries a pest outbreak")
	check_equal(farm.crop_type, Config.CropType.BEANS, "the pest scenario sows beans")

	var monitor := Fixture.player_with_role(farm, "monitor")

	# Establish a block of beans and keep it watered, so the only thing that can
	# go wrong this season is the outbreak.
	var block: Array = []
	for column in range(6):
		var tile: Node2D = farm.field.tile_at(column, 0)
		_sow(farm, tile)
		block.append(tile)

	_advance(farm, farm.event.start_seconds - 2.0, block)
	check(not farm.event.active, "the outbreak has not started yet")
	check_equal(farm.field.infested_count(), 0, "nothing is infested before the outbreak")

	_advance(farm, 3.0, block)
	check(farm.event.active, "the outbreak starts at the time the scenario says")
	check_greater(farm.field.infested_count(), 0, "the outbreak infests tiles that were sown")
	check_greater(farm.event.infested_total, 0, "the event records how many tiles it reached")

	var infested: Node2D = null
	for tile in farm.field.tiles:
		if tile.infested and infested == null:
			infested = tile
	check_not_null(infested, "at least one infested tile can be found")
	if infested == null:
		farm.queue_free()
		return
	check(not infested.pest_is_visible(),
		"a fresh outbreak is not obvious from across the field - it has to be scouted")

	# The outbreak builds up: new pests keep arriving, faster as time goes on.
	check_greater(farm.event.arrivals_peak, farm.event.arrivals_start,
		"pests arrive faster late in the season than early on")
	check_greater(farm.event.arrivals_per_minute_at(farm.event.arrival_ramp_seconds * 0.75),
		farm.event.arrivals_per_minute_at(farm.event.arrival_ramp_seconds * 0.25),
		"the arrival rate climbs as the outbreak goes on")
	check_near(farm.event.arrivals_per_minute_at(farm.event.arrival_ramp_seconds * 4.0),
		farm.event.arrivals_peak, 0.001, "and holds at the scenario's peak")

	var scout: Dictionary = farm.perform_action(monitor, Config.Tool.INSPECT, infested)
	check(bool(scout["ok"]), "the monitor can scout a tile")
	check(String(scout["message"]).contains("PEST"), "scouting reveals the pests")
	check(infested.pest_is_visible(), "a scouted tile shows its pest marker")

	var treat: Dictionary = farm.perform_action(monitor, Config.Tool.TREAT, infested)
	check(bool(treat["ok"]), "the monitor can treat the tile")
	check(not infested.infested, "treating clears the outbreak on that tile")
	check_greater(infested.treated_at, 0.0, "the time of the response is recorded")
	farm.queue_free()


func _test_pest_keeps_coming() -> void:
	# A whole season in which the monitor treats everything: well beyond the
	# first wave of pests should still turn up, most of them late in the season.
	var farm := Fixture.make(self, "pest")
	Fixture.play_season(farm, 10, 0.5, false)
	var record: Dictionary = farm.event.to_record()
	var initial: int = farm.event.initial_tiles
	check_greater(float(record.get("tiles_infested", 0)), float(initial + 3),
		"far more than the first %d pests appear over a season (%d in all)"
			% [initial, int(record.get("tiles_infested", 0))])
	check_greater(float(record.get("tiles_infested_by_new_arrivals", 0)), 0.0,
		"new pests keep arriving after the first wave")
	farm.queue_free()


func _test_pest_response_matters() -> void:
	# Same scenario, same random seed, same farming policy. The only difference
	# is whether the Field Monitor deals with the outbreak.
	var treated := _run_pest_season(false)
	var ignored := _run_pest_season(true)

	check_greater(treated["infested_seconds"], 0.0,
		"the outbreak did reach the crop in the treated run too")
	check(ignored["infested_seconds"] > treated["infested_seconds"],
		"ignoring the outbreak means the crop spends far longer under attack")
	check_greater(treated["condition"], ignored["condition"],
		"treated crops finish the season in better condition")
	check(treated["yield"] >= ignored["yield"],
		"treating the outbreak never produces a worse harvest than ignoring it")


func _run_pest_season(neglect: bool) -> Dictionary:
	var farm := Fixture.make(self, "pest")
	Fixture.play_season(farm, 10, 0.5, neglect)
	var result: Dictionary = farm.build_result("time")
	var infested_seconds := 0.0
	for record in (result.get("tiles", []) as Array):
		infested_seconds += float((record as Dictionary).get("seconds_infested", 0.0))
	var summary := {
		"yield": float(result.get("total_yield", 0.0)),
		"condition": float(result.get("average_condition", 0.0)),
		"infested_seconds": infested_seconds,
	}
	farm.queue_free()
	return summary
