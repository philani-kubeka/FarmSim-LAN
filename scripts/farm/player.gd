extends CharacterBody2D
## One of the two local players.
##
## The body, its collision shape, the "P1" tag and the carried-tool icon are
## nodes in player.tscn, so the character can be opened and adjusted in the
## editor. setup() only dresses those nodes for the player index and role it is
## given; it creates nothing.
##
## The player owns movement, facing and which tool it is carrying. It owns none
## of the farming rules: when the use key is pressed it emits use_requested and
## the farm hands that to the system responsible for the tool. That keeps the
## shared water reserve and the crop rules in one place instead of duplicated
## across two players.

signal use_requested(player: Node, tool_id: int, tile: Node)
signal tool_changed(player: Node, tool_id: int)

const AssetLibrary := preload("res://scripts/farm/asset_library.gd")

const RADIUS := 13.0

var player_index := 0
var role := "planter"
var tools: Array = []
var tool_index := 0
var facing := Vector2.DOWN
var colour := Color.WHITE

## The field this player acts on. Set by the farm.
var field: Node2D = null

## Test hook: when true, movement uses `test_input` instead of the keyboard.
## Real key handling is untouched, so this does not change how the game plays.
var use_test_input := false
var test_input := Vector2.ZERO

## LAN port. `controlled` is false for the other computer's player: it does not
## read this keyboard and only moves to where the network says it is.
## `net_mode` makes the local player use the "net_" bindings, which accept both
## WASD and the arrow keys, since each computer only has one player on it.
var controlled := true
var net_mode := false
const NET_SEND_INTERVAL := 1.0 / 30.0
const REMOTE_SMOOTHING := 18.0
var _net_send_timer := 0.0
var _remote_target := Vector2.ZERO
var _has_remote_target := false

@onready var _sprite: Sprite2D = $Body
@onready var _tool_icon: Sprite2D = $ToolIcon
@onready var _tag: Label = $Tag

var _target_tile: Node = null


## Called by the farm straight after instantiating the scene, before it is added
## to the tree, so the identity is applied again from _ready().
func setup(index: int, player_role: String, player_colour: Color) -> void:
	player_index = index
	role = player_role
	colour = player_colour
	tools = (Config.ROLE_TOOLS.get(player_role, [Config.Tool.WATER]) as Array).duplicate()
	tool_index = 0
	name = "Player%d" % (index + 1)
	if is_node_ready():
		_apply_identity()


func _ready() -> void:
	_apply_identity()


## Dresses the authored nodes for this player: body sprite, tag text and colour,
## and the icon of the tool currently in hand.
func _apply_identity() -> void:
	_sprite.texture = AssetLibrary.texture("player_%d" % (player_index + 1))
	_tag.text = "P%d" % (player_index + 1)
	_tag.add_theme_color_override("font_color", colour)
	_refresh_tool_icon()


# ------------------------------------------------------------------- tools --

func current_tool() -> int:
	if tools.is_empty():
		return Config.Tool.WATER
	return tools[tool_index % tools.size()]


func cycle_tool() -> int:
	if tools.is_empty():
		return Config.Tool.WATER
	tool_index = (tool_index + 1) % tools.size()
	_refresh_tool_icon()
	tool_changed.emit(self, current_tool())
	return current_tool()


func select_tool(tool_id: int) -> bool:
	var index: int = tools.find(tool_id)
	if index < 0:
		return false
	tool_index = index
	_refresh_tool_icon()
	tool_changed.emit(self, current_tool())
	return true


func _refresh_tool_icon() -> void:
	if _tool_icon == null:
		return
	_tool_icon.texture = AssetLibrary.texture(AssetLibrary.tool_key(current_tool()))


# ---------------------------------------------------------------- movement --

func action_prefix() -> String:
	if net_mode:
		return "net_"
	return "p%d_" % (player_index + 1)


func read_move_input() -> Vector2:
	if use_test_input:
		return test_input.limit_length(1.0)
	var prefix := action_prefix()
	return Input.get_vector(prefix + "left", prefix + "right", prefix + "up", prefix + "down")


func _physics_process(delta: float) -> void:
	if not controlled:
		_follow_remote(delta)
		return
	var direction := read_move_input()
	velocity = direction * Config.PLAYER_SPEED
	if direction.length() > 0.05:
		facing = direction.normalized()
		if absf(direction.x) > 0.1:
			_sprite.flip_h = direction.x < 0.0
	move_and_slide()
	_update_target_tile()
	if net_mode:
		_net_send_timer -= delta
		if _net_send_timer <= 0.0:
			_net_send_timer = NET_SEND_INTERVAL
			Net.send_transform(global_position, facing, _sprite.flip_h)

	if use_test_input:
		return
	var prefix := action_prefix()
	if Input.is_action_just_pressed(prefix + "cycle_tool"):
		cycle_tool()
	if Input.is_action_just_pressed(prefix + "use"):
		try_use()


## The other computer reported where its player is.
func apply_remote_transform(remote_position: Vector2, remote_facing: Vector2, flip: bool) -> void:
	if not _has_remote_target:
		global_position = remote_position
	_remote_target = remote_position
	_has_remote_target = true
	facing = remote_facing
	_sprite.flip_h = flip


func _follow_remote(delta: float) -> void:
	if _has_remote_target:
		var weight := clampf(REMOTE_SMOOTHING * delta, 0.0, 1.0)
		global_position = global_position.lerp(_remote_target, weight)
	_update_target_tile()


# ------------------------------------------------------------------ acting --

func target_tile() -> Node:
	return _target_tile


func _update_target_tile() -> void:
	if field == null:
		return
	var previous := _target_tile
	_target_tile = field.tile_near(global_position, Config.PLAYER_REACH)
	if previous == _target_tile:
		return
	if previous != null and is_instance_valid(previous):
		previous.set_highlighted(false)
	if _target_tile != null:
		_target_tile.set_highlighted(true, Color(colour.r, colour.g, colour.b, 0.22))


## Requests the farm to apply the current tool to the tile underfoot.
func try_use() -> void:
	_update_target_tile()
	use_requested.emit(self, current_tool(), _target_tile)


func describe() -> String:
	return "Player %d (%s)" % [player_index + 1, Config.role_label(role)]
