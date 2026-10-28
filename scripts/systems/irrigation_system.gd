extends "res://scripts/systems/farm_system.gd"
## Irrigation System - the shared water reserve and what it is spent on.
##
## There is one reserve per season and both players draw from it, which is what
## turns watering into a joint decision during the drought scenario rather than
## two independent habits. This system is the only thing that takes water out of
## the reserve, so "how much water went where" is answerable from one place.
##
## A refused watering is data, not an error: it is recorded because running the
## reserve dry is one of the outcomes the study is looking for.

signal tile_watered(tile: Node, litres: float)
signal reserve_refused(tile: Node)

## The reserve node this system spends. Left empty it falls back to the farm's
## WaterReserve, which is how farm.tscn wires it.
@export var reserve_path: NodePath

var reserve: Node = null


func _on_bound() -> void:
	if not reserve_path.is_empty():
		reserve = get_node_or_null(reserve_path)
	if reserve == null:
		reserve = farm.water


func handled_tools() -> Array:
	return [Config.Tool.WATER]


func apply(_player: Node, _tool_id: int, tile: Node) -> Dictionary:
	return water_tile(tile)


## Waters one tile out of the shared reserve.
func water_tile(tile: Node) -> Dictionary:
	if not tile.can_water():
		return refuse("There is nothing growing here to water.")
	# Ask the reserve rather than testing first: draw() is what counts a refusal,
	# and refused irrigation attempts are part of the research data.
	if not reserve.draw(Config.WATER_COST_PER_ACTION):
		reserve_refused.emit(tile)
		return refuse(
			"The shared reserve is empty. There is no more water this season.", "bad")
	var result: Dictionary = tile.apply_water(Config.WATER_COST_PER_ACTION)
	tile_watered.emit(tile, Config.WATER_COST_PER_ACTION)
	return result


## Waters every waterable tile within `radius` of a grid coordinate. Not bound to
## a tool yet - it is the hook a sprinkler or a future irrigation upgrade would
## use, and it spends the same reserve as a watering can.
func water_area(centre: Vector2i, radius: int) -> int:
	var watered := 0
	for x_offset in range(-radius, radius + 1):
		for y_offset in range(-radius, radius + 1):
			var tile: Node2D = field.tile_at(centre.x + x_offset, centre.y + y_offset)
			if tile == null:
				continue
			if bool(water_tile(tile).get("ok", false)):
				watered += 1
	return watered


func litres_remaining() -> float:
	return 0.0 if reserve == null else reserve.remaining


func fraction_remaining() -> float:
	return 0.0 if reserve == null else reserve.fraction()


## Advances the reserve itself - only relevant in a scenario that refills.
func simulate(delta: float) -> void:
	if reserve != null:
		reserve.simulate(delta)


func to_record() -> Dictionary:
	return {} if reserve == null else reserve.to_record()
