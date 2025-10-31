extends Node

# Global utilities singleton: Provides shared functions like logging.
# Access from any script as Globals.log_message("message").
enum LogLevel { DEBUG, INFO, WARNING, ERROR, NONE = 4 }
@export var current_log_level: LogLevel = LogLevel.INFO  # Default: Show INFO and above
@export var enable_debug_logging: bool = false  # Toggle in Inspector or settings
@export var difficulty: float = 1.0  # Multiplier: 1.0=Normal, <1=Easy, >1=Hard
@export var master_volume: float = 1.0
@export var music_volume: float = 1.0
@export var sfx_volume: float = 1.0

# In globals.gd (add after @export vars)
var previous_scene: String = "res://scenes/main_menu.tscn"  # Default fallback
var options_scene: PackedScene = preload("res://scenes/options_menu.tscn")


func _ready() -> void:
	if Engine.is_editor_hint() or enable_debug_logging:
		current_log_level = LogLevel.DEBUG
	log_message("Log level set to: " + LogLevel.keys()[current_log_level], LogLevel.DEBUG)
	_load_settings()  # Load persisted settings first

	# Apply loaded volumes to AudioServer buses
	var master_bus_idx: int = AudioServer.get_bus_index("Master")
	if master_bus_idx != -1:
		AudioServer.set_bus_volume_db(master_bus_idx, linear_to_db(master_volume))
		log_message(
			"Applied loaded Master volume to AudioServer: " + str(master_volume), LogLevel.DEBUG
		)
	else:
		log_message("Master audio bus not found!", LogLevel.ERROR)

	var music_bus_idx: int = AudioServer.get_bus_index("Music")
	if music_bus_idx != -1:
		AudioServer.set_bus_volume_db(music_bus_idx, linear_to_db(music_volume))
		log_message(
			"Applied loaded Music volume to AudioServer: " + str(music_volume), LogLevel.DEBUG
		)
	else:
		log_message("Music audio bus not found!", LogLevel.ERROR)

	var sfx_bus_idx: int = AudioServer.get_bus_index("SFX")
	if sfx_bus_idx != -1:
		AudioServer.set_bus_volume_db(sfx_bus_idx, linear_to_db(sfx_volume))
		log_message("Applied loaded SFX volume to AudioServer: " + str(sfx_volume), LogLevel.DEBUG)
	else:
		log_message("SFX audio bus not found!", LogLevel.ERROR)


# Add these new functions (for consistency with log level persistence)
# New: Optional param (default new; fixes error)
func _load_settings(config: ConfigFile = ConfigFile.new()) -> void:
	var err := config.load("user://settings.cfg")
	if err == OK:
		master_volume = config.get_value("Settings", "master_volume", 1.0)
		log_message("Loaded master_volume level: " + str(master_volume), LogLevel.DEBUG)

		music_volume = config.get_value("Settings", "music_volume", 1.0)
		log_message("Loaded music_volume level: " + str(music_volume), LogLevel.DEBUG)

		sfx_volume = config.get_value("Settings", "sfx_volume", 1.0)
		log_message("Loaded sfx_volume level: " + str(sfx_volume), LogLevel.DEBUG)

		current_log_level = config.get_value("Settings", "log_level", LogLevel.INFO)
		log_message("Loaded saved log level: " + LogLevel.keys()[current_log_level], LogLevel.DEBUG)

		difficulty = config.get_value("Settings", "difficulty", 1.0)
		# New: Validate and clamp difficulty to slider range (0.5-2.0)
		if difficulty < 0.5 or difficulty > 2.0:
			log_message(
				"Invalid difficulty loaded (" + str(difficulty) + ")—clamping to valid range.",
				LogLevel.WARNING
			)
			difficulty = clamp(difficulty, 0.5, 2.0)
		log_message("Loaded saved difficulty: " + str(difficulty), LogLevel.DEBUG)
	else:
		log_message("No saved settings found—using default.", LogLevel.DEBUG)


# New: Add _save_settings to globals.gd (move from options_menu.gd if needed)
func _save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()

	config.set_value("Settings", "log_level", current_log_level)
	config.set_value("Settings", "difficulty", difficulty)
	config.set_value("Settings", "master_volume", master_volume)
	config.set_value("Settings", "music_volume", music_volume)
	config.set_value("Settings", "sfx_volume", sfx_volume)

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
		log_message("Window close requested—performing cleanup...", LogLevel.DEBUG)

		# Example: Save game state if you have a save system.
		# Replace with your actual save function, e.g., from a save_manager.gd.
		# save_game_state()  # Uncomment and implement as needed.

		# After cleanup, let the quit proceed (optional on desktop; auto on web).
		get_tree().quit()
