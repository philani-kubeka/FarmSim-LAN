extends RefCounted
## The interface palette, plus the few helpers that are still needed at runtime.
##
## Every screen is now a hand-authored scene under res://scenes/ui/ and takes its
## colours, font sizes and panel styles from res://assets/ui/farm_sim_theme.tres.
## What is left here is:
##
## * the colour and font-size constants, which gameplay code still needs when it
##   colours a label by outcome (good / warn / bad) or tints a player;
## * label(), paragraph(), body(), note(), dim() and spacer(), for the handful of
##   lists whose length comes from data rather than from the scene - a scenario's
##   objectives, a season's causal explanations, the per-season summary lines.
##
## Nothing in here builds a screen any more. If you are adding a screen, author
## it as a .tscn and give it the theme.

const COL_BACKGROUND := Color("1d2a1f")
const COL_PANEL := Color("27362a")
const COL_PANEL_LIGHT := Color("32462f")
const COL_TEXT := Color("e8f0e2")
const COL_TEXT_DIM := Color("a9bda6")
const COL_ACCENT := Color("d9a441")
const COL_GOOD := Color("6fbf5e")
const COL_WARN := Color("e0a63c")
const COL_BAD := Color("d05a4a")
const COL_WATER := Color("4a9fd0")
const COL_PLAYER_1 := Color("e2b13c")
const COL_PLAYER_2 := Color("5fa8d3")

const FONT_TITLE := 40
const FONT_HEADING := 26
const FONT_BODY := 18
const FONT_SMALL := 15


static func background(color: Color = COL_BACKGROUND) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


static func panel(bg: Color = COL_PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	p.add_theme_stylebox_override("panel", style)
	return p


## A single-line label. Deliberately does NOT wrap: a wrapping label has a
## near-zero minimum width, so any container that hands out minimum widths will
## squeeze it to one character per line and then grow tall enough to hold the
## result. Use paragraph() for text that is meant to flow.
static func label(text: String, size: int = FONT_BODY, color: Color = COL_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


## Flowing text. Only safe inside a container that gives it a real width - a
## page column, or a child with SIZE_EXPAND_FILL.
static func paragraph(text: String, size: int = FONT_BODY, color: Color = COL_TEXT) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func title(text: String) -> Label:
	return paragraph(text, FONT_TITLE, COL_ACCENT)


static func heading(text: String) -> Label:
	return paragraph(text, FONT_HEADING, COL_TEXT)


static func body(text: String) -> Label:
	return paragraph(text, FONT_BODY, COL_TEXT)


static func dim(text: String) -> Label:
	return label(text, FONT_SMALL, COL_TEXT_DIM)


## Small, dim, flowing. For explanatory text inside a page column.
static func note(text: String) -> Label:
	return paragraph(text, FONT_SMALL, COL_TEXT_DIM)


static func button(text: String, size: int = FONT_BODY) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(180, 44)
	return b


## A button whose label can be a whole sentence - a quiz option, say. Its text is
## never allowed to decide how wide the screen is.
static func wide_button(text: String, size: int = FONT_BODY) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, 44)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if "autowrap_mode" in b:
		b.set("autowrap_mode", TextServer.AUTOWRAP_WORD_SMART)
	else:
		b.clip_text = true
	return b


static func spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


## A centred, scrollable column, used by nearly every screen.
##
## `preferred_width` is a preference, not a promise: the column takes that share
## of the window rather than that many pixels, so it narrows with the window
## instead of running off the edge of it. Anything taller than the window
## scrolls, which is the only way a button at the bottom of a long screen can
## never be cut off.
static func page_column(preferred_width: float = 900.0) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)

	var scroll := ScrollContainer.new()
	scroll.name = "PageScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(row)

	var share := clampf(preferred_width / 1280.0, 0.35, 0.98)
	var gutter := maxf((1.0 - share) / 2.0, 0.01)

	row.add_child(_gutter(gutter))

	var column := VBoxContainer.new()
	column.name = "PageContent"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = share
	column.add_theme_constant_override("separation", 12)
	row.add_child(column)

	row.add_child(_gutter(gutter))

	# The caller adds the margin to the screen; expose it via metadata so the
	# column alone is enough to work with.
	column.set_meta("root", margin)
	return column


static func _gutter(ratio: float) -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.size_flags_stretch_ratio = ratio
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


## Convenience: attach a column built by page_column() to a screen.
static func attach_page(screen: Control, column: VBoxContainer) -> void:
	screen.add_child(column.get_meta("root"))


static func progress_bar(value: float, maximum: float, colour: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = maximum
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 18)
	var fill := StyleBoxFlat.new()
	fill.bg_color = colour
	fill.corner_radius_top_left = 4
	fill.corner_radius_top_right = 4
	fill.corner_radius_bottom_left = 4
	fill.corner_radius_bottom_right = 4
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.35)
	bg.corner_radius_top_left = 4
	bg.corner_radius_top_right = 4
	bg.corner_radius_bottom_left = 4
	bg.corner_radius_bottom_right = 4
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	return bar


## The small "Exit" button on every in-session screen. It asks first (see
## SessionController.request_exit), then saves what was recorded and leaves.
static func exit_button() -> Button:
	var b := Button.new()
	b.name = "ExitButton"
	b.text = "Exit"
	b.theme_type_variation = &"GhostButton"
	b.custom_minimum_size = Vector2(110, 46)
	b.focus_mode = Control.FOCUS_ALL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func() -> void: SessionController.request_exit())
	return b
