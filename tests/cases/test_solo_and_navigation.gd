extends "res://tests/farm_sim_test.gd"
## Single player, Back on the questionnaires, and a way out of every screen.
##
## * Solo: one farmer carrying both roles' tools, no player setup, every
##   questionnaire answered once, and on a phone the two extra tool buttons
##   (Scout, Treat) sitting above the diamond without covering anything.
## * Back: going back to the previous question shows the answer given, a
##   changed answer replaces the old one (each question still counts once), and
##   with feedback on the earlier answer is locked.
## * Every screen has a visible way back or out, and answers Android's back
##   gesture.

const Fixture := preload("res://tests/farm_fixture.gd")
const TOUCH_SCENE := preload("res://scenes/ui/touch_controls.tscn")
const HUD_SCENE := preload("res://scenes/ui/farm_hud.tscn")

const WAYS_OUT := ["back", "exit", "quit", "leave", "menu", "lobby"]


func _init() -> void:
	super()
	is_async = true


func run_async() -> void:
	_check_solo_session_start()
	await _check_solo_farm()
	await _check_solo_phone_buttons()
	await _check_solo_assessment()
	await _check_assessment_back()
	await _check_feedback_back_is_locked()
	await _check_usability_back()
	await _check_exit_dialog()
	await _check_every_screen_has_a_way_out()
	_restore()


func _restore() -> void:
	GameState.reset_session()
	SessionController.pending_assessment = {}
	SessionController.pending_scenario = {}


# -------------------------------------------------------------------- solo --

func _check_solo_session_start() -> void:
	SessionController.start_new_session(true)
	check(GameState.single_player, "Play solo starts a single-player session")
	check_equal(GameState.player_count(), 1, "a solo session has one player")
	check_equal(GameState.role_for_player(0), "solo", "the solo farmer has the combined role")
	check_equal(SessionController.phase, SessionController.Phase.PRE_ASSESSMENT,
		"there are no roles to assign, so solo goes straight to the first knowledge check")
	var tools: Array = Config.ROLE_TOOLS["solo"]
	for role in ["planter", "monitor"]:
		for tool_id in (Config.ROLE_TOOLS[role] as Array):
			check(tool_id in tools, "the solo farmer carries the %s's %s" % [role, Config.tool_label(tool_id)])
	check_equal(String(GameState.to_summary_dictionary().get("mode", "")), "single",
		"the session file says it was a single-player session")


func _check_solo_farm() -> void:
	GameState.reset_session()
	GameState.single_player = true
	GameState.player_roles.assign(["solo", "monitor"])
	var farm := Fixture.make(self, "pest")
	await _frames()
	check_equal(farm.players.size(), 1, "a solo season has one farmer on the field")
	check(farm.get_node_or_null("Player2") == null, "the second farmer is not on the field")
	var me: Node = farm.players[0]
	check_equal((me.tools as Array).size(), 6, "the solo farmer carries all six tools")
	check_equal(me.action_prefix(), "net_", "the solo farmer answers to WASD and the arrow keys")
	check(not farm.hud.player_panels[1].visible, "the HUD shows one player panel")

	var tile: Node2D = farm.field.tile_at(2, 2)
	check(bool(farm.perform_action(me, Config.Tool.HOE, tile)["ok"]), "solo can till")
	check(bool(farm.perform_action(me, Config.Tool.SEED, tile)["ok"]), "solo can sow")
	check(bool(farm.perform_action(me, Config.Tool.WATER, tile)["ok"]), "solo can water")
	check(bool(farm.perform_action(me, Config.Tool.INSPECT, tile)["ok"]), "solo can scout")
	tile.infest(1.0)
	check(bool(farm.perform_action(me, Config.Tool.TREAT, tile)["ok"]), "solo can treat pests")
	var result: Dictionary = farm.build_result("time")
	check_equal((result.get("players", []) as Array).size(), 1, "the season record holds one player")
	var causes := "\n".join(PackedStringArray(result.get("causes", [])))
	check(not causes.contains("Planter") and not causes.contains("Field Monitor"),
		"solo season notes never talk about a partner's role")
	for line in (farm.build_causal_notes({"tiles": [], "players": []}) as Array):
		check(not String(line).contains("Planter"), "an empty solo season says 'till a tile', not 'the Planter'")
	farm.queue_free()
	await _frames()

	# Briefings talk to one player.
	for index in range(3):
		SessionController.pending_scenario = SessionController.scenario_definition(index)
		var briefing: Control = _open(SessionController.SCENE_BRIEFING)
		await _frames()
		var words := ""
		for label in briefing.find_children("*", "Label", true, false):
			words += (label as Label).text + "\n"
		check(not words.contains("Field Monitor's job") and not words.contains("together")
			and not words.contains("shared reserve"),
			"solo briefing %d is written for one player" % (index + 1))
		briefing.queue_free()
		await _frames()

	# The final screen: one score per test, no "P1", no "two players".
	GameState.pre_assessment = {"score": 3, "max_score": 8, "percent": 37.5,
		"players": [{"player": 1, "score": 3, "max_score": 8, "percent": 37.5}]}
	GameState.post_assessment = {"score": 6, "max_score": 8, "percent": 75.0,
		"players": [{"player": 1, "score": 6, "max_score": 8, "percent": 75.0}]}
	GameState.record_scenario_result(result)
	var final_screen: Control = _open(SessionController.SCENE_FINAL_RESULTS)
	await _frames()
	var text := ""
	for label in final_screen.find_children("*", "Label", true, false):
		text += (label as Label).text + "\n"
	check(text.contains("3/8") and text.contains("6/8"), "solo final screen shows the two scores")
	check(not text.contains("P1") and not text.contains("P2"), "solo final screen does not label scores P1/P2")
	check(not text.contains("two players") and not text.contains("both roles"),
		"solo final screen's data note talks about one player")
	final_screen.queue_free()
	await _frames()


func _check_solo_phone_buttons() -> void:
	for size in [Vector2(1280, 720), Vector2(1600, 720), Vector2(1280, 960)]:
		var label := "%dx%d" % [int(size.x), int(size.y)]
		var farm := Fixture.make(self, "pest")
		var hud: CanvasLayer = HUD_SCENE.instantiate()
		add_child(hud)
		hud.set_player(0, "solo", Config.Tool.HOE)
		hud.apply_mobile_layout(-1)
		var root: Control = hud.get_node("HudRoot")
		root.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
		root.size = size
		var controls: CanvasLayer = TOUCH_SCENE.instantiate()
		add_child(controls)
		var canvas: Control = controls.get_node("Canvas")
		canvas.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
		canvas.size = size
		controls.bind(farm.players[0])
		await _frames()

		var rects: Array[Rect2] = controls.covered_rects()
		check_equal(rects.size(), 7, "%s: a joystick and six tool buttons" % label)
		var screen := Rect2(Vector2.ZERO, size)
		var buttons := rects.slice(1)
		for i in range(buttons.size()):
			check(screen.encloses(buttons[i]), "%s: tool button %d is on screen" % [label, i + 1])
			for j in range(i + 1, buttons.size()):
				# Round buttons: they overlap only if their circles do.
				var gap: float = controls.button_centre(i).distance_to(controls.button_centre(j)) \
					- controls.button_radius(i) - controls.button_radius(j)
				check(gap > 0.0, "%s: tool buttons %d and %d do not overlap (%.0f px apart)" % [label, i + 1, j + 1, gap])
		# The two extra buttons sit above the diamond, on the right.
		var top_of_diamond: Vector2 = controls.button_centre(3)
		for slot in [4, 5]:
			var centre: Vector2 = controls.button_centre(slot)
			check(centre.y < top_of_diamond.y, "%s: extra button %d is above the diamond" % [label, slot - 3])
			check(centre.x > size.x * 0.5, "%s: extra button %d is on the right" % [label, slot - 3])
		var pause_rect: Rect2 = (controls.get_node("Canvas/PauseButton") as Control).get_global_rect()
		var top_bar: Rect2 = (hud.top_bar as Control).get_global_rect()
		var water: Rect2 = (hud.water_band as Control).get_global_rect()
		var panel: Rect2 = (hud.player_panels[0] as Control).get_global_rect()
		for slot in [4, 5]:
			var r: Rect2 = rects[1 + slot]
			check(not r.intersects(pause_rect), "%s: extra button %d clears the pause button" % [label, slot - 3])
			check(not r.intersects(top_bar) and not r.intersects(water),
				"%s: extra button %d clears the top bars" % [label, slot - 3])
			check(not r.intersects(panel), "%s: extra button %d clears the player panel" % [label, slot - 3])

		# Tapping Scout (slot 4) picks it up and uses it.
		var used := []
		farm.players[0].use_requested.connect(func(_p: Node, tool_id: int, _t: Node) -> void: used.append(tool_id))
		controls._on_touch(7, controls.button_centre(4), true)
		controls._on_touch(7, controls.button_centre(4), false)
		check_equal(farm.players[0].current_tool(), Config.Tool.INSPECT, "%s: the Scout button picks up the scout tool" % label)
		check_equal(used, [Config.Tool.INSPECT], "%s: and uses it" % label)
		controls._on_touch(7, controls.button_centre(5), true)
		controls._on_touch(7, controls.button_centre(5), false)
		check_equal(farm.players[0].current_tool(), Config.Tool.TREAT, "%s: the Treat button picks up pest treatment" % label)

		controls.queue_free()
		hud.queue_free()
		farm.queue_free()
		await _frames()


func _check_solo_assessment() -> void:
	GameState.reset_session()
	GameState.single_player = true
	GameState.player_roles.assign(["solo", "monitor"])
	SessionController.pending_assessment = {
		"path": SessionController.PRE_ASSESSMENT_PATH, "kind": "pre_assessment",
		"title": "Pre-session knowledge check", "intro": "Answer these before playing.",
		"show_feedback": false,
	}
	var screen: Control = _open(SessionController.SCENE_ASSESSMENT)
	await _frames()
	var count: int = screen._questions.size()
	for _q in range(count):
		screen._on_option_pressed(0)
		screen._on_next_pressed()
	await _frames()
	var players: Array = GameState.pre_assessment.get("players", [])
	check_equal(players.size(), 1, "solo answers the knowledge check once, with no hand-over")
	check_equal(int(GameState.pre_assessment.get("max_score", 0)), count, "the score is out of one player's questions")
	screen.queue_free()
	await _frames()


# -------------------------------------------------------------------- back --

func _open_quiz(feedback: bool) -> Control:
	GameState.reset_session()
	SessionController.pending_assessment = {
		"path": SessionController.PRE_ASSESSMENT_PATH, "kind": "back_check",
		"title": "Knowledge check", "intro": "", "show_feedback": feedback,
	}
	var screen: Control = _open(SessionController.SCENE_ASSESSMENT)
	await _frames()
	return screen


func _check_assessment_back() -> void:
	var screen: Control = await _open_quiz(false)
	var back := screen.find_child("BackButton", true, false) as Button
	check(back != null and back.visible, "the knowledge check has a Back button")
	check(back != null and back.disabled, "Back is off on the first question")
	check(screen.find_child("ExitButton", true, false) != null, "the knowledge check has an Exit button")

	screen._on_option_pressed(0)
	screen._on_next_pressed()
	check_equal(screen._index, 1, "Next moves to question 2")
	check(back != null and not back.disabled, "Back is on from question 2")
	back.pressed.emit()
	check_equal(screen._index, 0, "Back returns to question 1")
	check_equal(screen._selected, 0, "the answer given is shown again")
	screen._on_option_pressed(1)
	screen._on_next_pressed()
	check_equal(screen._answers.size(), 1, "changing an answer replaces it - the question still counts once")
	check_equal(int(screen._answers[0]["selected_index"]), 1, "the new answer is the one kept")
	var changed := false
	for event in GameplayLogger.events:
		if String(event.get("action", "")) == "answer_changed":
			changed = true
	check(changed, "the change is in the research log")
	screen.queue_free()
	await _frames()


func _check_feedback_back_is_locked() -> void:
	var screen: Control = await _open_quiz(true)
	screen._on_option_pressed(2)
	screen._on_next_pressed()
	screen.go_back()
	check_equal(screen._index, 0, "with feedback on, Back still returns to the previous question")
	var options: Array = screen._option_buttons
	var all_locked := true
	for option in options:
		if option.visible and not option.disabled:
			all_locked = false
	check(all_locked, "but the answer cannot be changed after the right one was shown")
	screen.queue_free()
	await _frames()


func _check_usability_back() -> void:
	GameState.reset_session()
	GameState.single_player = true
	var screen: Control = _open(SessionController.SCENE_USABILITY)
	await _frames()
	var back := screen.find_child("BackButton", true, false) as Button
	check(back != null, "the questionnaire has a Back button")
	check(screen.find_child("ExitButton", true, false) != null, "the questionnaire has an Exit button")
	screen._on_choice_pressed(0)
	check_equal(screen._index, 1, "answering moves to the next statement")
	back.pressed.emit()
	check_equal(screen._index, 0, "Back returns to the previous statement")
	check(screen._current_answers.is_empty(), "and takes that answer back so it can be given again")
	screen.queue_free()
	await _frames()


# -------------------------------------------------------------------- exit --

func _check_exit_dialog() -> void:
	GameState.reset_session()
	SessionController.request_exit()
	check(SessionController.exit_dialog_open(), "Exit asks first")
	var stay := SessionController._exit_dialog.find_child("StayButton", true, false) as Button
	check(stay != null and SessionController._exit_dialog.find_child("LeaveButton", true, false) != null,
		"it offers Keep going and Leave")
	if stay != null:
		stay.pressed.emit()
	check(not SessionController.exit_dialog_open(), "Keep going closes the question")

	var before := GameplayLogger.events.size()
	SessionController.leave_session()
	var left_clean := false
	for index in range(before, GameplayLogger.events.size()):
		if String(GameplayLogger.events[index].get("action", "")) == "session_left_before_start":
			left_clean = true
	check(left_clean, "leaving before anything is recorded writes no partial file")


# ------------------------------------------------------- every screen, out --

func _check_every_screen_has_a_way_out() -> void:
	GameState.reset_session()
	var farm_for_results := Fixture.make(self, "baseline")
	Fixture.play_season(farm_for_results, 8)
	SessionController.pending_results = farm_for_results.build_result("time")
	farm_for_results.queue_free()
	SessionController.pending_scenario = SessionController.scenario_definition(0)
	SessionController.pending_assessment = {
		"path": SessionController.PRE_ASSESSMENT_PATH, "kind": "way_out", "title": "Check",
		"intro": "", "show_feedback": false,
	}
	var screens := [
		["main menu", "res://scenes/ui/main_menu.tscn"],
		["play together", "res://scenes/ui/multiplayer_menu.tscn"],
		["how to play", "res://scenes/ui/instructions.tscn"],
		["player setup", "res://scenes/ui/player_setup.tscn"],
		["knowledge check", SessionController.SCENE_ASSESSMENT],
		["scenario briefing", SessionController.SCENE_BRIEFING],
		["season results", SessionController.SCENE_SCENARIO_RESULTS],
		["questionnaire", SessionController.SCENE_USABILITY],
		["final results", SessionController.SCENE_FINAL_RESULTS],
	]
	for entry in screens:
		var screen: Control = _open(String(entry[1]))
		await _frames()
		var way_out := _button_matching(screen, WAYS_OUT)
		check(way_out != null and way_out.is_visible_in_tree() and not way_out.disabled,
			"%s: has a visible way back or out (%s)" % [entry[0], way_out.text if way_out != null else "none"])
		check(screen.has_method("_on_back_pressed"),
			"%s: answers Android's back gesture" % entry[0])
		screen.queue_free()
		await _frames()

	var farm := Fixture.make(self, "baseline")
	var overlay: Node = farm.pause_overlay
	check(overlay != null and overlay.has_method("toggle"), "the farm can be paused (Esc, the II button, or back)")
	overlay.set_paused(true)
	var abandon := _button_matching(overlay, ["abandon"])
	check(abandon != null, "and its pause screen offers a way out")
	overlay.set_paused(false)
	farm.queue_free()
	await _frames()


# ------------------------------------------------------------------ helpers --

func _open(path: String) -> Control:
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var screen: Control = packed.instantiate()
	add_child(screen)
	return screen


func _button_matching(node: Node, words: Array) -> Button:
	for button in _buttons(node):
		if not button.is_visible_in_tree() or button.disabled:
			continue
		var text := button.text.to_lower()
		for word in words:
			if text.contains(String(word)):
				return button
	return null


func _buttons(node: Node) -> Array[Button]:
	var found: Array[Button] = []
	if node is Button:
		found.append(node)
	for child in node.get_children():
		found.append_array(_buttons(child))
	return found


func _frames(count: int = 4) -> void:
	for _index in range(count):
		await get_tree().process_frame
