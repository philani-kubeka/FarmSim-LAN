extends "res://scripts/systems/farm_system.gd"
## Scouting System - finding out what is actually happening in the field, and
## treating it.
##
## Moisture, condition and an early pest infestation are not readable off a tile
## at a glance; a tile has to be scouted. Only the Field Monitor carries the
## scout and the pest treatment, which is why a pair who never talk to each other
## lose tiles they could have saved.
##
## Pest damage becomes visible without scouting once it is bad enough. Finding it
## before that point is the whole job.

signal tile_scouted(tile: Node)
signal pests_treated(tile: Node, severity: float, response_seconds: float)


func handled_tools() -> Array:
	return [Config.Tool.INSPECT, Config.Tool.TREAT]


func apply(_player: Node, tool_id: int, tile: Node) -> Dictionary:
	if tool_id == Config.Tool.INSPECT:
		return scout(tile)
	return treat(tile)


## Reveals a tile's moisture, condition and any pests on it.
func scout(tile: Node) -> Dictionary:
	var result: Dictionary = tile.scout()
	tile_scouted.emit(tile)
	return result


## Treats a pest outbreak on one tile. How much condition the tile keeps depends
## entirely on how long the outbreak went unnoticed.
func treat(tile: Node) -> Dictionary:
	var severity: float = tile.pest_level
	var infested_at: float = tile.infested_at
	var result: Dictionary = tile.treat(farm.elapsed)
	if bool(result.get("ok", false)) and infested_at >= 0.0:
		pests_treated.emit(tile, severity, maxf(0.0, farm.elapsed - infested_at))
	return result


## Infested tiles a player could see right now, whether by scouting or because
## the damage has become obvious.
func visible_outbreaks() -> int:
	return field.count_where(func(tile: Node2D) -> bool: return tile.pest_is_visible())


## Every infested tile, seen or not. The difference between this and
## visible_outbreaks() is how much of the outbreak the pair have missed.
func total_outbreaks() -> int:
	return field.infested_count()


## Planted tiles nobody has looked at yet.
func unscouted_crops() -> int:
	return field.count_where(
		func(tile: Node2D) -> bool: return tile.is_planted() and not tile.scouted)
