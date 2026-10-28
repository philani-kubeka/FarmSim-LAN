extends CanvasLayer
## In-scenario interface: season clock, field counters, the shared water reserve,
## one panel per player, and the environmental event banner.
##
## The whole layout is authored in farm_hud.tscn - three bands, a top bar, a
## full-width water band under it, and a pair of player panels along the bottom -
## so the middle of the screen belongs entirely to the farm. Config.PLAY_AREA is
## kept clear of the top and bottom bands, and the test suite asserts that it is.
## This script only puts numbers and text into those nodes.
##
## Every label here is single-line by design, apart from the two player messages
## and the banner body. A wrapping label has a near-zero minimum width, and a
## container that hands out minimum widths will squeeze it to one character per
## line and then grow tall enough to hold the column. That is exactly what
## happened to the water panel in the first playable build.

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const AssetLibrary := preload("res://scripts/farm/asset_library.gd")

## Screen bands the HUD occupies, measured from the top and bottom of the
## viewport. Config.PLAY_AREA has to stay clear of both, or a player can end up
## standing behind a panel. Changing these means moving the bands in
## farm_hud.tscn to match.
const TOP_RESERVED_HEIGHT := 180.0
const BOTTOM_RESERVED_HEIGHT := 104.0

const MARGIN := 16.0
const TOP_BAR_TOP := 8.0
const TOP_BAR_BOTTOM := 104.0
const WATER_BAND_TOP := 112.0

## Counter node names under TopBar/Panel/Row/Counters, in the order they appear.
const FIELD_COUNTERS := [
	{"key": "sown", "label": "sown"},
	{"key": "growing", "label": "growing"},
	{"key": "mature", "label": "ready"},
	{"key": "harvested", "label": "harvested"},
	{"key": "stressed", "label": "dry"},
	{"key": "infested_visible", "label": "pests"},
]

const MESSAGE_SECONDS := 4.0
const BANNER_SECONDS := 7.0

# --- the bands, exposed because the layout test measures them ---
@onready var top_bar: Control = $HudRoot/TopBar
@onready var water_band: Control = $HudRoot/WaterBand
@onready var banner: Control = $HudRoot/EventBanner
## The two panels share the bottom band through an HBoxContainer that splits it
## proportionally. They used to be positioned with a hard-coded 664 px offset,
## which overlapped as soon as the viewport was wider than the design size.
@onready var player_panels: Array[Control] = [
	$HudRoot/PlayerPanels/PlayerPanel1, $HudRoot/PlayerPanels/PlayerPanel2,
]

@onready var _title_label: Label = $HudRoot/TopBar/Panel/Row/Scenario/Title
@onready var _crop_label: Label = $HudRoot/TopBar/Panel/Row/Scenario/Crop
@onready var _clock_label: Label = $HudRoot/TopBar/Panel/Row/Clock/ClockLabel
@onready var _clock_bar: ProgressBar = $HudRoot/TopBar/Panel/Row/Clock/ClockBar
@onready var _counters: HBoxContainer = $HudRoot/TopBar/Panel/Row/Counters

@onready var _water_caption: Label = $HudRoot/WaterBand/Panel/Row/Caption
@onready var _water_bar: ProgressBar = $HudRoot/WaterBand/Panel/Row/Bar
@onready var _water_label: Label = $HudRoot/WaterBand/Panel/Row/Amount
@onready var _water_note: Label = $HudRoot/WaterBand/Panel/Row/Note

@onready var _banner_icon: TextureRect = $HudRoot/EventBanner/Panel/Row/Icon
@onready var _banner_title: Label = $HudRoot/EventBanner/Panel/Row/Text/Title
@onready var _banner_body: Label = $HudRoot/EventBanner/Panel/Row/Text/Body
## Closes the drought / pest message early. It also closes itself after
## BANNER_SECONDS, as before.
@onready var banner_close_button: Button = $HudRoot/EventBanner/Panel/Row/CloseButton

var _counter_values := {}
var _player_role: Array[Label] = []
var _player_tool: Array[Label] = []
var _player_message: Array[Label] = []

var _banner_timer := 0.0
var _message_timers := [0.0, 0.0]


func _ready() -> void:
	layer = 1
	banner_close_button.pressed.connect(close_event)
	_counter_values.clear()
	for counter in FIELD_COUNTERS:
		var chip: Node = _counters.get_node_or_null(String(counter["key"]))
		if chip != null:
			_counter_values[counter["key"]] = chip.get_node("Value")

	_player_role.clear()
	_player_tool.clear()
	_player_message.clear()
	for panel in player_panels:
		_player_role.append(panel.get_node("Box/Header/Role"))
		_player_tool.append(panel.get_node("Box/Header/Tool"))
		_player_message.append(panel.get_node("Box/Message"))


func _process(delta: float) -> void:
	if _banner_timer > 0.0:
		_banner_timer -= delta
		if _banner_timer <= 0.0 and banner != null:
			banner.visible = false
	for index in range(_message_timers.size()):
		if _message_timers[index] > 0.0:
			_message_timers[index] -= delta
			if _message_timers[index] <= 0.0 and index < _player_message.size():
				_player_message[index].text = ""


# ----------------------------------------------------------------- updates --

func set_scenario(definition: Dictionary) -> void:
	_title_label.text = String(definition.get("title", "Scenario"))
	# The briefing belongs on the briefing screen, not squeezed into a bar.
	_crop_label.text = "Crop: %s" % String(definition.get("crop", "")).capitalize()


func update_clock(remaining: float, total: float) -> void:
	var minutes := int(remaining) / 60
	var seconds := int(remaining) % 60
	_clock_label.text = "Season time left  %d:%02d" % [minutes, seconds]
	_clock_bar.max_value = maxf(total, 0.001)
	_clock_bar.value = clampf(remaining, 0.0, total)


func update_water(remaining: float, capacity: float) -> void:
	_water_label.text = "%d / %d L" % [int(round(remaining)), int(round(capacity))]
	_water_bar.max_value = maxf(capacity, 0.001)
	_water_bar.value = clampf(remaining, 0.0, capacity)
	var fraction := 0.0 if capacity <= 0.0 else remaining / capacity
	if remaining <= 0.0:
		_water_note.text = "Empty. No more irrigation this season."
		_water_note.add_theme_color_override("font_color", UiKit.COL_BAD)
	elif fraction < 0.3:
		_water_note.text = "Running low - decide what to protect." if GameState.single_player and not Net.is_online() \
			else "Running low - decide together what to protect."
		_water_note.add_theme_color_override("font_color", UiKit.COL_WARN)
	else:
		_water_note.text = "Your water for the whole season." if GameState.single_player and not Net.is_online() \
			else "Both players draw from this."
		_water_note.add_theme_color_override("font_color", UiKit.COL_TEXT_DIM)
	if GameState.single_player and not Net.is_online() and _water_caption.text.begins_with("Shared"):
		_water_caption.text = _water_caption.text.replace("Shared water", "Water")


func update_field(counts: Dictionary) -> void:
	var growing := int(counts.get("planted", 0))
	var mature := int(counts.get("mature", 0))
	var harvested := int(counts.get("harvested", 0))
	var values := {
		"sown": growing + mature + harvested,
		"growing": growing,
		"mature": mature,
		"harvested": harvested,
		"stressed": int(counts.get("stressed", 0)),
		"infested_visible": int(counts.get("infested_visible", 0)),
	}
	for key in values.keys():
		if not _counter_values.has(key):
			continue
		var label: Label = _counter_values[key]
		label.text = str(values[key])
		if key == "stressed" or key == "infested_visible":
			label.add_theme_color_override("font_color",
				UiKit.COL_BAD if int(values[key]) > 0 else UiKit.COL_TEXT_DIM)


func set_player(index: int, role: String, tool_id: int) -> void:
	if index >= _player_role.size():
		return
	var you := " (you)" if Net.is_online() and index == Net.local_player_index else ""
	var who := "P%d" % (index + 1) if _short_names else "Player %d" % (index + 1)
	if GameState.single_player and not Net.is_online():
		who = "You"
		# One farmer, one panel: the second one is not needed.
		if player_panels.size() > 1:
			player_panels[1].visible = false
	var role_name := Config.role_label(role)
	if _short_names:
		role_name = role_name.split(" / ")[0]
	_player_role[index].text = "%s%s - %s" % [who, you, role_name]
	_player_tool[index].text = Config.tool_label(tool_id)


func show_player_message(index: int, message: String, kind: String = "info") -> void:
	if index >= _player_message.size():
		return
	_player_message[index].text = message
	_player_message[index].add_theme_color_override("font_color", _colour_for(kind))
	_message_timers[index] = MESSAGE_SECONDS


func show_event(title: String, body: String, icon_key: String,
		seconds: float = BANNER_SECONDS) -> void:
	if banner == null:
		return
	_banner_title.text = title
	_banner_body.text = body
	_banner_icon.texture = AssetLibrary.texture(icon_key)
	banner.visible = true
	_banner_timer = seconds


# ------------------------------------------------------------------ mobile --

## Phone layout. Room is left at the right of the top bar for the pause button,
## and at both ends of the bottom band for the joystick and the tool buttons.
## A phone only ever has one player on it, so only that player's panel shows
## (`local_index` -1 keeps both). Text is drawn a size larger, since the farm
## itself is never scaled up.
const MOBILE_FONT_SCALE := 1.2
const MOBILE_PAUSE_ROOM := 100.0
const MOBILE_LEFT_ROOM := 290.0
const MOBILE_RIGHT_ROOM := 330.0
const MOBILE_PANEL_HEIGHT := 104.0

var _short_names := false

var mobile_layout := false


func apply_mobile_layout(_local_index: int) -> void:
	if mobile_layout:
		return
	mobile_layout = true
	for text_label in all_labels():
		var size := text_label.get_theme_font_size("font_size")
		text_label.add_theme_font_size_override("font_size", int(round(size * MOBILE_FONT_SCALE)))
	top_bar.offset_right = -MARGIN - MOBILE_PAUSE_ROOM
	# Both players stay on screen, side by side in the gap between the joystick
	# and the tool buttons, so each player can see what the other is doing.
	var bottom: Control = $HudRoot/PlayerPanels
	bottom.offset_left = MOBILE_LEFT_ROOM
	bottom.offset_right = -MOBILE_RIGHT_ROOM
	bottom.offset_top = -MOBILE_PANEL_HEIGHT
	for index in range(player_panels.size()):
		player_panels[index].visible = index == 0 or not GameState.single_player or Net.is_online()
	# Room is tight on a phone: "P1 (you) - Planter / Irrigator".
	_short_names = true
	_water_caption.text = "Water" if GameState.single_player and not Net.is_online() else "Shared water"


## Hides the event message (the player tapped X).
func close_event() -> void:
	_banner_timer = 0.0
	if banner != null:
		banner.visible = false


## Every label the HUD puts on screen. Used by the layout test to check that
## none of them has been squeezed into a vertical column of single characters.
func all_labels() -> Array[Label]:
	var found: Array[Label] = []
	_collect_labels(self, found)
	return found


func _collect_labels(node: Node, found: Array[Label]) -> void:
	var label := node as Label
	if label != null:
		found.append(label)
	for child in node.get_children():
		_collect_labels(child, found)


func _colour_for(kind: String) -> Color:
	match kind:
		"good":
			return UiKit.COL_GOOD
		"warn":
			return UiKit.COL_WARN
		"bad":
			return UiKit.COL_BAD
		_:
			return UiKit.COL_TEXT_DIM
