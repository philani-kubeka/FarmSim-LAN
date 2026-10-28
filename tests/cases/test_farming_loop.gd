extends "res://tests/farm_sim_test.gd"
## The playable loop, driven through the same entry point the keyboard uses:
## till, sow, water, grow, harvest - plus the role split and the shared reserve.

const Fixture := preload("res://tests/farm_fixture.gd")
const CropTile := preload("res://scripts/farm/crop_tile.gd")


func run() -> void:
	_test_full_loop()
	_test_role_split()
	_test_shared_reserve()
	_test_empty_reserve()


func _test_full_loop() -> void:
	var farm := Fixture.make(self, "baseline")
	var planter := Fixture.player_with_role(farm, "planter")
	var tile: Node2D = farm.field.tile_at(1, 1)

	check(planter.select_tool(Config.Tool.HOE), "the planter can select the hoe")
	var till: Dictionary = farm.perform_action(planter, Config.Tool.HOE, tile)
	check(bool(till["ok"]), "the planter tills a tile")
	check_equal(tile.state, CropTile.State.TILLED, "the tile becomes a seedbed")

	check(planter.select_tool(Config.Tool.SEED), "the planter can select seed")
	var sow: Dictionary = farm.perform_action(planter, Config.Tool.SEED, tile)
	check(bool(sow["ok"]), "the planter sows the seedbed")
	check_equal(tile.crop, Config.CropType.MAIZE, "the scenario's crop is what gets sown")

	var before_water: float = farm.water.remaining
	var water_result: Dictionary = farm.perform_action(planter, Config.Tool.WATER, tile)
	check(bool(water_result["ok"]), "the planter waters the tile")
	check_near(farm.water.remaining, before_water - Config.WATER_COST_PER_ACTION, 0.001,
		"watering draws from the shared reserve")
	check_equal(tile.times_watered, 1, "the tile records the watering")

	# Grow it to maturity, keeping it watered the way a player would.
	var guard := 0
	while tile.state != CropTile.State.MATURE and guard < 2000:
		guard += 1
		if tile.moisture < Config.MOISTURE_HEALTHY_THRESHOLD:
			farm.perform_action(planter, Config.Tool.WATER, tile)
		farm.simulate(0.25)
	check_equal(tile.state, CropTile.State.MATURE, "a watered crop reaches maturity in the farm")
	check_greater(tile.health, 0.85, "a well tended crop matures in good condition")

	var harvest: Dictionary = farm.perform_action(planter, Config.Tool.HARVEST, tile)
	check(bool(harvest["ok"]), "a mature crop can be harvested")
	check_greater(tile.harvested_yield, 0.0, "harvesting produces yield")
	check_greater(farm.field.total_yield(), 0.0, "the field's total yield reflects the harvest")
	check_equal(tile.state, CropTile.State.HARVESTED, "the harvested tile is cleared")

	# Actions taken are attributed to the right player in the research data.
	var records: Array = farm._player_records()
	check_equal(records.size(), 2, "the result records both players")
	var planter_actions: Dictionary = {}
	for record in records:
		if String((record as Dictionary).get("role", "")) == "planter":
			planter_actions = (record as Dictionary).get("actions", {})
	check(planter_actions.has("hoe_ok"), "tilling is recorded against the planter")
	check(planter_actions.has("seed_ok"), "sowing is recorded against the planter")
	check(planter_actions.has("sickle_ok"), "harvesting is recorded against the planter")

	farm.queue_free()


func _test_role_split() -> void:
	var farm := Fixture.make(self, "baseline")
	var planter := Fixture.player_with_role(farm, "planter")
	var monitor := Fixture.player_with_role(farm, "monitor")
	var tile: Node2D = farm.field.tile_at(0, 0)

	check(not monitor.select_tool(Config.Tool.HOE), "the monitor cannot pick up a hoe")
	check(not monitor.select_tool(Config.Tool.SEED), "the monitor cannot pick up seed")
	check(not planter.select_tool(Config.Tool.TREAT), "the planter cannot pick up pest treatment")
	check(not planter.select_tool(Config.Tool.INSPECT), "the planter cannot scout")

	# Even if something bypassed the tool list, the farm refuses the action.
	var refused: Dictionary = farm.perform_action(monitor, Config.Tool.HOE, tile)
	check(not bool(refused["ok"]), "the farm refuses an action the player's role cannot do")
	check_equal(tile.state, CropTile.State.GRASS, "the refused action changed nothing")

	# Which means a season genuinely cannot be completed by one player alone.
	farm.perform_action(planter, Config.Tool.HOE, tile)
	farm.perform_action(planter, Config.Tool.SEED, tile)
	tile.infest(10.0)
	var planter_treat: Dictionary = farm.perform_action(planter, Config.Tool.TREAT, tile)
	check(not bool(planter_treat["ok"]),
		"the planter cannot deal with a pest outbreak, so the monitor is needed")
	var monitor_treat: Dictionary = farm.perform_action(monitor, Config.Tool.TREAT, tile)
	check(bool(monitor_treat["ok"]), "the monitor can deal with the outbreak")
	check(not tile.infested, "the outbreak is cleared by the player whose job it is")

	farm.queue_free()


func _test_shared_reserve() -> void:
	var farm := Fixture.make(self, "baseline")
	var planter := Fixture.player_with_role(farm, "planter")
	var monitor := Fixture.player_with_role(farm, "monitor")
	var tile: Node2D = farm.field.tile_at(2, 2)
	farm.perform_action(planter, Config.Tool.HOE, tile)
	farm.perform_action(planter, Config.Tool.SEED, tile)

	var start: float = farm.water.remaining
	farm.perform_action(planter, Config.Tool.WATER, tile)
	var after_planter: float = farm.water.remaining
	farm.simulate(6.0)
	farm.perform_action(monitor, Config.Tool.WATER, tile)
	var after_monitor: float = farm.water.remaining

	check_near(start - after_planter, Config.WATER_COST_PER_ACTION, 0.001,
		"the planter's watering costs the reserve")
	check_near(after_planter - after_monitor, Config.WATER_COST_PER_ACTION, 0.001,
		"the monitor's watering costs the same reserve, not a separate one")
	check_near(start - after_monitor, Config.WATER_COST_PER_ACTION * 2.0, 0.001,
		"both players' use comes out of one pool")
	farm.queue_free()


func _test_empty_reserve() -> void:
	var farm := Fixture.make(self, "drought")
	var planter := Fixture.player_with_role(farm, "planter")
	var tile: Node2D = farm.field.tile_at(4, 2)
	farm.perform_action(planter, Config.Tool.HOE, tile)
	farm.perform_action(planter, Config.Tool.SEED, tile)

	# Spend the reserve until a watering is refused.
	#
	# A reserve is not necessarily a whole number of waterings: the drought season
	# holds 140 L and one watering costs 3 L, so the last 2 L can never be drawn.
	# Partial draws are refused on purpose - a half-watered tile would be a
	# shortfall the players could not see - so "empty" means "less than one
	# watering left", not "exactly zero".
	var guard := 0
	var refused: Dictionary = {}
	while guard < 500:
		guard += 1
		refused = farm.perform_action(planter, Config.Tool.WATER, tile)
		if not bool(refused.get("ok", false)):
			break
	check(farm.water.remaining < Config.WATER_COST_PER_ACTION,
		"the reserve is spent down to less than one watering (%.1f L left)"
			% farm.water.remaining)

	check(not bool(refused["ok"]), "watering is refused once the reserve is empty")
	check_equal(refused["kind"], "bad", "an empty reserve is reported as a serious problem")
	check(String(refused["message"]).to_lower().contains("empty"),
		"the players are told the reserve is empty")
	check_greater(farm.water.refused_draws, 0, "refused waterings are counted")
	farm.queue_free()
