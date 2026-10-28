extends RefCounted
## Helpers for tests that need a real farm.
##
## The farm is the actual scene the players use - nothing is stubbed. Only time
## is different: tests advance the season through farm.simulate(delta) instead of
## waiting for frames.

const FARM_SCENE := "res://scenes/farm/farm.tscn"
const CropTile := preload("res://scripts/farm/crop_tile.gd")


## Builds the real farm scene for one scenario and parents it to `host`.
static func make(host: Node, scenario_id: String = "baseline") -> Node2D:
	# A solo session (GameState.single_player) keeps its combined role.
	GameState.player_roles.assign(["solo", "monitor"] if GameState.single_player else ["planter", "monitor"])
	var index := index_of(scenario_id)
	GameState.current_scenario_index = index
	SessionController.pending_scenario = SessionController.scenario_definition(index)
	var packed := load(FARM_SCENE) as PackedScene
	var farm: Node2D = packed.instantiate()
	host.add_child(farm)
	return farm


static func index_of(scenario_id: String) -> int:
	for index in range(SessionController.scenarios.size()):
		if String(SessionController.scenarios[index].get("id", "")) == scenario_id:
			return index
	return 0


static func player_with_role(farm: Node2D, role: String) -> Node:
	for player in farm.players:
		if player.role == role:
			return player
	return null


## Runs the season with a simple scripted strategy for both players, so a whole
## scenario can be played end to end without a human at the keyboard.
##
## `spread` is how many tiles the planter will try to establish. Varying it is
## how the drought tests show that over-committing costs yield.
##
## The policy deliberately ignores walking distance: it exercises the farming
## rules, not the ergonomics of moving around, which is what a headless test can
## honestly cover.
static func play_season(farm: Node2D, spread: int, step: float = 0.5,
		neglect_pests: bool = false) -> void:
	var planter := player_with_role(farm, "planter")
	var monitor := player_with_role(farm, "monitor")
	var guard := 0
	while farm.running and guard < 20000:
		guard += 1
		_planter_turn(farm, planter, spread)
		_monitor_turn(farm, monitor, neglect_pests)
		farm.simulate(step)


static func _planter_turn(farm: Node2D, planter: Node, spread: int) -> void:
	if planter == null:
		return
	var field: Node2D = farm.field

	# 1. Harvest anything ready.
	var mature := _first_where(field, _is_mature)
	if mature != null:
		farm.perform_action(planter, Config.Tool.HARVEST, mature)
		return

	# 2. Keep the established crop out of stress.
	var driest := _driest_planted(field)
	if driest != null and driest.moisture < Config.MOISTURE_HEALTHY_THRESHOLD:
		if farm.water.can_draw(Config.WATER_COST_PER_ACTION):
			farm.perform_action(planter, Config.Tool.WATER, driest)
			return

	# 3. Keep `spread` tiles under crop at any one time, moving on to fresh
	#    ground as each one is brought in.
	var established: int = field.planted_count() + field.mature_count() \
		+ field.tilled_count()
	if established < spread:
		var tilled := _first_where(field, _is_tilled)
		if tilled != null:
			farm.perform_action(planter, Config.Tool.SEED, tilled)
			return
		var fresh := _first_where(field, _is_grass)
		if fresh == null:
			fresh = _first_where(field, _is_reworkable)
		if fresh != null:
			farm.perform_action(planter, Config.Tool.HOE, fresh)


static func _monitor_turn(farm: Node2D, monitor: Node, neglect_pests: bool) -> void:
	if monitor == null:
		return
	var field: Node2D = farm.field

	if not neglect_pests:
		var infested := _first_where(field, _is_infested)
		if infested != null:
			farm.perform_action(monitor, Config.Tool.TREAT, infested)
			return

	var driest := _driest_planted(field)
	if driest != null and driest.moisture < Config.MOISTURE_STRESS_THRESHOLD + 0.1:
		if farm.water.can_draw(Config.WATER_COST_PER_ACTION):
			farm.perform_action(monitor, Config.Tool.WATER, driest)
			return

	var unscouted := _first_where(field, _is_unscouted)
	if unscouted != null:
		farm.perform_action(monitor, Config.Tool.INSPECT, unscouted)


static func _is_mature(tile: Node2D) -> bool:
	return tile.state == CropTile.State.MATURE


static func _is_tilled(tile: Node2D) -> bool:
	return tile.state == CropTile.State.TILLED


static func _is_grass(tile: Node2D) -> bool:
	return tile.state == CropTile.State.GRASS


static func _is_reworkable(tile: Node2D) -> bool:
	return tile.state == CropTile.State.HARVESTED or tile.state == CropTile.State.DEAD


static func _is_infested(tile: Node2D) -> bool:
	return tile.infested


static func _is_unscouted(tile: Node2D) -> bool:
	return tile.is_planted() and not tile.scouted


static func _first_where(field: Node2D, predicate: Callable) -> Node2D:
	for tile in field.tiles:
		if predicate.call(tile):
			return tile
	return null


static func _driest_planted(field: Node2D) -> Node2D:
	var best: Node2D = null
	for tile in field.tiles:
		if not tile.is_planted():
			continue
		if best == null or tile.moisture < best.moisture:
			best = tile
	return best
