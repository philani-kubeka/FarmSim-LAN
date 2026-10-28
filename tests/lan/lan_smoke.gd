extends Node
## End-to-end LAN check: two copies of the game on one computer play a whole
## session against each other through the real screens.
##
## Start both (run_lan_test.bat does this):
##   godot --headless --path . -- --lan-smoke --role=host
##   godot --headless --path . -- --lan-smoke --role=client
##
## boot.gd adds this node next to the current scene rather than as it, so the
## real scene changes do not free it.
##
## Each copy presses the buttons a player would, answers every question with the
## first option, and does some farming. The host checks that Player 2's actions
## reached the simulation and the session file; the client checks that it saw
## the host's field. Exit code 0 means everything passed.

const LanDiscovery := preload("res://scripts/net/lan_discovery.gd")
const TIME_SCALE := 12.0
const TIMEOUT_SECONDS := 240.0

var role := "host"
## --drop: the client walks out in the middle of the first season and never
## comes back. The host waits for it, gives up, saves a partial file and goes
## back to the lobby.
var drop := false
## --blip: the client's link drops in the middle of the first season (as a phone
## leaving Wi-Fi range would). It reconnects by itself, lands back in the same
## season, and the pair finish the whole session.
var blip := false
## Further disconnect cases (see run_lan_matrix in the test notes):
## --host-blip   the host's link drops mid-season and comes back.
## --host-quit   the host's app dies mid-season (host side).
## --expect-host-gone  client: the host died; check the reconnect screen, the
##               host's backup file, then give up and land on the main menu.
## --lobby-only  a freshly started host that only opens a lobby.
## --expect-lobby client: the host died and came back with a fresh lobby; land
##               in it, still connected.
## --wait-long   host: wait up to 90 s for Player 2 instead of 12 s.
## --rejoin      client: a fresh copy of the app joining a session that is
##               waiting for its Player 2 (found under Find games as "Rejoin").
var host_blip := false
var host_quit := false
var expect_host_gone := false
var lobby_only := false
var expect_lobby := false
var wait_long := false
var rejoin := false
var _saw_rejoin_beacon := false
var _client_saw_partner_lost := false
var _blipped := false
var _resumed_farm := false
var _host_saw_partner_lost := false
var _checks: Array[String] = []
var _failures: Array[String] = []
var _discovery: Node = null
var _seen_host_by_discovery := false
var _did_farm_action := {}
var _remote_tilled := false
var _snapshot_changes := 0
var _scenes_seen: Array[String] = []
var _done := false
var _started_msec := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.trim_prefix("--role=")
		if arg == "--drop":
			drop = true
		if arg == "--blip":
			blip = true
		host_blip = host_blip or arg == "--host-blip"
		host_quit = host_quit or arg == "--host-quit"
		expect_host_gone = expect_host_gone or arg == "--expect-host-gone"
		lobby_only = lobby_only or arg == "--lobby-only"
		expect_lobby = expect_lobby or arg == "--expect-lobby"
		wait_long = wait_long or arg == "--wait-long"
		rejoin = rejoin or arg == "--rejoin"
	_started_msec = Time.get_ticks_msec()
	print("[lan:%s] starting" % role)
	Engine.time_scale = TIME_SCALE
	get_tree().node_added.connect(_on_node_added)
	if role == "solo":
		# --role=solo: no network at all. One player plays the whole session
		# alone, from the main menu's Play solo to the final results.
		await get_tree().create_timer(0.5, true, false, true).timeout
		SessionController.start_new_session(true)
	elif role == "host":
		_start_host()
	else:
		_start_client()


func _start_host() -> void:
	check(Net.host("Smoke test farm") == OK, "host opens the game port")
	if lobby_only:
		Net.peer_joined.connect(func(_id: int) -> void:
			check(true, "the returning Player 2 found the new lobby")
			await get_tree().create_timer(2.0, true, false, true).timeout
			_done = true
			_report_and_quit())
		return
	_discovery = LanDiscovery.new()
	get_tree().root.add_child.call_deferred(_discovery)
	_discovery.ready.connect(func() -> void: _discovery.start_broadcasting(), CONNECT_ONE_SHOT)
	Net.peer_joined.connect(_on_host_peer_joined)
	Net.partner_lost.connect(_on_host_partner_lost)


## Player 2 dropped. Give them a while to come back (--blip does); if they do
## not (--drop), stop waiting the way a person would.
func _on_host_partner_lost(_reason: String) -> void:
	_host_saw_partner_lost = true
	print("[lan:host] Player 2 lost - waiting for a reconnect")
	await get_tree().create_timer(90.0 if wait_long else 12.0, true, false, true).timeout
	if Net.waiting_for_partner:
		print("[lan:host] Player 2 did not come back - giving up")
		SessionController.give_up_waiting()


func _on_host_peer_joined(_id: int) -> void:
	if Net.in_session:
		return
	check(true, "Player 2 connected")
	await get_tree().create_timer(1.0 * TIME_SCALE).timeout
	_discovery.stop()
	SessionController.start_new_session()


func _start_client() -> void:
	Net.partner_lost.connect(func(_r: String) -> void: _client_saw_partner_lost = true)
	if rejoin:
		_start_rejoin()
		return
	_discovery = LanDiscovery.new()
	get_tree().root.add_child.call_deferred(_discovery)
	await _discovery.ready
	_discovery.start_listening()
	_discovery.hosts_changed.connect(func(hosts: Array) -> void:
		if not hosts.is_empty():
			_seen_host_by_discovery = true)
	# Give discovery a few seconds; join by address either way.
	var waited := 0.0
	while waited < 5.0 and not _seen_host_by_discovery:
		await get_tree().create_timer(0.25 * TIME_SCALE).timeout
		waited += 0.25
	print("[lan:client] discovery saw the host: %s" % _seen_host_by_discovery)
	_discovery.stop()
	check(Net.join("127.0.0.1") == OK, "client starts connecting")


## A fresh copy of the app, arriving while the host waits for its Player 2.
func _start_rejoin() -> void:
	_discovery = LanDiscovery.new()
	get_tree().root.add_child.call_deferred(_discovery)
	await _discovery.ready
	_discovery.start_listening()
	var target := {}
	var waited := 0.0
	while waited < 20.0 and target.is_empty():
		for info in _discovery.hosts():
			if bool(info.get("rejoin", false)):
				target = info
		await get_tree().create_timer(0.25, true, false, true).timeout
		waited += 0.25
	_discovery.stop()
	_saw_rejoin_beacon = not target.is_empty()
	check(_saw_rejoin_beacon, "Find games lists the waiting session as one to rejoin")
	_seen_host_by_discovery = _saw_rejoin_beacon
	check(Net.join("127.0.0.1") == OK, "the fresh app starts joining the waiting session")


# ---------------------------------------------------------------- driving ---

func _on_node_added(node: Node) -> void:
	if node.get_parent() != get_tree().root or node == self or node == _discovery:
		return
	var scene_name := node.name
	_scenes_seen.append(scene_name)
	print("[lan:%s] screen: %s" % [role, scene_name])
	_drive.call_deferred(node)


func _drive(scene: Node) -> void:
	if not is_instance_valid(scene):
		return
	await get_tree().create_timer(0.3 * TIME_SCALE).timeout
	if not is_instance_valid(scene):
		return
	match String(scene.name):
		"PlayerSetup":
			if role != "client":
				_press(scene, "Page/PageScroll/Row/PageContent/Buttons/ConfirmButton")
			else:
				check((scene.get_node("Page/PageScroll/Row/PageContent/Buttons/ConfirmButton") as Button).disabled,
					"client cannot confirm roles")
		"AssessmentScreen":
			await _answer_assessment(scene)
		"ScenarioBriefing":
			if role != "client":
				_press(scene, "Page/PageScroll/Row/PageContent/StartButton")
		"Farm":
			if role == "client" and scene.get("resumed"):
				_resumed_farm = true
				check(scene.elapsed > 0.0, "client rejoined the season already under way (%.1f s in)" % scene.elapsed)
			if role == "host" and (host_blip or host_quit) and not _blipped:
				_blipped = true
				await _play_farm(scene)
				if host_quit:
					print("[lan:host] the host app dies (quitting without a goodbye)")
					_done = true
					print("[lan:host] === %d checks, %d failed ===" % [_checks.size(), _failures.size()])
					get_tree().quit(1 if not _failures.is_empty() else 0)
					return
				print("[lan:host] dropping the host's link on purpose (host-blip)")
				Net.simulate_connection_loss()
				return
			if blip and role == "client" and not _blipped:
				_blipped = true
				await _play_farm(scene)
				print("[lan:client] dropping the link on purpose (blip)")
				Net.simulate_connection_loss()
				return
			if drop and role == "client":
				await get_tree().create_timer(2.0 * TIME_SCALE).timeout
				print("[lan:client] dropping out on purpose")
				get_tree().quit(0)
				return
			await _play_farm(scene)
		"MultiplayerMenu":
			if role == "client" and expect_lobby and _client_saw_partner_lost:
				check(Net.is_client(), "client is still connected, in the new host's lobby")
				var notice_text := (scene.get_node("Page/PageScroll/Layout/Notice") as Label).text
				check(notice_text.contains("ended the session"), "the lobby says why: '%s'" % notice_text)
				_done = true
				_report_and_quit()
				return
			if role == "host" and GameState.pre_assessment.size() > 0:
				_done = true
				var partial := GameplayLogger.output_directory().path_join(
					"session_%s_partial.json" % GameState.session_id)
				check(FileAccess.file_exists(partial), "host saved a partial file when Player 2 left")
				check(not Net.in_session and Net.is_host(), "host is back in the lobby, still hosting")
				var notice_label := scene.get_node("Page/PageScroll/Layout/Notice") as Label
				check(notice_label.text.contains("disconnected"), "lobby says why: '%s'" % notice_label.text)
				_report_and_quit()
		"MainMenu":
			if role == "client" and expect_host_gone and _client_saw_partner_lost:
				var footer := (scene.get_node("Page/PageScroll/Row/PageContent/Footer") as Label).text
				check(footer.contains("left the session"), "client is back at the main menu, which says why: '%s'" % footer)
				_done = true
				_report_and_quit()
		"ScenarioResults":
			if role != "client":
				_press(scene, "Page/PageScroll/Row/PageContent/ContinueButton")
		"UsabilityScreen":
			await _answer_usability(scene)
		"FinalResults":
			_finish(scene)


func _press(scene: Node, path: String) -> void:
	var button := scene.get_node_or_null(path) as Button
	if button == null:
		check(false, "button exists: %s" % path)
		return
	if button.disabled:
		check(false, "button enabled: %s" % path)
		return
	button.pressed.emit()


func _answer_assessment(scene: Node) -> void:
	# Looked up by name: the phone layout moves these into two columns.
	var next := scene.find_child("NextButton", true, false) as Button
	var option := scene.find_child("Option0", true, false) as Button
	var question := scene.find_child("Question", true, false) as Control
	var guard := 0
	while is_instance_valid(scene) and guard < 40:
		guard += 1
		if not question.visible:
			break
		option.pressed.emit()
		await get_tree().process_frame
		if not is_instance_valid(scene):
			return
		next.pressed.emit()
		await get_tree().process_frame


func _answer_usability(scene: Node) -> void:
	var content := "Page/PageScroll/Row/PageContent"
	var guard := 0
	while is_instance_valid(scene) and guard < 40:
		guard += 1
		if not (scene.get_node(content + "/Statement") as Control).visible:
			break
		(scene.get_node(content + "/Answers").get_child(0) as Button).pressed.emit()
		await get_tree().process_frame
	# Offline (solo) the questionnaire ends on a "See our results" button.
	if role == "solo" and is_instance_valid(scene):
		var done_button := scene.get_node_or_null(content + "/HandoverButton") as Button
		if done_button != null and done_button.visible:
			done_button.pressed.emit()


## Each computer moves its own player onto the field and tills a tile.
func _play_farm(farm: Node) -> void:
	if role == "solo":
		await _play_solo_farm(farm)
		return
	var mine: Node = farm.players[Net.local_player_index]
	var other: Node = farm.players[1 - Net.local_player_index]
	check(mine.controlled and mine.net_mode, "%s controls its own player" % role)
	check(not other.controlled, "%s does not control the other player" % role)
	var scenario := int(GameState.current_scenario_index)
	if _did_farm_action.has(scenario):
		return
	_did_farm_action[scenario] = true

	# Walk onto a different column each, then till.
	var target: Node = farm.field.tile_at(1 if role == "host" else 8, 2)
	mine.use_test_input = true
	var guard := 0
	while is_instance_valid(farm) and mine.global_position.distance_to(target.global_position) > 20.0 and guard < 400:
		guard += 1
		mine.test_input = (target.global_position - mine.global_position).normalized()
		await get_tree().physics_frame
	if not is_instance_valid(farm):
		return
	mine.test_input = Vector2.ZERO
	# The Planter tills; the Field Monitor scouts. Either is a real action that
	# only the host can resolve.
	if Config.Tool.HOE in mine.tools:
		mine.select_tool(Config.Tool.HOE)
	else:
		mine.select_tool(Config.Tool.INSPECT)
	mine.try_use()
	await get_tree().create_timer(1.0 * TIME_SCALE).timeout
	if not is_instance_valid(farm):
		return
	if role == "host":
		# Player 2 stands near column 8. Either it tilled, or (as monitor) scouted.
		var remote_tile: Node = farm.field.tile_at(8, 2)
		if remote_tile.tilled_by == 1 or remote_tile.scouted:
			_remote_tilled = true
		var p2_pos: Vector2 = farm.players[1].global_position
		# In --drop mode Player 2 leaves before it gets there.
		check(drop or wait_long or p2_pos.distance_to(remote_tile.global_position) < 60.0,
			"host sees Player 2 walk to the tile (%.0f px away)" % p2_pos.distance_to(remote_tile.global_position))
	else:
		var host_tile: Node = farm.field.tile_at(1, 2)
		if host_tile.state != 0 or host_tile.scouted:
			_snapshot_changes += 1
		check(farm.elapsed > 0.0, "client clock follows the host (%.1f s)" % farm.elapsed)


## Solo: one farmer with every tool walks onto the field, tills, sows, waters
## and scouts the same tile - planter and monitor work by one person.
func _play_solo_farm(farm: Node) -> void:
	check(farm.players.size() == 1, "solo: one farmer on the field")
	var me: Node = farm.players[0]
	check((me.tools as Array).size() == 6, "solo: the farmer carries all six tools")
	var scenario := int(GameState.current_scenario_index)
	if _did_farm_action.has(scenario):
		return
	_did_farm_action[scenario] = true
	var target: Node = farm.field.tile_at(2, 2)
	me.use_test_input = true
	var guard := 0
	while is_instance_valid(farm) and me.global_position.distance_to(target.global_position) > 20.0 and guard < 400:
		guard += 1
		me.test_input = (target.global_position - me.global_position).normalized()
		await get_tree().physics_frame
	if not is_instance_valid(farm):
		return
	me.test_input = Vector2.ZERO
	for tool_id in [Config.Tool.HOE, Config.Tool.SEED, Config.Tool.WATER, Config.Tool.INSPECT]:
		me.select_tool(tool_id)
		me.try_use()
	check(target.state != 0, "solo: the farmer tilled and sowed a tile")
	check(target.scouted, "solo: the same farmer scouted it (a monitor's job)")


func _finish(scene: Node) -> void:
	if _done:
		return
	_done = true
	if role == "solo":
		check(GameState.single_player, "solo: the session stayed single-player")
		check(GameState.scenario_results.size() == 3, "solo: all three seasons were played")
		check(GameState.pre_assessment.get("players", []).size() == 1, "solo: one pre-test")
		check(GameState.post_assessment.get("players", []).size() == 1, "solo: one post-test")
		check(GameState.scenario_quizzes.size() == 3, "solo: three scenario quizzes")
		check((GameState.usability.get("responses", []) as Array).size() == 1, "solo: one questionnaire")
		var path := GameplayLogger.output_directory().path_join("session_%s.json" % GameState.session_id)
		check(FileAccess.file_exists(path), "solo: the session file was written")
		if FileAccess.file_exists(path):
			var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			check(doc is Dictionary and String((doc as Dictionary).get("mode", "")) == "single",
				"solo: the session file is marked as a single-player session")
		_report_and_quit()
		return
	check(GameState.scenario_results.size() == 3, "%s saw all three seasons" % role)
	check(GameState.pre_assessment.get("players", []).size() == 2, "pre-test holds both players")
	check(GameState.post_assessment.get("players", []).size() == 2, "post-test holds both players")
	check(GameState.scenario_quizzes.size() == 3, "three scenario quizzes recorded")
	if role == "host":
		check(_remote_tilled, "Player 2's action reached the host's field")
		check((GameState.usability.get("responses", []) as Array).size() == 2, "usability holds both players")
		var via_client := 0
		for event in GameplayLogger.events:
			if String(event.get("via", "")) == "player_2":
				via_client += 1
		check(via_client > 0, "Player 2's log lines reached the host (%d)" % via_client)
		var path := GameplayLogger.output_directory().path_join("session_%s.json" % GameState.session_id)
		check(FileAccess.file_exists(path), "host wrote the session file")
		var p2_actions := 0
		for result in GameState.scenario_results:
			for player in (result.get("players", []) as Array):
				if int(player.get("player", 0)) == 2:
					for key in (player.get("actions", {}) as Dictionary).keys():
						p2_actions += int(player["actions"][key])
		check(p2_actions > 0, "Player 2's actions are in the season results (%d)" % p2_actions)
	else:
		check(_snapshot_changes > 0, "client saw the host's tile change")
		check(_seen_host_by_discovery, "client found the host by LAN discovery")
	if rejoin:
		check(_resumed_farm or GameState.scenario_results.size() == 3,
			"the fresh app was put straight back into the session")
	if host_blip and role == "host":
		check(_host_saw_partner_lost, "host noticed its own link drop")
	if host_blip and role == "client":
		check(_client_saw_partner_lost, "client noticed the host drop and reconnected")
		check(_resumed_farm, "client got back into the farm after the host's link dropped")
	if blip:
		if role == "client":
			check(_resumed_farm, "client got back into the farm after losing the link")
		else:
			check(_host_saw_partner_lost, "host noticed Player 2 drop out")
			var back := false
			for event in GameplayLogger.events:
				if String(event.get("action", "")) == "player_2_reconnected":
					back = true
			check(back, "the session file records Player 2 reconnecting")
	_report_and_quit()


func check(ok: bool, what: String) -> void:
	_checks.append(what)
	if not ok:
		_failures.append(what)
		print("[lan:%s] FAIL %s" % [role, what])
	else:
		print("[lan:%s] ok   %s" % [role, what])


var _gave_up := false


func _physics_process(_delta: float) -> void:
	if role != "client" or not expect_host_gone or _gave_up:
		return
	if Net.reconnecting and Net.reconnect_attempts >= 3:
		_gave_up = true
		check(_client_saw_partner_lost, "client noticed the host was gone and shows the reconnect screen")
		var overlay_up := false
		for child in get_tree().root.get_children():
			if child.has_method("is_open") and child.is_open():
				overlay_up = true
		check(overlay_up, "the 'Connection lost - reconnecting' screen is up")
		check(get_tree().paused, "the game is paused while reconnecting")
		var backup := GameplayLogger.output_directory().path_join(
			"session_%s_autosave.json" % GameState.session_id)
		check(FileAccess.file_exists(backup), "the host left a backup of the research data (%s)" % backup.get_file())
		print("[lan:client] giving up on the host after %d attempts" % Net.reconnect_attempts)
		SessionController.give_up_reconnecting()


func _process(_delta: float) -> void:
	if not _done and (Time.get_ticks_msec() - _started_msec) / 1000.0 > TIMEOUT_SECONDS:
		_done = true
		check(false, "finished within %d s (screens: %s)" % [TIMEOUT_SECONDS, ", ".join(_scenes_seen)])
		_report_and_quit()


func _report_and_quit() -> void:
	print("[lan:%s] === %d checks, %d failed ===" % [role, _checks.size(), _failures.size()])
	await get_tree().create_timer(0.5 * TIME_SCALE).timeout
	get_tree().quit(1 if not _failures.is_empty() else 0)
