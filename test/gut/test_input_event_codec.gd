## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## Compatibility tests for gamepad bindings and unsupported events.

extends GutTest


func test_gamepad_button_round_trip_preserves_index_and_device() -> void:
	var original := InputEventJoypadButton.new()
	original.button_index = JOY_BUTTON_LEFT_SHOULDER
	original.device = 3

	var encoded: String = InputEventCodec.serialize_event(original)
	assert_eq(encoded, "joybtn:%d:3" % JOY_BUTTON_LEFT_SHOULDER)
	var restored := InputEventCodec.deserialize_event(encoded) as InputEventJoypadButton
	assert_not_null(restored)
	if restored == null:
		return
	assert_eq(restored.button_index, JOY_BUTTON_LEFT_SHOULDER)
	assert_eq(restored.device, 3)
	assert_eq(InputEventCodec.get_event_device_type(restored), "gamepad")
	assert_eq(InputEventCodec.get_event_label(restored), "LB")
	assert_true(InputEventCodec.events_match(original, restored))

	restored.device = 4
	assert_false(InputEventCodec.events_match(original, restored), "different device")
	restored.device = 3
	restored.button_index = JOY_BUTTON_RIGHT_SHOULDER
	assert_false(InputEventCodec.events_match(original, restored), "different button")


func test_gamepad_axis_round_trip_preserves_identity_and_direction() -> void:
	var original := InputEventJoypadMotion.new()
	original.axis = JOY_AXIS_RIGHT_Y
	original.axis_value = -0.5
	original.device = 2

	var encoded: String = InputEventCodec.serialize_event(original)
	assert_eq(encoded, "joyaxis:%d:-0.5:2" % JOY_AXIS_RIGHT_Y)
	var restored := InputEventCodec.deserialize_event(encoded) as InputEventJoypadMotion
	assert_not_null(restored)
	if restored == null:
		return
	assert_eq(restored.axis, JOY_AXIS_RIGHT_Y)
	assert_eq(restored.axis_value, -0.5)
	assert_eq(restored.device, 2)
	assert_eq(InputEventCodec.get_event_device_type(restored), "gamepad")
	assert_eq(InputEventCodec.get_event_label(restored), "Right Stick (Up)")
	assert_true(InputEventCodec.events_match(original, restored))

	restored.axis_value = 0.5
	assert_eq(InputEventCodec.get_event_label(restored), "Right Stick (Down)")
	assert_false(InputEventCodec.events_match(original, restored), "opposite direction")
	restored.axis_value = -0.5
	restored.axis = JOY_AXIS_RIGHT_X
	assert_false(InputEventCodec.events_match(original, restored), "different axis")
	restored.axis = JOY_AXIS_RIGHT_Y
	restored.device = 1
	assert_false(InputEventCodec.events_match(original, restored), "different device")


func test_malformed_gamepad_bindings_are_rejected(
	serialized: String = use_parameters(
		[
			"joybtn:0",
			"joybtn:A:0",
			"joybtn:0:pad",
			"joybtn:0:0:extra",
			"joyaxis:1:-0.5",
			"joyaxis:Y:-0.5:0",
			"joyaxis:1:left:0",
			"joyaxis:1:-0.5:pad",
			"joyaxis:1:-0.5:0:extra",
		]
	)
) -> void:
	assert_null(InputEventCodec.deserialize_event(serialized), serialized + " is invalid")


func test_mouse_click_is_not_a_remappable_binding() -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	assert_eq(InputEventCodec.serialize_event(click), "")
	assert_eq(InputEventCodec.get_event_device_type(click), "unknown")
	assert_eq(InputEventCodec.get_event_label(click), "Unknown")
	assert_false(InputEventCodec.events_match(click, click))
	assert_false(InputEventCodec.events_match(click, null))
