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


func _input(event: InputEvent) -> void:  # Add type hints
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos: Vector2 = event.position  # Explicitly type as Vector2
		Globals.log_message("Clicked at: (%s, %s)" % [pos.x, pos.y], Globals.LogLevel.INFO)


# Called when the node enters the scene tree for the first time.
# Initializes button signals and quit dialog connections.
func _ready() -> void:
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

	setup_quit_dialog()  # New: Handles dialog setup in one place
	# assert(quit_dialog != null, "QuitDialog must be assigned!")
	# Hide UI initially (buttons and dialog won't show right away)
	ui_panel.modulate.a = 0.0  # Start fully transparent for fade-in
	ui_panel.visible = false  # Or just hide if no fade needed
	ui_container.modulate.a = 0.0  # Start fully transparent for fade-in
	ui_container.visible = false  # Or just hide if no fade needed

	# New: Create and start a timer for delayed UI show
	# In _ready() (replace timer; no Timer needed)
	var delay_timer: Timer = Timer.new()  # Still use timer for initial delay
	delay_timer.wait_time = 0.5
	delay_timer.one_shot = true
	add_child(delay_timer)
	delay_timer.timeout.connect(_start_ui_fade)
	delay_timer.start()
	Globals.log_message("Starting initial delay timer...", Globals.LogLevel.DEBUG)
	# Optional: Signal init complete for web tests (after UI setup)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.godotInitialized = true;")
		Globals.log_message("JS init signal set for web.", Globals.LogLevel.DEBUG)


# New: Starts the sequenced fades after delay
func _start_ui_fade() -> void:
	ui_panel.visible = true  # Make visible before fade
	var tween := create_tween()  # Node-specific Tween (auto-frees on finish)
	tween.tween_property(ui_panel, "modulate:a", 1.0, 0.5)  # Fade panel over 0.5s
	tween.tween_callback(_fade_ui_container)  # Chain: Call next after panel fade
	Globals.log_message("Fading in UI panel.", Globals.LogLevel.DEBUG)


# New: Fades ui_container after panel
func _fade_ui_container() -> void:
	ui_container.visible = true
	var tween := create_tween()
	tween.tween_property(ui_container, "modulate:a", 1.0, 0.3)  # Shorter fade for container
	Globals.log_message("Fading in UI container.", Globals.LogLevel.DEBUG)


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
