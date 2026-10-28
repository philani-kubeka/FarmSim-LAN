extends Node
## Drives the whole research session: which screen is showing, which scenario is
## next, and what happens when each stage finishes.
##
## Gameplay code (players, crops, water) knows nothing about session flow, and
## this controller knows nothing about how a crop grows. That separation keeps
## the farming simulation reusable across all three scenarios.

signal phase_changed(phase: int)

enum Phase {
	BOOT,
	MAIN_MENU,
	INSTRUCTIONS,
	PLAYER_SETUP,
	PRE_ASSESSMENT,
	SCENARIO_BRIEFING,
	SCENARIO,
	SCENARIO_RESULTS,
	SCENARIO_QUIZ,
	POST_ASSESSMENT,
	FINAL_RESULTS,
	USABILITY,
}

const SCENE_MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const SCENE_PLAYER_SETUP := "res://scenes/ui/player_setup.tscn"
const SCENE_INSTRUCTIONS := "res://scenes/ui/instructions.tscn"
const SCENE_ASSESSMENT := "res://scenes/ui/assessment_screen.tscn"
const SCENE_BRIEFING := "res://scenes/ui/scenario_briefing.tscn"
const SCENE_SCENARIO_RESULTS := "res://scenes/ui/scenario_results.tscn"
const SCENE_FINAL_RESULTS := "res://scenes/ui/final_results.tscn"
const SCENE_FARM := "res://scenes/farm/farm.tscn"
const SCENE_USABILITY := "res://scenes/ui/usability_screen.tscn"
const SCENE_MULTIPLAYER := "res://scenes/ui/multiplayer_menu.tscn"

const SCENARIOS_DATA_PATH := "res://data/scenarios.json"
const PRE_ASSESSMENT_PATH := "res://data/assessments/pre_assessment.json"
const POST_ASSESSMENT_PATH := "res://data/assessments/post_assessment.json"
const USABILITY_PATH := "res://data/assessments/usability.json"

var phase: int = Phase.BOOT

## Loaded scenario definitions, in play order.
var scenarios: Array[Dictionary] = []

## Handover payloads for the screen that is about to load. Set immediately
## before change_scene_to_file() and read by that screen in _ready().
var pending_assessment := {}
var pending_results := {}
var pending_scenario := {}

## Where the previous screen came from, so Instructions can return correctly.
var _instructions_return_scene := SCENE_MAIN_MENU


## A message for the next menu to show, e.g. why a LAN session ended.
var notice := ""

## Client, after a reconnect into the middle of a season: where its player was
## standing and what both players were holding. The farm reads it once.
var farm_resume := {}

const ReconnectOverlay := preload("res://scripts/ui/reconnect_overlay.gd")
var _reconnect_overlay: CanvasLayer = null


func _ready() -> void:
	scenarios = load_scenarios()
	Net.session_lost.connect(_on_session_lost)
	Net.partner_lost.connect(_on_partner_lost)
	Net.partner_back.connect(_on_partner_back)


# ------------------------------------------------------------------- data ----

func load_scenarios() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var parsed: Variant = _read_json(SCENARIOS_DATA_PATH)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SessionController: scenarios.json missing or malformed")
		return out
	var list: Variant = (parsed as Dictionary).get("scenarios", [])
	if typeof(list) != TYPE_ARRAY:
		push_error("SessionController: scenarios.json has no scenarios array")
		return out
	for entry in (list as Array):
		if typeof(entry) == TYPE_DICTIONARY:
			out.append(entry as Dictionary)
	return out


func scenario_definition(index: int) -> Dictionary:
	if index < 0 or index >= scenarios.size():
		return {}
	return scenarios[index]


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("SessionController: JSON parse error in %s at line %d: %s"
			% [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


# ------------------------------------------------------------------ flow ----

func _set_phase(new_phase: int) -> void:
	phase = new_phase
	phase_changed.emit(new_phase)


## `broadcast`: in a LAN session the host's screen changes are mirrored on the
## client, together with a copy of the session state. Instructions are the one
## screen each player opens on their own, so they pass false.
func _change_scene(path: String, broadcast: bool = true) -> void:
	# In headless test mode the caller drives scenes directly; changing them
	# would fight the test harness.
	if Config.headless_test_mode:
		return
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("SessionController: failed to change to %s (error %d)" % [path, err])
		return
	if broadcast and Net.is_host():
		Net.send_scene(path, network_state())
	# Keep a running backup of the research data while a session is under way.
	# The client never writes session files - the host owns the data.
	if not Net.is_client() and phase != Phase.MAIN_MENU and phase != Phase.FINAL_RESULTS \
			and not GameState.session_id.is_empty():
		GameplayLogger.write_autosave()


# -------------------------------------------------------------- LAN sync ----

## Everything the client needs to draw the next screen the same way the host
## does. Sent with every screen change, so the client never has to work any of
## it out for itself.
func network_state() -> Dictionary:
	return {
		"phase": phase,
		"pending_assessment": pending_assessment,
		"pending_results": pending_results,
		"pending_scenario": pending_scenario,
		"session_id": GameState.session_id,
		"session_started_unix": GameState.session_started_unix,
		"player_roles": Array(GameState.player_roles),
		"single_player": GameState.single_player,
		"current_scenario_index": GameState.current_scenario_index,
		"pre_assessment": GameState.pre_assessment,
		"post_assessment": GameState.post_assessment,
		"scenario_results": Array(GameState.scenario_results),
		"scenario_quizzes": Array(GameState.scenario_quizzes),
		"usability": GameState.usability,
		"output_directory": GameplayLogger.output_directory(),
		"farm_resume": _farm_resume_state(),
	}


## Client side of network_state().
func apply_network_state(state: Dictionary) -> void:
	phase = int(state.get("phase", phase))
	pending_assessment = state.get("pending_assessment", {})
	pending_results = state.get("pending_results", {})
	pending_scenario = state.get("pending_scenario", {})
	GameState.session_id = String(state.get("session_id", GameState.session_id))
	GameState.session_started_unix = int(state.get("session_started_unix", 0))
	GameState.player_roles.assign(state.get("player_roles", ["planter", "monitor"]))
	GameState.single_player = bool(state.get("single_player", false))
	GameState.current_scenario_index = int(state.get("current_scenario_index", 0))
	GameState.pre_assessment = state.get("pre_assessment", {})
	GameState.post_assessment = state.get("post_assessment", {})
	GameState.scenario_results.assign(state.get("scenario_results", []))
	GameState.scenario_quizzes.assign(state.get("scenario_quizzes", []))
	GameState.usability = state.get("usability", {})
	host_output_directory = String(state.get("output_directory", ""))
	farm_resume = state.get("farm_resume", {})
	phase_changed.emit(phase)


## The farm's players, if a season is being played, so a player who reconnects
## lands where they were rather than back at the gate.
func _farm_resume_state() -> Dictionary:
	var scene := get_tree().current_scene if is_inside_tree() else null
	if scene == null or not scene.has_method("resume_state"):
		return {}
	return scene.resume_state()


# ------------------------------------------------------------ reconnecting ---

## The other player dropped mid-session (host), or this device lost the host
## (client). Freeze the game behind a waiting screen; nothing is ended.
func _on_partner_lost(reason: String) -> void:
	if Net.is_host() or Net.waiting_for_partner:
		GameplayLogger.log_event("session", "player_2_disconnected", {
			"reason": reason,
			"phase": phase,
			"scenario_index": GameState.current_scenario_index + 1,
		})
	_show_reconnect_overlay(reason)


func _on_partner_back() -> void:
	_hide_reconnect_overlay()
	if Net.is_host():
		# Put the returning player exactly where the pair is: the current screen,
		# with the whole session state.
		var scene := get_tree().current_scene
		if scene != null and not scene.scene_file_path.is_empty():
			Net.send_scene(scene.scene_file_path, network_state())


## Host gives up waiting: save what was recorded and go back to the lobby, still
## hosting, exactly as a disconnect used to.
func give_up_waiting() -> void:
	_hide_reconnect_overlay()
	Net.waiting_for_partner = false
	Net.in_session = false
	GameplayLogger.log_event("session", "session_ended_disconnect", {
		"reason": "Host stopped waiting for Player 2",
		"seconds_waited": snappedf(Net.seconds_lost(), 0.1),
	})
	if not GameState.scenario_results.is_empty() or not GameState.pre_assessment.is_empty():
		GameplayLogger.write_session_file("_partial")
	notice = "Player 2 disconnected and did not come back. What was recorded has been saved."
	_set_phase(Phase.MAIN_MENU)
	_change_scene(SCENE_MULTIPLAYER, false)


## Client: the host ended (or restarted) the session while this device was away.
## Land in the host's lobby, still connected, ready for the next session.
func session_over_while_away() -> void:
	_hide_reconnect_overlay()
	notice = "The host ended the session while you were away. You are back in their lobby."
	_set_phase(Phase.MAIN_MENU)
	_change_scene(SCENE_MULTIPLAYER, false)


## Client gives up reconnecting.
func give_up_reconnecting() -> void:
	_hide_reconnect_overlay()
	Net.leave()
	notice = "You left the session."
	_set_phase(Phase.MAIN_MENU)
	_change_scene(SCENE_MAIN_MENU, false)


func _show_reconnect_overlay(reason: String) -> void:
	if _reconnect_overlay == null or not is_instance_valid(_reconnect_overlay):
		_reconnect_overlay = ReconnectOverlay.new()
		get_tree().root.add_child(_reconnect_overlay)
	_reconnect_overlay.open(reason, Net.is_host() or Net.waiting_for_partner)


func _hide_reconnect_overlay() -> void:
	if _reconnect_overlay != null and is_instance_valid(_reconnect_overlay):
		_reconnect_overlay.close()


# ------------------------------------------------------------ leaving early --

const ExitDialog := preload("res://scripts/ui/exit_dialog.gd")
var _exit_dialog: CanvasLayer = null


## Every in-session screen's Exit button (and Android's back gesture when there
## is nothing left to go back to) asks first.
func request_exit() -> void:
	if _exit_dialog == null or not is_instance_valid(_exit_dialog):
		_exit_dialog = ExitDialog.new()
		get_tree().root.add_child(_exit_dialog)
	_exit_dialog.open()


func exit_dialog_open() -> bool:
	return _exit_dialog != null and is_instance_valid(_exit_dialog) and _exit_dialog.is_open()


func _hide_exit_dialog() -> void:
	if _exit_dialog != null and is_instance_valid(_exit_dialog):
		_exit_dialog.close()


## The player confirmed: end the session now and keep what was recorded. Same
## as Abandon on the pause screen (in a LAN game it ends it for both devices).
func leave_session() -> void:
	_hide_exit_dialog()
	if Net.is_client():
		Net.request_abandon()
		return
	if GameState.pre_assessment.is_empty() and GameState.scenario_results.is_empty():
		# Nothing recorded yet (still choosing roles, or on the first test):
		# no partial file is worth writing.
		GameplayLogger.log_event("session", "session_left_before_start", {})
		GameplayLogger.discard_autosave()
		if Net.is_host():
			_end_lan_session()
		else:
			goto_main_menu()
		return
	abandon_session()


## Where the host saved the session file, as reported by the host.
var host_output_directory := ""


## The other computer dropped out. The host keeps whatever was recorded; both
## sides go back to a menu and say why.
func _on_session_lost(reason: String) -> void:
	_hide_reconnect_overlay()
	notice = reason
	if Net.is_host():
		if not GameState.scenario_results.is_empty() or not GameState.pre_assessment.is_empty():
			GameplayLogger.log_event("session", "session_ended_disconnect", {"reason": reason})
			GameplayLogger.write_session_file("_partial")
		_set_phase(Phase.MAIN_MENU)
		_change_scene(SCENE_MULTIPLAYER, false)
	else:
		_set_phase(Phase.MAIN_MENU)
		_change_scene(SCENE_MAIN_MENU, false)


func goto_multiplayer() -> void:
	_set_phase(Phase.MAIN_MENU)
	_change_scene(SCENE_MULTIPLAYER, false)


func goto_main_menu() -> void:
	_set_phase(Phase.MAIN_MENU)
	_change_scene(SCENE_MAIN_MENU)


## `single`: one person plays alone, carrying both roles' tools. There are no
## roles to assign, so the player setup screen is skipped.
func start_new_session(single: bool = false) -> void:
	if Net.is_client():
		return
	if Net.is_host():
		Net.mark_session_started()
		single = false
	GameState.reset_session()
	GameState.single_player = single
	if single:
		GameState.player_roles.assign(["solo", "monitor"])
	GameplayLogger.clear()
	GameplayLogger.log_event("session", "session_started", {
		"session_id": GameState.session_id,
		"prototype_version": Config.PROTOTYPE_VERSION,
		"mode": "single" if single else "pair",
	})
	if single:
		begin_pre_assessment()
	else:
		goto_player_setup()


func goto_player_setup() -> void:
	_set_phase(Phase.PLAYER_SETUP)
	_change_scene(SCENE_PLAYER_SETUP)


func goto_instructions(return_scene: String = SCENE_MAIN_MENU) -> void:
	_instructions_return_scene = return_scene
	_set_phase(Phase.INSTRUCTIONS)
	_change_scene(SCENE_INSTRUCTIONS, false)


func leave_instructions() -> void:
	_change_scene(_instructions_return_scene, false)


## Player setup is done: roles are locked in, move to the pre-test.
func begin_pre_assessment() -> void:
	GameplayLogger.log_event("session", "roles_confirmed", {
		"player_1_role": GameState.role_for_player(0),
		"player_2_role": "" if GameState.single_player else GameState.role_for_player(1),
	})
	pending_assessment = {
		"path": PRE_ASSESSMENT_PATH,
		"kind": "pre_assessment",
		"title": "Pre-session knowledge check",
		"intro": "Answer these before playing." if GameState.single_player \
			else "Answer these before playing. Each of you answers separately, without discussing.",
		"show_feedback": false,
	}
	_set_phase(Phase.PRE_ASSESSMENT)
	_change_scene(SCENE_ASSESSMENT)


## Called by the assessment screen when a set of questions has been completed.
func submit_assessment(kind: String, result: Dictionary) -> void:
	GameplayLogger.log_assessment("assessment_completed", {
		"kind": kind,
		"score": result.get("score", 0),
		"max_score": result.get("max_score", 0),
		"percent": result.get("percent", 0.0),
		"player_scores": _player_scores(result),
	})
	match kind:
		"pre_assessment":
			GameState.pre_assessment = result
			start_next_scenario()
		"post_assessment":
			GameState.post_assessment = result
			goto_usability()
		_:
			GameState.record_scenario_quiz(result)
			_after_scenario_quiz()


## Compact per-player scores for the log, e.g. [{"player": 1, "score": 3, ...}].
func _player_scores(result: Dictionary) -> Array:
	var out := []
	for entry in (result.get("players", []) as Array):
		var p := entry as Dictionary
		out.append({
			"player": p.get("player", 0),
			"role": p.get("role", ""),
			"score": p.get("score", 0),
			"max_score": p.get("max_score", 0),
			"percent": p.get("percent", 0.0),
		})
	return out


## Loads the next scenario and shows its briefing. The season itself does not
## start until the players press through the briefing.
func start_next_scenario() -> void:
	var index := GameState.current_scenario_index
	var definition := scenario_definition(index)
	if definition.is_empty():
		push_error("SessionController: no scenario definition at index %d" % index)
		goto_post_assessment()
		return
	pending_scenario = definition
	_set_phase(Phase.SCENARIO_BRIEFING)
	_change_scene(SCENE_BRIEFING)


## Called by the briefing screen. This is where the clock actually starts.
func begin_scenario() -> void:
	var index := GameState.current_scenario_index
	GameplayLogger.log_scenario("scenario_started", {
		"scenario_index": index + 1,
		"scenario_id": pending_scenario.get("id", ""),
		"crop": pending_scenario.get("crop", ""),
		"event": pending_scenario.get("event", "none"),
	})
	_set_phase(Phase.SCENARIO)
	_change_scene(SCENE_FARM)


## Called by the farm scene once the season is over.
func finish_scenario(result: Dictionary) -> void:
	var index := GameState.current_scenario_index
	result["scenario_index"] = index + 1
	result["scenario_id"] = pending_scenario.get("id", "")
	GameState.record_scenario_result(result)
	GameplayLogger.log_scenario("scenario_completed", {
		"scenario_index": index + 1,
		"scenario_id": result.get("scenario_id", ""),
		"total_yield": result.get("total_yield", 0.0),
		"tiles_harvested": result.get("tiles_harvested", 0),
	})
	pending_results = result
	_set_phase(Phase.SCENARIO_RESULTS)
	_change_scene(SCENE_SCENARIO_RESULTS)


## Called by the results screen's continue button.
func begin_scenario_quiz() -> void:
	var definition := pending_scenario
	pending_assessment = {
		"path": definition.get("quiz_file", ""),
		"kind": "quiz_%d" % (GameState.current_scenario_index + 1),
		"title": "%s - knowledge check" % definition.get("title", "Scenario"),
		"intro": "A few questions about what just happened on the farm.",
		"show_feedback": true,
	}
	_set_phase(Phase.SCENARIO_QUIZ)
	_change_scene(SCENE_ASSESSMENT)


func _after_scenario_quiz() -> void:
	GameState.current_scenario_index += 1
	if GameState.current_scenario_index >= GameState.SCENARIO_COUNT:
		goto_post_assessment()
	else:
		start_next_scenario()


func goto_post_assessment() -> void:
	pending_assessment = {
		"path": POST_ASSESSMENT_PATH,
		"kind": "post_assessment",
		"title": "Post-session knowledge check",
		"intro": "The same topics as the first knowledge check." if GameState.single_player \
			else "The same topics as the first knowledge check. Answer them on your own again.",
		"show_feedback": false,
	}
	_set_phase(Phase.POST_ASSESSMENT)
	_change_scene(SCENE_ASSESSMENT)


## After the post-test each player answers the short usability questionnaire.
func goto_usability() -> void:
	_set_phase(Phase.USABILITY)
	_change_scene(SCENE_USABILITY)


## Called by the usability screen once both players have answered.
func submit_usability(result: Dictionary) -> void:
	GameState.usability = result
	GameplayLogger.log_assessment("usability_completed", {
		"instrument_id": result.get("instrument_id", ""),
		"players": (result.get("responses", []) as Array).size(),
	})
	goto_final_results()


func goto_final_results() -> void:
	# From here on a dropped connection loses nothing: the file is written.
	Net.in_session = false
	GameplayLogger.log_event("session", "session_completed", {
		"total_yield": GameState.total_yield(),
	})
	var written := GameplayLogger.write_session_file()
	if written.is_empty():
		push_warning("SessionController: session data was not written to disk")
	else:
		GameplayLogger.log_event("session", "session_file_written", {"path": written})
	_set_phase(Phase.FINAL_RESULTS)
	_change_scene(SCENE_FINAL_RESULTS)


## Ends the session early from the pause screen. Whatever has been recorded so
## far is written out, marked partial, so an abandoned run is still usable data.
func abandon_session() -> void:
	if Net.is_client():
		Net.request_abandon()
		return
	GameplayLogger.log_event("session", "session_ended_early", {
		"scenario_index": GameState.current_scenario_index + 1,
		"scenarios_completed": GameState.scenario_results.size(),
	})
	var written := GameplayLogger.write_session_file("_partial")
	if written.is_empty():
		push_warning("SessionController: partial session data was not written")
	_hide_exit_dialog()
	if Net.is_host():
		_end_lan_session()
		return
	goto_main_menu()


## Host: the session is over (finished or abandoned). Both computers go back to
## the multiplayer screen, still connected, so the pair can start again.
func _end_lan_session() -> void:
	Net.in_session = false
	_set_phase(Phase.MAIN_MENU)
	_change_scene(SCENE_MULTIPLAYER)


## Called by the final results screen's menu button.
func leave_results() -> void:
	if Net.is_host():
		_end_lan_session()
	elif Net.is_client():
		Net.leave()
		goto_main_menu()
	else:
		goto_main_menu()


func quit_to_desktop() -> void:
	if Net.is_client():
		# The session file belongs to the host. Player 2 just leaves.
		Net.leave()
		get_tree().quit()
		return
	if not GameState.scenario_results.is_empty() or not GameState.pre_assessment.is_empty():
		GameplayLogger.write_session_file("_partial")
	get_tree().quit()
