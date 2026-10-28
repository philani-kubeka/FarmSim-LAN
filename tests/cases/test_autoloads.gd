extends "res://tests/farm_sim_test.gd"
## Confirms the singleton layer is actually alive and sane at runtime, rather
## than merely being listed in project.godot.


func run() -> void:
	var root := get_tree().root
	for autoload_name in ["Config", "InputSetup", "GameState", "GameplayLogger", "SessionController"]:
		check(root.get_node_or_null(NodePath(autoload_name)) != null,
			"autoload '%s' is present in the scene tree" % autoload_name)

	check(Config.FIELD_COLUMNS > 0 and Config.FIELD_ROWS > 0, "field grid has a positive size")
	check(Config.TILE_SIZE > 0, "tile size is positive")
	check(Config.CROP_GROWTH_SECONDS.has(Config.CropType.MAIZE), "maize has a growth duration")
	check(Config.CROP_GROWTH_SECONDS.has(Config.CropType.BEANS), "beans have a growth duration")
	check(Config.CROP_BASE_YIELD.has(Config.CropType.MAIZE), "maize has a base yield")
	check(Config.CROP_BASE_YIELD.has(Config.CropType.BEANS), "beans have a base yield")
	check_equal(Config.crop_name(Config.CropType.MAIZE), "Maize", "crop_name resolves maize")
	check_equal(Config.crop_name(Config.CropType.BEANS), "Beans", "crop_name resolves beans")

	check(Config.MOISTURE_STRESS_THRESHOLD < Config.MOISTURE_HEALTHY_THRESHOLD,
		"stress threshold sits below the healthy threshold")
	check(Config.WATER_COST_PER_ACTION > 0.0, "watering costs something from the reserve")

	check(Config.ROLE_TOOLS.has("planter") and Config.ROLE_TOOLS.has("monitor"),
		"both roles are defined")

	# The two roles must not be interchangeable, otherwise multiplayer is cosmetic.
	var planter: Array = Config.ROLE_TOOLS["planter"]
	var monitor: Array = Config.ROLE_TOOLS["monitor"]
	check(Config.Tool.SEED in planter and not (Config.Tool.SEED in monitor),
		"only the planter can sow")
	check(Config.Tool.HOE in planter and not (Config.Tool.HOE in monitor),
		"only the planter can till")
	check(Config.Tool.TREAT in monitor and not (Config.Tool.TREAT in planter),
		"only the monitor can treat pests")
	check(Config.Tool.WATER in planter and Config.Tool.WATER in monitor,
		"both roles can irrigate, so the shared reserve is genuinely shared")

	check_equal(SessionController.scenarios.size(), 3, "three scenarios are loaded")
