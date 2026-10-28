extends Node
## The farm's single water reserve.
##
## There is exactly one of these per scenario and both players draw from it.
## That is the whole point: during the drought season irrigation stops being two
## independent decisions and becomes one shared decision the players have to make
## together.

signal changed(remaining: float, capacity: float)
signal depleted

var capacity := 0.0
var remaining := 0.0
var total_drawn := 0.0
var refused_draws := 0
## Litres per second the reserve recovers, if a scenario allows any.
var refill_per_second := 0.0


func configure(litres: float, refill: float = 0.0) -> void:
	capacity = maxf(0.0, litres)
	remaining = capacity
	refill_per_second = maxf(0.0, refill)
	total_drawn = 0.0
	refused_draws = 0
	changed.emit(remaining, capacity)


func fraction() -> float:
	if capacity <= 0.0:
		return 0.0
	return clampf(remaining / capacity, 0.0, 1.0)


func can_draw(litres: float) -> bool:
	return remaining >= litres


## Takes `litres` out of the reserve. Returns true only if the full amount was
## available: partial draws are refused so the shortfall is unambiguous to the
## players and in the data.
func draw(litres: float) -> bool:
	if not can_draw(litres):
		refused_draws += 1
		return false
	remaining -= litres
	total_drawn += litres
	changed.emit(remaining, capacity)
	if remaining <= 0.0:
		depleted.emit()
	return true


func simulate(delta: float) -> void:
	if refill_per_second <= 0.0 or remaining >= capacity:
		return
	remaining = minf(capacity, remaining + refill_per_second * delta)
	changed.emit(remaining, capacity)


func to_record() -> Dictionary:
	return {
		"capacity_litres": snappedf(capacity, 0.01),
		"remaining_litres": snappedf(remaining, 0.01),
		"used_litres": snappedf(total_drawn, 0.01),
		"refused_draws": refused_draws,
	}
