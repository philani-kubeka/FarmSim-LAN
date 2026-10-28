extends "res://scripts/systems/farm_system.gd"
## Harvesting System - taking the crop off, and what that is worth.
##
## Yield is the crop's base yield multiplied by the condition it was in when it
## was cut, so everything the other systems did during the season arrives here as
## a number. Covers FR-004 (yield score) and feeds FR-005 (the end-of-season
## summary), which reads the totals below.
##
## Harvesting a failed tile is allowed and deliberately returns nothing: clearing
## dead ground to sow again is a decision, and the data should show it was made.

const CropTile := preload("res://scripts/farm/crop_tile.gd")

signal crop_harvested(tile: Node, crop: int, amount: float)
signal failure_cleared(tile: Node)


func handled_tools() -> Array:
	return [Config.Tool.HARVEST]


func apply(_player: Node, _tool_id: int, tile: Node) -> Dictionary:
	return harvest(tile)


func harvest(tile: Node) -> Dictionary:
	var was_dead: bool = tile.state == CropTile.State.DEAD
	var result: Dictionary = tile.harvest()
	if not bool(result.get("ok", false)):
		return result
	if was_dead:
		failure_cleared.emit(tile)
	else:
		crop_harvested.emit(tile, tile.crop, tile.harvested_yield)
	return result


## Tiles standing ripe and waiting to be cut.
func ready_to_harvest() -> int:
	return field.mature_count()


## Harvests taken this season, across every cycle a tile went through.
func harvests_taken() -> int:
	return field.total_harvests()


## Everything the field produced this season, in crop units.
func total_yield() -> float:
	return field.total_yield()


## Average condition of every crop that reached an outcome - harvested or dead.
func average_condition() -> float:
	return field.average_condition_at_harvest()
