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
var hidden_menu: Node = null
var options_open: bool = false
var previous_scene: String = "res://scenes/main_menu.tscn"  # Default fallback
var options_scene: PackedScene = preload("res://scenes/options_menu.tscn")


func _ready() -> void:
	if Engine.is_editor_hint() or enable_debug_logging:
		current_log_level = LogLevel.DEBUG

	log_message("Log level set to: " + LogLevel.keys()[current_log_level], LogLevel.DEBUG)
	_load_settings()  # Load persisted settings first

	# Apply loaded volumes to AudioServer buses (using new helper)
	_apply_volume_to_bus("Master", master_volume)
	_apply_volume_to_bus("Music", music_volume)
	_apply_volume_to_bus("SFX", sfx_volume)


# New: Helper to apply volume to a named bus (extracted from _ready)
func _apply_volume_to_bus(bus_name: String, volume: float) -> void:
	var bus_idx: int = AudioServer.get_bus_index(bus_name)
	if bus_idx != -1:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(volume))
		log_message(
			"Applied loaded " + bus_name + " volume to AudioServer: " + str(volume), LogLevel.DEBUG
		)
	else:
		log_message(bus_name + " audio bus not found!", LogLevel.ERROR)


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


# Modified load_options with guards
func load_options(menu_to_hide: Node) -> void:
	## Loads options menu and hides the caller menu (if valid).
	##
	## :param menu_to_hide: The menu node to hide (guarded against null/invalid).
	## :type menu_to_hide: Node
	## :rtype: void
	if menu_to_hide == null:
		log_message("load_options: Called with null menu_to_hide—skipping hide.", LogLevel.WARNING)
	elif not is_instance_valid(menu_to_hide):
		log_message(
			"load_options: Invalid/freed menu_to_hide (" + str(menu_to_hide) + ")—skipping hide.",
			LogLevel.WARNING
		)
	else:
		hidden_menu = menu_to_hide
		hidden_menu.visible = false
		log_message("Hiding menu: " + menu_to_hide.name, LogLevel.DEBUG)

	if options_scene:
		var options_inst: CanvasLayer = options_scene.instantiate()
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
