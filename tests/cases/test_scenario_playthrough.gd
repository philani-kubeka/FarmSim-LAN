extends "res://tests/farm_sim_test.gd"
## Plays all three crop-management scenarios end to end with a scripted
## strategy, and checks that each one produces the outcome its design is
## supposed to produce.
##
## What this does NOT cover: walking, aiming and pressing keys. The policy calls
## the farm's action entry point directly, so this is a test of the farming and
## scenario rules, not of the ergonomics of two people at one keyboard. Those are
## covered by the movement test and by manual play.

const Fixture := preload("res://tests/farm_fixture.gd")

const REQUIRED_RESULT_KEYS := [
	"scenario_id", "title", "crop", "end_reason", "duration_seconds", "elapsed_seconds",
	"tiles_sown", "tiles_matured", "tiles_harvested", "tiles_failed", "tiles_still_growing",
	"average_condition", "total_yield", "water", "event", "players", "tiles", "causes",
]


func run() -> void:
	var baseline := _play("baseline", 10)
	var drought_sensible := _play("drought", 2)
	var drought_greedy := _play("drought", 12)
	var pest := _play("pest", 10)

	_check_result_shape(baseline, "baseline")
	_check_result_shape(drought_sensible, "drought")
	_check_result_shape(pest, "pest")

	# --- baseline: a settled season should go well ---
	check_greater(float(baseline["total_yield"]), 0.0, "the baseline season produces a harvest")
	check_greater(int(baseline["tiles_harvested"]), 4,
		"a well run baseline season brings in a reasonable number of harvests")
	check_equal(String(baseline["end_reason"]), "time",
		"a season runs its full length rather than ending when the last tile is cleared")
	check_near(float(baseline["elapsed_seconds"]), float(baseline["duration_seconds"]), 1.0,
		"the season used the whole clock, so every pair gets the same exposure")
	check_greater(float(baseline["average_condition"]), 0.7,
		"crops in the baseline season finish in good condition")
	check_equal(int(baseline["tiles_failed"]), 0, "nothing should fail in a settled season")
	check_equal(String((baseline["event"] as Dictionary)["event"]), "none",
		"no environmental event fires in the baseline season")

	# --- drought: the reserve has to run out, and over-committing has to hurt ---
	var drought_water: Dictionary = drought_greedy["water"]
	check_less(float(drought_water["remaining_litres"]),
		float(drought_water["capacity_litres"]),
		"the drought season uses its reserve")
	check(bool((drought_greedy["event"] as Dictionary)["triggered"]),
		"the drought event fires during the drought season")

	check_greater(float(drought_sensible["total_yield"]), 0.0,
		"a season farmed within the water available still produces a harvest")
	check(float(drought_sensible["total_yield"]) > float(drought_greedy["total_yield"]),
		"sowing more ground than the reserve can support produces a smaller harvest, not a bigger one")
	check(float(drought_sensible["average_condition"]) > float(drought_greedy["average_condition"]),
		"spreading the same water over more tiles leaves every crop in worse condition")
	check_greater(int(drought_greedy["tiles_failed"]), 0,
		"over-committing during a drought kills crops outright")
	check_equal(int(drought_greedy["tiles_harvested"]), 0,
		"a drought season spread far too thin brings nothing in at all")
	# The scripted policy checks the reserve before watering, exactly as a pair who
	# can read the water bar would, so it never provokes a refusal. What it does
	# do is run the reserve dry, which is the thing this comparison is about. The
	# refusal itself - the message the players get once the reserve cannot cover
	# another watering - is covered by test_farming_loop.
	var greedy_water: Dictionary = drought_greedy["water"]
	check(float(greedy_water["remaining_litres"]) < Config.WATER_COST_PER_ACTION,
		"over-committing during a drought empties the shared reserve (%.1f L left)"
			% float(greedy_water["remaining_litres"]))

	# The baseline and drought seasons sow the same crop, so the difference in
	# outcome is attributable to the water, which is the point of the comparison.
	check_equal(String(baseline["crop"]), String(drought_greedy["crop"]),
		"the baseline and drought seasons use the same crop")
	check(float(drought_greedy["total_yield"]) < float(baseline["total_yield"]),
		"the same farming approach yields less under drought than in a settled season")

	# --- pest ---
	var pest_event: Dictionary = pest["event"]
	check(bool(pest_event["triggered"]), "the pest outbreak fires during its season")
	check_greater(int(pest_event["tiles_infested"]), 0, "the outbreak reaches the crop")
	check_equal(String(pest["crop"]), "Beans", "the pest season is a bean season")

	# --- causal feedback ---
	for result in [baseline, drought_sensible, drought_greedy, pest]:
		var causes: Array = result["causes"]
		check(causes.size() >= 3,
			"the %s season explains its outcome in at least three points"
				% String(result["scenario_id"]))
		for note in causes:
			check(String(note).length() > 20, "each explanation is a real sentence")

	var drought_text := " ".join(PackedStringArray(drought_greedy["causes"]))
	check(drought_text.contains("drought") or drought_text.contains("reserve"),
		"the drought season's explanation talks about the water")
	var pest_text := " ".join(PackedStringArray(pest["causes"]))
	check(pest_text.contains("outbreak") or pest_text.contains("infested"),
		"the pest season's explanation talks about the outbreak")

	# --- the result has to survive the trip into the research file ---
	var json := JSON.stringify(baseline)
	var parser := JSON.new()
	check_equal(parser.parse(json), OK, "a season result serialises to valid JSON")


func _play(scenario_id: String, spread: int) -> Dictionary:
	var farm := Fixture.make(self, scenario_id)
	var finished := [{}]
	farm.season_finished.connect(func(result: Dictionary) -> void: finished[0] = result)
	Fixture.play_season(farm, spread)
	check(not farm.running, "the %s season ends on its own" % scenario_id)
	check(not (finished[0] as Dictionary).is_empty(),
		"the %s season emits its result when it ends" % scenario_id)
	var result: Dictionary = finished[0]
	farm.queue_free()
	return result


func _check_result_shape(result: Dictionary, scenario_id: String) -> void:
	check_equal(String(result.get("scenario_id", "")), scenario_id,
		"the result identifies the %s scenario" % scenario_id)
	for key in REQUIRED_RESULT_KEYS:
		check(result.has(key), "the %s result contains '%s'" % [scenario_id, key])

	var players: Array = result.get("players", [])
	check_equal(players.size(), 2, "the %s result records both players" % scenario_id)
	var roles: Array[String] = []
	for record in players:
		roles.append(String((record as Dictionary).get("role", "")))
		check((record as Dictionary).has("actions"),
			"each player record holds what that player actually did")
	check("planter" in roles and "monitor" in roles,
		"both roles appear in the %s result" % scenario_id)

	var tiles: Array = result.get("tiles", [])
	check_greater(tiles.size(), 0, "the %s result records the tiles that were worked" % scenario_id)
