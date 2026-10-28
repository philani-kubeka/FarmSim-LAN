extends Control
## One reusable screen for every knowledge instrument: the pre-test, the three
## scenario quizzes and the post-test. What it shows comes entirely from a JSON
## file, so the instrument can be revised without touching any code.
##
## Each player answers on their own, the same way the usability questionnaire
## works: Player 1 answers every question, a hand-over step hides the questions,
## then Player 2 answers the same questions. Each player gets their own score,
## and the stored result keeps both side by side under "players". The top-level
## score / max_score / percent are the pair combined (sum of both scores, mean
## percent) so older readers of the session file still get a sensible number.
##
## The layout is assessment_screen.tscn, with six quiz_option.tscn buttons
## authored under the question panel and shown or hidden to match however many
## options the current question has. Six is the most any instrument uses. The
## hand-over step reuses NextButton.
##
## The instrument itself is provisional. It has not been confirmed with the
## supervisor and must be reviewed before it is used in a real study.

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const CONTENT := "Page/PageScroll/Row/PageContent"
const MAX_OPTIONS := 6
## Players who answer on this device, in turn. Solo play has one; a LAN device
## answers for its own player only (see _start_player).
var PLAYER_COUNT := 2

@onready var _title: Label = get_node(CONTENT + "/Title")
@onready var _intro: Label = get_node(CONTENT + "/Intro")
@onready var _progress_label: Label = get_node(CONTENT + "/Progress")
@onready var _question_panel: Control = get_node(CONTENT + "/Question")
@onready var _question_label: Label = get_node(CONTENT + "/Question/Box/QuestionText")
@onready var _question_box: VBoxContainer = get_node(CONTENT + "/Question/Box")
@onready var _feedback_label: Label = get_node(CONTENT + "/Feedback")
@onready var _next_button: Button = get_node(CONTENT + "/NextButton")

var _config := {}
var _questions: Array = []
var _player := 0
var _answers: Array[Dictionary] = []
var _player_results: Array[Dictionary] = []
var _index := 0
var _selected := -1
var _started_msec := 0
var _player_started_msec := 0
var _question_started_msec := 0
var _show_feedback := false
var _awaiting_handover := false
var _option_buttons: Array[Button] = []


func _ready() -> void:
	PLAYER_COUNT = GameState.player_count()
	_config = SessionController.pending_assessment.duplicate(true)
	_show_feedback = bool(_config.get("show_feedback", false))
	_questions = _load_questions(String(_config.get("path", "")))
	_started_msec = Time.get_ticks_msec()

	_title.text = String(_config.get("title", "Knowledge check"))
	_intro.text = String(_config.get("intro", ""))

	_option_buttons.clear()
	for i in range(MAX_OPTIONS):
		var option: Button = _question_box.get_node("Option%d" % i)
		option.pressed.connect(_on_option_pressed.bind(i))
		_option_buttons.append(option)

	_next_button.pressed.connect(_on_next_pressed)
	# Two columns everywhere: a long question with its feedback showing no
	# longer fits one column on a 1280x720 window either.
	_apply_phone_layout()

	if _questions.is_empty():
		_question_label.text = "This instrument could not be loaded."
		_progress_label.text = String(_config.get("path", ""))
		_next_button.text = "Continue"
		_next_button.disabled = false
		return

	if Net.is_online():
		# LAN port: each computer answers for its own player only.
		Net.set_handler(self)
		_start_player(Net.local_player_index)
	else:
		_start_player(0)


func _exit_tree() -> void:
	Net.clear_handler(self)


# ------------------------------------------------------------------ data ----

func _load_questions(path: String) -> Array:
	if path.is_empty() or not FileAccess.file_exists(path):
		push_error("AssessmentScreen: instrument not found at '%s'" % path)
		return []
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_error("AssessmentScreen: could not parse %s: %s" % [path, json.get_error_message()])
		return []
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		push_error("AssessmentScreen: %s is not a JSON object" % path)
		return []
	_config["instrument_id"] = (data as Dictionary).get("id", path.get_file())
	var questions: Variant = (data as Dictionary).get("questions", [])
	if typeof(questions) != TYPE_ARRAY:
		push_error("AssessmentScreen: %s has no questions array" % path)
		return []
	return questions as Array


# ------------------------------------------------------------------ flow ----

func _start_player(player: int) -> void:
	_player = player
	_index = 0
	_answers = []
	_awaiting_handover = false
	_player_started_msec = Time.get_ticks_msec()
	var colour := UiKit.COL_PLAYER_1 if player == 0 else UiKit.COL_PLAYER_2
	var other := 2 if player == 0 else 1
	var lead := String(_config.get("intro", ""))
	if PLAYER_COUNT == 1 and not Net.is_online():
		_intro.text = lead
	elif Net.is_online():
		_intro.text = ("%s\n\n" % lead if not lead.is_empty() else "") \
			+ "Player %d, answer on your own. Player %d is answering on the other device." \
			% [player + 1, other]
	else:
		_intro.text = ("%s\n\n" % lead if not lead.is_empty() else "") \
			+ "Player %d, answer on your own. Player %d, please look away until it is your turn." \
			% [player + 1, other]
	_intro.add_theme_color_override("font_color", colour)
	_question_panel.visible = true
	_show_question()


func _current_question() -> Dictionary:
	if _index < 0 or _index >= _questions.size():
		return {}
	return _questions[_index] as Dictionary


func _show_question() -> void:
	var question := _current_question()
	_selected = -1
	_question_started_msec = Time.get_ticks_msec()
	_feedback_label.visible = false
	_next_button.disabled = true
	_next_button.text = "Next" if _index < _questions.size() - 1 else "Finish"

	_progress_label.text = "Player %d  -  question %d of %d" % [_player + 1, _index + 1, _questions.size()]
	_question_label.text = String(question.get("text", ""))

	var options: Array = question.get("options", [])
	for i in range(_option_buttons.size()):
		var button: Button = _option_buttons[i]
		if i < options.size():
			button.show_option(i, String(options[i]))
		else:
			button.hide_option()
	if not _option_buttons.is_empty() and _option_buttons[0].visible:
		_option_buttons[0].grab_focus()
	_after_change()


func _on_option_pressed(option_index: int) -> void:
	if _awaiting_handover:
		return
	_selected = option_index
	_next_button.disabled = false
	for i in range(_option_buttons.size()):
		var button: Button = _option_buttons[i]
		if not button.visible:
			continue
		button.set_chosen(i == option_index)

	if _show_feedback:
		var question := _current_question()
		var correct_index := int(question.get("correct_index", -1))
		var correct := option_index == correct_index
		_feedback_label.text = ("Correct. " if correct else "Not quite. ") \
			+ String(question.get("explanation", ""))
		_feedback_label.add_theme_color_override("font_color",
			UiKit.COL_GOOD if correct else UiKit.COL_WARN)
		_feedback_label.visible = true
		for button in _option_buttons:
			button.disabled = true
		# Keep the chosen answer readable even while disabled.
		_next_button.grab_focus()
		_after_change()


func _on_next_pressed() -> void:
	if _waiting_for_partner:
		return
	if _questions.is_empty() and Net.is_client():
		return
	if _questions.is_empty():
		SessionController.submit_assessment(String(_config.get("kind", "unknown")), {
			"kind": _config.get("kind", "unknown"),
			"instrument_id": _config.get("instrument_id", ""),
			"mode": "individual",
			"error": "instrument_not_loaded",
			"score": 0,
			"max_score": 0,
			"percent": 0.0,
			"players": [],
		})
		return

	if _awaiting_handover:
		_start_player(_player + 1)
		return

	_record_answer()
	_index += 1
	if _index < _questions.size():
		_show_question()
		return

	_player_results.append(_player_result())
	if Net.is_online():
		_finish_online()
		return
	if _player + 1 < PLAYER_COUNT:
		_show_handover()
	else:
		_finish()


## Between players: hide the questions so Player 2 starts fresh.
func _show_handover() -> void:
	_awaiting_handover = true
	_question_panel.visible = false
	_feedback_label.visible = false
	_progress_label.text = ""
	_intro.remove_theme_color_override("font_color")
	_intro.text = "Thank you, Player %d. Please pass over to Player %d." % [_player + 1, _player + 2]
	_next_button.text = "Continue - Player %d's turn" % (_player + 2)
	_next_button.disabled = false
	_next_button.grab_focus()
	_after_change()


func _record_answer() -> void:
	var question := _current_question()
	var correct_index := int(question.get("correct_index", -1))
	var answer := {
		"question_id": question.get("id", "q%d" % (_index + 1)),
		"topic": question.get("topic", ""),
		"selected_index": _selected,
		"correct_index": correct_index,
		"correct": _selected == correct_index,
		"seconds": snappedf((Time.get_ticks_msec() - _question_started_msec) / 1000.0, 0.01),
	}
	var revisit := _index < _answers.size()
	var changed := revisit and int(_answers[_index].get("selected_index", -1)) != _selected
	if revisit:
		# Went back to this question: the newer answer replaces the older one,
		# so every question still counts exactly once.
		answer["revisited"] = true
		_answers[_index] = answer
	else:
		_answers.append(answer)
	if revisit and not changed:
		return
	GameplayLogger.log_assessment("answer_changed" if changed else "question_answered", {
		"kind": _config.get("kind", ""),
		"player": _player + 1,
		"role": GameState.role_for_player(_player),
		"question_id": answer["question_id"],
		"topic": answer["topic"],
		"correct": answer["correct"],
		"seconds": answer["seconds"],
	})


# ------------------------------------------------------------- going back --

## Back: the previous question, with the answer that was given. With feedback
## on (the scenario quizzes) the earlier answer is shown locked, so nobody can
## change an answer after being told the right one. On the first question,
## Back offers to leave the session instead.
func go_back() -> void:
	if _awaiting_handover or _waiting_for_partner or _questions.is_empty():
		SessionController.request_exit()
		return
	if _index <= 0:
		SessionController.request_exit()
		return
	_index -= 1
	_show_question()
	var previous: Dictionary = _answers[_index] if _index < _answers.size() else {}
	var chosen := int(previous.get("selected_index", -1))
	if chosen >= 0:
		_on_option_pressed(chosen)


## Android's back gesture.
func _on_back_pressed() -> void:
	go_back()


func _player_result() -> Dictionary:
	var score := 0
	for answer in _answers:
		if bool(answer.get("correct", false)):
			score += 1
	var max_score := _answers.size()
	return {
		"player": _player + 1,
		"role": GameState.role_for_player(_player),
		"score": score,
		"max_score": max_score,
		"percent": (0.0 if max_score == 0 else snappedf(100.0 * score / max_score, 0.1)),
		"seconds": snappedf((Time.get_ticks_msec() - _player_started_msec) / 1000.0, 0.01),
		"answers": _answers,
	}


# --------------------------------------------------------------- LAN port ---

var _waiting_for_partner := false


## This computer's player is done. The client hands its answers to the host;
## the host waits for them, then records both exactly as the one-keyboard
## version would.
func _finish_online() -> void:
	var kind := String(_config.get("kind", "unknown"))
	Net.send_player_result(kind, _player_results[0])
	_waiting_for_partner = true
	_question_panel.visible = false
	_feedback_label.visible = false
	_progress_label.text = ""
	_intro.remove_theme_color_override("font_color")
	_next_button.disabled = true
	if Net.is_host():
		_next_button.text = "Waiting for Player 2..."
		_intro.text = "Thank you, Player 1. Waiting for Player 2 to finish on their computer."
		_try_combine()
	else:
		_next_button.text = "Waiting for Player 1..."
		_intro.text = "Thank you, Player 2. The session carries on once Player 1 has finished too."
	_after_change()


func _try_combine() -> void:
	if not Net.is_host() or not _waiting_for_partner:
		return
	var remote := Net.take_remote_result(String(_config.get("kind", "unknown")))
	if remote.is_empty():
		return
	_waiting_for_partner = false
	_player_results.append(remote)
	_player_results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("player", 0)) < int(b.get("player", 0)))
	_finish()


func on_remote_player_result(kind: String, _result: Dictionary) -> void:
	if kind == String(_config.get("kind", "")):
		_try_combine()


func _finish() -> void:
	var score := 0
	var max_score := 0
	var percent_sum := 0.0
	for result in _player_results:
		score += int(result.get("score", 0))
		max_score += int(result.get("max_score", 0))
		percent_sum += float(result.get("percent", 0.0))
	var result := {
		"kind": _config.get("kind", "unknown"),
		"instrument_id": _config.get("instrument_id", ""),
		"mode": "individual",
		# Pair combined: total correct across both players, and the mean percent.
		"score": score,
		"max_score": max_score,
		"percent": (0.0 if _player_results.is_empty() else snappedf(percent_sum / _player_results.size(), 0.1)),
		"seconds": snappedf((Time.get_ticks_msec() - _started_msec) / 1000.0, 0.01),
		"players": _player_results,
	}
	SessionController.submit_assessment(String(_config.get("kind", "unknown")), result)


# ------------------------------------------------------------ phone layout --
#
# A landscape screen is wide and short, so the quiz uses the width (on a phone and
# on a computer):
# the question and its feedback on the left, the answers on the right, and the
# title, intro and progress folded into one line at the top. Nothing about the
# questions, the answers or what gets recorded changes. Config then fits the
# whole page to the phone's height, so no question needs scrolling.

var _phone_layout := false
var _left_column: VBoxContainer = null
var _back_button: Button = null
var _exit_button: Button = null


func _apply_phone_layout() -> void:
	_phone_layout = true
	var content: VBoxContainer = get_node(CONTENT)
	content.add_theme_constant_override("separation", 8)
	for spacer_name in ["QuestionSpacer", "NextSpacer"]:
		var spacer := content.get_node_or_null(spacer_name) as Control
		if spacer != null:
			spacer.visible = false
	_title.visible = false
	# Two columns need the width: narrow the page's side margins.
	for gutter_name in ["GutterLeft", "GutterRight"]:
		var gutter := get_node_or_null("Page/PageScroll/Row/" + gutter_name) as Control
		if gutter != null:
			gutter.size_flags_stretch_ratio = 0.03
	_progress_label.clip_text = true
	_progress_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	var columns := HBoxContainer.new()
	columns.name = "Columns"
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 18)
	content.add_child(columns)
	content.move_child(columns, _question_panel.get_index())

	_left_column = VBoxContainer.new()
	_left_column.name = "Left"
	_left_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left_column.size_flags_stretch_ratio = 0.85
	_left_column.add_theme_constant_override("separation", 10)
	columns.add_child(_left_column)

	_question_label.reparent(_left_column, false)
	_feedback_label.reparent(_left_column, false)
	var push := Control.new()
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	push.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left_column.add_child(push)
	var nav := HBoxContainer.new()
	nav.name = "NavRow"
	nav.add_theme_constant_override("separation", 12)
	_left_column.add_child(nav)
	_back_button = Button.new()
	_back_button.name = "BackButton"
	_back_button.text = "< Back"
	_back_button.theme_type_variation = &"GhostButton"
	_back_button.custom_minimum_size = Vector2(130, 56)
	_back_button.pressed.connect(go_back)
	nav.add_child(_back_button)
	_next_button.reparent(nav, false)
	_next_button.theme_type_variation = &"PrimaryButton"
	_next_button.custom_minimum_size = Vector2(0, 56)
	_next_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Top line: what this is and how far along, plus a way out.
	var top := HBoxContainer.new()
	top.name = "TopRow"
	top.add_theme_constant_override("separation", 12)
	content.add_child(top)
	content.move_child(top, _progress_label.get_index())
	_progress_label.reparent(top, false)
	_progress_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_exit_button = UiKit.exit_button()
	top.add_child(_exit_button)

	_question_panel.reparent(columns, false)
	_question_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_question_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_question_box.add_theme_constant_override("separation", 8)
	_question_label.add_theme_font_size_override("font_size", 22)
	_feedback_label.add_theme_font_size_override("font_size", 16)
	for option in _option_buttons:
		option.custom_minimum_size = Vector2(0, 48)


## Phone layout: the intro only shows when there is no question on screen
## (hand-over, waiting for the partner), and the page is re-fitted to the phone.
func _after_change() -> void:
	if not _phone_layout:
		return
	var asking := _question_panel.visible
	_question_label.visible = asking
	_intro.visible = not asking
	if _back_button != null:
		_back_button.visible = asking
		_back_button.disabled = _index <= 0
	if asking and PLAYER_COUNT == 1 and not Net.is_online():
		_progress_label.text = "%s  -  question %d of %d" % [
			String(_config.get("title", "Knowledge check")), _index + 1, _questions.size()]
		_progress_label.add_theme_color_override("font_color", UiKit.COL_ACCENT)
	elif asking:
		_progress_label.text = "%s  -  Player %d  -  question %d of %d  -  answer on your own" % [
			String(_config.get("title", "Knowledge check")), _player + 1, _index + 1,
			_questions.size()]
		_progress_label.add_theme_color_override("font_color",
			UiKit.COL_PLAYER_1 if _player == 0 else UiKit.COL_PLAYER_2)
	else:
		_progress_label.text = String(_config.get("title", ""))
	Config.refit()
