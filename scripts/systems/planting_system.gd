extends "res://scripts/systems/farm_system.gd"
## Planting System - preparing ground and getting seed into it.
##
## Covers FR-001 (at least two crop types, chosen per scenario rather than
## hardcoded) and the first half of the till -> sow -> irrigate -> harvest loop.
## Only the Planter / Irrigator carries the hoe and the seed bag, so this system
## is the reason the two roles are not interchangeable.

signal tile_tilled(tile: Node, player_index: int)
signal crop_sown(tile: Node, crop_type: int, player_index: int)


func handled_tools() -> Array:
	return [Config.Tool.HOE, Config.Tool.SEED]


func apply(player: Node, tool_id: int, tile: Node) -> Dictionary:
	if tool_id == Config.Tool.HOE:
		return till(tile, player.player_index)
	return sow(tile, farm.crop_type, player.player_index)


## Prepares a seedbed. Grass, harvested stubble and failed tiles can all be
## worked again; a tile with something growing in it cannot.
func till(tile: Node, player_index: int) -> Dictionary:
	var result: Dictionary = tile.till(player_index)
	if bool(result.get("ok", false)):
		tile_tilled.emit(tile, player_index)
	return result


## Sows the scenario's crop into a prepared seedbed.
func sow(tile: Node, crop_type: int, player_index: int) -> Dictionary:
	var result: Dictionary = tile.plant(crop_type, player_index)
	if bool(result.get("ok", false)):
		crop_sown.emit(tile, crop_type, player_index)
	return result


## Tiles standing ready for seed right now.
func seedbeds_ready() -> int:
	return field.tilled_count()


## Distinct tiles that have been sown at least once this season.
func tiles_sown() -> int:
	return field.sown_tiles()
