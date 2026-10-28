extends "res://tests/farm_sim_test.gd"
## Walks a complete session through the session controller - setup, pre-test,
## three scenarios with results and quizzes, post-test, final results - and then
## checks the research file that comes out the other end.
##
## Screens are not involved: in test mode the controller does not change scenes,
## so this exercises the flow logic and the data it produces. Whether each screen
## renders is covered by the scene-load test.

const SCENARIO_KINDS := ["quiz_1", "quiz_2", "quiz_3"]


func run() -> void:
	GameplayLogger.clear()
	SessionController.start_new_session()

	check_equal(SessionController.phase, SessionController.Phase.PLAYER_SETUP,
		"starting a session lands on player setup")
	var session_id := GameState.session_id
	check_equal(session_id.length(), 8, "a fresh session id is issued")
	check(GameState.scenario_results.is_empty(), "a fresh session has no results yet")

	# --- pre-test ---
	SessionController.begin_pre_assessment()
	check_equal(SessionController.phase, SessionController.Phase.PRE_ASSESSMENT,
		"confirming the roles moves to the pre-test")
	check_equal(String(SessionController.pending_assessment.get("path", "")),
		SessionController.PRE_ASSESSMENT_PATH, "the pre-test loads the pre-test instrument")
	check(not bool(SessionController.pending_assessment.get("show_feedback", true)),
		"the pre-test does not show the answers, so it cannot teach before the game does")

	SessionController.submit_assessment("pre_assessment", _fake_assessment("pre_assessment", 3, 8))
	check_equal(int(GameState.pre_assessment.get("score", -1)), 3, "the pre-test score is kept")
	check_equal(SessionController.phase, SessionController.Phase.SCENARIO_BRIEFING,
		"finishing the pre-test leads to the first scenario's briefing, not straight into play")
	check_equal(String(SessionController.pending_scenario.get("id", "")), "baseline",
		"the first scenario is the baseline season")

	# --- three scenarios ---
	var expected_ids := ["baseline", "pest", "drought"]
	for index in range(3):
		check_equal(GameState.current_scenario_index, index,
			"the session is on scenario %d" % (index + 1))
		check_equal(String(SessionController.pending_scenario.get("id", "")), expected_ids[index],
			"scenario %d is '%s'" % [index + 1, expected_ids[index]])
		check_equal(SessionController.phase, SessionController.Phase.SCENARIO_BRIEFING,
			"scenario %d opens with its briefing" % (index + 1))

		SessionController.begin_scenario()
		check_equal(SessionController.phase, SessionController.Phase.SCENARIO,
			"pressing through the briefing starts scenario %d" % (index + 1))

		SessionController.finish_scenario(_fake_season_result(index))
		check_equal(SessionController.phase, SessionController.Phase.SCENARIO_RESULTS,
			"finishing a season shows its results")
		check_equal(GameState.scenario_results.size(), index + 1,
			"the season result is kept")
		check_equal(int(SessionController.pending_results.get("scenario_index", 0)), index + 1,
			"the results screen is handed this season's numbers")

		SessionController.begin_scenario_quiz()
		check_equal(SessionController.phase, SessionController.Phase.SCENARIO_QUIZ,
			"the results screen leads into the scenario quiz")
		var quiz_path := String(SessionController.pending_assessment.get("path", ""))
		check(quiz_path.contains("quiz_scenario_%d" % (index + 1)),
			"scenario %d leads to its own quiz" % (index + 1))
		check(bool(SessionController.pending_assessment.get("show_feedback", false)),
			"scenario quizzes explain the answer, because that is part of the teaching")

		SessionController.submit_assessment(SCENARIO_KINDS[index],
			_fake_assessment(SCENARIO_KINDS[index], 2, 3))
		check_equal(GameState.scenario_quizzes.size(), index + 1, "the quiz result is kept")

	# --- post-test ---
	check_equal(SessionController.phase, SessionController.Phase.POST_ASSESSMENT,
		"after the third quiz the session moves to the post-test")
	check_equal(String(SessionController.pending_assessment.get("path", "")),
		SessionController.POST_ASSESSMENT_PATH, "the post-test loads the post-test instrument")

	SessionController.submit_assessment("post_assessment", _fake_assessment("post_assessment", 6, 8))
	check_equal(SessionController.phase, SessionController.Phase.USABILITY,
		"finishing the post-test moves to the usability questions")
	SessionController.submit_usability({"instrument_id": "usability_v1", "responses": [
		{"player": 1, "answers": []}, {"player": 2, "answers": []}]})
	check_equal(SessionController.phase, SessionController.Phase.FINAL_RESULTS,
		"finishing the usability questions ends the session")
	check_equal(String(GameState.usability.get("instrument_id", "")), "usability_v1",
		"the usability answers are kept")
	check_near(GameState.knowledge_gain_percent(), 37.5, 0.1,
		"the session reports the change between the two tests")
	check_near(GameState.total_yield(), 90.0, 0.01, "the session totals the three harvests")

	_check_written_file(session_id)


func _check_written_file(session_id: String) -> void:
	var path := GameplayLogger.output_directory().path_join("session_%s.json" % session_id)
	check(FileAccess.file_exists(path), "completing a session writes its research file")
	if not FileAccess.file_exists(path):
		return

	var parser := JSON.new()
	check_equal(parser.parse(FileAccess.get_file_as_string(path)), OK,
		"the session file is valid JSON")
	var document: Variant = parser.data
	if typeof(document) != TYPE_DICTIONARY:
		fail("the session file parses to an object")
		return
	var doc := document as Dictionary

	for key in ["session_id", "player_roles", "pre_assessment", "post_assessment",
			"scenarios", "scenario_quizzes", "knowledge_gain_percent", "total_yield", "events"]:
		check(doc.has(key), "the session file contains '%s'" % key)

	check_equal(String(doc.get("session_id", "")), session_id,
		"the session file is keyed by this session's anonymous id")
	check_equal((doc.get("scenarios", []) as Array).size(), 3,
		"all three seasons are in the file")
	check_equal((doc.get("scenario_quizzes", []) as Array).size(), 3,
		"all three quizzes are in the file")
	check_equal(int((doc.get("pre_assessment", {}) as Dictionary).get("score", -1)), 3,
		"the pre-test score in the file matches what was submitted")
	check_equal(int((doc.get("post_assessment", {}) as Dictionary).get("score", -1)), 6,
		"the post-test score in the file matches what was submitted")

	# No personal data anywhere in the document.
	var raw := FileAccess.get_file_as_string(path).to_lower()
	for forbidden in ["\"name\"", "\"email\"", "\"surname\"", "\"password\""]:
		check(not raw.contains(forbidden),
			"the session file contains no %s field" % forbidden.replace("\"", ""))

	# The event log has to reflect the session that actually happened.
	var events: Array = doc.get("events", [])
	var actions: Array[String] = []
	for entry in events:
		actions.append(String((entry as Dictionary).get("action", "")))
	check("session_started" in actions, "the log records the session starting")
	check(actions.count("scenario_started") == 3,
		"the log records a start for each of the three scenarios")
	check("scenario_started" in actions, "the log records scenarios starting")
	check("scenario_completed" in actions, "the log records scenarios completing")
	check("assessment_completed" in actions, "the log records assessments completing")
	check("session_completed" in actions, "the log records the session completing")

	# This file was produced by the test suite, not by participants, so it is
	# removed rather than being left where study data is collected.
	DirAccess.remove_absolute(path)
	check(not FileAccess.file_exists(path),
		"the synthetic test session is cleaned up and not left among the study data")


func _fake_assessment(kind: String, score: int, max_score: int) -> Dictionary:
	return {
		"kind": kind,
		"instrument_id": "%s_v1" % kind,
		"score": score,
		"max_score": max_score,
		"percent": snappedf(100.0 * score / maxf(float(max_score), 1.0), 0.1),
		"seconds": 12.0,
		"answers": [],
	}


func _fake_season_result(index: int) -> Dictionary:
	return {
		"title": "Season %d" % (index + 1),
		"crop": "Maize",
		"total_yield": 30.0,
		"tiles_harvested": 4,
		"tiles_sown": 6,
		"tiles_failed": 0,
		"tiles_still_growing": 2,
		"average_condition": 0.8,
		"water": {"capacity_litres": 100.0, "used_litres": 40.0, "refused_draws": 0},
		"event": {"event": "none", "triggered": false},
		"players": [],
		"tiles": [],
		"causes": ["A synthetic season used by the automated flow test."],
	}
