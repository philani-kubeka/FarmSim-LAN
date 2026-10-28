extends "res://tests/farm_sim_test.gd"
## Two players on one keyboard, tested against real physics in the real farm
## scene: independent movement, collision with the farm boundary, and the
## keyboard bindings themselves.
##
## This is the one test that has to wait for actual frames rather than driving
## the simulation directly, because movement is physics.

const Fixture := preload("res://tests/farm_fixture.gd")


func _init() -> void:
	super()
	is_async = true


func run_async() -> void:
	var farm := Fixture.make(self, "baseline")
	var player_one: CharacterBody2D = farm.players[0]
	var player_two: CharacterBody2D = farm.players[1]
	player_one.use_test_input = true
	player_two.use_test_input = true

	await _settle()

	# --- both players move, and they move independently ---
	var start_one := player_one.global_position
	var start_two := player_two.global_position

	player_one.test_input = Vector2.RIGHT
	player_two.test_input = Vector2.ZERO
	await _physics_frames(25)

	check_greater(player_one.global_position.x - start_one.x, 20.0,
		"player 1 moves right when its own keys are held")
	check_near(player_one.global_position.y, start_one.y, 4.0,
		"player 1 does not drift vertically while moving right")
	check_near(player_two.global_position.distance_to(start_two), 0.0, 2.0,
		"player 2 does not move when only player 1's keys are held")

	var after_one := player_one.global_position
	player_one.test_input = Vector2.ZERO
	player_two.test_input = Vector2.UP
	await _physics_frames(25)

	check_less(player_two.global_position.y - start_two.y, -20.0,
		"player 2 moves up when its own keys are held")
	check_near(player_one.global_position.distance_to(after_one), 0.0, 2.0,
		"player 1 stays put when only player 2's keys are held")

	# --- diagonals are not faster than straight lines ---
	var diagonal_start := player_one.global_position
	player_two.test_input = Vector2.ZERO
	player_one.test_input = Vector2(1, 1)
	await _physics_frames(25)
	var diagonal_distance := player_one.global_position.distance_to(diagonal_start)
	var straight_distance := after_one.distance_to(start_one)
	check(diagonal_distance <= straight_distance * 1.15,
		"moving diagonally is not faster than moving straight")

	# --- the farm boundary holds them in ---
	player_one.test_input = Vector2.LEFT
	await _physics_frames(140)
	check(player_one.global_position.x >= Config.PLAY_AREA.position.x,
		"the boundary stops player 1 leaving the farm on the left")
	check(player_one.global_position.x < Config.PLAY_AREA.position.x + 60.0,
		"player 1 actually reached the left boundary rather than stopping early")

	player_two.test_input = Vector2.RIGHT
	await _physics_frames(140)
	check(player_two.global_position.x <= Config.PLAY_AREA.end.x,
		"the boundary stops player 2 leaving the farm on the right")

	player_one.test_input = Vector2.ZERO
	player_two.test_input = Vector2.ZERO

	# --- standing on a tile targets that tile ---
	var target: Node2D = farm.field.tile_at(3, 2)
	player_one.global_position = target.global_position
	await _physics_frames(3)
	check_equal(player_one.target_tile(), target,
		"the tile a player is standing on is the tile they will work")

	player_one.global_position = Vector2(Config.PLAY_AREA.position.x + 20.0,
		Config.PLAY_AREA.end.y - 20.0)
	await _physics_frames(3)
	check(player_one.target_tile() == null,
		"standing away from the field targets no tile")

	# --- facing follows the direction of travel ---
	player_one.test_input = Vector2.DOWN
	await _physics_frames(5)
	check_near(player_one.facing.y, 1.0, 0.1, "the player faces the way it is walking")
	player_one.test_input = Vector2.ZERO

	await _test_keyboard_bindings()

	farm.queue_free()


## Feeds real key events through Godot's input system and checks that the
## bindings registered by InputSetup respond. This is the actual keyboard path,
## not a stand-in for it.
func _test_keyboard_bindings() -> void:
	var pairs := {
		"p1_up": KEY_W,
		"p1_left": KEY_A,
		"p1_use": KEY_E,
		"p2_up": KEY_UP,
		"p2_left": KEY_LEFT,
		"p2_use": KEY_KP_0,
	}
	for action_name in pairs.keys():
		var keycode: int = pairs[action_name]
		var press := InputEventKey.new()
		press.physical_keycode = keycode
		press.pressed = true
		Input.parse_input_event(press)
		Input.flush_buffered_events()
		await _physics_frames(2)
		check(Input.is_action_pressed(action_name),
			"pressing %s activates '%s'" % [OS.get_keycode_string(keycode), action_name])

		var release := InputEventKey.new()
		release.physical_keycode = keycode
		release.pressed = false
		Input.parse_input_event(release)
		Input.flush_buffered_events()
		await _physics_frames(2)
		check(not Input.is_action_pressed(action_name),
			"releasing %s deactivates '%s'" % [OS.get_keycode_string(keycode), action_name])

	# Player 1's keys must never move player 2.
	check(not InputMap.event_is_action(_key_event(KEY_W), "p2_up"),
		"player 1's up key is not bound to player 2")
	check(not InputMap.event_is_action(_key_event(KEY_UP), "p1_up"),
		"player 2's up key is not bound to player 1")


func _key_event(keycode: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	return event


func _settle() -> void:
	await _physics_frames(4)


func _physics_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().physics_frame
