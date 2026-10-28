extends Node
## Base class for FarmSim's automated test cases.
##
## Cases are plain Nodes so they can add scene instances as children and free
## them cleanly. Simulation systems expose an explicit `simulate(delta)` entry
## point, which means almost every test can run synchronously and
## deterministically instead of waiting on real time.

## Human-readable name, defaults to the script's file name.
var case_name := ""
## Set true by a case that needs to await frames; the runner then calls
## run_async() instead of run().
var is_async := false

var assertions: Array[Dictionary] = []
var failure_count := 0


func _ready() -> void:
	# Cases keep running even when a test pauses the tree.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _init() -> void:
	if case_name.is_empty():
		var path: String = get_script().resource_path
		case_name = path.get_file().get_basename()


## Overridden by synchronous cases.
func run() -> void:
	pass


## Overridden by cases that set is_async = true.
func run_async() -> void:
	pass


# ------------------------------------------------------------ assertions ----

func check(condition: bool, message: String) -> bool:
	assertions.append({"ok": condition, "message": message})
	if not condition:
		failure_count += 1
		push_warning("[FAIL] %s :: %s" % [case_name, message])
	return condition


func check_equal(actual: Variant, expected: Variant, message: String) -> bool:
	var ok: bool = actual == expected
	return check(ok, "%s (expected %s, got %s)" % [message, str(expected), str(actual)] if not ok else message)


func check_near(actual: float, expected: float, tolerance: float, message: String) -> bool:
	var ok := absf(actual - expected) <= tolerance
	return check(ok, "%s (expected %.4f +/- %.4f, got %.4f)"
		% [message, expected, tolerance, actual] if not ok else message)


func check_greater(actual: float, threshold: float, message: String) -> bool:
	var ok := actual > threshold
	return check(ok, "%s (expected > %.4f, got %.4f)" % [message, threshold, actual] if not ok else message)


func check_less(actual: float, threshold: float, message: String) -> bool:
	var ok := actual < threshold
	return check(ok, "%s (expected < %.4f, got %.4f)" % [message, threshold, actual] if not ok else message)


func check_not_null(value: Variant, message: String) -> bool:
	return check(value != null, message)


func fail(message: String) -> void:
	check(false, message)


func summary() -> Dictionary:
	var passed := 0
	for assertion in assertions:
		if bool(assertion["ok"]):
			passed += 1
	return {
		"name": case_name,
		"passed": passed,
		"failed": failure_count,
		"assertions": assertions,
	}
