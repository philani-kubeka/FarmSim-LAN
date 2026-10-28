extends "res://tests/farm_sim_test.gd"
## The logger is the research instrument, so this test writes a real file and
## reads it back rather than trusting the in-memory list.


func run() -> void:
	GameState.reset_session()
	GameplayLogger.clear()
	GameplayLogger.set_enabled(true)

	check(GameplayLogger.events.is_empty(), "the logger starts empty")

	GameplayLogger.log_event("session", "session_started", {"session_id": GameState.session_id})
	GameplayLogger.log_player_action(0, "tile_tilled", {"tile": "3,2"})
	GameplayLogger.log_player_action(1, "tile_treated", {"tile": "4,1", "pest_level": 0.8})
	GameplayLogger.log_scenario("event_triggered", {"event": "drought"})
	GameplayLogger.log_assessment("question_answered", {"question_id": "k1", "correct": true})

	check_equal(GameplayLogger.events.size(), 5, "every logged event is retained")

	var player_event: Dictionary = GameplayLogger.events[1]
	check_equal(player_event.get("category"), "gameplay", "player actions are filed under gameplay")
	check_equal(player_event.get("player"), 1, "player actions record a 1-based player number")
	check_equal(player_event.get("role"), "planter", "player actions record the role, not a name")
	check(player_event.has("t"), "every event carries a timestamp")
	check(float(player_event.get("t", -1.0)) >= 0.0, "timestamps are non-negative")

	# No personal data: the only identifier in the document is the session id.
	var document := GameplayLogger.build_session_document()
	check(document.has("session_id"), "the session document is keyed by the anonymous session id")
	check(not document.has("player_name"), "no player name is stored")
	check(not document.has("email"), "no contact details are stored")
	check_equal(document.get("event_count"), 5, "the document reports its own event count")

	# Round-trip through disk.
	var path := GameplayLogger.write_session_file("_selftest")
	check(not path.is_empty(), "the session file is written to disk")
	if path.is_empty():
		return
	check(FileAccess.file_exists(path), "the written session file exists at %s" % path)

	var text := FileAccess.get_file_as_string(path)
	check(text.length() > 0, "the written session file is not empty")

	var json := JSON.new()
	check_equal(json.parse(text), OK, "the written session file is valid JSON")
	var reloaded: Variant = json.data
	if typeof(reloaded) != TYPE_DICTIONARY:
		fail("the written session file parses to an object")
		return

	var doc := reloaded as Dictionary
	check_equal(String(doc.get("session_id", "")), GameState.session_id,
		"the file on disk belongs to this session")
	check_equal(int(doc.get("event_count", -1)), 5, "the file on disk holds every event")
	var events: Variant = doc.get("events", [])
	check(typeof(events) == TYPE_ARRAY and (events as Array).size() == 5,
		"the events array survives the round trip")

	# The recorded events must match what actually happened, in order.
	var actions: Array[String] = []
	for entry in (events as Array):
		actions.append(String((entry as Dictionary).get("action", "")))
	check_equal(actions, ["session_started", "tile_tilled", "tile_treated",
		"event_triggered", "question_answered"] as Array[String],
		"the file records the same actions, in the order they happened")

	# Clean up the self-test artefact so it is never mistaken for study data.
	DirAccess.remove_absolute(path)
	check(not FileAccess.file_exists(path), "the self-test file is removed afterwards")

	GameplayLogger.clear()
