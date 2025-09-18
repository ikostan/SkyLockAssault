extends Node

# Global utilities singleton: Provides shared functions like logging.
# Access from any script as Globals.log_message("message").


# Custom logging function with timestamp.
# Prints messages with a timestamp for debugging in editor output or browser console.
# @param message: The string message to log.
func log_message(message: String) -> void:
	var timestamp: String = Time.get_datetime_string_from_system()
	print("[%s] %s" % [timestamp, message])
