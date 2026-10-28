extends Control
## What happened this season, and why.
##
## The "why" lines are not generic farming tips: each one is generated from a
## number that was actually recorded during the season, so two groups who played
## differently get different explanations.
##
## The layout is scenario_results.tscn - the ten stat cards are authored, and
## this script only puts the season's figures into them.

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const CONTENT := "Page/PageScroll/Row/PageContent"

@onready var _title: Label = %Title
## All ten figures share one grid now, so the season's numbers sit beside the
## explanation of them instead of on top of it (which pushed the screen past the
## bottom of the window).
@onready var _stats: GridContainer = %StatGrid
@onready var _water_stats: GridContainer = %StatGrid
@onready var _notes: VBoxContainer = %Box
@onready var _continue_button: Button = get_node(CONTENT + "/ContinueButton")

var _result := {}


func _ready() -> void:
	_result = SessionController.pending_results
	_title.text = "%s - results" % String(_result.get("title", "Season"))
	_add_exit()
	_compact_cards()
	_fill_stats()
	_fill_water_stats()
	_fill_notes()
	_continue_button.pressed.connect(_on_continue_pressed)
	if Net.is_client():
		_continue_button.disabled = true
		_continue_button.text = "Waiting for host..."
	else:
		_continue_button.grab_focus()


func _fill_stats() -> void:
	_set_stat("Harvest", "%.1f units" % float(_result.get("total_yield", 0.0)), UiKit.COL_ACCENT)
	_set_stat("Sown", str(_result.get("tiles_sown", 0)), UiKit.COL_TEXT)
	_set_stat("Harvests", str(_result.get("tiles_harvested", 0)), UiKit.COL_GOOD)
	_set_stat("Growing", str(_result.get("tiles_still_growing", 0)), UiKit.COL_WARN)
	_set_stat("Failed", str(_result.get("tiles_failed", 0)), UiKit.COL_BAD)
	_set_stat("Condition",
		"%d%%" % int(round(float(_result.get("average_condition", 0.0)) * 100.0)),
		UiKit.COL_TEXT)


func _fill_water_stats() -> void:
	var water: Dictionary = _result.get("water", {})
	var event: Dictionary = _result.get("event", {})
	var refused := int(water.get("refused_draws", 0))

	_set_water("WaterUsed", "%d / %d L" % [
		int(round(float(water.get("used_litres", 0.0)))),
		int(round(float(water.get("capacity_litres", 0.0)))),
	], UiKit.COL_WATER)
	_set_water("Refused", str(refused),
		UiKit.COL_BAD if refused > 0 else UiKit.COL_TEXT)

	var event_id := String(event.get("event", "none"))
	_set_water("Event", "none" if event_id == "none" else event_id.capitalize(),
		UiKit.COL_WARN if event_id != "none" else UiKit.COL_TEXT_DIM)

	var infested: Control = _water_stats.get_node("Infested")
	infested.visible = event_id == "pest"
	if infested.visible:
		_set_water("Infested", str(event.get("tiles_infested", 0)), UiKit.COL_BAD)


func _fill_notes() -> void:
	for child in _notes.get_children():
		child.queue_free()
	var causes: Array = _result.get("causes", [])
	if causes.is_empty():
		_notes.add_child(UiKit.body("No season data was recorded."))
		return
	for note in causes:
		var line := UiKit.body("- " + String(note))
		line.add_theme_font_size_override("font_size", 15 if Config.is_mobile() else 16)
		_notes.add_child(line)


func _set_stat(card_name: String, value: String, colour: Color) -> void:
	var card: Node = _stats.get_node_or_null(card_name)
	if card != null:
		card.show_stat(String(card.caption), value, colour)


func _set_water(card_name: String, value: String, colour: Color) -> void:
	var card: Node = _water_stats.get_node_or_null(card_name)
	if card != null:
		card.show_stat(String(card.caption), value, colour)


func _on_continue_pressed() -> void:
	SessionController.begin_scenario_quiz()


## The cards sit two to a row beside the explanation, so they are made a little
## tighter than the shared stat card - this is what keeps the whole season on
## one screen on a 16:9 phone.
func _compact_cards() -> void:
	for card in _stats.get_children():
		var panel := card as PanelContainer
		if panel == null:
			continue
		var base := panel.get_theme_stylebox("panel") as StyleBoxFlat
		if base != null:
			var tight: StyleBoxFlat = base.duplicate()
			tight.content_margin_top = 7
			tight.content_margin_bottom = 7
			tight.content_margin_left = 14
			tight.content_margin_right = 14
			panel.add_theme_stylebox_override("panel", tight)
		var value_label := panel.get_node_or_null("Box/Value") as Label
		if value_label != null:
			value_label.add_theme_font_size_override("font_size", 22)



## Title and an Exit button share the top line.
func _add_exit() -> void:
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 12)
	var content := _title.get_parent()
	content.add_child(header)
	content.move_child(header, _title.get_index())
	_title.reparent(header, false)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(UiKit.exit_button())


## Android's back gesture.
func _on_back_pressed() -> void:
	SessionController.request_exit()
