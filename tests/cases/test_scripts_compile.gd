extends "res://tests/farm_sim_test.gd"
## Loads every GDScript in the project and checks it actually compiles.
##
## This exists because of a real failure: `farm.gd` had a type-inference error
## (`var x := node.method()` where the node was typed `Node2D`, so the method
## returned Variant). A syntax parser does not catch that - only the engine
## does - and the consequence was a farm scene with no script at all, which
## renders as an empty grey window. Every script now gets compiled by the engine
## on every test run, whether or not a scene happens to reference it.

const SCRIPT_ROOTS := ["res://scripts", "res://tests"]


func run() -> void:
	var scripts := _find_scripts()
	check(scripts.size() > 10, "the project has scripts to compile (found %d)" % scripts.size())

	for path in scripts:
		# Plain load(), not CACHE_MODE_IGNORE: forcing a fresh compile of scripts
		# that are already loaded and executing breaks the GDScript VM outright
		# ("Internal script error! Opcode: 31"). The cache does not hide a broken
		# script - a script with a parse error never entered it.
		var resource: Variant = ResourceLoader.load(path, "Script")
		var compiled: bool = resource != null and resource is GDScript
		check(compiled,
			"script compiles: %s%s" % [path,
				"" if compiled else " - see godot_stderr.log for the parse error"])


func _find_scripts() -> Array[String]:
	var found: Array[String] = []
	for root in SCRIPT_ROOTS:
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
		elif entry.ends_with(".gd"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
