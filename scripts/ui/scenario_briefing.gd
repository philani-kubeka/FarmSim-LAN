extends Control
## Shown before each season starts.
##
## This is where the scenario is explained: the crop, the conditions, what each
## player is responsible for, and what they are trying to achieve. Putting it on
## its own screen means the players read it before the clock starts rather than
## trying to read a paragraph off a HUD bar while the crop dries out.
##
## The layout is scenario_briefing.tscn. Only the objective lines are built here,
## because how many there are comes from data/scenarios.json.

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const CONTENT := "Page/PageScroll/Row/PageContent"

@onready var _title: Label = %Title
@onready var _season: Label = %Season
@onready var _briefing: Label = %Text
@onready var _objectives: VBoxContainer = %ObjectiveList
@onready var _start_button: Button = get_node(CONTENT + "/StartButton")

var _definition := {}


func _ready() -> void:
	_definition = SessionController.pending_scenario
	if _definition.is_empty():
		_definition = SessionController.scenario_definition(0)

	_title.text = String(_definition.get("title", "Scenario"))
	_season.text = "Season %d of %d  -  %s" % [
		GameState.current_scenario_index + 1,
		GameState.SCENARIO_COUNT,
		String(_definition.get("crop", "")).capitalize(),
	]
	_briefing.text = String(_definition.get("briefing", ""))
	if GameState.single_player and _definition.has("briefing_solo"):
		_briefing.text = String(_definition["briefing_solo"])
	_fill_objectives()
	if GameState.single_player and not Net.is_online():
		# One role card instead of two: give the story and objectives the room.
		var columns := get_node("Page/PageScroll/Row/PageContent/Columns")
		(columns.get_node("Left") as Control).size_flags_stretch_ratio = 1.5
		(columns.get_node("Roles") as Control).size_flags_stretch_ratio = 0.8

	_start_button.pressed.connect(_on_start_pressed)
	_season.get_parent().add_child(UiKit.exit_button())
	if Net.is_client():
		_start_button.disabled = true
		_start_button.text = "Waiting for host to start..."
	else:
		_start_button.grab_focus()


func _fill_objectives() -> void:
	for child in _objectives.get_children():
		child.queue_free()
	var objective_list: Array = _definition.get("objectives", [])
	if objective_list.is_empty():
		_objectives.add_child(UiKit.body("Farm the season as well as you can."))
		return
	for objective in objective_list:
		var text := String(objective)
		if GameState.single_player:
			# Lines about sharing with a partner do not apply to one farmer.
			if text.contains("player"):
				continue
			text = text.replace("Decide together", "Decide")
		var line := UiKit.body("- " + text)
		line.add_theme_font_size_override("font_size", 17)
		_objectives.add_child(line)


func _on_start_pressed() -> void:
	SessionController.begin_scenario()



## Android's back gesture.
func _on_back_pressed() -> void:
	SessionController.request_exit()
