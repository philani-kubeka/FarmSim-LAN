extends Node
## Base class for the farm's systems.
##
## A system is a node under Farm/Systems. Each one owns exactly one part of the
## crop-management loop and nothing else: PlantingSystem prepares and sows
## ground, IrrigationSystem spends the shared reserve, HarvestingSystem takes the
## crop off, ScoutingSystem inspects and treats, GrowthSystem advances time, and
## WeatherSystem decides what the season throws at them.
##
## Systems hold no tile state. The tiles themselves are the single source of
## truth; a system translates "this player used this tool on this tile" into the
## one call on the tile that means it, and reports back what happened. That is
## what keeps two players, a test harness and a future scripted tutorial from
## each having their own version of the farming rules.
##
## Every system is bound once, when the farm has finished building its world:
##
##     for system in $Systems.get_children():
##         system.bind(self)

## The farm this system belongs to. Set by bind().
var farm: Node2D = null
## Convenience reference to the farm's field, set at the same time.
var field: Node2D = null


func bind(farm_node: Node2D) -> void:
	farm = farm_node
	field = farm_node.field
	_on_bound()


## Override to pick up anything else the system needs once the farm exists.
func _on_bound() -> void:
	pass


## Tools from Config.Tool that this system is responsible for. A tool must
## appear in exactly one system, or the farm would not know who to ask.
func handled_tools() -> Array:
	return []


func handles(tool_id: int) -> bool:
	return tool_id in handled_tools()


## Resolves one player action. Returns the same {ok, kind, message} dictionary
## the tiles produce, which is what the HUD shows and the logger records.
func apply(_player: Node, _tool_id: int, _tile: Node) -> Dictionary:
	return refuse("Nothing happens.")


func refuse(message: String, kind: String = "warn") -> Dictionary:
	return {"ok": false, "kind": kind, "message": message}
