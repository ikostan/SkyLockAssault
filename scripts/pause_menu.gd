extends CanvasLayer

# Pause menu overlay: Toggles with ESC, pauses the game tree, and handles resume/back to menu.
# Use for exiting game levels back to main menu without quitting.

@onready var resume_button: Button = $VBoxContainer/ResumeButton
@onready var back_to_main_button: Button = $VBoxContainer/BackToMainButton
@onready var options_button: Button = $VBoxContainer/OptionsButton
var options_menu: PackedScene = preload("res://scenes/options_menu.tscn")

# Called when the node enters the scene tree.
# Hides the menu initially.
func _ready() -> void:
	resume_button.pressed.connect(_on_resume_button_pressed)
	back_to_main_button.pressed.connect(_on_back_to_main_button_pressed)
	visible = false
	Globals.log_message("Resume menu is ready.", Globals.LogLevel.DEBUG)


# Processes unhandled input for pause toggle (e.g., ESC key).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):  # Default ESC action
		toggle_pause()


# Toggles the pause menu visibility and game pause state.
func toggle_pause() -> void:
	visible = not visible
	get_tree().paused = visible


# Connected to ResumeButton's pressed signal.
# Resumes the game by toggling pause.
func _on_resume_button_pressed() -> void:
	Globals.log_message("Resume button pressed.", Globals.LogLevel.DEBUG)
	toggle_pause()


# Connected to BackToMainButton's pressed signal.
# Unpauses and loads the main menu scene.
func _on_back_to_main_button_pressed() -> void:
	Globals.log_message("Back To Main Menu button pressed.", Globals.LogLevel.DEBUG)
	get_tree().paused = false  # Always unpause before scene change
	visible = false  # Extra: Force hide for smooth transition
	var main_menu_scene: PackedScene = load("res://scenes/main_menu.tscn")
	if main_menu_scene:
		Globals.log_message("Switch back to Main menu scene.", Globals.LogLevel.DEBUG)
		get_tree().change_scene_to_packed(main_menu_scene)
	else:
		Globals.log_message("Error: Main menu scene not set!", Globals.LogLevel.ERROR)
		# Optional: Fallback, e.g., get_tree().quit() if critical


func _on_options_button_pressed() -> void:
	Globals.load_options()
