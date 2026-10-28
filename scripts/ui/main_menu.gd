extends Control
## Main menu. Deliberately minimal: this is a supervised research session, not a
## commercial title, so there is no scenario select, no profile and no store.
##
## The layout is main_menu.tscn. This script only fills in the version footer and
## wires the three buttons.

@onready var _start_button: Button = $Page/PageScroll/Row/PageContent/StartButton
@onready var _multiplayer_button: Button = $Page/PageScroll/Row/PageContent/MultiplayerButton
@onready var _solo_button: Button = $Page/PageScroll/Row/PageContent/SoloButton
@onready var _instructions_button: Button = $Page/PageScroll/Row/PageContent/InstructionsButton
@onready var _quit_button: Button = $Page/PageScroll/Row/PageContent/QuitButton
@onready var _footer: Label = $Page/PageScroll/Row/PageContent/Footer


func _ready() -> void:
	#_footer.text = "%s %s - %s" % [
		#Config.PROTOTYPE_NAME, Config.PROTOTYPE_VERSION, Config.RESEARCH_CONTEXT
	#]
	_start_button.pressed.connect(_on_start_pressed)
	_multiplayer_button.pressed.connect(_on_multiplayer_pressed)
	_solo_button.pressed.connect(_on_solo_pressed)
	_instructions_button.pressed.connect(_on_instructions_pressed)
	# Back at the menu means out of any LAN game.
	if Net.is_online():
		Net.leave()
	if not SessionController.notice.is_empty():
		_footer.text = SessionController.notice
		SessionController.notice = ""
	_quit_button.pressed.connect(_on_quit_pressed)
	if Config.is_mobile():
		_apply_mobile_menu()
		_multiplayer_button.grab_focus()
	else:
		_start_button.grab_focus()


## A phone holds one farmer, so the one-keyboard session is not offered there:
## playing together over Wi-Fi is the game, and gets the big button.
func _apply_mobile_menu() -> void:
	_start_button.visible = false
	_multiplayer_button.text = "Play with a friend"
	_multiplayer_button.theme_type_variation = &"PrimaryButton"
	var tagline := get_node_or_null("Page/PageScroll/Row/PageContent/Tagline") as Label
	if tagline != null:
		tagline.text = "A farming game. Play solo, or team up with a friend on the same network - phone or computer."
	if _footer.text == "FarmSim - Local Multiplayer Port":
		_footer.visible = false
	var title := get_node_or_null("Page/PageScroll/Row/PageContent/Title") as Label
	if title != null:
		title.add_theme_font_size_override("font_size", 60)


func _on_start_pressed() -> void:
	SessionController.start_new_session()


## One person, both roles' tools, on a computer or a phone.
func _on_solo_pressed() -> void:
	SessionController.start_new_session(true)


## Android's back gesture on the main menu leaves the app.
func _on_back_pressed() -> void:
	SessionController.quit_to_desktop()


func _on_multiplayer_pressed() -> void:
	SessionController.goto_multiplayer()


func _on_instructions_pressed() -> void:
	SessionController.goto_instructions(SessionController.SCENE_MAIN_MENU)


func _on_quit_pressed() -> void:
	SessionController.quit_to_desktop()
