extends "res://tests/farm_sim_test.gd"
## LAN port: the parts of multiplayer that can be checked on one copy of the
## game. The two-copy end-to-end check is tests/lan/lan_smoke.gd
## (run_lan_test.bat).

const LanDiscovery := preload("res://scripts/net/lan_discovery.gd")


func run() -> void:
	# Offline is the default, and offline is the original game.
	check(not Net.is_online(), "starts offline")
	check(not Net.is_host() and not Net.is_client(), "neither host nor client when offline")

	# Beacons
	var beacon := JSON.stringify({"game": "FarmSim", "v": 1, "name": "Test farm",
		"port": 7777, "players": 1, "max": 2, "in_session": false})
	var parsed := LanDiscovery.parse_beacon(beacon)
	check_equal(parsed.get("name", ""), "Test farm", "beacon name survives the round trip")
	check_equal(int(parsed.get("port", 0)), 7777, "beacon port survives the round trip")
	check(LanDiscovery.parse_beacon("not json").is_empty(), "garbage is not a beacon")
	check(LanDiscovery.parse_beacon(JSON.stringify({"game": "Other", "v": 1})).is_empty(),
		"another game's beacon is ignored")
	check(LanDiscovery.parse_beacon(JSON.stringify({"game": "FarmSim", "v": 99})).is_empty(),
		"a different protocol version is ignored")

	# Hosting opens and closes cleanly.
	check_equal(Net.host("Self test", 17777), OK, "can host on a spare port")
	check(Net.is_host(), "is host after hosting")
	check_equal(Net.player_count(), 1, "one player while waiting")
	Net.leave()
	check(not Net.is_online(), "offline again after leaving")

	# Session state round trip, as the client receives it.
	GameState.reset_session()
	GameState.swap_roles()
	var state := SessionController.network_state()
	var id := GameState.session_id
	GameState.reset_session()
	SessionController.apply_network_state(state)
	check_equal(GameState.session_id, id, "session id reaches the client")
	check_equal(GameState.role_for_player(0), "monitor", "swapped roles reach the client")
	GameState.reset_session()

	# The network-only input bindings exist.
	for action in ["net_up", "net_down", "net_left", "net_right", "net_use", "net_cycle_tool"]:
		check(InputMap.has_action(action), "input action exists: %s" % action)
