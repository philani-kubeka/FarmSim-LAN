extends PanelContainer
## One player's role, spelled out: what they are responsible for, which keys they
## use, and which tools they carry.
##
## The same card appears on the instructions screen, on each scenario briefing
## and on the pause overlay, so the two roles are described identically wherever
## a player looks them up. Drop the scene into a screen, set Player Index and
## Accent in the Inspector, and it fills itself in from GameState and Config.

## 0 for Player 1, 1 for Player 2.
@export var player_index: int = 0
## Colour for the player's name. Use UiKit.COL_PLAYER_1 / COL_PLAYER_2.
@export var accent: Color = Color(0.8862745, 0.69411767, 0.23529412, 1)
## The instructions screen wants a larger name than the briefing does.
@export var name_font_size: int = 18

@onready var _name: Label = $Box/PlayerName
@onready var _description: Label = $Box/Description
@onready var _move: Label = $Box/Move
@onready var _use: Label = $Box/Use
@onready var _tools: Label = $Box/Tools


func _ready() -> void:
	refresh()


## Re-reads the role from GameState. Call it after the roles are swapped.
func refresh() -> void:
	var role := GameState.role_for_player(player_index)
	var prefix := "p%d_" % (player_index + 1)
	if GameState.single_player and not Net.is_online():
		# Solo: one card, and the one-player key set.
		visible = player_index == 0
		prefix = "net_"

	_name.add_theme_font_size_override("font_size", name_font_size)
	_name.add_theme_color_override("font_color", accent)
	_name.text = "Player %d - %s" % [player_index + 1, Config.role_label(role)]
	if role == "solo":
		_name.text = "You - %s" % Config.role_label(role)

	_description.text = String(Config.ROLE_DESCRIPTIONS.get(role, ""))

	if Config.is_mobile():
		_move.text = "Move: drag the joystick on the left of the screen"
		_use.text = "Use a tool: tap its round button on the right"
		if role == "solo":
			_use.text = "Use a tool: tap its round button on the right (Scout and Treat sit above the others)"
		_tools.text = "Carries: " + ", ".join(_tool_names(role))
		return

	_move.text = "Move: %s %s %s %s" % [
		InputSetup.describe(prefix + "up"),
		InputSetup.describe(prefix + "left"),
		InputSetup.describe(prefix + "down"),
		InputSetup.describe(prefix + "right"),
	]
	_use.text = "Use tool: %s     Change tool: %s" % [
		InputSetup.describe(prefix + "use"),
		InputSetup.describe(prefix + "cycle_tool"),
	]
	if prefix == "net_":
		_move.text = "Move: W A S D or the arrow keys"
		_use.text = "Use tool: E or Space     Change tool: Q or Shift"

	_tools.text = "Carries: " + ", ".join(_tool_names(role))


func _tool_names(role: String) -> Array[String]:
	var names: Array[String] = []
	for tool_id in (Config.ROLE_TOOLS.get(role, []) as Array):
		names.append(Config.tool_label(tool_id))
	return names
