extends Control

# Default relative path; override in Inspector if needed
@export var quit_dialog_path: NodePath = NodePath("VideoStreamPlayer/Panel/VBoxContainer/QuitDialog")
# Reference to the quit dialog node, assigned in setup_quit_dialog or _ready()
var quit_dialog: ConfirmationDialog
var game_scene: PackedScene = preload("res://scenes/main_scene.tscn")
var options_menu: PackedScene = preload("res://scenes/options_menu.tscn")

@onready var ui_panel: Panel = $VideoStreamPlayer/Panel
@onready var ui_container: VBoxContainer = $VideoStreamPlayer/Panel/VBoxContainer
@onready var start_button: Button = $VideoStreamPlayer/Panel/VBoxContainer/StartButton
@onready var options_button: Button = $VideoStreamPlayer/Panel/VBoxContainer/OptionsButton
@onready var quit_button: Button = $VideoStreamPlayer/Panel/VBoxContainer/QuitButton

# Handles the main menu UI, including button connections and quit dialog logic.
# This script manages scene transitions and platform-specific quitting for web/desktop.


# Called when the node enters the scene tree for the first time.
# Initializes button signals and quit dialog connections.
func _ready() -> void:
	Globals.log_message("Initializing main menu...", Globals.LogLevel.DEBUG)

	start_button.pressed.connect(_on_start_pressed)
	options_button.pressed.connect(_on_options_button_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	setup_quit_dialog()  # New: Handles dialog setup in one place
	# assert(quit_dialog != null, "QuitDialog must be assigned!")
	# Hide UI initially (buttons and dialog won't show right away)
	ui_panel.modulate.a = 0.0  # Start fully transparent for fade-in
	ui_panel.visible = false  # Or just hide if no fade needed
	ui_container.modulate.a = 0.0  # Start fully transparent for fade-in
	ui_container.visible = false  # Or just hide if no fade needed

	# New: Create and start a timer for delayed UI show
	var delay_timer: Timer = Timer.new()
	delay_timer.wait_time = 0.5  # Delay in seconds (change to 5.0 for longer)
	delay_timer.one_shot = true  # Runs once
	add_child(delay_timer)  # Add to scene tree
	delay_timer.timeout.connect(_show_ui_panel)  # Connect to show function
	delay_timer.start()
	Globals.log_message("Starting UI delay timer #1...", Globals.LogLevel.DEBUG)
	
	delay_timer.timeout.connect(_show_ui_container)
	delay_timer.start()
	Globals.log_message("Starting UI delay timer #2...", Globals.LogLevel.DEBUG)

# New: Function to reveal the UI after delay (with optional fade-in)
func _show_ui_panel() -> void:
	ui_panel.visible = true  # Make visible
	# Optional: Fade in over 1 second for smooth effect (learning Tween basics)
	var tween: Tween = create_tween()
	tween.tween_property(ui_panel, "modulate:a", 1.0, 1.0)  # From current alpha to 1.0
	Globals.log_message("Showing main menu UI after delay.", Globals.LogLevel.DEBUG)

func _show_ui_container() -> void:
	ui_container.visible = true  # Make visible
	# Optional: Fade in over 1 second for smooth effect (learning Tween basics)
	var tween: Tween = create_tween()
	tween.tween_property(ui_container, "modulate:a", 1.0, 1.0)  # From current alpha to 1.0
	Globals.log_message("Showing main menu UI after delay.", Globals.LogLevel.DEBUG)


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
		var quit_button: Button = $VideoStreamPlayer/VBoxContainer/QuitButton
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
func _on_options_button_pressed() -> void:
	Globals.load_options()


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
