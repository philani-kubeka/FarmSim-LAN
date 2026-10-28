extends Control
## The "Play Together" lobby: host a LAN game, or find one and join it.
##
## The screen is a rail of three tabs on the left and one card on the right.
##
## * Host a game   - name the farm and open it on this device (Player 1).
## * Find games    - every FarmSim host heard on the network in the last few
##                   seconds, one big row each. Tap a row to join.
## * Join by address - for networks that drop broadcast traffic (many school and
##                   campus networks do).
##
## As soon as this device is hosting or has joined, the card switches to the
## lobby: two player seats, the host's address, and Start / Leave. The rail is
## locked while you are in a lobby, so there is only ever one thing to do next.
##
## The layout is multiplayer_menu.tscn; this script only wires it up. It works
## the same on a phone and on a computer.

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const LAYOUT := "Page/PageScroll/Layout"
const PAGES := LAYOUT + "/Body/Card/Pages"

enum Page { HOST, FIND, ADDRESS, LOBBY }

@onready var _notice: Label = get_node(LAYOUT + "/Notice")
@onready var _back_button: Button = get_node(LAYOUT + "/Header/BackButton")
@onready var _tagline: Label = get_node(LAYOUT + "/Header/Titles/Tagline")
@onready var _discovery: Node = $LanDiscovery

@onready var _host_tab: Button = get_node(LAYOUT + "/Body/Rail/HostTab")
@onready var _find_tab: Button = get_node(LAYOUT + "/Body/Rail/FindTab")
@onready var _address_tab: Button = get_node(LAYOUT + "/Body/Rail/AddressTab")
@onready var _device_address: Label = get_node(LAYOUT + "/Body/Rail/DeviceAddress")

@onready var _pages := {
	Page.HOST: get_node(PAGES + "/HostPage"),
	Page.FIND: get_node(PAGES + "/FindPage"),
	Page.ADDRESS: get_node(PAGES + "/AddressPage"),
	Page.LOBBY: get_node(PAGES + "/LobbyPage"),
}

@onready var _host_name: LineEdit = get_node(PAGES + "/HostPage/NameRow/HostName")
@onready var _preview_slots: Array = [
	get_node(PAGES + "/HostPage/HostPreview/Slot1"), get_node(PAGES + "/HostPage/HostPreview/Slot2"),
]
@onready var _host_button: Button = get_node(PAGES + "/HostPage/HostButton")

@onready var _searching: Label = get_node(PAGES + "/FindPage/FindHeader/Searching")
@onready var _game_list: VBoxContainer = get_node(PAGES + "/FindPage/GameScroll/GameList")
@onready var _empty_state: Label = get_node(PAGES + "/FindPage/GameScroll/GameList/EmptyState")

@onready var _address: LineEdit = get_node(PAGES + "/AddressPage/Address")
@onready var _join_address: Button = get_node(PAGES + "/AddressPage/JoinAddressButton")

@onready var _lobby_name: Label = get_node(PAGES + "/LobbyPage/LobbyHeader/LobbyName")
@onready var _lobby_address: Label = get_node(PAGES + "/LobbyPage/LobbyHeader/LobbyAddress")
@onready var _slots: Array = [
	get_node(PAGES + "/LobbyPage/Slots/Slot1"), get_node(PAGES + "/LobbyPage/Slots/Slot2"),
]
@onready var _lobby_status: Label = get_node(PAGES + "/LobbyPage/LobbyStatus")
@onready var _leave_button: Button = get_node(PAGES + "/LobbyPage/LobbyButtons/LeaveButton")
@onready var _start_button: Button = get_node(PAGES + "/LobbyPage/LobbyButtons/StartButton")

var _hosts: Array = []
## The tab the player picked. The lobby page overrides it while online.
var _chosen_page: int = Page.HOST
## Name of the game this device joined, for the client's lobby header.
var _joined_name := ""
var _dots := 0.0


func _ready() -> void:
	var group := ButtonGroup.new()
	for tab in [_host_tab, _find_tab, _address_tab]:
		tab.button_group = group
	_host_tab.pressed.connect(func() -> void: _select_tab(Page.HOST))
	_find_tab.pressed.connect(func() -> void: _select_tab(Page.FIND))
	_address_tab.pressed.connect(func() -> void: _select_tab(Page.ADDRESS))

	_host_name.text = Net.host_name if not Net.host_name.is_empty() else Net.default_host_name()
	_tagline.text = "Two devices on the same network, one farmer each. Phones and computers can play together."

	_host_button.pressed.connect(_on_host_pressed)
	_host_name.text_submitted.connect(func(_text: String) -> void: _on_host_pressed())
	_start_button.pressed.connect(_on_start_pressed)
	_leave_button.pressed.connect(_on_leave_pressed)
	_join_address.pressed.connect(_on_join_address_pressed)
	_address.set_meta(&"keyboard_reveal", _join_address)
	_host_name.set_meta(&"keyboard_reveal", _host_button)
	_address.text_submitted.connect(func(_text: String) -> void: _on_join_address_pressed())
	_back_button.pressed.connect(_on_back_pressed)

	_discovery.hosts_changed.connect(_on_hosts_changed)
	# Bound methods, not lambdas: they disconnect themselves when this screen is
	# freed, and Net outlives every screen.
	Net.peer_joined.connect(_on_net_changed)
	Net.peer_left.connect(_on_net_changed)
	Net.joined.connect(_on_net_changed)
	Net.status_changed.connect(_on_net_changed)
	Net.connection_failed.connect(_on_connection_failed)
	Net.session_lost.connect(_on_session_lost)

	if not SessionController.notice.is_empty():
		_show_notice(SessionController.notice, UiKit.COL_WARN)
		SessionController.notice = ""
	else:
		_show_notice("", UiKit.COL_TEXT_DIM)

	if Config.is_mobile():
		_apply_phone_layout()
	_preview_slots[0].show_seat(0, true, "You", "Player 1 - host", UiKit.COL_TEXT_DIM)
	_preview_slots[1].show_seat(1, false, "Your partner", "Joins from their device")

	# Phones mostly join; computers mostly host.
	_select_tab(Page.FIND if Config.is_mobile() else Page.HOST)
	if not Config.is_mobile():
		_host_button.grab_focus()


func _process(delta: float) -> void:
	if not _searching.is_visible_in_tree():
		return
	_dots += delta * 2.5
	_searching.text = "Searching" + ".".repeat(1 + int(_dots) % 3)


# ---------------------------------------------------------------- actions ---

## Shows one of the three offline pages. Ignored while in a lobby.
func _select_tab(page: int) -> void:
	_chosen_page = page
	match page:
		Page.HOST: _host_tab.button_pressed = true
		Page.FIND: _find_tab.button_pressed = true
		Page.ADDRESS: _address_tab.button_pressed = true
	_update_discovery()
	_refresh()


func _on_host_pressed() -> void:
	if Net.is_online():
		return
	if Net.host(_host_name.text) == OK:
		_show_notice("", UiKit.COL_TEXT_DIM)
	_update_discovery()
	_refresh()


func _on_start_pressed() -> void:
	if Net.is_host() and Net.is_ready():
		_discovery.stop()
		SessionController.start_new_session()


func _join_host(info: Dictionary) -> void:
	var rejoin := bool(info.get("rejoin", false))
	if not rejoin and (bool(info.get("in_session", false)) \
			or int(info.get("players", 1)) >= int(info.get("max", 2))):
		_show_notice("That farm is full or already playing.", UiKit.COL_WARN)
		return
	_joined_name = String(info.get("name", ""))
	_join(String(info.get("ip", "")), int(info.get("port", Net.GAME_PORT)))


func _on_join_address_pressed() -> void:
	var text := _address.text.strip_edges()
	if text.is_empty():
		_show_notice("Type the host's address first - it is shown on their screen.", UiKit.COL_WARN)
		return
	var port := Net.GAME_PORT
	if ":" in text:
		var parts := text.split(":")
		text = parts[0]
		port = int(parts[1]) if parts[1].is_valid_int() else Net.GAME_PORT
	_joined_name = ""
	_join(text, port)


func _join(address: String, port: int) -> void:
	_discovery.stop()
	if Net.join(address, port) == OK:
		_show_notice("", UiKit.COL_TEXT_DIM)
	if _joined_name.is_empty():
		_joined_name = address
	_refresh()


func _on_leave_pressed() -> void:
	var was_hosting := Net.is_host()
	Net.leave()
	_show_notice("Stopped hosting." if was_hosting else "Left the game.", UiKit.COL_TEXT_DIM)
	_update_discovery()
	_refresh()


func _on_back_pressed() -> void:
	Net.leave()
	SessionController.goto_main_menu()


func _on_net_changed(_value: Variant = null) -> void:
	_refresh()


func _on_session_lost(reason: String) -> void:
	_show_notice(reason, UiKit.COL_WARN)
	_update_discovery()
	_refresh()


func _on_connection_failed(reason: String) -> void:
	_show_notice(reason, UiKit.COL_BAD)
	_update_discovery()
	_refresh()


func _on_hosts_changed(hosts: Array) -> void:
	_hosts = hosts
	_rebuild_game_list()
	_refresh()


# ---------------------------------------------------------------- display ---

## Broadcast while hosting, listen while looking for a game, otherwise neither.
func _update_discovery() -> void:
	if Net.is_host():
		if _discovery.mode != _discovery.Mode.BROADCASTING:
			_discovery.start_broadcasting()
	elif not Net.is_online() and _chosen_page == Page.FIND:
		if _discovery.mode != _discovery.Mode.LISTENING:
			if _discovery.start_listening() != OK:
				_show_notice("Could not listen for games on this device (UDP %d is in use). "
					% _discovery.DISCOVERY_PORT + "You can still join by address.", UiKit.COL_WARN)
	else:
		_discovery.stop()


## One big tappable row per discovered farm.
func _rebuild_game_list() -> void:
	for child in _game_list.get_children():
		if child != _empty_state:
			child.queue_free()
	_empty_state.visible = _hosts.is_empty()
	for info in _hosts:
		_game_list.add_child(_make_game_row(info))


func _make_game_row(info: Dictionary) -> Button:
	var rejoin := bool(info.get("rejoin", false))
	var full := not rejoin and (bool(info.get("in_session", false)) \
		or int(info.get("players", 1)) >= int(info.get("max", 2)))
	var row := Button.new()
	row.theme_type_variation = &"GameRow"
	row.custom_minimum_size = Vector2(0, 72)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.disabled = full
	row.focus_mode = Control.FOCUS_ALL
	row.pressed.connect(_join_host.bind(info))

	var box := HBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 18
	box.offset_right = -14
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 12)
	row.add_child(box)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 0)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(text)

	var name_label := Label.new()
	name_label.theme_type_variation = &"Display"
	name_label.text = String(info.get("name", "FarmSim"))
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	text.add_child(name_label)

	var ip_label := Label.new()
	ip_label.theme_type_variation = &"Dim"
	ip_label.text = String(info.get("ip", ""))
	text.add_child(ip_label)

	var pill := Label.new()
	pill.theme_type_variation = &"Pill"
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if rejoin:
		pill.text = "Waiting for you"
		pill.add_theme_color_override("font_color", UiKit.COL_ACCENT)
	elif bool(info.get("in_session", false)):
		pill.text = "Playing"
		pill.add_theme_color_override("font_color", UiKit.COL_WARN)
	else:
		pill.text = "%d/%d farmers" % [int(info.get("players", 1)), int(info.get("max", 2))]
		pill.add_theme_color_override("font_color", UiKit.COL_TEXT_DIM if full else UiKit.COL_GOOD)
	box.add_child(pill)

	if not full:
		var join := Label.new()
		join.theme_type_variation = &"Display"
		join.text = "Rejoin >" if rejoin else "Join >"
		join.add_theme_color_override("font_color", UiKit.COL_ACCENT)
		join.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(join)
	return row


## Redraws the screen, then has Config re-fit it to the phone: switching tab or
## joining changes how tall the page is.
func _refresh() -> void:
	_refresh_view()
	Config.refit()


func _refresh_view() -> void:
	var online := Net.is_online()
	var hosting := Net.is_host()
	var joined := Net.is_client()

	var page: int = Page.LOBBY if online else _chosen_page
	for key in _pages.keys():
		(_pages[key] as Control).visible = key == page
	for tab in [_host_tab, _find_tab, _address_tab]:
		tab.disabled = online

	var addresses := Net.local_addresses()
	_device_address.text = addresses[0] if not addresses.is_empty() else "No network"

	_host_name.editable = not online
	_address.editable = not online
	_join_address.disabled = online
	_searching.visible = page == Page.FIND
	_empty_state.visible = _hosts.is_empty()

	if not online:
		return

	# --- the lobby ---
	var ready := Net.is_ready()
	if hosting:
		_lobby_name.text = Net.host_name
		_lobby_address.text = "Join at %s" % (addresses[0] if not addresses.is_empty() else "?")
		_lobby_address.visible = true
		_slots[0].show_seat(0, true, "You", "Host", UiKit.COL_GOOD)
		if ready:
			_slots[1].show_seat(1, true, "Partner", "Connected", UiKit.COL_GOOD)
		else:
			_slots[1].show_seat(1, false, "Open seat", "Waiting to join...")
		_lobby_status.text = "Everyone's here! Press Start session when you are both ready." \
			if ready else "Waiting for Player 2. They should open Find games on their device."
		_lobby_status.add_theme_color_override("font_color", UiKit.COL_GOOD if ready else UiKit.COL_TEXT)
		_leave_button.text = "Stop hosting"
		_start_button.visible = true
		_start_button.disabled = not ready
	else:
		_lobby_name.text = _joined_name if not _joined_name.is_empty() else "Joining..."
		_lobby_address.visible = false
		if ready:
			_slots[0].show_seat(0, true, "Host", "Connected", UiKit.COL_GOOD)
			_slots[1].show_seat(1, true, "You", "Ready", UiKit.COL_GOOD)
			_lobby_status.text = "You're in as Player 2. Waiting for the host to start..."
			_lobby_status.add_theme_color_override("font_color", UiKit.COL_GOOD)
		else:
			_slots[0].show_seat(0, false, "Host", "Connecting...")
			_slots[1].show_seat(1, true, "You", "Connecting...", UiKit.COL_TEXT_DIM)
			_lobby_status.text = "Connecting..."
			_lobby_status.add_theme_color_override("font_color", UiKit.COL_TEXT)
		_leave_button.text = "Leave"
		_start_button.visible = false
	if joined or hosting:
		_start_button.get_parent().visible = true


func _show_notice(text: String, colour: Color) -> void:
	_notice.text = text
	_notice.visible = not text.is_empty()
	_notice.add_theme_color_override("font_color", colour)
	Config.refit()


# ------------------------------------------------------------ phone layout --

## Bigger thumb targets and less reading on a phone held sideways. The tab
## names already say what each page is, so the page headings and blurbs go;
## the device address shows in the lobby once you host, so it goes from the
## rail. What is left is drawn as large as the screen allows (Config fits it).
const PHONE_TAB_HEIGHT := 78.0
const PHONE_ACTION_HEIGHT := 84.0
const PHONE_FONT_BOOST := 4


func _apply_phone_layout() -> void:
	_tagline.visible = false
	for path in ["/HostPage/Heading", "/HostPage/Blurb", "/FindPage/FindHint",
			"/AddressPage/Heading", "/AddressPage/AddressSpacer"]:
		(get_node(PAGES + path) as Control).visible = false
	for path in ["/Body/Rail/DeviceLabel", "/Body/Rail/DeviceAddress"]:
		(get_node(LAYOUT + path) as Control).visible = false
	for slot in _slots + _preview_slots:
		slot.custom_minimum_size.y = 96
	for tab in [_host_tab, _find_tab, _address_tab]:
		tab.custom_minimum_size.y = PHONE_TAB_HEIGHT
		_boost_font(tab)
	_back_button.custom_minimum_size = Vector2(170, 70)
	_boost_font(_back_button)
	for button in [_host_button, _join_address, _start_button, _leave_button]:
		button.custom_minimum_size.y = PHONE_ACTION_HEIGHT
		button.custom_minimum_size.x = maxf(button.custom_minimum_size.x, 280.0)
		_boost_font(button)
	_host_name.custom_minimum_size.y = 62
	_address.custom_minimum_size.y = 62
	for field in [_host_name, _address]:
		_boost_font(field)
	(get_node(PAGES + "/HostPage/NameRow/NameLabel") as Label).text = "Name"


func _boost_font(control: Control) -> void:
	var size := control.get_theme_font_size("font_size")
	control.add_theme_font_size_override("font_size", size + PHONE_FONT_BOOST)
