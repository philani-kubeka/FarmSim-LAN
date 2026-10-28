extends "res://tests/farm_sim_test.gd"
## Exercises the session-level state that the research data depends on.


func run() -> void:
	GameState.reset_session()

	check_equal(GameState.session_id.length(), 8, "a session id is generated")
	check(GameState.session_id.strip_edges() == GameState.session_id,
		"the session id has no stray whitespace")
	check(GameState.session_started_unix > 0, "the session start time is recorded")
	check_equal(GameState.current_scenario_index, 0, "a new session starts at the first scenario")
	check(GameState.scenario_results.is_empty(), "a new session has no scenario results yet")

	# Two sessions must not collide in the data set.
	var first_id := GameState.session_id
	GameState.reset_session()
	check(GameState.session_id != first_id, "each session gets a different id")

	# Roles
	check_equal(GameState.role_for_player(0), "planter", "player 1 starts as the planter")
	check_equal(GameState.role_for_player(1), "monitor", "player 2 starts as the monitor")
	GameState.swap_roles()
	check_equal(GameState.role_for_player(0), "monitor", "swapping moves the monitor to player 1")
	check_equal(GameState.role_for_player(1), "planter", "swapping moves the planter to player 2")
	GameState.swap_roles()
	check_equal(GameState.role_for_player(0), "planter", "swapping back restores the original roles")

	# Out-of-range access must not crash mid-session.
	check_equal(GameState.role_for_player(7), "planter", "an invalid player index falls back safely")

	# Scores
	check(is_nan(GameState.knowledge_gain_percent()),
		"knowledge gain is undefined until both tests are done")
	GameState.pre_assessment = {"score": 3, "max_score": 8, "percent": 37.5}
	check(is_nan(GameState.knowledge_gain_percent()),
		"knowledge gain is still undefined with only a pre-test")
	GameState.post_assessment = {"score": 6, "max_score": 8, "percent": 75.0}
	check_near(GameState.knowledge_gain_percent(), 37.5, 0.01,
		"knowledge gain is the post-test minus the pre-test")

	# Yields accumulate across scenarios.
	GameState.record_scenario_result({"total_yield": 40.0, "tiles_harvested": 6})
	GameState.record_scenario_result({"total_yield": 22.5, "tiles_harvested": 4})
	check_near(GameState.total_yield(), 62.5, 0.001, "total yield sums every scenario")
	check_equal(GameState.scenario_results.size(), 2, "each scenario result is kept")

	# The summary document is what ends up in the research data.
	var summary := GameState.to_summary_dictionary()
	for key in ["session_id", "player_roles", "pre_assessment", "post_assessment",
			"scenarios", "scenario_quizzes", "knowledge_gain_percent", "total_yield"]:
		check(summary.has(key), "session summary contains '%s'" % key)
	check(summary["knowledge_gain_percent"] != null,
		"a completed session reports a numeric knowledge gain")

	# An incomplete session must still serialise: JSON has no NAN literal.
	GameState.reset_session()
	var partial := GameState.to_summary_dictionary()
	check_equal(partial["knowledge_gain_percent"], null,
		"an incomplete session reports null rather than NAN")
	var json := JSON.stringify(partial)
	var parsed := JSON.new()
	check_equal(parsed.parse(json), OK, "an incomplete session summary is still valid JSON")

	GameState.reset_session()
