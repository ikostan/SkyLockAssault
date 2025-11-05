extends Button

# gdlint:ignore = class-definitions-order
class_name InputRemapButton

@export var action: String
@export var action_event_index: int = 0

# gdlint:ignore = class-definitions-order
const KEY_LABELS: Dictionary = {
	Key.KEY_W: "W",
	Key.KEY_S: "S",
	Key.KEY_X: "X",
	Key.KEY_A: "A",
	Key.KEY_D: "D",
	Key.KEY_SPACE: "Space",
	Key.KEY_Q: "Q"
}

var listening: bool = false


func _ready() -> void:
	toggle_mode = true
	update_button_text()
	if not pressed.is_connected(_on_pressed):
		# Safe: Only connect if not already
		pressed.connect(_on_pressed)


func _on_pressed() -> void:
	listening = button_pressed
	if listening:
		text = "Press a key..."
	else:
		update_button_text()


func _input(event: InputEvent) -> void:
	if listening and event is InputEventKey and event.pressed:
		# Erase old event
		var events := InputMap.action_get_events(action)
		if events.size() > action_event_index:
			InputMap.action_erase_event(action, events[action_event_index])

		# Add new event (physical_keycode for cross-layout)
		var new_event := InputEventKey.new()
		new_event.physical_keycode = event.physical_keycode
		InputMap.action_add_event(action, new_event)

		# Update display and stop listening
		update_button_text()
		button_pressed = false
		listening = false

		# Save changes
		Settings.save_input_mappings()

		get_viewport().set_input_as_handled()


func update_button_text() -> void:
	var events := InputMap.action_get_events(action)
	if events.size() > action_event_index:
		var event := events[action_event_index]
		if event is InputEventKey:
			# Web-safe: key_label gives printable string ("W", "Space") on all platforms
			var label: String = KEY_LABELS.get(
				event.physical_keycode, OS.get_keycode_string(event.key_label)
			)
			text = label if label != "" else "Unbound"
	else:
		text = "Unbound"
