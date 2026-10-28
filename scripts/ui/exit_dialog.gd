extends CanvasLayer
## "Leave the session?" - asked before any in-session screen lets a player out.
##
## Opened by the Exit button on every in-session screen and by Android's back
## gesture when there is nothing left to go back to (SessionController
## .request_exit). Leaving ends the session the same way the pause screen's
## Abandon always has: whatever was recorded is saved as a partial file, and in
## a LAN game both devices go back to the lobby.

const THEME := preload("res://assets/ui/farm_sim_theme.tres")

var _message: Label
var _stay: Button
var _leave: Button
var _open := false


func _init() -> void:
	layer = 55
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _build() -> void:
	var root := Control.new()
	root.theme = THEME
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.06, 0.04, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	card.custom_minimum_size = Vector2(540, 0)
	center.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	card.add_child(box)

	var title := Label.new()
	title.theme_type_variation = &"Title"
	title.text = "Leave the session?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.custom_minimum_size = Vector2(480, 0)
	box.add_child(_message)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)

	_stay = Button.new()
	_stay.name = "StayButton"
	_stay.text = "Keep going"
	_stay.theme_type_variation = &"PrimaryButton"
	_stay.custom_minimum_size = Vector2(220, 62)
	_stay.pressed.connect(close)
	row.add_child(_stay)

	_leave = Button.new()
	_leave.name = "LeaveButton"
	_leave.text = "Leave"
	_leave.theme_type_variation = &"DangerButton"
	_leave.custom_minimum_size = Vector2(200, 62)
	_leave.pressed.connect(func() -> void:
		close()
		SessionController.leave_session())
	row.add_child(_leave)


func open() -> void:
	var recorded := not GameState.pre_assessment.is_empty() or not GameState.scenario_results.is_empty()
	if Net.is_online():
		_message.text = "This ends the session for both players and takes you back to the lobby. " \
			+ ("Everything recorded so far is saved." if recorded else "Nothing has been recorded yet.")
	else:
		_message.text = "This ends the session and takes you back to the main menu. " \
			+ ("Everything recorded so far is saved." if recorded else "Nothing has been recorded yet.")
	_open = true
	visible = true
	_stay.grab_focus()


func close() -> void:
	_open = false
	visible = false


func is_open() -> bool:
	return _open
