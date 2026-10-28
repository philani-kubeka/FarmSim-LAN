extends Node
## Automated test entry point.
##
## Run it with:   run_tests.bat            (Windows, from the project folder)
## or directly:   godot --headless --path . res://tests/test_runner.tscn
##
## Writes test_out/test_results.json next to the project and exits with a
## non-zero code when anything failed, so the result can be inspected without a
## human watching the console.

const CASE_SCRIPTS := [
	# foundation
	"res://tests/cases/test_scripts_compile.gd",
	"res://tests/cases/test_autoloads.gd",
	"res://tests/cases/test_input_map.gd",
	"res://tests/cases/test_data_files.gd",
	"res://tests/cases/test_assets.gd",
	"res://tests/cases/test_scenes_load.gd",
	"res://tests/cases/test_game_state.gd",
	"res://tests/cases/test_logger.gd",
	"res://tests/cases/test_lan.gd",
	# simulation
	"res://tests/cases/test_crop_tile.gd",
	"res://tests/cases/test_water_reserve.gd",
	"res://tests/cases/test_farm_environment.gd",
	"res://tests/cases/test_farming_loop.gd",
	"res://tests/cases/test_environment_events.gd",
	"res://tests/cases/test_scenario_playthrough.gd",
	# integration
	"res://tests/cases/test_session_flow.gd",
	"res://tests/cases/test_results_screens.gd",
	"res://tests/cases/test_player_movement.gd",
	"res://tests/cases/test_hud_layout.gd",
	"res://tests/cases/test_screen_layout.gd",
	"res://tests/cases/test_window_scaling.gd",
	"res://tests/cases/test_mobile.gd",
	"res://tests/cases/test_solo_and_navigation.gd",
	# the whole thing, through the real screens
	"res://tests/cases/test_full_session.gd",
]

const OUTPUT_DIR := "res://test_out"
const OUTPUT_FILE := "res://test_out/test_results.json"

var _case_results: Array[Dictionary] = []


func _ready() -> void:
	# A test that exercises the pause overlay pauses the whole SceneTree. The
	# runner has to keep going regardless.
	process_mode = Node.PROCESS_MODE_ALWAYS
	Config.headless_test_mode = true
	print("=== FarmSim automated tests ===")
	print("Godot %s" % Engine.get_version_info().get("string", "unknown"))
	print("Project: %s" % ProjectSettings.get_setting("application/config/name", "?"))
	print("")
	await _run_all()
	_write_results()
	_print_summary()
	get_tree().quit(1 if _total_failures() > 0 else 0)


func _run_all() -> void:
	for script_path in CASE_SCRIPTS:
		await _run_case(script_path)


func _run_case(script_path: String) -> void:
	var result := {
		"name": script_path.get_file().get_basename(),
		"passed": 0,
		"failed": 0,
		"assertions": [],
		"error": null,
	}

	if not ResourceLoader.exists(script_path):
		result["error"] = "test script not found: %s" % script_path
		result["failed"] = 1
		_case_results.append(result)
		print("  MISSING  %s" % script_path)
		return

	var script: Variant = load(script_path)
	if script == null:
		result["error"] = "test script failed to load: %s" % script_path
		result["failed"] = 1
		_case_results.append(result)
		print("  LOADFAIL %s" % script_path)
		return

	var case_instance: Node = (script as GDScript).new()
	add_child(case_instance)

	if bool(case_instance.get("is_async")):
		await case_instance.run_async()
	else:
		case_instance.run()

	var summary: Dictionary = case_instance.call("summary")
	result["name"] = summary.get("name", result["name"])
	result["passed"] = summary.get("passed", 0)
	result["failed"] = summary.get("failed", 0)
	result["assertions"] = summary.get("assertions", [])

	# A test case that asserts nothing did not pass - it stopped early. A
	# GDScript runtime error aborts the running function without aborting the
	# engine, so without this check a case that died on its first line would be
	# reported green.
	if int(result["passed"]) == 0 and int(result["failed"]) == 0:
		result["error"] = ("test case produced no assertions - it almost certainly hit a "
			+ "runtime error. Check godot_stderr.log.")
		print("  DEAD  %-24s  no assertions were recorded" % result["name"])

	_case_results.append(result)

	var status := "PASS" if int(result["failed"]) == 0 and result["error"] == null else "FAIL"
	print("  %-4s  %-24s  %d passed, %d failed"
		% [status, result["name"], int(result["passed"]), int(result["failed"])])
	for assertion in (result["assertions"] as Array):
		if not bool((assertion as Dictionary).get("ok", false)):
			print("          - %s" % String((assertion as Dictionary).get("message", "")))

	case_instance.queue_free()


func _total_failures() -> int:
	var total := 0
	for result in _case_results:
		total += int(result.get("failed", 0))
		if result.get("error") != null:
			total += 1
	return total


func _total_passes() -> int:
	var total := 0
	for result in _case_results:
		total += int(result.get("passed", 0))
	return total


func _write_results() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	var document := {
		"prototype": Config.PROTOTYPE_NAME,
		"prototype_version": Config.PROTOTYPE_VERSION,
		"godot_version": Engine.get_version_info().get("string", "unknown"),
		"generated_unix": int(Time.get_unix_time_from_system()),
		"generated_iso": Time.get_datetime_string_from_system(true),
		"total_passed": _total_passes(),
		"total_failed": _total_failures(),
		"cases": _case_results,
	}
	var file := FileAccess.open(OUTPUT_FILE, FileAccess.WRITE)
	if file == null:
		printerr("Could not write %s (error %d)" % [OUTPUT_FILE, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(document, "  "))
	file.close()
	print("")
	print("Results written to %s" % OUTPUT_FILE)


func _print_summary() -> void:
	print("")
	print("=== %d passed, %d failed ===" % [_total_passes(), _total_failures()])
