extends Node

# Global utilities singleton: Provides shared functions like logging.
# Access from any script as Globals.log_message("message").
enum LogLevel { DEBUG, INFO, WARNING, ERROR }
@export var current_log_level: LogLevel = LogLevel.INFO  # Default: Show INFO and above
@export var enable_debug_logging: bool = true  # Toggle in Inspector or settings


func _ready() -> void:
	if Engine.is_editor_hint() or enable_debug_logging:
		current_log_level = LogLevel.DEBUG
	else:
		current_log_level = LogLevel.INFO
	log_message("Log level set to: " + LogLevel.keys()[current_log_level], LogLevel.INFO)


# Custom logging function with timestamp and level filtering.
# @param message: The string message to log.
# @param level: The log level (default INFO).
func log_message(message: String, level: LogLevel = LogLevel.INFO) -> void:
	if level < current_log_level:
		return  # Skip if below threshold
	var level_str: String = LogLevel.keys()[level]  # Converts enum to string: "INFO", etc.
	var timestamp: String = Time.get_datetime_string_from_system()
	print("[%s] [%s] %s" % [timestamp, level_str, message])
