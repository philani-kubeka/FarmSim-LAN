extends "res://tests/farm_sim_test.gd"
## The two screens that sit between the farm and the next scenario, built from
## real data rather than an empty handover.
##
## A real season is played first, its result is pushed through the session
## controller exactly as the farm does, and then the screens are instantiated
## and their actual on-screen text is inspected. This is the join that the
## scene-load test cannot check, because a results screen with no results to
## show will happily render nothing at all.

const Fixture := preload("res://tests/farm_fixture.gd")

const SCENARIO_RESULTS := "res://scenes/ui/scenario_results.tscn"
const FINAL_RESULTS := "res://scenes/ui/final_results.tscn"


func run() -> void:
	GameState.reset_session()
	GameplayLogger.clear()

	# --- play a real season and hand its result over the way the farm does ---
	var farm := Fixture.make(self, "baseline")
	Fixture.play_season(farm, 6)
	var result: Dictionary = farm.build_result("time")
	farm.queue_free()

	check_greater(float(result.get("total_yield", 0.0)), 0.0,
		"the season used for this test actually produced a harvest")

	GameState.current_scenario_index = 0
	SessionController.finish_scenario(result)
	check(not SessionController.pending_results.is_empty(),
		"finishing a season hands the results screen something to show")

	# --- the scenario results screen ---
	var screen := _instantiate(SCENARIO_RESULTS)
	if screen == null:
		return
	var text := _all_text(screen)

	check(text.contains("results"), "the results screen is titled as results")
	check(text.contains("Harvest"), "the results screen shows the harvest")
	check(text.contains("Tiles sown"), "the results screen shows how much was sown")
	check(text.contains("Water used"), "the results screen shows what the reserve cost")
	check(text.contains("%d" % int(result.get("tiles_harvested", -1))),
		"the number of harvested tiles from the season appears on screen")

	# The causal explanations are the educational payload, so they have to be
	# on the screen, not just in the data.
	var causes: Array = result.get("causes", [])
	check_greater(causes.size(), 2, "the season produced several explanations")
	var shown := 0
	for note in causes:
		if text.contains(String(note)):
			shown += 1
	check_equal(shown, causes.size(),
		"every explanation the season generated is displayed (%d of %d)" % [shown, causes.size()])

	var buttons := _all_buttons(screen)
	check_greater(buttons.size(), 0, "the results screen has a way forward")
	var has_continue := false
	for button in buttons:
		if button.text.to_lower().contains("continue"):
			has_continue = true
	check(has_continue, "the results screen leads on to the knowledge check")
	screen.queue_free()

	# --- the final results screen ---
	GameState.pre_assessment = {"kind": "pre_assessment", "score": 3, "max_score": 8, "percent": 37.5}
	GameState.post_assessment = {"kind": "post_assessment", "score": 6, "max_score": 8, "percent": 75.0}
	GameState.record_scenario_quiz({"kind": "quiz_1", "score": 2, "max_score": 3, "percent": 66.7})

	var final_screen := _instantiate(FINAL_RESULTS)
	if final_screen == null:
		return
	var final_text := _all_text(final_screen)

	check(final_text.contains("Session complete"), "the final screen says the session is over")
	check(final_text.contains(GameState.session_id),
		"the final screen shows the anonymous session id")
	check(final_text.contains("3 / 8"), "the final screen shows the pre-test score")
	check(final_text.contains("6 / 8"), "the final screen shows the post-test score")
	check(final_text.contains("+37.5"), "the final screen shows the change between the two tests")
	check(final_text.contains("quiz 2/3"), "the final screen shows the scenario quiz score")
	final_screen.queue_free()

	# Individually answered tests show each player's own score and change.
	GameState.pre_assessment = {"kind": "pre_assessment", "score": 6, "max_score": 16, "percent": 37.5,
		"players": [{"player": 1, "score": 2, "max_score": 8, "percent": 25.0},
			{"player": 2, "score": 4, "max_score": 8, "percent": 50.0}]}
	GameState.post_assessment = {"kind": "post_assessment", "score": 12, "max_score": 16, "percent": 75.0,
		"players": [{"player": 1, "score": 6, "max_score": 8, "percent": 75.0},
			{"player": 2, "score": 6, "max_score": 8, "percent": 75.0}]}
	final_screen = _instantiate(FINAL_RESULTS)
	if final_screen == null:
		return
	final_text = _all_text(final_screen)
	check(final_text.contains("P1 · 2/8") and final_text.contains("P2 · 4/8"),
		"the final screen shows each player's own pre-test score")
	check(final_text.contains("P1 · +50") and final_text.contains("P2 · +25"),
		"the final screen shows each player's own change")
	check(final_text.contains("Research data"),
		"the final screen tells the researcher where the data went")
	check(final_text.contains("no personal information"),
		"the final screen states that no personal data was collected")

	var final_buttons := _all_buttons(final_screen)
	check_greater(final_buttons.size(), 1, "the final screen offers a way out")
	final_screen.queue_free()

	GameState.reset_session()


func _instantiate(path: String) -> Control:
	var packed: Variant = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if packed == null:
		fail("screen loads: %s" % path)
		return null
	var screen: Control = (packed as PackedScene).instantiate()
	if screen == null:
		fail("screen instantiates: %s" % path)
		return null
	add_child(screen)
	check(screen.get_child_count() > 0, "screen builds its contents: %s" % path)
	return screen


## Everything the screen would actually put in front of a player.
func _all_text(node: Node) -> String:
	var parts: Array[String] = []
	_collect_text(node, parts)
	return "\n".join(parts)


func _collect_text(node: Node, parts: Array[String]) -> void:
	var label := node as Label
	if label != null and not label.text.is_empty():
		parts.append(label.text)
	var button := node as Button
	if button != null and not button.text.is_empty():
		parts.append(button.text)
	for child in node.get_children():
		_collect_text(child, parts)


func _all_buttons(node: Node) -> Array[Button]:
	var found: Array[Button] = []
	_collect_buttons(node, found)
	return found


func _collect_buttons(node: Node, found: Array[Button]) -> void:
	var button := node as Button
	if button != null:
		found.append(button)
	for child in node.get_children():
		_collect_buttons(child, found)
