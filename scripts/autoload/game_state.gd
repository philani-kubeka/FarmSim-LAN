extends Node
## Holds everything that survives a scene change within one research session:
## the anonymous session id, the two players' roles, assessment scores and the
## per-scenario outcomes.
##
## Deliberately plain data. No personal information is collected: participants
## are identified only by a randomly generated session id and the labels
## "Player 1" / "Player 2".

signal state_reset

const SCENARIO_COUNT := 3

var session_id := ""
var session_started_unix := 0

## Role ids from Config.ROLE_TOOLS, one per player index (0 = P1, 1 = P2).
var player_roles: Array[String] = ["planter", "monitor"]

## Filled in as the session progresses.
var pre_assessment := {}
var post_assessment := {}
var scenario_results: Array[Dictionary] = []
var scenario_quizzes: Array[Dictionary] = []
## Per-player usability answers, filled in after the post-test.
var usability := {}
## Who played. Empty for the normal human study; AI-played sessions fill it in.
var participant := {}

## True for a single-player session: one farmer, carrying both roles' tools.
## Set by SessionController.start_new_session(true) after reset_session().
var single_player := false

## Index of the scenario about to be played (0-based).
var current_scenario_index := 0


func _ready() -> void:
	reset_session()


func reset_session() -> void:
	session_id = _generate_session_id()
	session_started_unix = int(Time.get_unix_time_from_system())
	player_roles = ["planter", "monitor"]
	single_player = false
	pre_assessment = {}
	post_assessment = {}
	scenario_results = []
	scenario_quizzes = []
	usability = {}
	participant = {}
	current_scenario_index = 0
	state_reset.emit()


## How many people are playing this session: 1 solo, otherwise 2.
func player_count() -> int:
	return 1 if single_player else 2


func swap_roles() -> void:
	var first := player_roles[0]
	player_roles[0] = player_roles[1]
	player_roles[1] = first


func role_for_player(player_index: int) -> String:
	if player_index < 0 or player_index >= player_roles.size():
		return "planter"
	return player_roles[player_index]


func record_scenario_result(result: Dictionary) -> void:
	scenario_results.append(result)


func record_scenario_quiz(result: Dictionary) -> void:
	scenario_quizzes.append(result)


## Total harvested yield across every scenario played so far.
func total_yield() -> float:
	var total := 0.0
	for result in scenario_results:
		total += float(result.get("total_yield", 0.0))
	return total


## Knowledge gain in percentage points, or NAN if either test is missing.
## Each player answers the tests on their own; this is the pair mean.
func knowledge_gain_percent() -> float:
	if pre_assessment.is_empty() or post_assessment.is_empty():
		return NAN
	var pre := float(pre_assessment.get("percent", 0.0))
	var post := float(post_assessment.get("percent", 0.0))
	return post - pre


## One player's own knowledge gain (player_index 0 = P1), or NAN if missing.
func knowledge_gain_for_player(player_index: int) -> float:
	var pre := player_assessment(pre_assessment, player_index)
	var post := player_assessment(post_assessment, player_index)
	if pre.is_empty() or post.is_empty():
		return NAN
	return float(post.get("percent", 0.0)) - float(pre.get("percent", 0.0))


## The part of an assessment result belonging to one player, or {} if absent.
func player_assessment(assessment: Dictionary, player_index: int) -> Dictionary:
	for entry in (assessment.get("players", []) as Array):
		if int((entry as Dictionary).get("player", 0)) == player_index + 1:
			return entry as Dictionary
	return {}


func _generate_session_id() -> String:
	var alphabet := "abcdefghjkmnpqrstuvwxyz23456789"
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var out := ""
	for _i in range(8):
		out += alphabet[rng.randi_range(0, alphabet.length() - 1)]
	return out


## Everything the logger needs to describe this session.
func to_summary_dictionary() -> Dictionary:
	var summary := {
		"session_id": session_id,
		"session_started_unix": session_started_unix,
		"prototype": Config.PROTOTYPE_NAME,
		"prototype_version": Config.PROTOTYPE_VERSION,
		"research_context": Config.RESEARCH_CONTEXT,
		# "single" (one farmer with both roles' tools) or "pair".
		"mode": "single" if single_player else "pair",
		"player_roles": ({"player_1": player_roles[0]} if single_player else {
			"player_1": player_roles[0],
			"player_2": player_roles[1],
		}),
		"pre_assessment": pre_assessment,
		"scenarios": scenario_results,
		"scenario_quizzes": scenario_quizzes,
		"post_assessment": post_assessment,
		"usability": usability,
		# JSON has no NAN literal, so an incomplete session reports null here.
		"knowledge_gain_percent": (null if is_nan(knowledge_gain_percent()) else knowledge_gain_percent()),
		"knowledge_gain_by_player": {
			"player_1": _json_number(knowledge_gain_for_player(0)),
			"player_2": _json_number(knowledge_gain_for_player(1)),
		},
		"total_yield": total_yield(),
	}
	if not participant.is_empty():
		summary["participant"] = participant
	return summary


func _json_number(value: float) -> Variant:
	if is_nan(value):
		return null
	return value
