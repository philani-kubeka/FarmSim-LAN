extends Control
## Entry point. Confirms the autoloads are alive, then hands over to the menu.
##
## The splash itself is boot.tscn; this script only decides where to go next.

const SPLASH_SECONDS := 0.8

const TEST_RUNNER_SCENE := "res://tests/test_runner.tscn"
const LAN_SMOKE_SCRIPT := "res://tests/lan/lan_smoke.gd"


func _ready() -> void:
	# The automated suite is launched by running the project normally with
	# `-- --run-tests`, which is the most portable way to start it: no custom
	# main loop, no special main scene, so the autoload layer behaves exactly as
	# it does during a real session.
	if not Config.headless_test_mode and "--run-tests" in OS.get_cmdline_user_args():
		call_deferred("_start_test_runner")
		return

	if Config.headless_test_mode:
		return
	# LAN port: two copies playing each other, see tests/lan/lan_smoke.gd.
	if "--lan-smoke" in OS.get_cmdline_user_args():
		var smoke: Node = (load(LAN_SMOKE_SCRIPT) as GDScript).new()
		smoke.name = "LanSmoke"
		get_tree().root.add_child.call_deferred(smoke)
		return
	await get_tree().create_timer(SPLASH_SECONDS).timeout
	if is_inside_tree():
		SessionController.goto_main_menu()


func _start_test_runner() -> void:
	Config.headless_test_mode = true
	var err := get_tree().change_scene_to_file(TEST_RUNNER_SCENE)
	if err != OK:
		printerr("Boot: could not load the test runner (error %d)" % err)
		get_tree().quit(2)
