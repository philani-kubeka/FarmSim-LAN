extends CanvasLayer
## BombSquad-style touch controls for the phone build.
##
## Left half of the screen: a floating joystick. Put a thumb down anywhere there
## and the stick appears under it; drag to walk. When nobody is touching it, a
## faint ring sits in the bottom-left corner so players know where to reach.
##
## Bottom-right: one big round button per tool the player carries, laid out in a
## diamond like BombSquad's punch / jump / bomb / grab. A solo farmer carries six
## tools: the planter's four stay in the diamond and the monitor's two (Scout,
## Treat) sit as two slightly smaller buttons above it, top right. Tapping a button picks
## up that tool and uses it on the tile underfoot in one go, so there is no
## "change tool" step on a phone. The tool in hand has a white ring.
##
## Top-right: a pause button.
##
## Movement is fed into the same input actions the keyboard uses
## (Input.action_press with an analogue strength), so the player script, the
## LAN code and the research log all see exactly what they see on a computer.
## The farm adds this layer only when Config.is_mobile().

const AssetLibrary := preload("res://scripts/farm/asset_library.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")

## Joystick geometry, in layout pixels.
const STICK_RADIUS := 92.0
const KNOB_RADIUS := 40.0
const STICK_MARGIN := 34.0
const DEADZONE := 0.18
## Share of the screen width, from the left, that starts the joystick.
const STICK_ZONE := 0.45

## Action buttons.
const BUTTON_RADIUS := 50.0
const BUTTON_SPREAD := 96.0
const BUTTON_MARGIN := 26.0
## Touches a little outside a button still count; thumbs are not precise.
const HIT_SLOP := 1.18

const PAUSE_SIZE := 68.0

## One colour per diamond position, as in BombSquad: left, bottom, right, top.
const SLOT_COLOURS := [
	Color("e8b23c"), Color("5cae4a"), Color("d0533f"), Color("4a8fd0"),
	Color("9a6fd0"), Color("2fa79a"),
]
## The two extra buttons above the diamond (solo play): left and right of
## centre, a couple of spacings up.
const EXTRA_OFFSETS := [Vector2(-0.62, -2.2), Vector2(0.62, -2.2)]
const EXTRA_RADIUS := 42.0
## Diamond positions relative to the cluster centre: left, bottom, right, top.
const SLOT_OFFSETS := [
	Vector2(-1, 0), Vector2(0, 1), Vector2(1, 0), Vector2(0, -1),
]

signal pause_pressed

var player: Node = null

@onready var _canvas: Control = $Canvas
@onready var _pause_button: Button = $Canvas/PauseButton

var _stick_touch := -99
var _stick_base := Vector2.ZERO
var _stick_vector := Vector2.ZERO
## touch index -> tool slot it went down on
var _button_touches := {}
var _flash := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _icons: Array = []


func _ready() -> void:
	layer = 5
	_canvas.draw.connect(_on_canvas_draw)
	_pause_button.pressed.connect(func() -> void: pause_pressed.emit())
	get_viewport().size_changed.connect(_canvas.queue_redraw)


## Hands the controls the player they drive (this device's player).
func bind(target: Node) -> void:
	player = target
	_icons.clear()
	for tool_id in _tools():
		_icons.append(AssetLibrary.texture(AssetLibrary.tool_key(tool_id)))
	if player != null and player.has_signal("tool_changed"):
		player.tool_changed.connect(func(_p: Node, _t: int) -> void: _canvas.queue_redraw())
	if is_node_ready():
		_canvas.queue_redraw()


func _tools() -> Array:
	if player == null:
		return []
	return (player.tools as Array).slice(0, 4 + EXTRA_OFFSETS.size())


func _screen_size() -> Vector2:
	return _canvas.size


# ----------------------------------------------------------------- layout --

func stick_rest_centre() -> Vector2:
	var size := _screen_size()
	return Vector2(STICK_MARGIN + STICK_RADIUS, size.y - STICK_MARGIN - STICK_RADIUS)


func cluster_centre() -> Vector2:
	var size := _screen_size()
	var reach := BUTTON_SPREAD + BUTTON_RADIUS + BUTTON_MARGIN
	return Vector2(size.x - reach, size.y - reach)


func button_centre(slot: int) -> Vector2:
	if slot >= SLOT_OFFSETS.size():
		return cluster_centre() + EXTRA_OFFSETS[slot - SLOT_OFFSETS.size()] * BUTTON_SPREAD
	return cluster_centre() + SLOT_OFFSETS[slot] * BUTTON_SPREAD


func button_radius(slot: int) -> float:
	return EXTRA_RADIUS if slot >= SLOT_OFFSETS.size() else BUTTON_RADIUS


## Everything the controls cover, for the layout test.
func covered_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var c := stick_rest_centre()
	rects.append(Rect2(c - Vector2.ONE * STICK_RADIUS, Vector2.ONE * STICK_RADIUS * 2.0))
	for slot in range(_tools().size()):
		var b := button_centre(slot)
		var r := button_radius(slot)
		rects.append(Rect2(b - Vector2.ONE * r, Vector2.ONE * r * 2.0))
	return rects


# ------------------------------------------------------------------ input --

func _input(event: InputEvent) -> void:
	if player == null:
		return
	var preview := Config.is_touch_preview()
	if event is InputEventScreenTouch:
		_on_touch(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_on_drag(event.index, event.position)
	elif preview and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_on_touch(-1, event.position, event.pressed)
	elif preview and event is InputEventMouseMotion and _stick_touch == -1:
		_on_drag(-1, event.position)


## Event positions reaching _input are already in the stretched layout space the
## controls are drawn in, whatever the phone's real resolution is.
func _on_touch(index: int, at: Vector2, pressed: bool) -> void:
	if pressed:
		if _pause_rect().has_point(at):
			return  # the pause Button handles it
		var slot := _slot_at(at)
		if slot >= 0:
			_button_touches[index] = slot
			_press_slot(slot)
			get_viewport().set_input_as_handled()
			return
		if _stick_touch == -99 and at.x < _screen_size().x * STICK_ZONE:
			_stick_touch = index
			_stick_base = _clamp_base(at)
			_set_stick(at)
			get_viewport().set_input_as_handled()
	else:
		_button_touches.erase(index)
		if index == _stick_touch:
			_stick_touch = -99
			_set_stick(_stick_base)
			get_viewport().set_input_as_handled()


func _on_drag(index: int, at: Vector2) -> void:
	if index != _stick_touch:
		return
	_set_stick(at)
	get_viewport().set_input_as_handled()


func _clamp_base(at: Vector2) -> Vector2:
	var size := _screen_size()
	return Vector2(clampf(at.x, STICK_RADIUS + 8.0, size.x - STICK_RADIUS - 8.0),
		clampf(at.y, STICK_RADIUS + 8.0, size.y - STICK_RADIUS - 8.0))


func _set_stick(at: Vector2) -> void:
	var raw := (at - _stick_base) / STICK_RADIUS
	_stick_vector = raw.limit_length(1.0)
	_feed_actions(_stick_vector if _stick_vector.length() > DEADZONE else Vector2.ZERO)
	_canvas.queue_redraw()


## The joystick drives the very same actions the keyboard does.
func _feed_actions(vector: Vector2) -> void:
	var prefix: String = player.action_prefix()
	_feed(prefix + "left", maxf(-vector.x, 0.0))
	_feed(prefix + "right", maxf(vector.x, 0.0))
	_feed(prefix + "up", maxf(-vector.y, 0.0))
	_feed(prefix + "down", maxf(vector.y, 0.0))


func _feed(action: String, strength: float) -> void:
	if not InputMap.has_action(action):
		return
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _slot_at(at: Vector2) -> int:
	for slot in range(_tools().size()):
		if at.distance_to(button_centre(slot)) <= button_radius(slot) * HIT_SLOP:
			return slot
	return -1


## Pick up that tool (if it is not already in hand) and use it.
func _press_slot(slot: int) -> void:
	var tools := _tools()
	if slot >= tools.size():
		return
	var tool_id: int = tools[slot]
	if player.current_tool() != tool_id:
		player.select_tool(tool_id)
	player.try_use()
	_flash[slot] = 1.0
	_canvas.queue_redraw()


func _pause_rect() -> Rect2:
	return _pause_button.get_rect().grow(8.0)


func _process(delta: float) -> void:
	var dirty := false
	for slot in range(_flash.size()):
		if _flash[slot] > 0.0:
			_flash[slot] = maxf(_flash[slot] - delta * 4.0, 0.0)
			dirty = true
	if dirty:
		_canvas.queue_redraw()


func _exit_tree() -> void:
	if player != null and is_instance_valid(player):
		_feed_actions(Vector2.ZERO)


# ------------------------------------------------------------------ draw --

func _on_canvas_draw() -> void:
	_draw_stick()
	_draw_buttons()


func _draw_stick() -> void:
	var active := _stick_touch != -99
	var base := _stick_base if active else stick_rest_centre()
	var knob := base + _stick_vector * STICK_RADIUS if active else base
	var alpha := 0.85 if active else 0.45
	_canvas.draw_circle(base, STICK_RADIUS, Color(0, 0, 0, 0.28 * alpha))
	_canvas.draw_arc(base, STICK_RADIUS, 0.0, TAU, 64, Color(1, 1, 1, 0.55 * alpha), 4.0, true)
	_canvas.draw_circle(knob + Vector2(0, 4), KNOB_RADIUS, Color(0, 0, 0, 0.3 * alpha))
	_canvas.draw_circle(knob, KNOB_RADIUS, Color(0.93, 0.95, 0.9, 0.9 * alpha))
	_canvas.draw_arc(knob, KNOB_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, alpha), 3.0, true)


func _draw_buttons() -> void:
	var tools := _tools()
	var font := _canvas.get_theme_font("font", "Display")
	var current: int = player.current_tool() if player != null else -1
	for slot in range(tools.size()):
		var centre := button_centre(slot)
		var colour: Color = SLOT_COLOURS[slot]
		var flash: float = _flash[slot]
		var radius := button_radius(slot) * (1.0 + 0.08 * flash)
		var in_hand: bool = tools[slot] == current
		# drop shadow and a darker rim underneath, for the chunky "raised" look
		_canvas.draw_circle(centre + Vector2(0, 6), radius, Color(0, 0, 0, 0.35))
		_canvas.draw_circle(centre + Vector2(0, 3), radius, colour.darkened(0.35))
		_canvas.draw_circle(centre, radius, colour.lerp(Color.WHITE, 0.35 * flash))
		_canvas.draw_circle(centre + Vector2(0, -radius * 0.35), radius * 0.62,
			Color(1, 1, 1, 0.12))
		if in_hand:
			_canvas.draw_arc(centre, radius + 5.0, 0.0, TAU, 64, Color.WHITE, 5.0, true)
		if slot < _icons.size() and _icons[slot] != null:
			var icon: Texture2D = _icons[slot]
			var icon_size := Vector2(48, 48) * (button_radius(slot) / BUTTON_RADIUS)
			_canvas.draw_texture_rect(icon, Rect2(centre - icon_size * 0.5 - Vector2(0, 10), icon_size), false)
		if font != null:
			var text := "Treat" if tools[slot] == Config.Tool.TREAT \
				else Config.tool_label(tools[slot]).split(" ")[0]
			var size := 15
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x
			var at := centre + Vector2(-width * 0.5, radius * 0.62)
			_canvas.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4,
				Color(0, 0, 0, 0.6))
			_canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)
