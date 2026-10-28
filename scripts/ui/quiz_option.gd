extends Button
## One answer on a knowledge-check question.
##
## An option can be a whole sentence, so the button wraps its text rather than
## deciding how wide the screen is - which is what pushed the quiz off the right
## edge of the window in an earlier build.

const UiKit := preload("res://scripts/ui/ui_kit.gd")


## Shows option `index` (0 -> "A.", 1 -> "B.", ...) with its text.
func show_option(index: int, option_text: String) -> void:
	text = "%s.  %s" % [char(65 + index), option_text]
	visible = true
	disabled = false
	remove_theme_color_override("font_color")
	remove_theme_color_override("font_disabled_color")
	for state in ["normal", "hover", "disabled", "focus"]:
		remove_theme_stylebox_override(state)


func hide_option() -> void:
	visible = false


## Marks this option as the one the pair picked.
## Stays clearly marked after the options lock (feedback mode disables them).
func set_chosen(chosen: bool) -> void:
	add_theme_color_override("font_color", UiKit.COL_ACCENT if chosen else UiKit.COL_TEXT)
	if not chosen:
		remove_theme_color_override("font_disabled_color")
		for state in ["normal", "hover", "disabled", "focus"]:
			remove_theme_stylebox_override(state)
		return
	add_theme_color_override("font_disabled_color", UiKit.COL_ACCENT)
	var base := get_theme_stylebox("normal") as StyleBoxFlat
	var style: StyleBoxFlat = base.duplicate() if base != null else StyleBoxFlat.new()
	style.border_color = UiKit.COL_ACCENT
	style.set_border_width_all(3)
	for state in ["normal", "hover", "disabled"]:
		add_theme_stylebox_override(state, style)
