extends CanvasLayer
## Shown on both devices when the LAN link drops in the middle of a session.
##
## The game is frozen underneath (so the season clock and the crops wait too)
## and the pair sees how long the link has been down. The host can stop waiting
## and keep what was recorded; the client can give up and leave. Otherwise it
## closes by itself the moment the other player is back.
##
## SessionController adds one of these to the root on demand and reuses it.

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const LanDiscovery := preload("res://scripts/net/lan_discovery.gd")
const THEME := preload("res://assets/ui/farm_sim_theme.tres")

var _is_host := false
## Host only: advertises the paused session on the LAN as "Rejoin", so a player
## whose app was closed can find it again under Find games.
var _beacon: Node = null
var _was_paused := false
var _open := false

var _title: Label
var _message: Label
var _timer: Label
var _button: Button


func _init() -> void:
	layer = 60
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
	shade.color = Color(0.03, 0.06, 0.04, 0.78)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	card.custom_minimum_size = Vector2(560, 0)
	center.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)

	_title = Label.new()
	_title.theme_type_variation = &"Title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)

	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.custom_minimum_size = Vector2(500, 0)
	_message.add_theme_font_size_override("font_size", 20)
	box.add_child(_message)

	_timer = Label.new()
	_timer.theme_type_variation = &"Display"
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer.add_theme_color_override("font_color", UiKit.COL_ACCENT)
	box.add_child(_timer)

	_button = Button.new()
	_button.custom_minimum_size = Vector2(320, 64)
	_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_button.theme_type_variation = &"DangerButton"
	_button.pressed.connect(_on_button_pressed)
	box.add_child(_button)


## `host` true: this device is waiting for Player 2. False: this device is
## Player 2, trying to get back to the host.
func open(reason: String, host: bool) -> void:
	_is_host = host
	if not _open:
		_was_paused = get_tree().paused
	_open = true
	visible = true
	get_tree().paused = true
	_title.text = "Connection lost"
	if host:
		_message.text = "%s The game is paused until they reconnect - their device " % reason \
			+ "rejoins by itself. They can also re-open FarmSim and pick your farm again."
		_button.text = "Stop waiting and save"
		if _beacon == null:
			_beacon = LanDiscovery.new()
			add_child(_beacon)
		_beacon.start_broadcasting()
	else:
		_message.text = "%s Trying to get back in - the game carries on from where " % reason \
			+ "you left off as soon as the host can be reached."
		_button.text = "Leave the session"
	_refresh_timer()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	if _beacon != null:
		_beacon.stop()
	get_tree().paused = _was_paused


func is_open() -> bool:
	return _open


func _process(_delta: float) -> void:
	if _open:
		_refresh_timer()


func _refresh_timer() -> void:
	var seconds := int(Net.seconds_lost())
	var clock := "%d:%02d" % [seconds / 60, seconds % 60]
	if _is_host:
		_timer.text = "Waiting for Player 2...  %s" % clock
	else:
		_timer.text = "Reconnecting...  %s  (attempt %d)" % [clock, maxi(Net.reconnect_attempts, 1)]


func _on_button_pressed() -> void:
	if _is_host:
		SessionController.give_up_waiting()
	else:
		SessionController.give_up_reconnecting()
