## settings.gd
## Input settings singleton: Loads/saves InputMap events to preserve custom mappings.
## Supports keys, joypad buttons, and joypad axes (serialized).
## Autoload as "Settings".
##
## :vartype CONFIG_PATH: String
## :vartype ACTIONS: Array[String]

extends Node

const CONFIG_PATH: String = "user://settings.cfg"
const ACTIONS: Array[String] = [
	"speed_up", 
	"speed_down",
	"move_left",
	"move_right",
	"fire",
	"next_weapon",
	"pause"
]
const DEFAULT_KEYS: Dictionary = {
	"speed_up": KEY_W,
	"speed_down": KEY_X,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"fire": KEY_SPACE,
	"next_weapon": KEY_Q,
	"pause": KEY_ESCAPE,
}


func _ready() -> void:
	load_input_mappings()
	save_input_mappings()  # Re-save in new format after load (upgrades old cfg)


## Serializes an InputEvent to string for ConfigFile storage.
## Handles Key (no device), JoypadButton, and JoypadMotion (with device).
## :param ev: The event to serialize.
## :type ev: InputEvent
## :rtype: String
func serialize_event(ev: InputEvent) -> String:
	if ev is InputEventKey:
		return "key:" + str(ev.physical_keycode)
	elif ev is InputEventJoypadButton:
		return "joybtn:" + str(ev.button_index) + ":" + str(ev.device)
	elif ev is InputEventJoypadMotion:
		return "joyaxis:" + str(ev.axis) + ":" + str(ev.axis_value) + ":" + str(ev.device)
	return ""


## Loads input mappings from config, overriding project defaults only if saved.
## Handles old int keycode format for backward compat.
## Skips if no saved data (preserves project key+joypad bindings).
## :param path: Config file path (default: CONFIG_PATH).
## :type path: String
## :param actions: Actions to load (default: ACTIONS).
## :type actions: Array[String]
## :rtype: void
func load_input_mappings(path: String = CONFIG_PATH, actions: Array[String] = ACTIONS) -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load(path)
	if err != OK:
		Globals.log_message("No settings.cfg—using project defaults.", Globals.LogLevel.INFO)
		return
	for action: String in actions:
		var value: Variant = config.get_value("input", action, null)
		if value == null:
			continue
		var serials: Array[String] = []
		if value is int:  # Old format: single keycode int
			serials = ["key:" + str(value)]
		elif value is Array:  # New format
			serials = value
		else:
			Globals.log_message("Invalid saved value for " + action + ": skipping.", Globals.LogLevel.WARNING)
			continue
		InputMap.action_erase_events(action)
		for s: String in serials:
			_deserialize_and_add(action, s)
		
		# Add this block (ensures default key if no events after load)
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		if events.is_empty() and DEFAULT_KEYS.has(action):
			var keycode: int = DEFAULT_KEYS[action]
			if keycode != -1:
				var nev: InputEventKey = InputEventKey.new()
				nev.physical_keycode = keycode
				InputMap.action_add_event(action, nev)
				Globals.log_message("Added default key for " + action, Globals.LogLevel.DEBUG)


## Deserializes string to event and adds to action.
## Handles device for joy events (-1 if omitted).
## :param action: Target action.
## :type action: String
## :param serialized: Serialized event string.
## :type serialized: String
## :rtype: void
func _deserialize_and_add(action: String, serialized: String) -> void:
	if serialized.begins_with("key:"):
		var kc: int = int(serialized.substr(4))
		var nev: InputEventKey = InputEventKey.new()
		nev.physical_keycode = kc
		InputMap.action_add_event(action, nev)
	elif serialized.begins_with("joybtn:"):
		var parts: PackedStringArray = serialized.split(":")
		var btn: int = int(parts[1])
		var dev: int = -1 if parts.size() < 3 else int(parts[2])
		var nev: InputEventJoypadButton = InputEventJoypadButton.new()
		nev.button_index = btn
		nev.device = dev
		InputMap.action_add_event(action, nev)
	elif serialized.begins_with("joyaxis:"):
		var parts: PackedStringArray = serialized.split(":")
		var axis: int = int(parts[1])
		var aval: float = float(parts[2])
		var dev: int = -1 if parts.size() < 4 else int(parts[3])
		var nev: InputEventJoypadMotion = InputEventJoypadMotion.new()
		nev.axis = axis
		nev.axis_value = aval
		nev.device = dev
		InputMap.action_add_event(action, nev)


## Saves current InputMap events to config (all per action as array).
## :param path: Config file path (default: CONFIG_PATH).
## :type path: String
## :param actions: Actions to save (default: ACTIONS).
## :type actions: Array[String]
## :rtype: void
func save_input_mappings(path: String = CONFIG_PATH, actions: Array[String] = ACTIONS) -> void:
	var config: ConfigFile = ConfigFile.new()
	for action: String in actions:
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		var serials: Array[String] = []
		for ev: InputEvent in events:
			var s: String = serialize_event(ev)
			if not s.is_empty():
				serials.append(s)
		if not serials.is_empty():
			config.set_value("input", action, serials)
	config.save(path)
