extends "res://tests/farm_sim_test.gd"
## The phone build: touch controls and the HUD's phone layout.
##
## Checks that the BombSquad-style controls drive the real player (a tool button
## picks up the tool and uses it, the joystick moves the same input actions the
## keyboard does), and that on every common phone shape nothing in the HUD sits
## underneath a thumb control or the pause button.

const Fixture := preload("res://tests/farm_fixture.gd")
const TOUCH_SCENE := preload("res://scenes/ui/touch_controls.tscn")
const HUD_SCENE := preload("res://scenes/ui/farm_hud.tscn")

## Layout sizes a phone produces with aspect "expand": 16:9, 19.5:9, 20:9 and a
## 4:3 tablet.
const SIZES := [Vector2(1280, 720), Vector2(1560, 720), Vector2(1600, 720), Vector2(1280, 960)]


func _init() -> void:
	super()
	is_async = true


func run_async() -> void:
	await _check_controls_drive_player()
	for size in SIZES:
		await _check_layout(size)
	await _check_quizzes_fit()
	await _check_season_screens_fit()


func _check_controls_drive_player() -> void:
	var farm := Fixture.make(self, "baseline")
	var player: Node = farm.players[0]
	var controls: CanvasLayer = TOUCH_SCENE.instantiate()
	add_child(controls)
	controls.bind(player)
	await _frames()

	var tools: Array = player.tools
	check_equal(controls.covered_rects().size(), 1 + mini(tools.size(), 4),
		"one joystick and one round button per tool")

	# Tap the third tool's button: it is picked up and used straight away.
	var used := []
	player.use_requested.connect(func(_p: Node, tool_id: int, _t: Node) -> void: used.append(tool_id))
	controls._on_touch(3, controls.button_centre(2), true)
	controls._on_touch(3, controls.button_centre(2), false)
	check_equal(player.current_tool(), tools[2], "tapping a tool button picks that tool up")
	check_equal(used, [tools[2]], "and uses it on the tile underfoot in the same tap")

	# The joystick drives the keyboard's own actions, with an analogue strength.
	var prefix: String = player.action_prefix()
	var start: Vector2 = controls.stick_rest_centre()
	controls._on_touch(0, start, true)
	controls._on_drag(0, start + Vector2(controls.STICK_RADIUS, 0))
	check_near(Input.get_action_strength(prefix + "right"), 1.0, 0.01,
		"dragging the stick right presses %sright fully" % prefix)
	check_near(Input.get_action_strength(prefix + "left"), 0.0, 0.01, "and not left")
	controls._on_touch(0, start, false)
	check_near(Input.get_action_strength(prefix + "right"), 0.0, 0.01,
		"letting go of the stick stops the player")

	# A touch on the left that is not on a button starts the stick, not a tool.
	var before: int = player.current_tool()
	controls._on_touch(1, Vector2(200, 400), true)
	check_equal(player.current_tool(), before, "a thumb on the left never changes tool")
	controls._on_touch(1, Vector2(200, 400), false)

	controls.queue_free()
	farm.queue_free()
	await _frames()


func _check_layout(size: Vector2) -> void:
	var label := "%dx%d" % [int(size.x), int(size.y)]
	var hud: CanvasLayer = HUD_SCENE.instantiate()
	add_child(hud)
	hud.set_scenario({"title": "Scenario 2 - Drought season", "crop": "maize"})
	hud.set_player(1, "monitor", Config.Tool.INSPECT)
	hud.update_water(42.0, 140.0)
	hud.show_player_message(1, "Pests treated early - very little damage done.", "good")
	hud.apply_mobile_layout(1)
	var root: Control = hud.get_node("HudRoot")
	root.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	root.size = size

	var controls: CanvasLayer = TOUCH_SCENE.instantiate()
	add_child(controls)
	var canvas: Control = controls.get_node("Canvas")
	canvas.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	canvas.size = size
	var farm := Fixture.make(self, "baseline")
	controls.bind(farm.players[1])
	await _frames()

	var screen := Rect2(Vector2.ZERO, size)
	check(hud.player_panels[0].visible and hud.player_panels[1].visible,
		"%s: both players' panels show, side by side" % label)
	var first: Rect2 = hud.player_panels[0].get_global_rect()
	var second: Rect2 = hud.player_panels[1].get_global_rect()
	check(not first.intersects(second), "%s: the two player panels do not overlap" % label)
	for panel_rect in [first, second]:
		check(screen.encloses(panel_rect), "%s: the player panel is on screen" % label)
		# The bottom fence (posts and shadow reach 12 px below its line) stays visible.
		check(panel_rect.position.y >= size.y - 720.0 + 588.0 - 0.5 or size.y != 720.0,
			"%s: the player panels sit below the bottom fence" % label)
		for rect in controls.covered_rects():
			check(not rect.intersects(panel_rect),
				"%s: no thumb control covers a player panel" % label)
	for rect in controls.covered_rects():
		check(screen.encloses(rect), "%s: every thumb control is fully on screen" % label)
	var pause_rect: Rect2 = (controls.get_node("Canvas/PauseButton") as Control).get_global_rect()
	check(not pause_rect.intersects((hud.top_bar as Control).get_global_rect()),
		"%s: the pause button does not sit on the top bar" % label)
	check(screen.encloses(pause_rect), "%s: the pause button is on screen" % label)

	hud.queue_free()
	controls.queue_free()
	farm.queue_free()
	await _frames()


func _frames() -> void:
	for _index in range(6):
		await get_tree().process_frame


## Every quiz question, with its feedback showing (the tallest it gets), has to
## fit a phone screen without scrolling, on every common phone shape. Run with
## the phone layout forced on, then put the computer layout back.
const PHONE_SHAPES := [Vector2i(1280, 720), Vector2i(1560, 720), Vector2i(1680, 720)]
const INSTRUMENTS := ["pre_assessment", "quiz_scenario_1", "quiz_scenario_2",
	"quiz_scenario_3", "post_assessment"]


func _check_quizzes_fit() -> void:
	var root := get_tree().root
	var saved_size := root.size
	var saved_aspect := root.content_scale_aspect
	var saved_factor := root.content_scale_factor
	var saved_pending := SessionController.pending_assessment
	Config.force_mobile = true
	Config.refresh_platform()
	for shape in PHONE_SHAPES:
		root.size = shape
		# The lobby, on every tab: it is the first screen a phone player sees.
		var lobby: Control = (load(SessionController.SCENE_MULTIPLAYER) as PackedScene).instantiate()
		add_child(lobby)
		for tab in [0, 1, 2]:
			lobby._select_tab(tab)
			var lobby_fit := await _fitted(lobby)
			check(lobby_fit.x <= lobby_fit.y + 0.5, "%dx%d: lobby tab %d fits a phone without scrolling"
				% [shape.x, shape.y, tab])
		lobby.queue_free()
		await _frames()
		for instrument in INSTRUMENTS:
			SessionController.pending_assessment = {
				"path": "res://data/assessments/%s.json" % instrument,
				"kind": "phone_fit_check", "title": "Pre-session knowledge check",
				"intro": "Answer these before playing.", "show_feedback": true,
			}
			var screen: Control = (load(SessionController.SCENE_ASSESSMENT) as PackedScene).instantiate()
			add_child(screen)
			var worst := 0.0
			for question in range(screen._questions.size()):
				screen._on_option_pressed(0)
				var fit := await _fitted(screen)
				worst = maxf(worst, fit.x - fit.y)
				screen._on_next_pressed()
			check(worst <= 1.0, "%dx%d: every %s question fits a phone without scrolling (worst overflow %.0f px)"
				% [shape.x, shape.y, instrument, maxf(worst, 0.0)])
			check(root.content_scale_factor >= Config.MIN_FIT_SCALE - 0.001,
				"%dx%d: %s is never drawn smaller than the readable minimum" % [shape.x, shape.y, instrument])
			screen.queue_free()
			await _frames()
	Config.force_mobile = false
	Config.refresh_platform()
	root.content_scale_aspect = saved_aspect
	root.content_scale_factor = saved_factor
	root.size = saved_size
	SessionController.pending_assessment = saved_pending


## Fits the screen the way Config does for the current scene, then measures it.
func _fitted(screen: Control) -> Vector2:
	var root := get_tree().root
	root.content_scale_factor = Config.menu_scale()
	for _step in range(20):
		await _frames()
		var fit := Config.page_fit(screen)
		if fit.x <= fit.y + 0.5 or root.content_scale_factor <= Config.MIN_FIT_SCALE + 0.001:
			return fit
		root.content_scale_factor = maxf(Config.MIN_FIT_SCALE, root.content_scale_factor - Config.FIT_STEP)
	return Config.page_fit(screen)


## The scenario briefing and the season results must fit a 1280x720 window
## without a scroll bar, for every scenario, with a real season's explanation
## (the longest text the prototype puts on screen).
func _check_season_screens_fit() -> void:
	var saved_pending := SessionController.pending_scenario
	var saved_results := SessionController.pending_results
	for index in range(3):
		var scenario_id: String = ["baseline", "drought", "pest"][index]
		var farm := Fixture.make(self, scenario_id)
		Fixture.play_season(farm, 30)
		var result: Dictionary = farm.build_result("time")
		farm.queue_free()
		SessionController.pending_scenario = SessionController.scenario_definition(index)
		SessionController.pending_results = result
		for path in [SessionController.SCENE_BRIEFING, SessionController.SCENE_SCENARIO_RESULTS]:
			var screen: Control = (load(path) as PackedScene).instantiate()
			add_child(screen)
			await _frames()
			var fit := Config.page_fit(screen)
			check(fit.x <= fit.y + 0.5, "%s fits the window without scrolling for %s (needs %.0f of %.0f px)"
				% [path.get_file(), scenario_id, fit.x, fit.y])
			screen.queue_free()
			await _frames()
	# And the end of the session, with all three seasons on it.
	var saved_scenarios := GameState.scenario_results.duplicate()
	GameState.scenario_results.clear()
	for index in range(3):
		var farm := Fixture.make(self, ["baseline", "pest", "drought"][index])
		Fixture.play_season(farm, 30)
		if GameState.scenario_results.size() <= index:
			GameState.record_scenario_result(farm.build_result("time"))
		farm.queue_free()
	var final_screen: Control = (load(SessionController.SCENE_FINAL_RESULTS) as PackedScene).instantiate()
	add_child(final_screen)
	await _frames()
	var final_fit := Config.page_fit(final_screen)
	check(final_fit.x <= final_fit.y + 0.5, "the final results fit the window without scrolling (needs %.0f of %.0f px)"
		% [final_fit.x, final_fit.y])
	final_screen.queue_free()
	await _frames()
	GameState.scenario_results.assign(saved_scenarios)
	SessionController.pending_scenario = saved_pending
	SessionController.pending_results = saved_results
