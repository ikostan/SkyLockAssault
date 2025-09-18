extends Control

@onready var quit_dialog: ConfirmationDialog = $CenterContainer/VBoxContainer/QuitDialog
var game_scene: PackedScene = preload("res://scenes/main_scene.tscn")

# Handles the main menu UI, including button connections and quit dialog logic.
# This script manages scene transitions and platform-specific quitting for web/desktop.


# Called when the node enters the scene tree for the first time.
# Initializes button signals and quit dialog connections.
func _ready() -> void:
	Globals.log_message("Initializing main menu...")
	$CenterContainer/VBoxContainer/StartButton.pressed.connect(_on_start_pressed)
	$CenterContainer/VBoxContainer/OptionsButton.pressed.connect(_on_options_pressed)
	$CenterContainer/VBoxContainer/QuitButton.pressed.connect(_on_quit_pressed)

	# Connect dialog signals (can also do this in editor; add null check)
	if quit_dialog:
		# Add signals
		Globals.log_message("QuitDialog found via get_node (using scene node).")
		if not quit_dialog.confirmed.is_connected(_on_quit_dialog_confirmed):
			quit_dialog.confirmed.connect(_on_quit_dialog_confirmed)
		if not quit_dialog.get_cancel_button().pressed.is_connected(_on_quit_dialog_canceled):
			quit_dialog.get_cancel_button().pressed.connect(_on_quit_dialog_canceled)
	else:
		var message: String = "Warning: QuitDialog node not found! Add it to the scene."
		Globals.log_message(message)


# Handles the Start button press.
# Loads the main game scene using a preloaded PackedScene for efficiency.
func _on_start_pressed() -> void:
	# Stub; later: get_tree().change_scene_to_file("res://game_scene.tscn")
	Globals.log_message("Start Game menu button pressed.")

	if game_scene:
		Globals.log_message("Loading main game scene...")
		get_tree().change_scene_to_packed(game_scene)
	else:
		Globals.log_message("Error: Game scene not set!")


# Handles the Options button press.
# Placeholder for loading an options scene.
func _on_options_pressed() -> void:
	# Stub; later: get_tree().change_scene_to_file("res://options_scene.tscn")
	var message: String = "Options menu coming soon!"
	Globals.log_message(message)
	# Future: var options_scene = preload("res://scenes/options_scene.tscn"); get_tree().change_scene_to_packed(options_scene)


# Handles the Quit button press.
# Displays the quit confirmation dialog if valid.
func _on_quit_pressed() -> void:
	# Show confirmation dialog
	if is_instance_valid(quit_dialog):
		quit_dialog.show()
		Globals.log_message("Attempting to show QuitDialog.")
		quit_dialog.popup_centered()  # Sets visible=true internally
	else:
		var message: String = "No quit_dialog found."
		Globals.log_message(message)


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
	var message: String = "Quit confirmed and executed!"
	Globals.log_message(message)


# Called when the quit dialog is canceled.
# Hides the dialog and logs the action.
func _on_quit_dialog_canceled() -> void:
	# Optional: Handle cancel (e.g., play sound or log)
	quit_dialog.hide()
	var message: String = "Quit canceled—back to skies!"
	Globals.log_message(message)
	# Dialog auto-hides on cancel, no extra code needed
