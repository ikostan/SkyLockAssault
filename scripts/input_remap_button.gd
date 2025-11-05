extends Button
class_name InputRemapButton

@export var action: String
@export var action_event_index: int = 0

const KEY_LABELS: Dictionary = {
	Key.KEY_W: "W",  # forward
	Key.KEY_S: "S",  # backward
	Key.KEY_X: "X",  # backward
	Key.KEY_A: "A",  # left
	Key.KEY_D: "D",  # right
	Key.KEY_SPACE: "Space",  # fire
	Key.KEY_Q: "Q"  # next weapon
}

var listening: bool = false


func _ready() -> void:
	toggle_mode = true
	update_button_text()
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

		# Add new event
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
			var keycode := DisplayServer.keyboard_get_keycode_from_physical(event.physical_keycode)
			text = KEY_LABELS.get(keycode, OS.get_keycode_string(keycode))
	else:
		text = "Unbound"
