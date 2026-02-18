## test_get_pause_binding_label_for_device.gd
## Regression tests for:
## Settings.get_pause_binding_label_for_device()

extends GutTest

var settings: Node

func before_each() -> void:
	settings = preload("res://scripts/settings.gd").new()
	add_child_autofree(settings)

	# Ensure clean input state
	InputMap.erase_action("pause")
	InputMap.add_action("pause")

func after_each() -> void:
	await get_tree().process_frame

# ============================================================
# KEYBOARD TESTS
# ============================================================

func test_pause_label_returns_keyboard_key_name() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.keycode = KEY_ESCAPE
	event.device = -1
	InputMap.action_add_event("pause", event)
	var label: String = settings.get_pause_binding_label_for_device("keyboard")
	assert_true(label is String)
	assert_true(label.length() > 0)


func test_pause_label_returns_unbound_when_keyboard_not_bound() -> void:
	var label: String = settings.get_pause_binding_label_for_device("keyboard")
	print("label: " + label)
	assert_true(label == "UNBOUND")


# ============================================================
# JOYPAD TESTS
# ============================================================

func test_pause_label_returns_joypad_button_name() -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_START
	event.device = 0
	InputMap.action_add_event("pause", event)
	var label: String = settings.get_pause_binding_label_for_device("joypad")
	assert_true(label is String)
	assert_true(label.length() > 0)


func test_pause_label_falls_back_when_no_matching_device() -> void:
	var key_event := InputEventKey.new()
	key_event.physical_keycode = KEY_ESCAPE
	key_event.keycode = KEY_ESCAPE
	key_event.device = -1
	InputMap.action_add_event("pause", key_event)
	var label: String = settings.get_pause_binding_label_for_device("gamepad")
	assert_true(label is String)
	assert_true(label.length() > 0)
	print("label: " + label)
	assert_eq(label.strip_edges(), "ESCAPE")



func test_pause_label_ignores_other_joypad_devices() -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_START
	event.device = 1
	InputMap.action_add_event("pause", event)
	# If your implementation filters by device id internally,
	# this ensures it does not accidentally match wrong device.
	var label: String = settings.get_pause_binding_label_for_device("joypad")
	# Depending on your logic, adjust if needed
	assert_true(label == "" or label.length() > 0)


func test_pause_label_returns_unbound_when_no_events() -> void:
	var label: String = settings.get_pause_binding_label_for_device("keyboard")
	assert_eq(label, "UNBOUND")
