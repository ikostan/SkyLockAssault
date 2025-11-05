extends Node

const CONFIG_PATH: String = "user://settings.cfg"
const ACTIONS: Array[String] = [
	"move_forward", "move_backward", "move_left", "move_right", "fire", "next_weapon"
]

const DEFAULT_KEYS: Dictionary = {
	"move_forward": KEY_W,
	"move_backward": KEY_X,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"fire": KEY_SPACE,
	"next_weapon": KEY_Q
}


func _ready() -> void:
	load_input_mappings()


func load_input_mappings(path: String = CONFIG_PATH, actions: Array[String] = ACTIONS) -> void:
	var config: ConfigFile = ConfigFile.new()
	var err := config.load(path)
	for action: String in actions:
		var keycode: int = config.get_value("input", action, -1)
		if keycode == -1:
			keycode = DEFAULT_KEYS.get(action, -1)  # Fallback to default
		if keycode != -1:
			# Erase existing (if any)
			var events: Array[InputEvent] = InputMap.action_get_events(action)
			if events.size() > 0 and events[0] is InputEventKey:
				InputMap.action_erase_event(action, events[0])

			# Add key event
			var new_event: InputEventKey = InputEventKey.new()
			new_event.physical_keycode = keycode
			InputMap.action_add_event(action, new_event)
		else:
			push_warning("Input action '%s' is missing from both config and DEFAULT_KEYS. No key mapping applied." % action)


func save_input_mappings(path: String = CONFIG_PATH, actions: Array[String] = ACTIONS) -> void:
	var config: ConfigFile = ConfigFile.new()
	for action: String in actions:
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		if events.size() > 0 and events[0] is InputEventKey:
			config.set_value("input", action, events[0].physical_keycode)
	config.save(path)
