extends Node
## LAN multiplayer for FarmSim (Local Multiplayer Port).
##
## Two computers on the same network, one player each. The host is always
## Player 1 and owns the simulation, the session flow and the research data.
## The client is Player 2: it sends its movement and tool use to the host and
## draws whatever the host tells it the farm looks like.
##
## Every RPC in the port goes through this autoload, because /root/Net exists on
## both peers at the same path no matter which screen is showing. Screens that
## care about network messages register themselves with set_handler() and the
## messages are forwarded to them.
##
## When nobody has hosted or joined, is_online() is false and the whole game
## behaves exactly like the original one-keyboard version.

signal hosting_started(port: int)
signal joined(host_ip: String)
signal connection_failed(reason: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
## Fired on either side when the session can no longer continue.
signal session_lost(reason: String)
signal status_changed(text: String)
## Mid-session the other player dropped (or this device lost the host). Nothing
## ends: the host waits, the client keeps trying to reconnect.
signal partner_lost(reason: String)
## The other player is back and the session carries on.
signal partner_back()

const GAME_PORT := 7777
const MAX_CLIENTS := 1
## Player index of this computer (0 = host / Player 1, 1 = client / Player 2).
var local_player_index := 0
## Name the host advertises on the network.
var host_name := ""
## True once the host has started the research session.
var in_session := false

## Results sent by the other player that the current screen has not consumed
## yet, keyed by assessment kind ("pre_assessment", "quiz_1", "usability", ...).
var remote_results := {}

var _peer: ENetMultiplayerPeer = null
var _handler: Object = null
var _remote_peer_id := 0

# ------------------------------------------------------------- reconnecting --
# A phone that locks its screen, walks out of Wi-Fi range or switches apps drops
# off the network for a while. Mid-session that no longer ends the session:
#
# * Host: Player 2 vanished without saying goodbye -> waiting_for_partner. The
#   game pauses, and the next device to connect takes Player 2's seat again.
# * Client: the host vanished -> reconnecting. It keeps dialling the same
#   address every RECONNECT_INTERVAL seconds until it gets through.
#
# Once both are connected again the host re-sends the current screen with the
# whole session state, so the returning player lands exactly where the pair is.
# Leaving on purpose (Leave, Back, Quit) sends a goodbye first, so a deliberate
# exit still ends the session the way it always did.

const RECONNECT_INTERVAL := 2.0
## ENet notices a dead link after at most this long (it used to be ~30 s).
const PEER_TIMEOUT_MIN_MS := 3000
const PEER_TIMEOUT_MAX_MS := 10000

## Host: Player 2 dropped mid-session and the host is waiting for them.
var waiting_for_partner := false
## Client: lost the host mid-session and is trying to get back in.
var reconnecting := false
## When the link was lost (Time.get_ticks_msec), for the waiting screen and log.
var lost_since_msec := 0
## How many times the client has dialled the host since the link was lost.
var reconnect_attempts := 0

var _host_address := ""
var _host_port := GAME_PORT
var _retry_timer := 0.0
var _attempt_in_progress := false
var _attempt_started_msec := 0
## An attempt (dialling, or waiting for the host to put us back in) older than
## this is abandoned and a fresh one started.
const ATTEMPT_TIMEOUT_MSEC := 9000
var _partner_said_goodbye := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ------------------------------------------------------------------ state ---

func is_online() -> bool:
	return _peer != null


func is_host() -> bool:
	return is_online() and multiplayer.is_server()


func is_client() -> bool:
	return is_online() and not multiplayer.is_server()


## Both players are connected.
func is_ready() -> bool:
	return is_online() and _remote_peer_id != 0


func remote_peer_id() -> int:
	return _remote_peer_id


func player_count() -> int:
	if not is_online():
		return 0
	return 2 if _remote_peer_id != 0 else 1


## The screen or farm that wants to receive network messages. One at a time;
## the previous handler is replaced.
func set_handler(handler: Object) -> void:
	_handler = handler


func clear_handler(handler: Object) -> void:
	if _handler == handler:
		_handler = null


# -------------------------------------------------------------- host/join ---

func host(advertised_name: String = "", port: int = GAME_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		connection_failed.emit("Could not open port %d (error %d). Is another copy already hosting?" % [port, err])
		return err
	_peer = peer
	multiplayer.multiplayer_peer = peer
	local_player_index = 0
	host_name = advertised_name if not advertised_name.strip_edges().is_empty() else default_host_name()
	in_session = false
	remote_results.clear()
	hosting_started.emit(port)
	status_changed.emit("Hosting on port %d. Waiting for Player 2..." % port)
	return OK


func join(address: String, port: int = GAME_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address.strip_edges(), port)
	if err != OK:
		connection_failed.emit("Could not connect to %s:%d (error %d)." % [address, port, err])
		return err
	_peer = peer
	multiplayer.multiplayer_peer = peer
	local_player_index = 1
	in_session = false
	remote_results.clear()
	_host_address = address.strip_edges()
	_host_port = port
	status_changed.emit("Connecting to %s..." % address)
	return OK


## Closes the connection, if there is one. Safe to call at any time. Tells the
## other side first, so it knows this was on purpose and does not wait for a
## reconnect.
func leave() -> void:
	if _peer != null and _remote_peer_id != 0 and not reconnecting:
		_rpc_goodbye.rpc_id(_remote_peer_id)
		var connection := _peer.host
		if connection != null:
			connection.flush()
	_close_peer()
	_remote_peer_id = 0
	in_session = false
	remote_results.clear()
	local_player_index = 0
	waiting_for_partner = false
	reconnecting = false
	_attempt_in_progress = false
	_partner_said_goodbye = false


func _close_peer() -> void:
	if _peer != null:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


## Seconds since the link was lost, for the waiting screen.
func seconds_lost() -> float:
	if lost_since_msec == 0:
		return 0.0
	return (Time.get_ticks_msec() - lost_since_msec) / 1000.0


func _tighten_timeout(peer_id: int) -> void:
	if _peer == null:
		return
	var packet_peer := _peer.get_peer(peer_id)
	if packet_peer != null:
		packet_peer.set_timeout(32, PEER_TIMEOUT_MIN_MS, PEER_TIMEOUT_MAX_MS)


func default_host_name() -> String:
	if OS.has_feature("mobile"):
		var model := OS.get_model_name()
		if not model.is_empty() and model != "GenericDevice":
			return "%s's farm" % model
	var who := OS.get_environment("USERNAME")
	if who.is_empty():
		who = OS.get_environment("USER")
	if who.is_empty():
		who = "FarmSim"
	return "%s's farm" % who


## This computer's LAN addresses, for showing to the person hosting.
func local_addresses() -> Array[String]:
	var out: Array[String] = []
	for address in IP.get_local_addresses():
		if address.count(".") == 3 and not address.begins_with("127.") and not address.begins_with("169.254."):
			out.append(address)
	return out


# ---------------------------------------------------------------- signals ---

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		if in_session:
			# Mid-session only the missing Player 2 may come back.
			if not waiting_for_partner or _remote_peer_id != 0:
				_peer.disconnect_peer(id)
				return
			_remote_peer_id = id
			_tighten_timeout(id)
			# The session resumes when this device says hello (_rpc_hello).
			return
		if _remote_peer_id != 0:
			# Only one partner.
			_peer.disconnect_peer(id)
			return
		_remote_peer_id = id
		_tighten_timeout(id)
		status_changed.emit("Player 2 has joined.")
	else:
		_remote_peer_id = 1
	peer_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	if id != _remote_peer_id:
		return
	_remote_peer_id = 0
	peer_left.emit(id)
	if not multiplayer.is_server():
		return
	var on_purpose := _partner_said_goodbye
	_partner_said_goodbye = false
	if in_session and not on_purpose:
		if not waiting_for_partner:
			waiting_for_partner = true
			lost_since_msec = Time.get_ticks_msec()
			status_changed.emit("Player 2 lost connection. Waiting for them to come back...")
			partner_lost.emit("Player 2 lost connection.")
		return
	status_changed.emit("Player 2 left. Waiting for Player 2...")
	if in_session:
		in_session = false
		waiting_for_partner = false
		session_lost.emit("Player 2 left the session.")


func _on_connected_to_server() -> void:
	_remote_peer_id = 1
	_attempt_in_progress = false
	_tighten_timeout(1)
	var was_reconnecting := reconnecting
	_rpc_hello.rpc_id(1, was_reconnecting or in_session)
	if was_reconnecting:
		# Connected, but not back in the game until the host answers with the
		# current screen (_rpc_scene) or says the session is over. Until then the
		# waiting screen stays up, and no new attempt is started.
		_attempt_in_progress = true
		_attempt_started_msec = Time.get_ticks_msec()
		status_changed.emit("Reconnected - catching up with the host...")
		return
	joined.emit("")
	status_changed.emit("Connected. Waiting for the host to start the session...")


func _on_connection_failed() -> void:
	if reconnecting:
		# Not there yet - _process dials again shortly.
		_attempt_in_progress = false
		_close_peer()
		return
	leave()
	connection_failed.emit("Could not reach the host.")


func _on_server_disconnected() -> void:
	var on_purpose := _partner_said_goodbye
	_partner_said_goodbye = false
	if in_session and not on_purpose and not _host_address.is_empty():
		_begin_reconnect()
		return
	var was_in_session := in_session
	leave()
	session_lost.emit("The host closed the game." if was_in_session else "Disconnected from the host.")


## Client: the host vanished mid-session. Keep the session state, keep being
## Player 2, and dial the host until it answers.
func _begin_reconnect() -> void:
	_close_peer()
	_remote_peer_id = 0
	_attempt_in_progress = false
	if not reconnecting:
		# A fresh loss. (If the host turned us away while it had not yet noticed
		# the drop, keep counting from the original loss.)
		reconnect_attempts = 0
		lost_since_msec = Time.get_ticks_msec()
	reconnecting = true
	_retry_timer = 0.5
	status_changed.emit("Lost the host. Reconnecting...")
	partner_lost.emit("Lost connection to the host.")


func _process(delta: float) -> void:
	if not reconnecting:
		return
	if _attempt_in_progress:
		if Time.get_ticks_msec() - _attempt_started_msec < ATTEMPT_TIMEOUT_MSEC:
			return
		_attempt_in_progress = false
		_close_peer()
		_retry_timer = 0.0
	_retry_timer -= delta
	if _retry_timer > 0.0:
		return
	_retry_timer = RECONNECT_INTERVAL
	_try_reconnect()


func _try_reconnect() -> void:
	_close_peer()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(_host_address, _host_port) != OK:
		return
	_peer = peer
	multiplayer.multiplayer_peer = peer
	local_player_index = 1
	_attempt_in_progress = true
	_attempt_started_msec = Time.get_ticks_msec()
	reconnect_attempts += 1


## Test hook (the LAN smoke test's --blip / --host-blip modes): drop the link
## the way a phone going out of range would, without saying goodbye.
func simulate_connection_loss() -> void:
	if is_client():
		var host_peer := _peer.get_peer(1)
		if host_peer != null:
			host_peer.peer_disconnect_now()
		_begin_reconnect()
	elif is_host() and _remote_peer_id != 0:
		var client_peer := _peer.get_peer(_remote_peer_id)
		if client_peer != null:
			client_peer.peer_disconnect_now()
		_on_peer_disconnected(_remote_peer_id)


# ----------------------------------------------------------- handshake RPCs --

## Client -> host, every time it connects. `resuming` is true when it was in a
## session before (it lost the link, or the app was restarted mid-session).
@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello(resuming: bool) -> void:
	if not is_host() or multiplayer.get_remote_sender_id() != _remote_peer_id:
		return
	if in_session and waiting_for_partner:
		waiting_for_partner = false
		var away := seconds_lost()
		lost_since_msec = 0
		status_changed.emit("Player 2 is back.")
		GameplayLogger.log_event("session", "player_2_reconnected", {"seconds_away": snappedf(away, 0.1)})
		partner_back.emit()
	elif resuming and not in_session:
		# The host ended the session while Player 2 was away.
		_rpc_session_over.rpc_id(_remote_peer_id)


## Host -> client: the session Player 2 was trying to get back to is over.
@rpc("authority", "call_remote", "reliable")
func _rpc_session_over() -> void:
	in_session = false
	reconnecting = false
	_attempt_in_progress = false
	lost_since_msec = 0
	joined.emit("")
	SessionController.session_over_while_away()


## Either side, just before leaving on purpose.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_goodbye() -> void:
	_partner_said_goodbye = true


# ------------------------------------------------------- session flow RPC ---

## Host -> client: show this screen, with this copy of the session state.
func send_scene(path: String, state: Dictionary) -> void:
	if not is_host() or not is_ready():
		return
	_rpc_scene.rpc_id(_remote_peer_id, path, state)


@rpc("authority", "call_remote", "reliable")
func _rpc_scene(path: String, state: Dictionary) -> void:
	if reconnecting:
		# Back in: the host has put us on the screen the pair is on.
		reconnecting = false
		_attempt_in_progress = false
		lost_since_msec = 0
		status_changed.emit("Reconnected.")
		partner_back.emit()
	in_session = true
	SessionController.apply_network_state(state)
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Net: could not open %s (error %d)" % [path, err])


func mark_session_started() -> void:
	in_session = true


## Client -> host: a gameplay log line, so the host's session file is complete.
func send_log(category: String, action: String, details: Dictionary) -> void:
	if is_client():
		_rpc_log.rpc_id(1, category, action, details)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_log(category: String, action: String, details: Dictionary) -> void:
	if not is_host():
		return
	details["via"] = "player_2"
	GameplayLogger.log_event(category, action, details)


## Either side: this player's part of an assessment or questionnaire.
func send_player_result(kind: String, result: Dictionary) -> void:
	if is_ready():
		_rpc_player_result.rpc_id(_remote_peer_id, kind, result)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_player_result(kind: String, result: Dictionary) -> void:
	remote_results[kind] = result
	_forward("on_remote_player_result", [kind, result])


## Takes (and removes) a result the other player already sent.
func take_remote_result(kind: String) -> Dictionary:
	if not remote_results.has(kind):
		return {}
	var result: Dictionary = remote_results[kind]
	remote_results.erase(kind)
	return result


## Client -> host: Player 2 wants to stop the session.
func request_abandon() -> void:
	if is_client():
		_rpc_abandon.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_abandon() -> void:
	if is_host():
		SessionController.leave_session()


# ------------------------------------------------------------ farm RPCs -----
# Thin pass-throughs: the farm registers itself as the handler and does the work.

func send_transform(position: Vector2, facing: Vector2, flip: bool) -> void:
	if is_ready():
		_rpc_transform.rpc_id(_remote_peer_id, position, facing, flip)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_transform(position: Vector2, facing: Vector2, flip: bool) -> void:
	_forward("on_remote_transform", [position, facing, flip])


func send_use(tool_id: int, tile_column: int, tile_row: int) -> void:
	if is_client():
		_rpc_use.rpc_id(1, tool_id, tile_column, tile_row)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_use(tool_id: int, tile_column: int, tile_row: int) -> void:
	_forward("on_remote_use", [tool_id, tile_column, tile_row])


func send_tool(player_index: int, tool_id: int) -> void:
	if is_ready():
		_rpc_tool.rpc_id(_remote_peer_id, player_index, tool_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_tool(player_index: int, tool_id: int) -> void:
	_forward("on_remote_tool", [player_index, tool_id])


func send_snapshot(snapshot: Dictionary) -> void:
	if is_host() and is_ready():
		_rpc_snapshot.rpc_id(_remote_peer_id, snapshot)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_snapshot(snapshot: Dictionary) -> void:
	_forward("on_snapshot", [snapshot])


func send_player_message(player_index: int, message: String, kind: String) -> void:
	if is_host() and is_ready():
		_rpc_player_message.rpc_id(_remote_peer_id, player_index, message, kind)


@rpc("authority", "call_remote", "reliable")
func _rpc_player_message(player_index: int, message: String, kind: String) -> void:
	_forward("on_remote_player_message", [player_index, message, kind])


func send_event(title: String, body: String, icon_key: String) -> void:
	if is_host() and is_ready():
		_rpc_event.rpc_id(_remote_peer_id, title, body, icon_key)


@rpc("authority", "call_remote", "reliable")
func _rpc_event(title: String, body: String, icon_key: String) -> void:
	_forward("on_remote_event", [title, body, icon_key])


func send_pause(paused: bool) -> void:
	if is_ready():
		_rpc_pause.rpc_id(_remote_peer_id, paused)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_pause(paused: bool) -> void:
	_forward("on_remote_pause", [paused])


func _forward(method: String, args: Array) -> void:
	if _handler != null and is_instance_valid(_handler) and _handler.has_method(method):
		_handler.callv(method, args)
