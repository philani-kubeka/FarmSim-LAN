extends Control
## Short usability questionnaire, shown after the post-test.
##
## Like the knowledge checks, each player answers
## this on their own: Player 1 first, then a hand-over screen, then Player 2.
## Every answer is logged as an event and the whole set is stored in the session
## file under "usability", keyed by the session id like everything else.
##
## The statements and answer choices come from data/assessments/usability.json,
## so the wording can be changed without touching code.

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const CONTENT := "Page/PageScroll/Row/PageContent"
## Players who answer on this device in turn: 1 solo, 2 at one keyboard.
var PLAYER_COUNT := 2
var _back_button: Button = null

@onready var _title: Label = get_node(CONTENT + "/Title")
@onready var _intro: Label = get_node(CONTENT + "/Intro")
@onready var _progress: Label = get_node(CONTENT + "/Progress")
@onready var _statement: Label = get_node(CONTENT + "/Statement/Box/StatementText")
@onready var _statement_panel: Control = get_node(CONTENT + "/Statement")
@onready var _answers_row: HBoxContainer = get_node(CONTENT + "/Answers")
@onready var _handover_button: Button = get_node(CONTENT + "/HandoverButton")

var _instrument := {}
var _statements: Array = []
var _choices: Array = []
var _choice_buttons: Array[Button] = []
var _player := 0
var _index := 0
var _shown_msec := 0
var _responses: Array[Dictionary] = []
var _current_answers: Array[Dictionary] = []
var _started_msec := 0


func _ready() -> void:
	PLAYER_COUNT = GameState.player_count()
	_started_msec = Time.get_ticks_msec()
	_add_navigation()
	_instrument = _load_instrument(SessionController.USABILITY_PATH)
	_statements = _instrument.get("statements", [])
	_choices = _instrument.get("choices", [])
	_title.text = String(_instrument.get("title", "How was the game?"))

	for i in range(_answers_row.get_child_count()):
		var button := _answers_row.get_child(i) as Button
		if button == null:
			continue
		if i < _choices.size():
			button.text = String((_choices[i] as Dictionary).get("label", "?"))
			button.pressed.connect(_on_choice_pressed.bind(i))
			button.visible = true
		else:
			button.visible = false
		_choice_buttons.append(button)

	_handover_button.pressed.connect(_on_handover_pressed)

	if _statements.is_empty() or _choices.is_empty():
		_intro.text = "The usability questions could not be loaded."
		_set_question_visible(false)
		_handover_button.text = "Continue"
		_handover_button.visible = true
		return

	if Net.is_online():
		Net.set_handler(self)
		_start_player(Net.local_player_index)
	else:
		_start_player(0)


func _exit_tree() -> void:
	Net.clear_handler(self)


func _load_instrument(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("UsabilityScreen: instrument not found at '%s'" % path)
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_error("UsabilityScreen: could not parse %s: %s" % [path, json.get_error_message()])
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {}
	return json.data as Dictionary


# ------------------------------------------------------------------- flow ---

func _start_player(player: int) -> void:
	_player = player
	_index = 0
	_current_answers = []
	var colour := UiKit.COL_PLAYER_1 if player == 0 else UiKit.COL_PLAYER_2
	_intro.text = "Answer for yourself. There are no wrong answers." if PLAYER_COUNT == 1 and not Net.is_online() \
		else "Player %d, answer for yourself. There are no wrong answers." % (player + 1)
	_intro.add_theme_color_override("font_color", colour)
	_handover_button.visible = false
	_set_question_visible(true)
	_show_statement()


func _show_statement() -> void:
	var statement := _statements[_index] as Dictionary
	_progress.text = ("Question %d of %d" % [_index + 1, _statements.size()]) \
		if PLAYER_COUNT == 1 and not Net.is_online() \
		else "Player %d  -  question %d of %d" % [_player + 1, _index + 1, _statements.size()]
	if _back_button != null:
		_back_button.visible = true
		_back_button.disabled = _index <= 0
	Config.refit()
	_statement.text = String(statement.get("text", ""))
	_shown_msec = Time.get_ticks_msec()
	if not _choice_buttons.is_empty():
		_choice_buttons[0].grab_focus()


func _on_choice_pressed(choice_index: int) -> void:
	var statement := _statements[_index] as Dictionary
	var choice := _choices[choice_index] as Dictionary
	var answer := {
		"statement_id": statement.get("id", "u%d" % (_index + 1)),
		"topic": statement.get("topic", ""),
		"answer": choice.get("id", ""),
		"seconds": snappedf((Time.get_ticks_msec() - _shown_msec) / 1000.0, 0.01),
	}
	_current_answers.append(answer)
	GameplayLogger.log_assessment("usability_answered", {
		"kind": "usability",
		"player": _player + 1,
		"role": GameState.role_for_player(_player),
		"statement_id": answer["statement_id"],
		"topic": answer["topic"],
		"answer": answer["answer"],
		"seconds": answer["seconds"],
	})

	_index += 1
	if _index < _statements.size():
		_show_statement()
		return

	_responses.append({
		"player": _player + 1,
		"role": GameState.role_for_player(_player),
		"answers": _current_answers,
	})
	_set_question_visible(false)
	if _back_button != null:
		_back_button.visible = false
	if Net.is_online():
		_finish_online()
		return
	if _player + 1 < PLAYER_COUNT:
		_intro.text = "Thank you, Player %d. Please pass over to Player %d." % [_player + 1, _player + 2]
		_handover_button.text = "Player %d is ready" % (_player + 2)
	else:
		_intro.text = "Thank you!" if PLAYER_COUNT == 1 else "Thank you both!"
		_handover_button.text = "See our results"
	_intro.remove_theme_color_override("font_color")
	_progress.text = ""
	_handover_button.visible = true
	_handover_button.grab_focus()


func _on_handover_pressed() -> void:
	if Net.is_online():
		if Net.is_host() and _statements.is_empty():
			_submit()
		return
	if not _statements.is_empty() and _responses.size() < PLAYER_COUNT:
		_start_player(_responses.size())
		return
	_submit()


func _submit() -> void:
	SessionController.submit_usability({
		"instrument_id": _instrument.get("id", "usability"),
		"seconds": snappedf((Time.get_ticks_msec() - _started_msec) / 1000.0, 0.01),
		"responses": _responses,
	})


# --------------------------------------------------------------- LAN port ---

const KIND := "usability"
var _waiting_for_partner := false


func _finish_online() -> void:
	Net.send_player_result(KIND, _responses[0])
	_waiting_for_partner = true
	_intro.remove_theme_color_override("font_color")
	_progress.text = ""
	_handover_button.visible = true
	_handover_button.disabled = true
	if Net.is_host():
		_intro.text = "Thank you, Player 1. Waiting for Player 2 to finish on their computer."
		_handover_button.text = "Waiting for Player 2..."
		_try_combine()
	else:
		_intro.text = "Thank you, Player 2! Waiting for Player 1."
		_handover_button.text = "Waiting for Player 1..."


func _try_combine() -> void:
	if not Net.is_host() or not _waiting_for_partner:
		return
	var remote := Net.take_remote_result(KIND)
	if remote.is_empty():
		return
	_waiting_for_partner = false
	_responses.append(remote)
	_responses.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("player", 0)) < int(b.get("player", 0)))
	_submit()


func on_remote_player_result(kind: String, _result: Dictionary) -> void:
	if kind == KIND:
		_try_combine()


func _set_question_visible(shown: bool) -> void:
	_statement_panel.visible = shown
	_answers_row.visible = shown
	Config.refit()


# ------------------------------------------------------------- navigation --

## A Back button (previous statement) and an Exit button under the answers.
func _add_navigation() -> void:
	var row := HBoxContainer.new()
	row.name = "NavRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	var content := get_node(CONTENT)
	content.add_child(row)
	content.move_child(row, _answers_row.get_index() + 1)
	_back_button = Button.new()
	_back_button.name = "BackButton"
	_back_button.text = "< Back"
	_back_button.theme_type_variation = &"GhostButton"
	_back_button.custom_minimum_size = Vector2(140, 50)
	_back_button.pressed.connect(go_back)
	row.add_child(_back_button)
	row.add_child(UiKit.exit_button())


## Back to the previous statement; its answer is taken back so it can be given
## again. On the first statement (or between players) it offers to leave.
func go_back() -> void:
	if _index <= 0 or _current_answers.is_empty() or not _statement_panel.visible:
		SessionController.request_exit()
		return
	_index -= 1
	var undone: Dictionary = _current_answers.pop_back()
	GameplayLogger.log_assessment("usability_answer_withdrawn", {
		"kind": "usability",
		"player": _player + 1,
		"statement_id": undone.get("statement_id", ""),
	})
	_show_statement()


## Android's back gesture.
func _on_back_pressed() -> void:
	go_back()
