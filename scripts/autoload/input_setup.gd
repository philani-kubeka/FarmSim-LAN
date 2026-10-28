extends Node
## Registers the two-player control scheme in Godot's InputMap at startup.
##
## Design note (recorded in documentation/DEVELOPMENT_LOG.md): the actions are
## built here in code with named Key constants instead of being stored in
## project.godot. Doing it this way keeps the binding table readable, keeps it
## under version control as plain source, and lets the automated test suite
## assert that every action the gameplay code relies on actually exists.

## action name -> array of physical key codes bound to it.
const BINDINGS := {
	# --- Player 1: left hand, WASD ---
	"p1_up": [KEY_W],
	"p1_down": [KEY_S],
	"p1_left": [KEY_A],
	"p1_right": [KEY_D],
	"p1_use": [KEY_E],
	"p1_cycle_tool": [KEY_Q],

	# --- Player 2: right hand, arrow keys ---
	# Two alternatives are bound for each action so the prototype works on
	# laptops without a numeric keypad.
	"p2_up": [KEY_UP],
	"p2_down": [KEY_DOWN],
	"p2_left": [KEY_LEFT],
	"p2_right": [KEY_RIGHT],
	"p2_use": [KEY_KP_0, KEY_CTRL],
	"p2_cycle_tool": [KEY_KP_1, KEY_SHIFT],

	# --- LAN port: one player per computer, so either hand works ---
	"net_up": [KEY_W, KEY_UP],
	"net_down": [KEY_S, KEY_DOWN],
	"net_left": [KEY_A, KEY_LEFT],
	"net_right": [KEY_D, KEY_RIGHT],
	"net_use": [KEY_E, KEY_SPACE],
	"net_cycle_tool": [KEY_Q, KEY_SHIFT],

	# --- Shared / system ---
	"ui_pause": [KEY_ESCAPE],
	"debug_skip": [KEY_F9],
}

## Actions the gameplay code requires. Used by the test suite.
const REQUIRED_ACTIONS := [
	"p1_up", "p1_down", "p1_left", "p1_right", "p1_use", "p1_cycle_tool",
	"p2_up", "p2_down", "p2_left", "p2_right", "p2_use", "p2_cycle_tool",
	"ui_pause",
]


func _ready() -> void:
	register_actions()


## Idempotent: safe to call again from tests.
func register_actions() -> void:
	for action_name in BINDINGS.keys():
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name, 0.2)
		InputMap.action_erase_events(action_name)
		for keycode in BINDINGS[action_name]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action_name, event)


## Human-readable binding summary, used by the in-game instructions screen.
func describe(action_name: String) -> String:
	var parts: Array[String] = []
	for keycode in BINDINGS.get(action_name, []):
		parts.append(OS.get_keycode_string(keycode))
	return " or ".join(parts)
