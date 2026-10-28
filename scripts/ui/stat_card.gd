extends PanelContainer
## One figure with a caption under a panel: "Harvest / 41.2 units".
##
## Used along the top of the season results and the final results, so every
## number on those screens is presented the same way and a new one is a matter of
## dropping in another card rather than writing more layout code.

@export var caption: String = "Caption":
	set(value):
		caption = value
		if is_node_ready():
			$Box/Caption.text = value

@export var value: String = "0":
	set(new_value):
		value = new_value
		if is_node_ready():
			$Box/Value.text = new_value

@export var value_colour: Color = Color(0.9098039, 0.9411765, 0.8862745, 1):
	set(new_colour):
		value_colour = new_colour
		if is_node_ready():
			$Box/Value.add_theme_color_override("font_color", new_colour)


func _ready() -> void:
	$Box/Caption.text = caption
	$Box/Value.text = value
	$Box/Value.add_theme_color_override("font_color", value_colour)


## Fills the card in one call, the way the results screens use it.
func show_stat(stat_caption: String, stat_value: String, colour: Color) -> void:
	caption = stat_caption
	value = stat_value
	value_colour = colour
