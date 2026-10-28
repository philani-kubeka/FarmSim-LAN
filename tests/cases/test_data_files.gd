extends "res://tests/farm_sim_test.gd"
## Validates the researcher-editable JSON: the scenario definitions and every
## knowledge instrument. A broken instrument would otherwise only be discovered
## in the middle of a session with participants sitting in front of it.

const WeatherSystem := preload("res://scripts/systems/weather_system.gd")

const ASSESSMENT_DIR := "res://data/assessments"
const REQUIRED_INSTRUMENTS := [
	"res://data/assessments/pre_assessment.json",
	"res://data/assessments/post_assessment.json",
	"res://data/assessments/quiz_scenario_1.json",
	"res://data/assessments/quiz_scenario_2.json",
	"res://data/assessments/quiz_scenario_3.json",
]

const REQUIRED_SCENARIO_KEYS := [
	"id", "title", "crop", "duration_seconds", "water_reserve_litres",
	"drying_multiplier", "event", "briefing", "objectives", "quiz_file",
]


func run() -> void:
	_check_scenarios()
	for path in REQUIRED_INSTRUMENTS:
		_check_instrument(path)
	_check_pre_post_comparable()


func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		fail("data file exists: %s" % path)
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		fail("%s is valid JSON (%s at line %d)" % [path, json.get_error_message(), json.get_error_line()])
		return null
	check(true, "%s is valid JSON" % path.get_file())
	return json.data


func _check_scenarios() -> void:
	var data: Variant = _load_json(SessionController.SCENARIOS_DATA_PATH)
	if typeof(data) != TYPE_DICTIONARY:
		return
	var scenarios: Variant = (data as Dictionary).get("scenarios", [])
	if typeof(scenarios) != TYPE_ARRAY:
		fail("scenarios.json contains a scenarios array")
		return
	check_equal((scenarios as Array).size(), 3, "scenarios.json defines exactly three scenarios")

	var seen_ids: Array[String] = []
	var events: Array[String] = []
	for entry in (scenarios as Array):
		var scenario := entry as Dictionary
		var scenario_id := String(scenario.get("id", ""))
		for key in REQUIRED_SCENARIO_KEYS:
			check(scenario.has(key), "scenario '%s' has key '%s'" % [scenario_id, key])
		check(not (scenario_id in seen_ids), "scenario id '%s' is unique" % scenario_id)
		seen_ids.append(scenario_id)
		events.append(String(scenario.get("event", "none")))

		check(float(scenario.get("duration_seconds", 0.0)) > 0.0,
			"scenario '%s' has a positive duration" % scenario_id)
		check(float(scenario.get("water_reserve_litres", 0.0)) > 0.0,
			"scenario '%s' starts with some water" % scenario_id)
		check(String(scenario.get("crop", "")) in ["maize", "beans"],
			"scenario '%s' uses an implemented crop" % scenario_id)

		var quiz_file := String(scenario.get("quiz_file", ""))
		check(FileAccess.file_exists(quiz_file),
			"scenario '%s' points at an existing quiz file" % scenario_id)

	# The research design needs one settled season, one drought and one pest event.
	check("drought" in events, "one scenario runs a drought event")
	check("pest" in events, "one scenario runs a pest outbreak event")

	# The drought scenario must actually be scarcer than the baseline, otherwise
	# the prioritisation decision it is meant to teach does not exist.
	var baseline := _scenario_by_id(scenarios as Array, "baseline")
	var drought := _scenario_by_id(scenarios as Array, "drought")
	var pest := _scenario_by_id(scenarios as Array, "pest")
	if not baseline.is_empty() and not drought.is_empty():
		check(float(drought.get("water_reserve_litres", 0.0))
				< float(baseline.get("water_reserve_litres", 0.0)),
			"the drought season starts with less water than the baseline season")
		check(float(drought.get("event_drying_multiplier", drought.get("drying_multiplier", 1.0)))
				> float(baseline.get("drying_multiplier", 1.0)),
			"the drought season dries the soil faster than the baseline season")

	# Each reserve is checked against what its own target area actually needs for
	# a full season. These are the numbers that decide whether a scenario poses
	# the question it is supposed to pose.
	_check_reserve(baseline, 1.25, true,
		"water is genuinely not the constraint in the baseline season")
	_check_reserve(drought, 0.75, false,
		"the drought reserve cannot cover the target area, so there is a real decision")
	_check_reserve(pest, 1.15, true,
		"water is not the problem in the pest season - the outbreak is")


## `ratio` is the fraction of a full season's water demand the reserve has to be
## above (generous = true) or below (generous = false).
func _check_reserve(scenario: Dictionary, ratio: float, generous: bool, message: String) -> void:
	if scenario.is_empty():
		return
	var crop: int = Config.crop_id_from_name(String(scenario.get("crop", "")))
	# A drought builds up over time, so the demand is sized against the season's
	# average drying rate, not its peak.
	var multiplier: float = WeatherSystem.season_average_multiplier(scenario)
	var needed: float = Config.litres_to_sustain(
		crop,
		int(scenario.get("target_tiles", 0)),
		float(scenario.get("duration_seconds", 0.0)),
		multiplier)
	var reserve: float = float(scenario.get("water_reserve_litres", 0.0))
	check(needed > 0.0, "the %s season's water demand can be computed"
		% String(scenario.get("id", "?")))
	if needed <= 0.0:
		return
	var satisfied: bool = reserve >= needed * ratio if generous else reserve <= needed * ratio
	check(satisfied, "%s (%.0f L reserve against %.0f L of demand, ratio %.2f)"
		% [message, reserve, needed, reserve / needed])


func _scenario_by_id(scenarios: Array, wanted: String) -> Dictionary:
	for entry in scenarios:
		if typeof(entry) == TYPE_DICTIONARY and String((entry as Dictionary).get("id", "")) == wanted:
			return entry as Dictionary
	return {}


func _check_instrument(path: String) -> void:
	var data: Variant = _load_json(path)
	if typeof(data) != TYPE_DICTIONARY:
		return
	var doc := data as Dictionary
	var label := path.get_file()
	check(doc.has("id"), "%s has an instrument id" % label)
	check(doc.has("notes"), "%s carries the provisional-instrument note" % label)

	var questions: Variant = doc.get("questions", [])
	if typeof(questions) != TYPE_ARRAY:
		fail("%s contains a questions array" % label)
		return
	check((questions as Array).size() > 0, "%s contains at least one question" % label)

	var seen_ids: Array[String] = []
	for entry in (questions as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			fail("%s: every question is an object" % label)
			continue
		var question := entry as Dictionary
		var question_id := String(question.get("id", ""))
		check(not question_id.is_empty(), "%s: question has an id" % label)
		check(not (question_id in seen_ids), "%s: question id '%s' is unique" % [label, question_id])
		seen_ids.append(question_id)

		check(not String(question.get("text", "")).is_empty(),
			"%s/%s has question text" % [label, question_id])
		check(not String(question.get("topic", "")).is_empty(),
			"%s/%s is tagged with a topic" % [label, question_id])
		check(not String(question.get("explanation", "")).is_empty(),
			"%s/%s has an explanation for the feedback screen" % [label, question_id])

		var options: Variant = question.get("options", [])
		if typeof(options) != TYPE_ARRAY:
			fail("%s/%s has an options array" % [label, question_id])
			continue
		var option_count: int = (options as Array).size()
		check(option_count >= 2, "%s/%s offers at least two options" % [label, question_id])
		# The assessment screen builds six option buttons.
		check(option_count <= 6, "%s/%s has no more options than the screen can show" % [label, question_id])

		var correct_index := int(question.get("correct_index", -1))
		check(correct_index >= 0 and correct_index < option_count,
			"%s/%s has a correct_index inside its option range" % [label, question_id])


func _check_pre_post_comparable() -> void:
	var pre: Variant = _load_json("res://data/assessments/pre_assessment.json")
	var post: Variant = _load_json("res://data/assessments/post_assessment.json")
	if typeof(pre) != TYPE_DICTIONARY or typeof(post) != TYPE_DICTIONARY:
		return
	var pre_ids := _question_ids(pre as Dictionary)
	var post_ids := _question_ids(post as Dictionary)
	pre_ids.sort()
	post_ids.sort()
	check_equal(pre_ids, post_ids,
		"the post-test uses exactly the same item bank as the pre-test, so the scores are comparable")


func _question_ids(doc: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for entry in (doc.get("questions", []) as Array):
		if typeof(entry) == TYPE_DICTIONARY:
			ids.append(String((entry as Dictionary).get("id", "")))
	return ids
