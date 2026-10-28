extends Node
## LAN discovery: lets a joining player see hosted games without typing an IP.
##
## The host sends a small JSON beacon by UDP broadcast once a second. A joining
## player listens on the same port and keeps a list of every host it has heard
## from recently. Nothing else is involved - no server, no internet - so it
## only works on one local network (and Windows Firewall may ask once to allow
## FarmSim on private networks).
##
## Beacon:  {"game": "FarmSim", "v": 1, "name": "...", "port": 7777,
##           "players": 1, "max": 2, "in_session": false}

signal hosts_changed(hosts: Array)

const DISCOVERY_PORT := 7778
const GAME_ID := "FarmSim"
const PROTOCOL_VERSION := 1
const BROADCAST_INTERVAL := 1.0
## A host not heard from for this long is dropped from the list.
const HOST_TIMEOUT := 4.0

enum Mode { IDLE, BROADCASTING, LISTENING }

var mode: int = Mode.IDLE

var _socket: PacketPeerUDP = null
var _broadcast_timer := 0.0
var _targets: Array[String] = []
## ip -> {"ip", "name", "port", "players", "max", "in_session", "seen_msec"}
var _hosts := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	stop()


# ---------------------------------------------------------------- control ---

func start_broadcasting() -> void:
	stop()
	_socket = PacketPeerUDP.new()
	_socket.set_broadcast_enabled(true)
	_targets = _broadcast_targets()
	mode = Mode.BROADCASTING
	_broadcast_timer = 0.0


func start_listening() -> Error:
	stop()
	_socket = PacketPeerUDP.new()
	var err := _socket.bind(DISCOVERY_PORT)
	if err != OK:
		_socket = null
		push_warning("LanDiscovery: could not listen on UDP %d (error %d)" % [DISCOVERY_PORT, err])
		return err
	mode = Mode.LISTENING
	_hosts.clear()
	hosts_changed.emit([])
	return OK


func stop() -> void:
	if _socket != null:
		_socket.close()
	_socket = null
	mode = Mode.IDLE
	if not _hosts.is_empty():
		_hosts.clear()
		hosts_changed.emit([])


func hosts() -> Array:
	var out: Array = _hosts.values()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("name", "")) < String(b.get("name", "")))
	return out


# ------------------------------------------------------------------- loop ---

func _process(delta: float) -> void:
	match mode:
		Mode.BROADCASTING:
			_broadcast_timer -= delta
			if _broadcast_timer <= 0.0:
				_broadcast_timer = BROADCAST_INTERVAL
				_send_beacon()
		Mode.LISTENING:
			_receive_beacons()
			_expire_hosts()


func _send_beacon() -> void:
	var beacon := JSON.stringify(build_beacon()).to_utf8_buffer()
	for target in _targets:
		_socket.set_dest_address(target, DISCOVERY_PORT)
		_socket.put_packet(beacon)


func build_beacon() -> Dictionary:
	return {
		"game": GAME_ID,
		"v": PROTOCOL_VERSION,
		"name": Net.host_name,
		"port": Net.GAME_PORT,
		"players": Net.player_count(),
		"max": Net.MAX_CLIENTS + 1,
		"in_session": Net.in_session,
		# A session whose Player 2 dropped out: they may take the seat back.
		"rejoin": Net.waiting_for_partner,
	}


func _receive_beacons() -> void:
	var changed := false
	while _socket.get_available_packet_count() > 0:
		var packet := _socket.get_packet()
		var ip := _socket.get_packet_ip()
		var info := parse_beacon(packet.get_string_from_utf8())
		if info.is_empty() or ip.is_empty():
			continue
		info["ip"] = ip
		info["seen_msec"] = Time.get_ticks_msec()
		var previous: Dictionary = _hosts.get(ip, {})
		if previous.is_empty() or _summary(previous) != _summary(info):
			changed = true
		_hosts[ip] = info
	if changed:
		hosts_changed.emit(hosts())


## Returns the beacon's fields, or {} if the packet is not a FarmSim beacon.
static func parse_beacon(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {}
	var data := json.data as Dictionary
	if String(data.get("game", "")) != GAME_ID or int(data.get("v", 0)) != PROTOCOL_VERSION:
		return {}
	return {
		"name": String(data.get("name", "FarmSim host")),
		"port": int(data.get("port", Net.GAME_PORT)),
		"players": int(data.get("players", 1)),
		"max": int(data.get("max", 2)),
		"in_session": bool(data.get("in_session", false)),
		"rejoin": bool(data.get("rejoin", false)),
	}


func _expire_hosts() -> void:
	var now := Time.get_ticks_msec()
	var stale: Array = []
	for ip in _hosts.keys():
		if now - int((_hosts[ip] as Dictionary).get("seen_msec", 0)) > HOST_TIMEOUT * 1000.0:
			stale.append(ip)
	for ip in stale:
		_hosts.erase(ip)
	if not stale.is_empty():
		hosts_changed.emit(hosts())


func _summary(info: Dictionary) -> String:
	return "%s|%d|%d|%s" % [info.get("name", ""), info.get("port", 0),
		info.get("players", 0), info.get("in_session", false)]


## The global broadcast address, plus a /24 subnet broadcast for every local
## IPv4 address. Some Windows setups only deliver one or the other.
func _broadcast_targets() -> Array[String]:
	var out: Array[String] = ["255.255.255.255"]
	var addresses := Net.local_addresses()
	for address in addresses:
		var parts := address.split(".")
		var subnet := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
		if not subnet in out:
			out.append(subnet)
	# No network at all: still let a second copy on this computer find us.
	if addresses.is_empty():
		out.append("127.0.0.1")
	return out
