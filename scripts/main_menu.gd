extends Control

# Default relative path; override in Inspector if needed
@export var quit_dialog_path: NodePath = NodePath("CenterContainer/VBoxContainer/QuitDialog")
# Reference to the quit dialog node, assigned in setup_quit_dialog or _ready()
var quit_dialog: ConfirmationDialog
var game_scene: PackedScene = preload("res://scenes/main_scene.tscn")

@onready var start_button: Button = $CenterContainer/VBoxContainer/StartButton
@onready var options_button: Button = $CenterContainer/VBoxContainer/OptionsButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/QuitButton

# Handles the main menu UI, including button connections and quit dialog logic.
# This script manages scene transitions and platform-specific quitting for web/desktop.


# Called when the node enters the scene tree for the first time.
# Initializes button signals and quit dialog connections.
func _ready() -> void:
	Globals.log_message("Initializing main menu...", Globals.LogLevel.DEBUG)
	start_button.pressed.connect(_on_start_pressed)
	options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	setup_quit_dialog()  # New: Handles dialog setup in one place
	# assert(quit_dialog != null, "QuitDialog must be assigned!")

	# Assign from exported path


# Connect dialog signals (can also do this in editor; add null check)
func setup_quit_dialog() -> void:
	quit_dialog = get_node(quit_dialog_path)
	if quit_dialog:
		Globals.log_message(
			"QuitDialog found via get_node (using scene node).", Globals.LogLevel.DEBUG
		)
		if not quit_dialog.confirmed.is_connected(_on_quit_dialog_confirmed):
			quit_dialog.confirmed.connect(_on_quit_dialog_confirmed)
		if not quit_dialog.get_cancel_button().pressed.is_connected(_on_quit_dialog_canceled):
			quit_dialog.get_cancel_button().pressed.connect(_on_quit_dialog_canceled)
	else:
		Globals.log_message(
			"Warning: QuitDialog not assigned! Disabling Quit button.", Globals.LogLevel.WARNING
		)
		# Fallback: Disable Quit button to prevent null errors
		var quit_button: Button = $CenterContainer/VBoxContainer/QuitButton
		if quit_button:
			quit_button.disabled = true
			quit_button.visible = false  # Or hide it entirely


# Handles the Start button press.
# Loads the main game scene using a preloaded PackedScene for efficiency.
func _on_start_pressed() -> void:
	# Stub; later: get_tree().change_scene_to_file("res://game_scene.tscn")
	Globals.log_message("Start Game menu button pressed.", Globals.LogLevel.DEBUG)

	if game_scene:
		Globals.log_message("Loading main game scene...", Globals.LogLevel.DEBUG)
		get_tree().change_scene_to_packed(game_scene)
	else:
		Globals.log_message("Error: Game scene not set!", Globals.LogLevel.ERROR)


# Handles the Options button press.
# Placeholder for loading an options scene.
func _on_options_pressed() -> void:
	# Stub; later: get_tree().change_scene_to_file("res://options_scene.tscn")
	Globals.log_message("Options menu coming soon!", Globals.LogLevel.DEBUG)
	# Future: var options_scene = preload("res://scenes/options_scene.tscn"); get_tree().change_scene_to_packed(options_scene)


# Handles the Quit button press.
# Displays the quit confirmation dialog if valid.
func _on_quit_pressed() -> void:
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
	# Optional: Handle cancel (e.g., play sound or log)
	quit_dialog.hide()
	Globals.log_message("Quit canceled—back to skies!", Globals.LogLevel.DEBUG)
	# Dialog auto-hides on cancel, no extra code needed
