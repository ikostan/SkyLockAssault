"""
Main Menu Script

Handles initialization, button connections, and platform-specific behaviors for the main menu scene.

This script manages the main menu UI, including button presses, quit confirmation, and scene transitions.
It includes platform-specific handling for web exports.

:vartype quit_dialog: ConfirmationDialog
:vartype game_scene: PackedScene
:vartype options_menu: PackedScene
:vartype ui_panel: Panel
:vartype ui_container: VBoxContainer
:vartype start_button: Button
:vartype options_button: Button
:vartype quit_button: Button
:vartype background_music: AudioStreamPlayer2D
"""

extends Control

# Default relative path; override in Inspector if needed
const QUIT_DIALOG_DEFAULT_PATH: String = "VideoStreamPlayer/Panel/VBoxContainer/QuitDialog"
@export var quit_dialog_path: NodePath = NodePath(QUIT_DIALOG_DEFAULT_PATH)

# Reference to the quit dialog node, assigned in setup_quit_dialog or _ready()
var quit_dialog: ConfirmationDialog
var game_scene: PackedScene = preload("res://scenes/main_scene.tscn")
var options_menu: PackedScene = preload("res://scenes/options_menu.tscn")

@onready var ui_panel: Panel = $VideoStreamPlayer/Panel
@onready var ui_container: VBoxContainer = $VideoStreamPlayer/Panel/VBoxContainer
@onready var start_button: Button = $VideoStreamPlayer/Panel/VBoxContainer/StartButton
@onready var options_button: Button = $VideoStreamPlayer/Panel/VBoxContainer/OptionsButton
@onready var quit_button: Button = $VideoStreamPlayer/Panel/VBoxContainer/QuitButton
@onready var background_music: AudioStreamPlayer2D = $AudioStreamPlayer2D


func _input(event: InputEvent) -> void:
	"""
	Handles input events for the main menu.

	Logs mouse clicks and unlocks audio on web platforms upon user gesture.

	:param event: The input event to process.
	:type event: InputEvent
	:rtype: void
	"""
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos: Vector2 = event.position  # Explicitly type as Vector2
		Globals.log_message("Clicked at: (%s, %s)" % [pos.x, pos.y], Globals.LogLevel.DEBUG)

	# New: Unlock audio on first qualifying gesture (click or key press)
	if OS.get_name() == "Web" and not background_music.playing:
		background_music.play()
		Globals.log_message(
			"User gesture detected—starting background music.", Globals.LogLevel.DEBUG
		)


# Called when the node enters the scene tree for the first time.
# Initializes button signals, quit dialog connections, and web callbacks.
func _ready() -> void:
	"""
	Initializes the main menu when the node enters the scene tree.

	Connects button signals and sets up the quit dialog.

	:rtype: void
	"""
	Globals.log_message("Initializing main menu...", Globals.LogLevel.DEBUG)

	# Connect START button signal
	@warning_ignore("return_value_discarded")
	start_button.pressed.connect(_on_start_pressed)
	# Connect OPTIONS button signal
	@warning_ignore("return_value_discarded")
	options_button.pressed.connect(_on_options_button_pressed)
	# Connect QUIT button signal
	@warning_ignore("return_value_discarded")
	quit_button.pressed.connect(_on_quit_pressed)

	# Setup quit dialog
	setup_quit_dialog()


func setup_quit_dialog() -> void:
	"""
	Sets up the quit confirmation dialog.

	Finds the dialog node and connects signals if not already connected.
	Hides the dialog initially.

	:rtype: void
	"""
	quit_dialog = get_node_or_null(quit_dialog_path)
	if is_instance_valid(quit_dialog):
		# Connect 'confirmed' signal only if not already connected to avoid errors
		if not quit_dialog.confirmed.is_connected(_on_quit_dialog_confirmed):
			quit_dialog.confirmed.connect(_on_quit_dialog_confirmed)
		# Connect 'canceled' signal only if not already connected to avoid errors
		if not quit_dialog.canceled.is_connected(_on_quit_dialog_canceled):
			quit_dialog.canceled.connect(_on_quit_dialog_canceled)
		quit_dialog.hide()  # Ensure initially hidden
		Globals.log_message("QuitDialog signals connected.", Globals.LogLevel.DEBUG)
	else:
		Globals.log_message(
			"QuitDialog not found at path: " + str(quit_dialog_path), Globals.LogLevel.ERROR
		)


# Handles the Start button press.
# Loads the main game scene using PackedScene for efficiency.
func _on_start_pressed(args: Array = []) -> void:
	"""
	Handles the Start button press.

	Loads and transitions to the main game scene.

	:param args: Optional arguments (unused).
	:type args: Array
	:rtype: void
	"""
	# Stub; later: get_tree().change_scene_to_file("res://game_scene.tscn")
	Globals.log_message("Start Game menu button pressed.", Globals.LogLevel.DEBUG)

	if game_scene:
		Globals.log_message("Loading main game scene...", Globals.LogLevel.DEBUG)
		get_tree().change_scene_to_packed(game_scene)
	else:
		Globals.log_message("Error: Game scene not set!", Globals.LogLevel.ERROR)


# Handles the Options button press.
# Placeholder for loading an options scene.
# Shows options menu and toggles web overlays if on web.
func _on_options_button_pressed(args: Array = []) -> void:
	"""
	Handles the Options button press.

	Loads options and logs the action.

	:param args: Optional arguments (unused).
	:type args: Array
	:rtype: void
	"""
	Globals.log_message("Options button pressed.", Globals.LogLevel.DEBUG)
	Globals.load_options()  # Your existing load


# Handles the Quit button press.
# Displays the quit confirmation dialog if valid.
func _on_quit_pressed(args: Array = []) -> void:
	"""
	Handles the Quit button press.

	Shows the quit confirmation dialog if available.

	:param args: Optional arguments (unused).
	:type args: Array
	:rtype: void
	"""
	# Show confirmation dialog
	if is_instance_valid(quit_dialog):
		quit_dialog.show()
		Globals.log_message("Attempting to show QuitDialog.", Globals.LogLevel.DEBUG)
		quit_dialog.popup_centered()  # Sets visible=true internally
	else:
		Globals.log_message("No quit_dialog found.", Globals.LogLevel.ERROR)


# Called when the quit dialog is confirmed.
# Executes platform-specific quit (web redirect or app quit).
func _on_quit_dialog_confirmed() -> void:
	"""
	Handles quit dialog confirmation.

	Performs platform-specific quit actions.

	:rtype: void
	"""
	# User confirmed: Execute platform-specific quit
	if OS.get_name() == "Web":
		# Web export: Redirect to itch.io game page (clean exit, no freeze)
		JavaScriptBridge.eval("window.location.href = 'https://ikostan.itch.io/sky-lock-assault';")
	else:
		# Desktop/editor: Standard quit
		get_tree().quit()
	Globals.log_message("Quit confirmed and executed!", Globals.LogLevel.DEBUG)


# Called when the quit dialog is canceled.
# Hides the dialog and logs the action.
func _on_quit_dialog_canceled() -> void:
	"""
	Handles quit dialog cancellation.

	Hides the dialog and logs the action.

	:rtype: void
	"""
	# Optional: Handle cancel (e.g., play sound or log)
	quit_dialog.hide()
	Globals.log_message("Quit canceled.", Globals.LogLevel.DEBUG)
	# Dialog auto-hides on cancel, no extra code needed
