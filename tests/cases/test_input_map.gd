extends "res://tests/farm_sim_test.gd"
## The two players share one keyboard, so this checks both that every action the
## gameplay code uses exists and that the two control sets do not collide.


func run() -> void:
	for action_name in InputSetup.REQUIRED_ACTIONS:
		var exists := InputMap.has_action(action_name)
		check(exists, "input action '%s' is registered" % action_name)
		if exists:
			check(InputMap.action_get_events(action_name).size() > 0,
				"input action '%s' has at least one key bound" % action_name)

	var p1_keys := _keys_for_prefix("p1_")
	var p2_keys := _keys_for_prefix("p2_")
	check(p1_keys.size() >= 6, "player 1 has a full control set")
	check(p2_keys.size() >= 6, "player 2 has a full control set")

	var shared: Array[int] = []
	for key in p1_keys:
		if key in p2_keys:
			shared.append(key)
	check(shared.is_empty(),
		"player 1 and player 2 share no keys (overlap: %s)" % str(shared))

	# Player 2 must be usable on a laptop with no numeric keypad.
	var p2_use_keys: Array[int] = _keys_for_action("p2_use")
	check(p2_use_keys.size() >= 2, "player 2's use key has a non-keypad alternative")


func _keys_for_action(action_name: String) -> Array[int]:
	var keys: Array[int] = []
	if not InputMap.has_action(action_name):
		return keys
	for event in InputMap.action_get_events(action_name):
		var key_event := event as InputEventKey
		if key_event != null:
			keys.append(key_event.physical_keycode)
	return keys


func _keys_for_prefix(prefix: String) -> Array[int]:
	var keys: Array[int] = []
	for action_name in InputSetup.REQUIRED_ACTIONS:
		if not String(action_name).begins_with(prefix):
			continue
		for key in _keys_for_action(action_name):
			if not (key in keys):
				keys.append(key)
	return keys
