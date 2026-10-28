extends Control
## Assigns the two complementary roles before the session starts. No names, no
## accounts: participants are "Player 1" and "Player 2" and the session is
## identified only by a random id.
##
## The layout is player_setup.tscn. This script fills the two authored cards in
## from the current role assignment and refills them when the roles are swapped.

const CONTENT := "Page/PageScroll/Row/PageContent"
const UiKit := preload("res://scripts/ui/ui_kit.gd")

@onready var _session_id: Label = get_node(CONTENT + "/SessionId")
@onready var _swap_button: Button = get_node(CONTENT + "/SwapButton")
@onready var _how_button: Button = get_node(CONTENT + "/Buttons/HowButton")
@onready var _confirm_button: Button = get_node(CONTENT + "/Buttons/ConfirmButton")
@onready var _cards: Array[Node] = [
	get_node(CONTENT + "/Players/Player1/Box"),
	get_node(CONTENT + "/Players/Player2/Box"),
]


func _ready() -> void:
	_session_id.text = "Anonymous session id: %s" % GameState.session_id
	_swap_button.pressed.connect(_on_swap_pressed)
	_how_button.pressed.connect(_on_how_pressed)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	# A way back out before anything starts.
	var back := Button.new()
	back.name = "BackButton"
	back.text = "< Back"
	back.custom_minimum_size = Vector2(150, 44)
	back.pressed.connect(_on_back_pressed)
	var row := _confirm_button.get_parent()
	row.add_child(back)
	row.move_child(back, 0)
	_refresh_all()
	if Net.is_online():
		(get_node(CONTENT + "/Intro") as Label).text = "One farmer per device. Check who has which role - " \
			+ "the host can swap them - then the host confirms. The roles are complementary: " \
			+ "neither player can finish a season alone."
	if Net.is_client():
		# The host runs the session; Player 2 follows along.
		_swap_button.disabled = true
		_confirm_button.disabled = true
		_confirm_button.text = "Waiting for host..."
		_how_button.grab_focus()
	else:
		_confirm_button.grab_focus()


func _refresh_all() -> void:
	for index in range(_cards.size()):
		_refresh(index)


func _refresh(player_index: int) -> void:
	var box: Node = _cards[player_index]
	var role := GameState.role_for_player(player_index)
	var prefix := "p%d_" % (player_index + 1)

	(box.get_node("Role") as Label).text = Config.role_label(role)
	(box.get_node("Description") as Label).text = String(
		Config.ROLE_DESCRIPTIONS.get(role, ""))
	if Net.is_online():
		if player_index == Net.local_player_index:
			(box.get_node("Controls") as Label).text = \
				"You, on this phone.  Joystick to move, tap a tool button to use it" \
				if Config.is_mobile() else \
				"You, on this computer.  Move WASD or arrows   Use E or Space   Change tool Q or Shift"
		else:
			(box.get_node("Controls") as Label).text = "Playing on the other device."
		return
	(box.get_node("Controls") as Label).text = "Move %s%s%s%s   Use %s   Change tool %s" % [
		InputSetup.describe(prefix + "up"),
		InputSetup.describe(prefix + "left"),
		InputSetup.describe(prefix + "down"),
		InputSetup.describe(prefix + "right"),
		InputSetup.describe(prefix + "use"),
		InputSetup.describe(prefix + "cycle_tool"),
	]


func _on_swap_pressed() -> void:
	GameState.swap_roles()
	_refresh_all()
	if Net.is_host():
		Net.send_scene(SessionController.SCENE_PLAYER_SETUP, SessionController.network_state())
	GameplayLogger.log_event("session", "roles_swapped", {
		"player_1_role": GameState.role_for_player(0),
		"player_2_role": GameState.role_for_player(1),
	})


func _on_how_pressed() -> void:
	SessionController.goto_instructions(SessionController.SCENE_PLAYER_SETUP)


func _on_confirm_pressed() -> void:
	SessionController.begin_pre_assessment()



## Back (button or Android gesture): leave before the session starts.
func _on_back_pressed() -> void:
	SessionController.request_exit()
