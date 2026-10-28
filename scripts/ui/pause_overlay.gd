extends CanvasLayer
## Pause during a season.
##
## The layout is pause_overlay.tscn, which the farm instances as a child. It runs
## with PROCESS_MODE_ALWAYS (set on the scene root) so it can still see the pause
## key and drive its own buttons while the rest of the tree is frozen. The farm's
## clock, the crops and both players are on the default process mode, so they
## stop dead.
##
## Pausing is recorded in the research data: a session where a pair stopped for
## two minutes mid-drought is not the same session as one that ran straight
## through, and the event log should say so.

signal resumed
signal quit_requested
## LAN port: lets the farm tell the other computer to pause as well.
signal paused_changed(paused: bool, from_remote: bool)

const CONTENT := "PauseRoot/Page/PageScroll/Row/PageContent"

var is_paused := false

@onready var _panel: Control = $PauseRoot
@onready var _hint: Label = get_node(CONTENT + "/Hint")
@onready var _resume_button: Button = get_node(CONTENT + "/Buttons/ResumeButton")
@onready var _abandon_button: Button = get_node(CONTENT + "/Buttons/AbandonButton")

var _paused_at_msec := 0


func _ready() -> void:
	_hint.text = "Tap Resume to carry on." if Config.is_mobile() \
		else "Press %s again to carry on." % InputSetup.describe("ui_pause")
	_resume_button.pressed.connect(func() -> void: set_paused(false))
	_abandon_button.pressed.connect(_on_quit_pressed)
	_apply(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_pause"):
		set_paused(not is_paused)
		get_viewport().set_input_as_handled()


func toggle() -> void:
	set_paused(not is_paused)


## `from_remote`: the other computer paused, so this one follows without
## logging it a second time or sending it back.
func set_paused(paused: bool, from_remote: bool = false) -> void:
	if paused == is_paused:
		return
	is_paused = paused
	_apply(paused)
	paused_changed.emit(paused, from_remote)
	if from_remote:
		if not paused:
			resumed.emit()
		return

	if paused:
		_paused_at_msec = Time.get_ticks_msec()
		GameplayLogger.log_scenario("paused", {
			"scenario_id": SessionController.pending_scenario.get("id", ""),
		})
	else:
		var seconds := (Time.get_ticks_msec() - _paused_at_msec) / 1000.0
		GameplayLogger.log_scenario("resumed", {
			"scenario_id": SessionController.pending_scenario.get("id", ""),
			"paused_seconds": snappedf(seconds, 0.01),
		})
		resumed.emit()


func _apply(paused: bool) -> void:
	if _panel != null:
		_panel.visible = paused
	get_tree().paused = paused
	if paused and _resume_button != null:
		_resume_button.grab_focus()


func _on_quit_pressed() -> void:
	set_paused(false)
	GameplayLogger.log_event("session", "session_abandoned", {
		"scenario_id": SessionController.pending_scenario.get("id", ""),
		"scenario_index": GameState.current_scenario_index + 1,
	})
	quit_requested.emit()
	SessionController.abandon_session()


func _exit_tree() -> void:
	# Never leave the tree paused because a scene changed while the overlay was up.
	if is_inside_tree() and get_tree() != null:
		get_tree().paused = false
