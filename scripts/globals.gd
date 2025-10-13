extends Node

# Global utilities singleton: Provides shared functions like logging.
# Access from any script as Globals.log_message("message").
enum LogLevel { DEBUG, INFO, WARNING, ERROR, NONE = 4 }
@export var current_log_level: LogLevel = LogLevel.INFO  # Default: Show INFO and above
@export var enable_debug_logging: bool = false  # Toggle in Inspector or settings
@export var difficulty: float = 1.0  # Multiplier: 1.0=Normal, <1=Easy, >1=Hard

# In globals.gd (add after @export vars)
var previous_scene: String = "res://scenes/main_menu.tscn"  # Default fallback
var options_scene: PackedScene = preload("res://scenes/options_menu.tscn")


func _ready() -> void:
	if Engine.is_editor_hint() or enable_debug_logging:
		current_log_level = LogLevel.DEBUG
	else:
		current_log_level = LogLevel.INFO
	log_message("Log level set to: " + LogLevel.keys()[current_log_level], LogLevel.INFO)
	# In _ready(), add after initial log level set:
	_load_settings()  # If not already; loads log level and could expand for more


# Add these new functions (for consistency with log level persistence)
func _load_settings(config: ConfigFile = ConfigFile.new()) -> void:  # New: Optional param (default new; fixes error)
	var err := config.load("user://settings.cfg")
	if err == OK:
		current_log_level = config.get_value("Settings", "log_level", LogLevel.INFO)
		log_message("Loaded saved log level: " + LogLevel.keys()[current_log_level], LogLevel.INFO)

		difficulty = config.get_value("Settings", "difficulty", 1.0)
		# New: Validate and clamp difficulty to slider range (0.5-2.0)
		if difficulty < 0.5 or difficulty > 2.0:
			log_message(
				"Invalid difficulty loaded (" + str(difficulty) + ")—clamping to valid range.",
				LogLevel.WARNING
			)
			difficulty = clamp(difficulty, 0.5, 2.0)
		log_message("Loaded saved difficulty: " + str(difficulty), LogLevel.INFO)
	else:
		log_message("No saved settings found—using default.", LogLevel.DEBUG)


# New: Add _save_settings to globals.gd (move from options_menu.gd if needed)
func _save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("Settings", "log_level", current_log_level)
	config.set_value("Settings", "difficulty", difficulty)
	config.save("user://settings.cfg")
	log_message("Settings saved.", LogLevel.DEBUG)


# In globals.gd (load_options())
func load_options() -> void:
	log_message("Instancing options menu over current scene.", LogLevel.DEBUG)
	if options_scene:
		var options_inst := options_scene.instantiate()
		get_tree().root.add_child(options_inst)  # Add to root (on top)
	else:
		log_message("Error: Options scene not found!", LogLevel.ERROR)


# Custom logging function with timestamp and level filtering.
# @param message: The string message to log.
# @param level: The log level (default INFO).
func log_message(message: String, level: LogLevel = LogLevel.INFO) -> void:
	if level < current_log_level:
		return  # Skip if below threshold
	var level_str: String = LogLevel.keys()[level]  # Converts enum to string: "INFO", etc.
	var timestamp: String = Time.get_datetime_string_from_system()
	print("[%s] [%s] %s" % [timestamp, level_str, message])


# Override to handle engine notifications, like window close requests.
# @param what: The notification ID (int constant from Godot).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# Cleanup logic here—runs just before quit.
		log_message("Window close requested—performing cleanup...", LogLevel.INFO)

		# Example: Save game state if you have a save system.
		# Replace with your actual save function, e.g., from a save_manager.gd.
		# save_game_state()  # Uncomment and implement as needed.

		# After cleanup, let the quit proceed (optional on desktop; auto on web).
		get_tree().quit()
