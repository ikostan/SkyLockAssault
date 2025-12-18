# input_remap_button.gd (full updated script - removes Godot 3.x methods, uses custom dicts only)
# Extends to handle joypad remapping and display (keys, buttons, axes).
# Use device = -1 for "all controllers".
# Handles listening, updating text, saving. Extends Button.
# :vartype action: String
# :vartype action_event_index: int
# :vartype KEY_LABELS: Dictionary
# :vartype JOY_BUTTON_LABELS: Dictionary
# :vartype JOY_AXIS_BASE_LABELS: Dictionary
# :vartype JOY_AXIS_LABELS: Dictionary
# :vartype listening: bool

# gdlint:ignore = class-definitions-order
class_name InputRemapButton

extends Button

const KEY_LABELS: Dictionary = {
	Key.KEY_W: "W",
	Key.KEY_S: "S",
	Key.KEY_X: "X",
	Key.KEY_A: "A",
	Key.KEY_D: "D",
	Key.KEY_SPACE: "Space",
	Key.KEY_Q: "Q",
	Key.KEY_LEFT: "Left",
	Key.KEY_RIGHT: "Right",
	Key.KEY_UP: "Up",
	Key.KEY_DOWN: "Down",
	Key.KEY_ESCAPE: "Esc"
	# Add more as needed for arrow keys, etc.
}

# Custom labels for joypad buttons (replaces removed Input.get_joy_button_string)
const JOY_BUTTON_LABELS: Dictionary = {
	JOY_BUTTON_A: "A",
	JOY_BUTTON_B: "B",
	JOY_BUTTON_X: "X",
	JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back",
	JOY_BUTTON_GUIDE: "Guide",
	JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "Left Stick",
	JOY_BUTTON_RIGHT_STICK: "Right Stick",
	JOY_BUTTON_LEFT_SHOULDER: "L1",
	JOY_BUTTON_RIGHT_SHOULDER: "R1",
	JOY_BUTTON_DPAD_UP: "D-Pad Up",
	JOY_BUTTON_DPAD_DOWN: "D-Pad Down",
	JOY_BUTTON_DPAD_LEFT: "D-Pad Left",
	JOY_BUTTON_DPAD_RIGHT: "D-Pad Right",
	JOY_BUTTON_MISC1: "Misc 1",
	JOY_BUTTON_PADDLE1: "Paddle 1",
	JOY_BUTTON_PADDLE2: "Paddle 2",
	JOY_BUTTON_PADDLE3: "Paddle 3",
	JOY_BUTTON_PADDLE4: "Paddle 4",
	JOY_BUTTON_TOUCHPAD: "Touchpad"
	# Add more from Godot docs if needed (e.g., for PS/Xbox specifics)
}

# Custom base labels for axes (replaces removed Input.get_joy_axis_string)
const JOY_AXIS_BASE_LABELS: Dictionary = {
	JOY_AXIS_LEFT_X: "Left Stick X",
	JOY_AXIS_LEFT_Y: "Left Stick Y",
	JOY_AXIS_RIGHT_X: "Right Stick X",
	JOY_AXIS_RIGHT_Y: "Right Stick Y",
	JOY_AXIS_TRIGGER_LEFT: "Left Trigger",
	JOY_AXIS_TRIGGER_RIGHT: "Right Trigger"
	# Add more axes if your game uses them
}

# Custom labels for common joypad axes/directions (for nice display)
const JOY_AXIS_LABELS: Dictionary = {
	JOY_AXIS_LEFT_X: {-1.0: "Left Stick Left", 1.0: "Left Stick Right"},
	JOY_AXIS_LEFT_Y: {-1.0: "Left Stick Up", 1.0: "Left Stick Down"},
	JOY_AXIS_RIGHT_X: {-1.0: "Right Stick Left", 1.0: "Right Stick Right"},
	JOY_AXIS_RIGHT_Y: {-1.0: "Right Stick Up", 1.0: "Right Stick Down"},
	JOY_AXIS_TRIGGER_LEFT: {1.0: "Left Trigger"},
	JOY_AXIS_TRIGGER_RIGHT: {1.0: "Right Trigger"}
}

@export var action: String = ""
@export var action_event_index: int = 0

var listening: bool = false


# Ready: Setup toggle, text, connect pressed.
# :rtype: void
func _ready() -> void:
	toggle_mode = true
	update_button_text()
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)


# Pressed: Toggle listening, update text.
# :rtype: void
func _on_pressed() -> void:
	listening = button_pressed
	if listening:
		text = "Press a key or controller button/axis..."
	else:
		update_button_text()


# Input: Handle remap for key/button/motion if listening.
# :param event: Input event.
# :type event: InputEvent
# :rtype: void
func _input(event: InputEvent) -> void:
	if not listening:
		return

	# Handle keyboard key press
	if event is InputEventKey and event.pressed:
		erase_old_event()
		var new_event := InputEventKey.new()
		new_event.physical_keycode = event.physical_keycode
		InputMap.action_add_event(action, new_event)
		finish_remap()
		return

	# Handle joypad button press
	if event is InputEventJoypadButton and event.pressed:
		erase_old_event()
		var new_event := InputEventJoypadButton.new()
		new_event.button_index = event.button_index
		new_event.device = -1  # All devices
		InputMap.action_add_event(action, new_event)
		finish_remap()
		return

	# Handle joypad axis motion (if moved past deadzone)
	if event is InputEventJoypadMotion and abs(event.axis_value) > 0.5:
		erase_old_event()
		var new_event := InputEventJoypadMotion.new()
		new_event.axis = event.axis
		new_event.axis_value = sign(event.axis_value)  # Normalize to +1 or -1
		new_event.device = -1  # All devices
		InputMap.action_add_event(action, new_event)
		finish_remap()
		return


# Helper to erase old event at index
# Erase old event at index.
# :rtype: void
func erase_old_event() -> void:
	var events := InputMap.action_get_events(action)
	if events.size() > action_event_index:
		InputMap.action_erase_event(action, events[action_event_index])


# In input_remap_button.gd, inside finish_remap() func (before Settings.save_input_mappings())
# Finish remap: update display, stop listening, save
# :rtype: void
func finish_remap() -> void:
	update_button_text()
	button_pressed = false
	listening = false
	# Log remap at DEBUG (uses get_event_label for new binding)
	var new_label: String = get_event_label(InputMap.action_get_events(action)[action_event_index])
	Globals.log_message(
		"User remapped action '" + action + "' to '" + new_label + "'", Globals.LogLevel.DEBUG
	)
	Settings.save_input_mappings()
	get_viewport().set_input_as_handled()


# Updated to display key, joypad button, or axis label
# :rtype: void
func update_button_text() -> void:
	var events := InputMap.action_get_events(action)
	if events.size() > action_event_index:
		var event := events[action_event_index]
		text = get_event_label(event)
	else:
		text = "Unbound"


# Get display label for any event type (uses custom dicts only)
# Get label for event (key/button/axis).
# :param event: Input event.
# :type event: InputEvent
# :rtype: String
func get_event_label(event: InputEvent) -> String:
	if event is InputEventKey:
		return KEY_LABELS.get(event.physical_keycode, OS.get_keycode_string(event.key_label))

	if event is InputEventJoypadButton:
		return JOY_BUTTON_LABELS.get(event.button_index, "Button " + str(event.button_index))

	if event is InputEventJoypadMotion:
		var axis_labels: Dictionary = JOY_AXIS_LABELS.get(event.axis, {})
		var dir_key: float = event.axis_value  # +1 or -1
		return axis_labels.get(
			dir_key,
			(
				JOY_AXIS_BASE_LABELS.get(event.axis, "Axis " + str(event.axis))
				+ (" +" if dir_key > 0 else " -")
			)
		)
	return "Unbound"
