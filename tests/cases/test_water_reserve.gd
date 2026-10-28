extends "res://tests/farm_sim_test.gd"
## The shared reserve. There is one per farm and both players draw from it, so
## these tests are really about the "shared" part.

const WaterReserveScript := preload("res://scripts/farm/water_reserve.gd")


func run() -> void:
	var reserve: Node = WaterReserveScript.new()
	add_child(reserve)
	reserve.configure(30.0)

	check_near(reserve.capacity, 30.0, 0.001, "the reserve starts at its capacity")
	check_near(reserve.remaining, 30.0, 0.001, "nothing has been used yet")
	check_near(reserve.fraction(), 1.0, 0.001, "the reserve reports itself as full")

	var changes := [0]
	var depleted := [false]
	reserve.changed.connect(func(_r: float, _c: float) -> void: changes[0] += 1)
	reserve.depleted.connect(func() -> void: depleted[0] = true)

	check(reserve.draw(3.0), "a draw within the reserve succeeds")
	check_near(reserve.remaining, 27.0, 0.001, "a draw reduces what is left")
	check_equal(changes[0], 1, "a draw notifies listeners so the HUD can update")

	# The point of the shared reserve: what one player takes, the other cannot.
	var before_second_player: float = reserve.remaining
	reserve.draw(3.0)
	check_near(reserve.remaining, before_second_player - 3.0, 0.001,
		"a draw by the second player comes out of the same reserve")

	# Drain it.
	for _index in range(8):
		reserve.draw(3.0)
	check_near(reserve.remaining, 0.0, 0.001, "the reserve can be emptied")
	check(depleted[0], "emptying the reserve raises the depleted signal")

	check(not reserve.can_draw(3.0), "an empty reserve cannot be drawn from")
	check(not reserve.draw(3.0), "drawing from an empty reserve is refused")
	check_equal(reserve.refused_draws, 1, "refused draws are counted for the research data")
	check_near(reserve.remaining, 0.0, 0.001, "a refused draw does not push the reserve negative")

	# Partial draws are refused outright rather than half-filling a watering can,
	# so a shortfall is unambiguous both on screen and in the data.
	reserve.configure(4.0)
	check(not reserve.draw(5.0), "a draw larger than what is left is refused, not partially served")
	check_near(reserve.remaining, 4.0, 0.001, "a refused draw leaves the reserve untouched")

	check_near(reserve.total_drawn, 0.0, 0.001, "reconfiguring resets the usage counters")

	# Optional slow recovery, off by default.
	reserve.configure(10.0, 0.5)
	reserve.draw(6.0)
	reserve.simulate(4.0)
	check_near(reserve.remaining, 6.0, 0.001, "a refilling reserve recovers over time")
	reserve.simulate(100.0)
	check_near(reserve.remaining, 10.0, 0.001, "a refilling reserve never exceeds its capacity")

	var record: Dictionary = reserve.to_record()
	for key in ["capacity_litres", "remaining_litres", "used_litres", "refused_draws"]:
		check(record.has(key), "the water record contains '%s'" % key)

	reserve.queue_free()
