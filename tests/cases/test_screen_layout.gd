extends "res://tests/farm_sim_test.gd"
## Measures every page screen after a real layout pass.
##
## Written after a play session where the quiz question and its option buttons
## ran off the right-hand edge of the window and the briefing's start button was
## cut off by the bottom of it. The HUD had a layout test by then; the page
## screens did not, and the same class of fault was sitting in all of them.
##
## The rule being enforced: text never decides how wide a screen is, and nothing
## a player has to read or press ends up outside the window.

const Fixture := preload("res://tests/farm_fixture.gd")

## Every screen built from a page column, with the state each one needs.
const SCREENS := [
	{"path": "res://scenes/ui/main_menu.tscn", "name": "main menu"},
	{"path": "res://scenes/ui/player_setup.tscn", "name": "player setup"},
	{"path": "res://scenes/ui/instructions.tscn", "name": "instructions"},
	{"path": "res://scenes/ui/assessment_screen.tscn", "name": "assessment"},
	{"path": "res://scenes/ui/scenario_briefing.tscn", "name": "scenario briefing"},
	{"path": "res://scenes/ui/scenario_results.tscn", "name": "scenario results"},
	{"path": "res://scenes/ui/final_results.tscn", "name": "final results"},
	{"path": "res://scenes/ui/usability_screen.tscn", "name": "usability"},
]

## The longest question and option in the instruments, used to give the
## assessment screen its worst case rather than its easiest one.
var _longest_question := ""


func _init() -> void:
	super()
	is_async = true


func run_async() -> void:
	_prepare_state()

	var screen_size: Vector2 = get_tree().root.get_visible_rect().size
	check(screen_size.x > 0.0 and screen_size.y > 0.0,
		"the viewport has a real size (%.0f x %.0f)" % [screen_size.x, screen_size.y])

	for entry in SCREENS:
		await _check_screen(String(entry["path"]), String(entry["name"]), screen_size)

	GameState.reset_session()


## Give each screen something realistic, and deliberately hard, to render.
func _prepare_state() -> void:
	GameState.reset_session()
	GameState.pre_assessment = {"kind": "pre_assessment", "score": 3, "max_score": 8,
		"percent": 37.5}
	GameState.post_assessment = {"kind": "post_assessment", "score": 7, "max_score": 8,
		"percent": 87.5}

	SessionController.pending_scenario = SessionController.scenario_definition(1)
	SessionController.pending_assessment = {
		"path": SessionController.PRE_ASSESSMENT_PATH,
		"kind": "layout_check",
		"title": "Pre-session knowledge check",
		"intro": "Answer these before playing. Each of you answers separately, without discussing.",
		"show_feedback": true,
	}

	# A real season, so the results screens have real explanations to lay out -
	# which are the longest strings the prototype ever puts on screen.
	var farm := Fixture.make(self, "drought")
	Fixture.play_season(farm, 12)
	var result: Dictionary = farm.build_result("time")
	farm.queue_free()
	SessionController.pending_results = result
	GameState.record_scenario_result(result)
	GameState.record_scenario_quiz({"kind": "quiz_1", "score": 2, "max_score": 3, "percent": 66.7})

	_longest_question = _longest_text_in_instruments()
	check(_longest_question.length() > 60,
		"the instruments contain a genuinely long question to lay out (%d characters)"
			% _longest_question.length())


func _longest_text_in_instruments() -> String:
	var longest := ""
	for path in [SessionController.PRE_ASSESSMENT_PATH, SessionController.POST_ASSESSMENT_PATH]:
		if not FileAccess.file_exists(path):
			continue
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path)) != OK:
			continue
		if typeof(parser.data) != TYPE_DICTIONARY:
			continue
		for entry in ((parser.data as Dictionary).get("questions", []) as Array):
			var question := entry as Dictionary
			if String(question.get("text", "")).length() > longest.length():
				longest = String(question.get("text", ""))
			for option in (question.get("options", []) as Array):
				if String(option).length() > longest.length():
					longest = String(option)
	return longest


func _check_screen(path: String, screen_name: String, screen_size: Vector2) -> void:
	var packed: Variant = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if packed == null:
		fail("%s loads" % screen_name)
		return
	var screen: Control = (packed as PackedScene).instantiate()
	if screen == null:
		fail("%s instantiates" % screen_name)
		return
	add_child(screen)
	await _layout_frames()

	var screen_rect := Rect2(Vector2.ZERO, screen_size)

	# Every page screen has to be scrollable, or a screen taller than the window
	# simply loses whatever is at the bottom of it - which is how the briefing's
	# start button disappeared.
	var scroll := _find_scroll(screen)
	check(scroll != null, "%s can scroll if it is taller than the window" % screen_name)

	var overflowing: Array[String] = []
	var offscreen_buttons: Array[String] = []

	for label in _labels(screen):
		if label.text.strip_edges().is_empty() or not label.is_visible_in_tree():
			continue
		var rect := label.get_global_rect()
		if rect.end.x > screen_size.x + 1.0 or rect.position.x < -1.0:
			overflowing.append("'%s' (x %.0f..%.0f)"
				% [label.text.left(30), rect.position.x, rect.end.x])

	for button in _buttons(screen):
		if not button.is_visible_in_tree():
			continue
		var rect := button.get_global_rect()
		if rect.end.x > screen_size.x + 1.0 or rect.position.x < -1.0:
			overflowing.append("button '%s' (x %.0f..%.0f)"
				% [button.text.left(24), rect.position.x, rect.end.x])
		# Vertical overflow is only acceptable because the screen scrolls, and
		# only if the content is genuinely taller than the window.
		if rect.end.y > screen_size.y + 1.0 and scroll != null:
			if _content_height(scroll) <= screen_size.y:
				offscreen_buttons.append("'%s' (bottom at %.0f, window %.0f)"
					% [button.text.left(24), rect.end.y, screen_size.y])

	check(overflowing.is_empty(),
		"%s: nothing runs off the side of the window %s" % [screen_name, str(overflowing)])
	check(offscreen_buttons.is_empty(),
		"%s: no button is cut off while the screen still fits %s"
			% [screen_name, str(offscreen_buttons)])

	# The column has to be narrower than the window, or the text has taken over.
	var column: Control = screen.find_child("PageContent", true, false)
	check(column != null, "%s is built from a page column" % screen_name)
	if column != null:
		var column_rect: Rect2 = column.get_global_rect()
		check(column_rect.size.x <= screen_size.x,
			"%s's column fits the window (%.0f wide, window %.0f)"
				% [screen_name, column_rect.size.x, screen_size.x])
		check(column_rect.size.x > 200.0,
			"%s's column has a usable width (%.0f)" % [screen_name, column_rect.size.x])
		check(screen_rect.has_point(column_rect.position + Vector2(1, 1)),
			"%s's column starts inside the window" % screen_name)

	screen.queue_free()
	await _layout_frames()


## How tall the scrollable content actually is.
func _content_height(scroll: ScrollContainer) -> float:
	if scroll.get_child_count() == 0:
		return 0.0
	var content := scroll.get_child(0) as Control
	if content == null:
		return 0.0
	return content.get_combined_minimum_size().y


func _find_scroll(node: Node) -> ScrollContainer:
	var scroll := node as ScrollContainer
	if scroll != null:
		return scroll
	for child in node.get_children():
		var found := _find_scroll(child)
		if found != null:
			return found
	return null


func _labels(node: Node) -> Array[Label]:
	var found: Array[Label] = []
	_collect_labels(node, found)
	return found


func _collect_labels(node: Node, found: Array[Label]) -> void:
	var label := node as Label
	if label != null:
		found.append(label)
	for child in node.get_children():
		_collect_labels(child, found)


func _buttons(node: Node) -> Array[Button]:
	var found: Array[Button] = []
	_collect_buttons(node, found)
	return found


func _collect_buttons(node: Node, found: Array[Button]) -> void:
	var button := node as Button
	if button != null:
		found.append(button)
	for child in node.get_children():
		_collect_buttons(child, found)


func _layout_frames() -> void:
	for _index in range(6):
		await get_tree().process_frame
