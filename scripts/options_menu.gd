extends Control

@onready var log_lvl_option: OptionButton = $VBoxContainer/HBoxContainer/LogLevelOptionButton
@onready var back_button: Button = $VBoxContainer/BackButton


func _ready() -> void:
	# Populate OptionButton with all LogLevel enum values
	for level: String in Globals.LogLevel.keys():
		log_lvl_option.add_item(level)

	# Set to current log level (find index by enum value)
	var current_value: int = Globals.current_log_level
	var index: int = Globals.LogLevel.values().find(current_value)
	if index != -1:
		log_lvl_option.selected = index
	else:
		log_lvl_option.selected = 1  # Fallback to INFO (index 1)
		Globals.log_message("Invalid saved log level—reset to INFO.", Globals.LogLevel.WARNING)

	# Connect signals
	log_lvl_option.item_selected.connect(_on_log_selected)
	back_button.pressed.connect(_on_back_pressed)

	Globals.log_message("Options menu loaded.", Globals.LogLevel.DEBUG)


# Handles log level selection change
# Update _on_log_selected to use the selected name for enum lookup:
func _on_log_selected(index: int) -> void:
	var selected_name: String = log_lvl_option.get_item_text(index)
	Globals.current_log_level = Globals.LogLevel[selected_name]  # Gets the int enum value
	Globals.log_message("Log level changed to: " + selected_name, Globals.LogLevel.INFO)
	_save_settings()


# Saves settings to file (call from here or Globals as needed)
func _save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("Settings", "log_level", Globals.current_log_level)
	config.save("user://settings.cfg")  # Web-safe path
	Globals.log_message("Settings saved.", Globals.LogLevel.DEBUG)


# Handles Back button: Return to main menu
# In options_menu.gd (_on_back_pressed())
func _on_back_pressed() -> void:
	if Globals.previous_scene != "":
		get_tree().change_scene_to_file(Globals.previous_scene)
		Globals.log_message(
			"Returning to previous scene: " + Globals.previous_scene, Globals.LogLevel.DEBUG
		)
	else:
		# Fallback to main menu if not set (e.g., direct run)
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		Globals.log_message(
			"No previous scene set—falling back to main menu.", Globals.LogLevel.WARNING
		)
