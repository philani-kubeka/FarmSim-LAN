extends "res://tests/farm_sim_test.gd"
## The whole thing, end to end, through the real screens.
##
## Nothing here is a stand-in. The pre-test is answered by pressing the buttons
## on the real assessment screen, loaded from the real instrument. Each briefing
## is opened and its start button pressed. Each season is played on the real farm
## with a scripted strategy until it ends on its own. Each results screen and
## quiz is driven the same way. What comes out is a genuine session file, which
## is then read back and checked against what actually happened.
##
## What it still cannot do is press keys as two people at one keyboard. Walking,
## aiming and timing remain a manual check.

const Fixture := preload("res://tests/farm_fixture.gd")

## How many tiles the scripted planter commits to in each season.
const SPREAD := {"baseline": 10, "drought": 2, "pest": 10}

## A copy of the produced session file is left here for inspection. test_out/ is
## ignored by git and is not where study data is collected.
const SAMPLE_COPY := "res://test_out/sample_session.json"

var _session_id := ""


func _init() -> void:
	super()
	is_async = true


func run_async() -> void:
	GameplayLogger.clear()
	SessionController.start_new_session()
	_session_id = GameState.session_id
	check_equal(SessionController.phase, SessionController.Phase.PLAYER_SETUP,
		"a new session starts at player setup")

	# --- pre-test, answered on the real screen ---
	SessionController.begin_pre_assessment()
	# Each player answers on their own: P1 gets 3 right, P2 gets 5 right.
	await _drive_assessment(SessionController.PRE_ASSESSMENT_PATH, [3, 5])
	check_equal(int(GameState.player_assessment(GameState.pre_assessment, 0).get("score", -1)), 3,
		"player 1's pre-test scored their three deliberately correct answers")
	check_equal(int(GameState.player_assessment(GameState.pre_assessment, 1).get("score", -1)), 5,
		"player 2's pre-test is scored separately")
	check_equal(int(GameState.player_assessment(GameState.pre_assessment, 0).get("max_score", -1)), 8,
		"each player's pre-test was marked out of its eight items")
	check_equal(int(GameState.pre_assessment.get("score", -1)), 8,
		"the combined pre-test score is the sum of both players")

	# --- three seasons ---
	var expected := ["baseline", "pest", "drought"]
	for index in range(3):
		check_equal(SessionController.phase, SessionController.Phase.SCENARIO_BRIEFING,
			"season %d opens with a briefing" % (index + 1))
		await _drive_briefing(expected[index])

		check_equal(SessionController.phase, SessionController.Phase.SCENARIO,
			"pressing through the briefing starts season %d" % (index + 1))
		await _play_season(expected[index], index == 0)

		check_equal(SessionController.phase, SessionController.Phase.SCENARIO_RESULTS,
			"the season hands its result to the results screen")
		await _drive_results(index)

		check_equal(SessionController.phase, SessionController.Phase.SCENARIO_QUIZ,
			"the results screen leads into the season's quiz")
		var quiz_path := String(SessionController.pending_assessment.get("path", ""))
		await _drive_assessment(quiz_path, [2, 1])
		check_equal(GameState.scenario_quizzes.size(), index + 1,
			"the quiz for season %d was recorded" % (index + 1))
		var quiz: Dictionary = GameState.scenario_quizzes[GameState.scenario_quizzes.size() - 1]
		check_equal((quiz.get("players", []) as Array).size(), 2,
			"both players answered the season %d quiz individually" % (index + 1))

	# --- post-test ---
	check_equal(SessionController.phase, SessionController.Phase.POST_ASSESSMENT,
		"after the third quiz the session moves to the post-test")
	await _drive_assessment(SessionController.POST_ASSESSMENT_PATH, [7, 8])
	check_equal(int(GameState.player_assessment(GameState.post_assessment, 0).get("score", -1)), 7,
		"player 1's post-test scored their seven deliberately correct answers")
	check_equal(int(GameState.player_assessment(GameState.post_assessment, 1).get("score", -1)), 8,
		"player 2's post-test is scored separately")
	check_equal(SessionController.phase, SessionController.Phase.USABILITY,
		"after the post-test each player answers the usability questions")
	await _drive_usability()
	check_equal(SessionController.phase, SessionController.Phase.FINAL_RESULTS,
		"the session ends on the final results screen")
	check_near(GameState.knowledge_gain_for_player(0), 50.0, 0.2,
		"player 1's change is +50 points (3/8 to 7/8)")
	check_near(GameState.knowledge_gain_for_player(1), 37.5, 0.2,
		"player 2's change is +37.5 points (5/8 to 8/8)")
	check_near(GameState.knowledge_gain_percent(), 43.75, 0.2,
		"the pair's change is the mean of the two players")

	await _check_final_screen()
	_check_session_file()

	GameState.reset_session()


# ------------------------------------------------------------------ steps ---

func _drive_briefing(scenario_id: String) -> void:
	var screen := _open(SessionController.SCENE_BRIEFING)
	if screen == null:
		return
	await _frames(2)

	var text := _all_text(screen)
	var definition := SessionController.pending_scenario
	check_equal(String(definition.get("id", "")), scenario_id,
		"the briefing is for the %s season" % scenario_id)
	check(text.contains(String(definition.get("title", ""))), "the briefing shows the season title")
	check(text.contains(String(definition.get("briefing", "")).left(40)),
		"the briefing shows the scenario's own briefing text")
	check(text.contains("Planter / Irrigator") and text.contains("Field Monitor"),
		"the briefing names both roles before play starts")
	for objective in (definition.get("objectives", []) as Array):
		check(text.contains(String(objective)),
			"the briefing lists the objective: %s" % String(objective).left(40))

	var start := _button_matching(screen, ["start"])
	check_not_null(start, "the briefing has a start button")
	if start != null:
		start.pressed.emit()
	screen.queue_free()
	await _frames(1)


func _play_season(scenario_id: String, exercise_pause: bool) -> void:
	var farm := _open_farm()
	if farm == null:
		return
	await _frames(2)

	check_equal(String(farm.definition.get("id", "")), scenario_id,
		"the farm builds the %s season the controller selected" % scenario_id)
	check_not_null(farm.pause_overlay, "the farm has a pause overlay")

	if exercise_pause and farm.pause_overlay != null:
		await _exercise_pause(farm)

	Fixture.play_season(farm, int(SPREAD.get(scenario_id, 10)))
	check(not farm.running, "the %s season ends on its own" % scenario_id)
	farm.queue_free()
	await _frames(1)


func _exercise_pause(farm: Node2D) -> void:
	var overlay: CanvasLayer = farm.pause_overlay
	check_equal(overlay.process_mode, Node.PROCESS_MODE_ALWAYS,
		"the pause overlay keeps running while the tree is frozen")
	check(not overlay.is_paused, "the season does not start paused")

	overlay.set_paused(true)
	await _frames(2)
	check(overlay.is_paused, "the overlay reports itself as paused")
	check(get_tree().paused, "pausing actually freezes the scene tree")

	var paused_text := _all_text(overlay)
	check(paused_text.contains("Paused"), "the pause screen says it is paused")
	check(paused_text.contains("Planter / Irrigator") and paused_text.contains("Field Monitor"),
		"the pause screen reminds both players of their roles")
	check(paused_text.contains("Hoe") or paused_text.contains("Scout"),
		"the pause screen lists the tools each role carries")
	check_not_null(_button_matching(overlay, ["resume"]), "the pause screen can be dismissed")
	check_not_null(_button_matching(overlay, ["abandon", "menu"]),
		"the pause screen offers a way out of the session")

	overlay.set_paused(false)
	await _frames(2)
	check(not overlay.is_paused, "resuming clears the pause")
	check(not get_tree().paused, "resuming unfreezes the scene tree")

	var actions := _logged_actions()
	check("paused" in actions, "pausing is recorded in the research data")
	check("resumed" in actions, "resuming is recorded in the research data")


func _drive_results(index: int) -> void:
	var screen := _open(SessionController.SCENE_SCENARIO_RESULTS)
	if screen == null:
		return
	await _frames(2)

	var result: Dictionary = SessionController.pending_results
	var text := _all_text(screen)
	check(text.contains("Harvest"), "the results screen shows the harvest for season %d" % (index + 1))
	var causes: Array = result.get("causes", [])
	check_greater(causes.size(), 2, "season %d produced several explanations" % (index + 1))
	var shown := 0
	for note in causes:
		if text.contains(String(note)):
			shown += 1
	check_equal(shown, causes.size(),
		"season %d shows every explanation it generated (%d of %d)"
			% [index + 1, shown, causes.size()])

	var button := _button_matching(screen, ["continue"])
	check_not_null(button, "the results screen leads onwards")
	if button != null:
		button.pressed.emit()
	screen.queue_free()
	await _frames(1)


func _check_final_screen() -> void:
	var screen := _open(SessionController.SCENE_FINAL_RESULTS)
	if screen == null:
		return
	await _frames(2)
	var text := _all_text(screen)
	check(text.contains("Session complete"), "the final screen closes the session")
	check(text.contains(_session_id), "the final screen shows the anonymous session id")
	check(text.contains("P1 · 3/8") and text.contains("P2 · 5/8"),
		"the final screen shows each player's pre-test score")
	check(text.contains("P1 · 7/8") and text.contains("P2 · 8/8"),
		"the final screen shows each player's post-test score")
	check(text.contains("P1 · +50"), "the final screen shows each player's change between the two tests")
	for title in ["Baseline season", "Drought season", "Pest outbreak"]:
		check(text.contains(title), "the final screen lists the %s" % title)
	screen.queue_free()
	await _frames(1)


# ------------------------------------------------------------- the record ---

func _check_session_file() -> void:
	var path := GameplayLogger.output_directory().path_join("session_%s.json" % _session_id)
	check(FileAccess.file_exists(path), "a complete session writes its research file")
	if not FileAccess.file_exists(path):
		return

	var raw := FileAccess.get_file_as_string(path)
	var parser := JSON.new()
	check_equal(parser.parse(raw), OK, "the session file is valid JSON")
	if typeof(parser.data) != TYPE_DICTIONARY:
		fail("the session file parses to an object")
		return
	var doc := parser.data as Dictionary

	# --- the session ---
	check_equal(String(doc.get("session_id", "")), _session_id,
		"the file belongs to this session")
	var pre_players: Array = (doc.get("pre_assessment", {}) as Dictionary).get("players", [])
	var post_players: Array = (doc.get("post_assessment", {}) as Dictionary).get("players", [])
	check_equal(pre_players.size(), 2, "the file holds both players' pre-tests")
	check_equal(post_players.size(), 2, "the file holds both players' post-tests")
	if pre_players.size() == 2 and post_players.size() == 2:
		check_equal(int((pre_players[0] as Dictionary).get("score", -1)), 3,
			"player 1's pre-test score in the file is the one that was actually scored")
		check_equal(int((post_players[1] as Dictionary).get("score", -1)), 8,
			"player 2's post-test score in the file is the one that was actually scored")
	var by_player := doc.get("knowledge_gain_by_player", {}) as Dictionary
	check_near(float(by_player.get("player_1", 0.0)), 50.0, 0.2,
		"the file records player 1's own knowledge change")
	check_equal(((doc.get("usability", {}) as Dictionary).get("responses", []) as Array).size(), 2,
		"the session file holds both players' usability answers")
	check_near(float(doc.get("knowledge_gain_percent", 0.0)), 43.75, 0.2,
		"the file records the knowledge change")

	# --- the seasons ---
	var scenarios: Array = doc.get("scenarios", [])
	check_equal(scenarios.size(), 3, "all three seasons are in the file")
	var expected := ["baseline", "pest", "drought"]
	var total_yield := 0.0
	for index in range(mini(scenarios.size(), 3)):
		var season := scenarios[index] as Dictionary
		check_equal(String(season.get("scenario_id", "")), expected[index],
			"season %d in the file is the %s season" % [index + 1, expected[index]])
		check_equal(int(season.get("scenario_index", -1)), index + 1,
			"season %d is numbered correctly" % (index + 1))
		check_greater(int(season.get("tiles_sown", 0)), 0,
			"season %d records tiles that were actually sown" % (index + 1))
		check_greater((season.get("tiles", []) as Array).size(), 0,
			"season %d records the individual tiles that were worked" % (index + 1))
		check_greater((season.get("causes", []) as Array).size(), 2,
			"season %d records its causal explanations" % (index + 1))
		check((season.get("water", {}) as Dictionary).has("used_litres"),
			"season %d records what the shared reserve cost" % (index + 1))
		total_yield += float(season.get("total_yield", 0.0))

	check_near(float(doc.get("total_yield", -1.0)), total_yield, 0.05,
		"the session total matches the sum of the three seasons")
	check_greater(total_yield, 0.0, "the scripted session actually harvested something")

	# The drought season is the one the design says should be hardest.
	if scenarios.size() == 3:
		var baseline_yield := float((scenarios[0] as Dictionary).get("total_yield", 0.0))
		var drought_yield := float((scenarios[2] as Dictionary).get("total_yield", 0.0))
		check(drought_yield <= baseline_yield,
			"the drought season did not out-yield the settled season (%.1f vs %.1f)"
				% [drought_yield, baseline_yield])
		check(bool(((scenarios[2] as Dictionary).get("event", {}) as Dictionary)
			.get("triggered", false)), "the drought event is recorded as having fired")
		check(bool(((scenarios[1] as Dictionary).get("event", {}) as Dictionary)
			.get("triggered", false)), "the pest outbreak is recorded as having fired")

	# --- the quizzes ---
	check_equal((doc.get("scenario_quizzes", []) as Array).size(), 3,
		"all three quizzes are in the file")

	# --- the event log ---
	var events: Array = doc.get("events", [])
	check_greater(events.size(), 100,
		"the event log holds the session's actions (%d events)" % events.size())
	var actions: Array[String] = []
	var categories: Array[String] = []
	for entry in events:
		actions.append(String((entry as Dictionary).get("action", "")))
		categories.append(String((entry as Dictionary).get("category", "")))
	for required in ["session_started", "roles_confirmed", "scenario_started",
			"scenario_completed", "assessment_completed", "question_answered",
			"season_started", "season_finished", "paused", "resumed", "session_completed"]:
		check(required in actions, "the log records '%s'" % required)
	check_equal(actions.count("scenario_started"), 3, "the log records three seasons starting")
	check_equal(actions.count("scenario_completed"), 3, "the log records three seasons completing")
	check_equal(actions.count("assessment_completed"), 5,
		"the log records five instruments: pre-test, three quizzes and the post-test")
	for category in ["session", "scenario", "gameplay", "assessment"]:
		check(category in categories, "the log contains '%s' events" % category)

	# Gameplay actions have to be attributed to a player and a role.
	var attributed := 0
	for entry in events:
		var event := entry as Dictionary
		if String(event.get("category", "")) != "gameplay":
			continue
		if event.has("player") and event.has("role"):
			attributed += 1
	check_greater(attributed, 50,
		"gameplay events are attributed to a player and a role (%d of them)" % attributed)

	# --- no personal data ---
	var lowered := raw.to_lower()
	for forbidden in ["\"name\"", "\"email\"", "\"surname\"", "\"password\"", "\"username\""]:
		check(not lowered.contains(forbidden),
			"the session file contains no %s field" % forbidden.replace("\"", ""))

	# Keep a copy where it can be inspected, and take the synthetic run out of
	# the directory where real study data is collected.
	DirAccess.make_dir_recursive_absolute("res://test_out")
	var copy := FileAccess.open(SAMPLE_COPY, FileAccess.WRITE)
	if copy != null:
		copy.store_string(raw)
		copy.close()
		check(FileAccess.file_exists(SAMPLE_COPY),
			"a sample of the produced file is left in test_out for inspection")
	DirAccess.remove_absolute(path)
	check(not FileAccess.file_exists(path),
		"the synthetic session is not left among the study data")


# ----------------------------------------------------------------- driving --

## Answers a knowledge instrument by pressing the buttons on the real screen,
## once per player with a hand-over in between. For each player the first
## `correct_counts[player]` questions are answered correctly and the rest
## deliberately wrongly, so each player's score is known in advance.
func _drive_assessment(instrument_path: String, correct_counts: Array) -> void:
	var questions := _questions_in(instrument_path)
	check_greater(questions.size(), 0, "instrument has questions: %s" % instrument_path)
	if questions.is_empty():
		return

	var screen := _open(SessionController.SCENE_ASSESSMENT)
	if screen == null:
		return
	await _frames(2)

	for player in range(correct_counts.size()):
		var correct_count := int(correct_counts[player])
		if player > 0:
			var handover := _button_matching(screen, ["continue"])
			var panel := screen.find_child("Question", true, false) as Control
			check(handover != null and panel != null and not panel.visible,
				"player %d gets a hand-over step with the questions hidden" % (player + 1))
			if handover == null:
				break
			handover.pressed.emit()
			await _frames(1)
		await _answer_all(screen, questions, correct_count)

	screen.queue_free()
	await _frames(1)


func _answer_all(screen: Control, questions: Array, correct_count: int) -> void:
	for index in range(questions.size()):
		var question := questions[index] as Dictionary
		var options := _option_buttons(screen)
		check_equal(options.size(), (question.get("options", []) as Array).size(),
			"question %d shows all of its options" % (index + 1))
		if options.is_empty():
			break

		var correct_index := int(question.get("correct_index", 0))
		var choice := correct_index
		if index >= correct_count:
			choice = (correct_index + 1) % options.size()
		options[choice].pressed.emit()
		await _frames(1)

		var next := _button_matching(screen, ["next", "finish", "continue"])
		if next == null:
			fail("question %d has a way to move on" % (index + 1))
			break
		next.pressed.emit()
		await _frames(1)


## Answers the usability questionnaire as both players: Player 1 says "Yes" to
## everything, Player 2 says "No", so the stored result is known in advance.
func _drive_usability() -> void:
	var screen := _open(SessionController.SCENE_USABILITY)
	if screen == null:
		return
	await _frames(2)
	var content := "Page/PageScroll/Row/PageContent"
	for player in range(2):
		var pick := "Answers/YesButton" if player == 0 else "Answers/NoButton"
		for _i in range(5):
			var b := screen.get_node_or_null(content + "/" + pick) as Button
			if b == null or not b.visible:
				fail("player %d can answer every usability question" % (player + 1))
				break
			b.pressed.emit()
			await _frames(1)
		var handover := screen.get_node_or_null(content + "/HandoverButton") as Button
		check(handover != null and handover.visible,
			"player %d finishing leads onwards" % (player + 1))
		if handover != null:
			handover.pressed.emit()
			await _frames(1)
	var responses: Array = GameState.usability.get("responses", [])
	check_equal(responses.size(), 2, "both players' usability answers were recorded")
	if responses.size() == 2:
		var first: Array = (responses[0] as Dictionary).get("answers", [])
		var second: Array = (responses[1] as Dictionary).get("answers", [])
		check_equal(first.size(), 5, "player 1 answered all five statements")
		check_equal(String((first[0] as Dictionary).get("answer", "")), "yes",
			"player 1's answers are stored as given")
		check_equal(String((second[0] as Dictionary).get("answer", "")), "no",
			"player 2's answers are stored separately")
	screen.queue_free()
	await _frames(1)


func _questions_in(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return []
	if typeof(parser.data) != TYPE_DICTIONARY:
		return []
	var questions: Variant = (parser.data as Dictionary).get("questions", [])
	if typeof(questions) != TYPE_ARRAY:
		return []
	return questions as Array


# ------------------------------------------------------------------ tools ---

func _open(path: String) -> Control:
	var packed: Variant = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if packed == null:
		fail("screen loads: %s" % path)
		return null
	var screen: Control = (packed as PackedScene).instantiate()
	if screen == null:
		fail("screen instantiates: %s" % path)
		return null
	add_child(screen)
	return screen


func _open_farm() -> Node2D:
	var packed: Variant = ResourceLoader.load(SessionController.SCENE_FARM, "PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE)
	if packed == null:
		fail("the farm scene loads")
		return null
	var farm: Node2D = (packed as PackedScene).instantiate()
	add_child(farm)
	return farm


func _option_buttons(node: Node) -> Array[Button]:
	var found: Array[Button] = []
	for button in _buttons(node):
		if not button.visible:
			continue
		# The assessment screen labels its options "A.  ...", "B.  ..." and so on.
		if button.text.length() > 1 and button.text[1] == ".":
			found.append(button)
	return found


func _button_matching(node: Node, words: Array) -> Button:
	for button in _buttons(node):
		var text := button.text.to_lower()
		if text.length() > 1 and text[1] == ".":
			continue
		for word in words:
			if text.contains(String(word)):
				return button
	return null


func _buttons(node: Node) -> Array[Button]:
	var found: Array[Button] = []
	_collect_buttons(node, found)
	return found


func _collect_buttons(node: Node, found: Array[Button]) -> void:
	var button := node as Button
	if button != null:
		found.append(button)
	for child in node.get_children():
		_collect_buttons(child, found)


func _all_text(node: Node) -> String:
	var parts: Array[String] = []
	_collect_text(node, parts)
	return "\n".join(parts)


func _collect_text(node: Node, parts: Array[String]) -> void:
	var label := node as Label
	if label != null and not label.text.is_empty():
		parts.append(label.text)
	var button := node as Button
	if button != null and not button.text.is_empty():
		parts.append(button.text)
	for child in node.get_children():
		_collect_text(child, parts)


func _logged_actions() -> Array[String]:
	var actions: Array[String] = []
	for event in GameplayLogger.events:
		actions.append(String(event.get("action", "")))
	return actions


func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame
