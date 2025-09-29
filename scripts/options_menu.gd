extends CanvasLayer

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

	# In options_menu.gd (_ready()—add at end)
	process_mode = Node.PROCESS_MODE_ALWAYS  # Ignores pause for this node/tree
	Globals.log_message(
		"Set options_menu process_mode to ALWAYS for pause ignoring.", Globals.LogLevel.DEBUG
	)
	Globals.log_message("Options menu loaded.", Globals.LogLevel.DEBUG)


# Explicit mapping from display names to enum values
var log_level_display_to_enum := {
	"Debug": Globals.LogLevel.DEBUG,
	"Info": Globals.LogLevel.INFO,
	"Warning": Globals.LogLevel.WARNING,
	"Error": Globals.LogLevel.ERROR,
	"None": Globals.LogLevel.NONE
}

# Handles log level selection change
func _on_log_selected(index: int) -> void:
	var selected_name: String = log_lvl_option.get_item_text(index)
	var selected_enum := log_level_display_to_enum.get(selected_name, Globals.LogLevel.INFO)
	Globals.current_log_level = selected_enum
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
	get_tree().paused = false  # Unpause if was paused (safe call)
	Globals.log_message("Closing options menu.", Globals.LogLevel.DEBUG)
	queue_free()  # Remove self from tree (returns to underlying scene)
