extends Control
## Controls and objectives reference. Reachable from the main menu and from the
## player setup screen.
##
## The layout is instructions.tscn; the two role cards are instances of
## role_card.tscn and fill themselves in from the current role assignment.

@onready var _back_button: Button = $Page/PageScroll/Row/PageContent/BackButton


func _ready() -> void:
	_back_button.pressed.connect(_on_back_pressed)
	if Config.is_mobile():
		($Page/PageScroll/Row/PageContent/Intro as Label).text = "FarmSim is played by two people, one per device. You share one field, one water reserve and one harvest, but you do not have the same tools. Talk to each other."
	_back_button.grab_focus()


func _on_back_pressed() -> void:
	SessionController.leave_instructions()
