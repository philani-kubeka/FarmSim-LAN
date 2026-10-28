extends "res://tests/farm_sim_test.gd"
## Loads and instantiates every scene in the project, and puts each one into the
## live scene tree so that its _ready() actually runs. A scene that references a
## missing script, a missing resource or a bad node path fails here rather than
## in front of a participant.

const SCENE_ROOTS := ["res://scenes", "res://tests"]


func run() -> void:
	# Give the assessment screen a real instrument to load; without a handover
	# payload it would legitimately report a missing instrument.
	SessionController.pending_assessment = {
		"path": SessionController.PRE_ASSESSMENT_PATH,
		"kind": "self_test",
		"title": "Scene load self-test",
		"intro": "",
		"show_feedback": true,
	}
	SessionController.pending_scenario = SessionController.scenario_definition(0)

	var scene_paths := _find_scenes()
	check(scene_paths.size() > 0, "the project contains scenes to test")

	for path in scene_paths:
		# The runner's own scene is already instantiated; re-running it would
		# recurse and quit the engine.
		if path == "res://tests/test_runner.tscn":
			continue
		_check_scene(path)


func _check_scene(path: String) -> void:
	var packed: Variant = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if packed == null:
		fail("scene loads: %s" % path)
		return
	check(true, "scene loads: %s" % path)

	var instance: Node = (packed as PackedScene).instantiate()
	if instance == null:
		fail("scene instantiates: %s" % path)
		return

	add_child(instance)
	check(instance.is_inside_tree(), "scene enters the tree and runs _ready(): %s" % path)
	check(instance.get_script() != null, "scene root has a script attached: %s" % path)
	instance.queue_free()


func _find_scenes() -> Array[String]:
	var found: Array[String] = []
	for root in SCENE_ROOTS:
		_walk(root, found)
	found.sort()
	return found


func _walk(dir_path: String, found: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_walk(full, found)
		elif entry.ends_with(".tscn"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
