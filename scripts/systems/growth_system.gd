extends "res://scripts/systems/farm_system.gd"
## Growth System - time passing in the field.
##
## Every tile's moisture falls, its condition rises or falls with how it is being
## kept, and a sown crop advances towards maturity. None of that is driven by
## _process directly: the farm calls simulate(delta, context) so the automated
## suite can play a whole season in milliseconds and get the same answer a real
## 200-second season would give.
##
## The system holds no state of its own. It applies the season's current drying
## multiplier - which WeatherSystem decides - to every tile at once, and reports
## the counts the HUD puts on screen.

signal crop_matured(tile: Node)
signal crop_failed(tile: Node)

const CropTile := preload("res://scripts/farm/crop_tile.gd")

var _was_mature: Dictionary = {}
var _was_dead: Dictionary = {}


## Advances the whole field by `delta` seconds.
## context keys: drying_multiplier (float), elapsed (float).
func simulate(delta: float, context: Dictionary) -> void:
	field.simulate(delta, context)
	_announce_transitions()


## Turns the tiles' own state changes into signals, so a logger, a tutorial or a
## feedback panel can react to a crop ripening without polling every tile.
func _announce_transitions() -> void:
	for tile in field.tiles:
		var key: String = tile.coordinates()
		var mature: bool = tile.state == CropTile.State.MATURE
		var dead: bool = tile.state == CropTile.State.DEAD
		if mature and not bool(_was_mature.get(key, false)):
			crop_matured.emit(tile)
		if dead and not bool(_was_dead.get(key, false)):
			crop_failed.emit(tile)
		_was_mature[key] = mature
		_was_dead[key] = dead


## The counters the HUD shows, in one call.
func field_counts() -> Dictionary:
	return {
		"planted": field.planted_count(),
		"mature": field.mature_count(),
		"harvested": field.harvested_count(),
		"stressed": field.stressed_count(),
	}


## Tiles currently below the stress line - dry enough to be losing condition.
func stressed_crops() -> int:
	return field.stressed_count()
