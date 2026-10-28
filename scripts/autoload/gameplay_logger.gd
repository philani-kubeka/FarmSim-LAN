extends Node
## Local, anonymous research logger.
##
## Every meaningful gameplay and assessment event is appended to an in-memory
## list and flushed to a single JSON file per session. No account, no login and
## no personal data: a session is identified by a random 8-character id.
##
## Output location:
##   res://data/sessions/  while running from the project folder (the normal
##                         case for a supervised research session), because that
##                         keeps the data next to the project and easy to collect
##   user://sessions/      as a fallback when res:// is read-only (exported build)

signal event_logged(event: Dictionary)

var events: Array[Dictionary] = []
var _output_dir := ""
var _session_start_msec := 0
var _enabled := true


func _ready() -> void:
	_session_start_msec = Time.get_ticks_msec()
	_output_dir = _resolve_output_dir()


## Seconds since the logger started, rounded to milliseconds.
func session_time() -> float:
	return (Time.get_ticks_msec() - _session_start_msec) / 1000.0


func set_enabled(enabled: bool) -> void:
	_enabled = enabled


func clear() -> void:
	events.clear()
	_session_start_msec = Time.get_ticks_msec()


## Records one event. `category` groups events for analysis
## (gameplay / assessment / session / scenario).
func log_event(category: String, action: String, details: Dictionary = {}) -> Dictionary:
	var event := {
		"t": snappedf(session_time(), 0.001),
		"category": category,
		"action": action,
	}
	for key in details.keys():
		event[key] = details[key]
	# LAN port: Player 2's computer keeps no session file of its own. Its events
	# go to the host, which writes the one file for the pair.
	if Net.is_client():
		Net.send_log(category, action, details)
		return event
	if _enabled:
		events.append(event)
		event_logged.emit(event)
	return event


func log_player_action(player_index: int, action: String, details: Dictionary = {}) -> void:
	var merged := details.duplicate()
	merged["player"] = player_index + 1
	merged["role"] = GameState.role_for_player(player_index)
	log_event("gameplay", action, merged)


func log_scenario(action: String, details: Dictionary = {}) -> void:
	log_event("scenario", action, details)


func log_assessment(action: String, details: Dictionary = {}) -> void:
	log_event("assessment", action, details)


## Builds the full session document that gets written to disk.
func build_session_document() -> Dictionary:
	var doc := GameState.to_summary_dictionary()
	doc["logged_at_unix"] = int(Time.get_unix_time_from_system())
	doc["event_count"] = events.size()
	doc["events"] = events
	return doc


## Writes the session document. Returns the path written, or "" on failure.
func write_session_file(suffix: String = "") -> String:
	# A final or partial file supersedes the running backup.
	if suffix != AUTOSAVE_SUFFIX:
		discard_autosave()
	var doc := build_session_document()
	var filename := "session_%s%s.json" % [GameState.session_id, suffix]
	var path := _output_dir.path_join(filename)
	var json := JSON.stringify(doc, "  ")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("GameplayLogger: could not open %s (error %d)" % [path, FileAccess.get_open_error()])
		return ""
	file.store_string(json)
	file.close()
	return path


## The running backup written at every screen change of a session, so data
## survives the host's app being killed (a phone battery dying, Android closing
## the app). Removed when the real session file - final or partial - is written.
const AUTOSAVE_SUFFIX := "_autosave"


func write_autosave() -> String:
	if GameState.session_id.is_empty():
		return ""
	return write_session_file(AUTOSAVE_SUFFIX)


func discard_autosave() -> void:
	if GameState.session_id.is_empty():
		return
	var path := _output_dir.path_join("session_%s%s.json" % [GameState.session_id, AUTOSAVE_SUFFIX])
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## Sends session files somewhere else, e.g. AI-played sessions kept apart from
## human ones. An empty string restores the normal location.
func set_output_directory(dir_path: String) -> void:
	if dir_path.is_empty():
		_output_dir = _resolve_output_dir()
	else:
		DirAccess.make_dir_recursive_absolute(dir_path)
		_output_dir = dir_path

func output_directory() -> String:
	return _output_dir


func _resolve_output_dir() -> String:
	if _directory_is_writable(Config.PROJECT_SESSION_DIR):
		return Config.PROJECT_SESSION_DIR
	DirAccess.make_dir_recursive_absolute(Config.USER_SESSION_DIR)
	return Config.USER_SESSION_DIR


func _directory_is_writable(dir_path: String) -> bool:
	var err := DirAccess.make_dir_recursive_absolute(dir_path)
	if err != OK and err != ERR_ALREADY_EXISTS:
		return false
	var probe_path := dir_path.path_join(".write_probe")
	var probe := FileAccess.open(probe_path, FileAccess.WRITE)
	if probe == null:
		return false
	probe.store_string("ok")
	probe.close()
	DirAccess.remove_absolute(probe_path)
	return true
