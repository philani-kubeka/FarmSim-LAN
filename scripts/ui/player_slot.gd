extends PanelContainer
## One seat in the LAN lobby: a portrait, a big "P1"/"P2" badge, who is sitting
## there and whether they are connected. Filled seats glow in the player's
## colour; an empty seat is dim and gently pulses while it waits.

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const AssetLibrary := preload("res://scripts/farm/asset_library.gd")

@onready var _portrait: TextureRect = $Box/Top/Portrait
@onready var _badge: Label = $Box/Top/Badge
@onready var _who: Label = $Box/Who
@onready var _state: Label = $Box/State

var _filled := false
var _pulse := 0.0


## `index` 0 or 1. `who` is the line under the badge ("You", "Thabo's phone"...),
## `state` the small line under that. An empty seat passes filled = false.
func show_seat(index: int, filled: bool, who: String, state: String, state_colour: Color = UiKit.COL_TEXT_DIM) -> void:
	_filled = filled
	var colour: Color = UiKit.COL_PLAYER_1 if index == 0 else UiKit.COL_PLAYER_2
	_badge.text = "P%d" % (index + 1)
	_who.text = who
	_state.text = state
	_state.add_theme_color_override("font_color", state_colour)
	_portrait.texture = AssetLibrary.texture("player_%d" % (index + 1))

	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(18)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	if filled:
		style.bg_color = Color(colour.r * 0.32, colour.g * 0.32, colour.b * 0.32, 0.95)
		style.border_color = colour
		style.set_border_width_all(3)
		style.border_width_bottom = 7
		_badge.add_theme_color_override("font_color", colour)
		_who.add_theme_color_override("font_color", UiKit.COL_TEXT)
		_portrait.modulate = Color.WHITE
	else:
		style.bg_color = Color(0, 0, 0, 0.22)
		style.border_color = Color(colour.r, colour.g, colour.b, 0.35)
		style.set_border_width_all(2)
		_badge.add_theme_color_override("font_color", Color(colour.r, colour.g, colour.b, 0.45))
		_who.add_theme_color_override("font_color", UiKit.COL_TEXT_DIM)
		_portrait.modulate = Color(0, 0, 0, 0.45)
	add_theme_stylebox_override("panel", style)
	modulate.a = 1.0


func _process(delta: float) -> void:
	if _filled:
		return
	_pulse += delta
	modulate.a = 0.75 + 0.25 * sin(_pulse * 3.0)
