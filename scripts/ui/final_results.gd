extends Control
## End of the session: the pre/post comparison, the three season outcomes, and
## confirmation of where the research data was written.
##
## The layout is final_results.tscn. Only the per-season lines are built here,
## because how many there are depends on how far the pair got.

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const CONTENT := "Page/PageScroll/Row/PageContent"

@onready var _session_id: Label = get_node(CONTENT + "/SessionId")
@onready var _knowledge: HBoxContainer = get_node(CONTENT + "/Knowledge")
@onready var _seasons: VBoxContainer = get_node(CONTENT + "/Seasons/Box")
@onready var _data_note: Label = get_node(CONTENT + "/Data/Box/Note")
@onready var _menu_button: Button = get_node(CONTENT + "/Buttons/MenuButton")
@onready var _quit_button: Button = get_node(CONTENT + "/Buttons/QuitButton")


func _ready() -> void:
	_session_id.text = "Anonymous session id: %s" % GameState.session_id
	_fill_knowledge()
	_fill_seasons()
	_fill_data_note()
	_menu_button.pressed.connect(func() -> void: SessionController.leave_results())
	if Net.is_host():
		_menu_button.text = "Back to lobby"
	elif Net.is_client():
		_menu_button.text = "Leave game"
	_quit_button.pressed.connect(func() -> void: SessionController.quit_to_desktop())
	# The page holds a lot; the empty spacer rows between sections are what push
	# it past a 1280x720 window, and the headings already separate the sections.
	for spacer in ["KnowledgeSpacer", "SeasonsSpacer", "DataSpacer", "ButtonSpacer"]:
		var node := get_node(CONTENT).get_node_or_null(spacer) as Control
		if node != null:
			node.visible = false
	_menu_button.theme_type_variation = &"PrimaryButton"
	if Config.is_mobile():
		_apply_phone_layout()
	_menu_button.grab_focus()


## A phone held sideways has room for the numbers but not for the headings and
## gaps between them. The cards and the season lines say what they are, so the
## headings and spacers go, the session id moves into the research-data note,
## and the buttons get bigger. Config then fits what is left to the screen.
func _apply_phone_layout() -> void:
	var content := get_node(CONTENT)
	for node_name in ["KnowledgeSpacer", "SeasonsSpacer", "DataSpacer", "ButtonSpacer",
			"KnowledgeHeading", "SeasonsHeading", "SessionId", "Data/Box/Heading"]:
		var node := content.get_node_or_null(node_name) as Control
		if node != null:
			node.visible = false
	(content as VBoxContainer).add_theme_constant_override("separation", 10)
	_data_note.text = "Session id %s. %s" % [GameState.session_id, _data_note.text]
	for button in [_menu_button, _quit_button]:
		button.custom_minimum_size = Vector2(260, 64)
		button.add_theme_font_size_override("font_size", 22)
	_menu_button.theme_type_variation = &"PrimaryButton"
	for line in _seasons.get_children():
		if line is Label:
			(line as Label).add_theme_font_size_override("font_size", 16)


func _fill_knowledge() -> void:
	_set_stat("Before", _score_text(GameState.pre_assessment), UiKit.COL_TEXT)
	_set_stat("After", _score_text(GameState.post_assessment), UiKit.COL_TEXT)

	var gain := GameState.knowledge_gain_percent()
	if is_nan(gain):
		_set_stat("Change", "not available", UiKit.COL_TEXT_DIM)
		return
	var colour := UiKit.COL_TEXT
	var p1 := GameState.knowledge_gain_for_player(0)
	var p2 := GameState.knowledge_gain_for_player(1)
	if not is_nan(p1) and not is_nan(p2):
		if gain > 0.0:
			colour = UiKit.COL_GOOD
		elif gain < 0.0:
			colour = UiKit.COL_BAD
		_set_stat("Change", "P1 · %+.0f   P2 · %+.0f pts" % [p1, p2], colour)
		return
	if gain > 0.0:
		colour = UiKit.COL_GOOD
	elif gain < 0.0:
		colour = UiKit.COL_BAD
	_set_stat("Change", "%+.1f points" % gain, colour)


## Each player answers on their own, so show both: "P1 3/8  P2 5/8".
## Falls back to the single score for results without per-player parts.
func _score_text(assessment: Dictionary) -> String:
	if assessment.is_empty():
		return "-"
	var players: Array = assessment.get("players", [])
	if players.is_empty():
		return "%d / %d  (%.0f%%)" % [
			int(assessment.get("score", 0)),
			int(assessment.get("max_score", 0)),
			float(assessment.get("percent", 0.0)),
		]
	var parts: Array[String] = []
	for entry in players:
		var p := entry as Dictionary
		parts.append(_player_score(p))
	return "  ".join(parts)


## "P1 · 2/8" for a pair; just "2/8" when one person played alone.
func _player_score(p: Dictionary) -> String:
	var score := "%d/%d" % [int(p.get("score", 0)), int(p.get("max_score", 0))]
	if GameState.single_player:
		return score
	return "P%d · %s" % [int(p.get("player", 0)), score]


func _fill_seasons() -> void:
	for child in _seasons.get_children():
		child.queue_free()

	if GameState.scenario_results.is_empty():
		_seasons.add_child(UiKit.body("No seasons were completed."))
		return

	for index in range(GameState.scenario_results.size()):
		var result: Dictionary = GameState.scenario_results[index]
		var quiz_text := ""
		if index < GameState.scenario_quizzes.size():
			var quiz: Dictionary = GameState.scenario_quizzes[index]
			quiz_text = "   quiz " + _quiz_text(quiz)
		_seasons.add_child(UiKit.body("%s - %.1f units from %d harvests, average condition %d%%%s"
			% [
				String(result.get("title", "Season %d" % (index + 1))),
				float(result.get("total_yield", 0.0)),
				int(result.get("tiles_harvested", 0)),
				int(round(float(result.get("average_condition", 0.0)) * 100.0)),
				quiz_text,
			]))

	_seasons.add_child(UiKit.spacer(4))
	_seasons.add_child(UiKit.label("Total harvest across the session: %.1f units"
		% GameState.total_yield(), UiKit.FONT_BODY, UiKit.COL_ACCENT))


func _quiz_text(quiz: Dictionary) -> String:
	var players: Array = quiz.get("players", [])
	if players.is_empty():
		return "%d/%d" % [int(quiz.get("score", 0)), int(quiz.get("max_score", 0))]
	var parts: Array[String] = []
	for entry in players:
		var p := entry as Dictionary
		parts.append(_player_score(p))
	return ", ".join(parts)


func _fill_data_note() -> void:
	if Net.is_client():
		_data_note.text = (
			"The session file was saved on the host's computer (Player 1), in %s. "
			% SessionController.host_output_directory
			+ "This computer keeps no copy. It contains no personal information.")
		return
	_data_note.text = (
		"A JSON file for this session was written to %s. It holds the anonymous session id, "
		% GameplayLogger.output_directory()
		+ ("the role, every assessment answer, every season outcome and a timestamped log of "
			+ "what you did." if GameState.single_player
			else "both roles, every assessment answer, every season outcome and a timestamped log of "
			+ "what the two players did.")
		+ " It contains no personal information.")


func _set_stat(card_name: String, value: String, colour: Color) -> void:
	var card: Node = _knowledge.get_node_or_null(card_name)
	if card != null:
		card.show_stat(String(card.caption), value, colour)



## Android's back gesture: the session is over, so back means back to the menu.
func _on_back_pressed() -> void:
	SessionController.leave_results()
