## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_main_scene_messages.gd
##
## GUT tests for MainScene.show_message() and the unbound-input check (#1151).
##
## Each show_message() call starts a new message generation, and an older message's timer
## must not hide a newer message. The KEY_PRESS_UNBOUND flag still resets when its own
## message expires. Small joystick movements, below Settings.AXIS_DEADZONE_THRESHOLD, never
## count as unbound input.
##
## The message timers are real SceneTreeTimers. To keep the suite fast, Engine.time_scale is
## raised while a test runs, so the 4-second message lasts about 0.5 real seconds. The test's
## own waits use SceneTreeTimers too, so they scale the same way.

extends GutTest

const GutHelper = preload("res://test/gut/gut_test_helper.gd")
const TIME_SCALE: float = 8.0
## Margin, in game seconds, between a message timer and a test's check, so the two timers
## never end on the same frame.
const MARGIN: float = 0.5

var _main_scene: MainScene = null
var _saved_time_scale: float = 1.0
var _saved_events: Dictionary = {}


func before_each() -> void:
	_saved_time_scale = Engine.time_scale
	_saved_events.clear()
	for action: StringName in InputMap.get_actions():
		_saved_events[action] = InputMap.action_get_events(action).duplicate()
	_main_scene = preload(GamePaths.MAIN_SCENE).instantiate()
	add_child(_main_scene)
	await get_tree().process_frame
	# Start every test with no message and no flags, whatever the level start showed.
	_main_scene.message_label.visible = false
	_main_scene.message_label.text = ""
	_main_scene._showing_unbound_key_message = false
	Engine.time_scale = TIME_SCALE


func after_each() -> void:
	Engine.time_scale = _saved_time_scale
	if is_instance_valid(_main_scene):
		GutHelper.safe_hard_free(_main_scene)
	_main_scene = null
	for action: StringName in _saved_events:
		InputMap.action_erase_events(action)
		for ev: InputEvent in _saved_events[action]:
			InputMap.action_add_event(action, ev)
	await get_tree().process_frame


# ── Helpers ──────────────────────────────────────────────────────────────────


## Waits [param seconds] of game time, using the same kind of timer as show_message().
func _wait_game_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _label_shows(text: String) -> bool:
	return _main_scene.message_label.visible and _main_scene.message_label.text == text


func _joy_axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var ev: InputEventJoypadMotion = InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	ev.device = 0
	return ev


## Removes every binding on [param axis], in both directions, from every InputMap action.
## after_each() puts them back.
func _unbind_axis(axis: JoyAxis) -> void:
	for action: StringName in InputMap.get_actions():
		for ev: InputEvent in InputMap.action_get_events(action):
			if ev is InputEventJoypadMotion and (ev as InputEventJoypadMotion).axis == axis:
				InputMap.action_erase_event(action, ev)


# ── show_message() ───────────────────────────────────────────────────────────


## MSG-01 | A single message hides after MESSAGE_DURATION.
func test_msg_01_single_message_hides_after_duration() -> void:
	_main_scene.show_message("ONE")
	assert_true(_label_shows("ONE"), "shown at once")

	await _wait_game_seconds(_main_scene.MESSAGE_DURATION - MARGIN)
	assert_true(_label_shows("ONE"), "still shown just before the time is up")

	await _wait_game_seconds(2.0 * MARGIN)
	assert_false(_main_scene.message_label.visible, "hidden after the time is up")


## MSG-02 | A second message stays visible for its full time after the first timer ends.
func test_msg_02_newer_message_outlives_older_timer() -> void:
	var half: float = _main_scene.MESSAGE_DURATION / 2.0
	_main_scene.show_message("FIRST")
	await _wait_game_seconds(half)
	_main_scene.show_message("SECOND")

	# The first timer ends here; it must not hide the second message.
	await _wait_game_seconds(half + MARGIN)
	assert_true(_label_shows("SECOND"), "the older timer didn't hide the newer message")

	await _wait_game_seconds(half - 2.0 * MARGIN)
	assert_true(_label_shows("SECOND"), "shown until its own time is up")

	await _wait_game_seconds(2.0 * MARGIN)
	assert_false(_main_scene.message_label.visible, "hidden by its own timer")


## MSG-03 | Each call starts a new generation.
func test_msg_03_each_call_increases_generation() -> void:
	var start: int = _main_scene._message_generation
	_main_scene.show_message("A")
	_main_scene.show_message("B")
	_main_scene.show_message("C")
	assert_eq(_main_scene._message_generation, start + 3, "one generation per call")
	assert_true(_label_shows("C"), "the latest text is shown")


## MSG-04 | The KEY_PRESS_UNBOUND flag resets when its own message expires, even if a newer
## message is still showing, so the key-press warning can appear again.
func test_msg_04_key_press_flag_resets_under_newer_message() -> void:
	var half: float = _main_scene.MESSAGE_DURATION / 2.0
	_main_scene._showing_unbound_key_message = true
	_main_scene.show_message("KEY", MainScene.MessageType.KEY_PRESS_UNBOUND)
	await _wait_game_seconds(half)
	_main_scene.show_message("CRITICAL", MainScene.MessageType.CRITICAL_UNBOUND)

	await _wait_game_seconds(half + MARGIN)
	assert_false(_main_scene._showing_unbound_key_message, "flag reset by its own timer")
	assert_true(_label_shows("CRITICAL"), "the newer message is still shown")


## MSG-05 | The KEY_PRESS_UNBOUND flag stays set while its message is showing.
func test_msg_05_key_press_flag_set_while_showing() -> void:
	_main_scene._showing_unbound_key_message = true
	_main_scene.show_message("KEY", MainScene.MessageType.KEY_PRESS_UNBOUND)

	await _wait_game_seconds(_main_scene.MESSAGE_DURATION - MARGIN)
	assert_true(_main_scene._showing_unbound_key_message, "still set before expiry")

	await _wait_game_seconds(2.0 * MARGIN)
	assert_false(_main_scene._showing_unbound_key_message, "reset on expiry")


## MSG-06 | The critical warning keeps its once-per-session flag after its message expires.
func test_msg_06_critical_flag_survives_expiry() -> void:
	_main_scene._showing_unbound_warning = true
	_main_scene.show_message("CRITICAL", MainScene.MessageType.CRITICAL_UNBOUND)

	await _wait_game_seconds(_main_scene.MESSAGE_DURATION + MARGIN)
	assert_false(_main_scene.message_label.visible, "message hidden")
	assert_true(_main_scene._showing_unbound_warning, "once-per-session flag still set")

	_main_scene._check_unbound_controls()
	assert_false(_main_scene.message_label.visible, "the check doesn't show it again")


## MSG-07 | A message shown after an older one expired gets its full time too.
func test_msg_07_back_to_back_messages() -> void:
	_main_scene.show_message("FIRST")
	await _wait_game_seconds(_main_scene.MESSAGE_DURATION + MARGIN)
	assert_false(_main_scene.message_label.visible, "first hidden")

	_main_scene.show_message("SECOND")
	await _wait_game_seconds(_main_scene.MESSAGE_DURATION - MARGIN)
	assert_true(_label_shows("SECOND"), "second shown for its full time")


# ── Unbound input and the deadzone ───────────────────────────────────────────


## DZ-01 | The deadzone lives in Settings, keeps its value, and is gone from the UI class.
func test_dz_01_deadzone_constant_moved_to_settings() -> void:
	assert_eq(Settings.AXIS_DEADZONE_THRESHOLD, 0.5, "value unchanged")
	var remap_constants: Dictionary = (
		load("res://scripts/ui/components/input_remap_button.gd").get_script_constant_map()
	)
	assert_false(
		remap_constants.has("AXIS_DEADZONE_THRESHOLD"), "InputRemapButton no longer owns it"
	)
	var source: String = FileAccess.get_file_as_string("res://scripts/core/main_scene.gd")
	assert_false(source.contains("InputRemapButton"), "gameplay doesn't use the UI class")


## DZ-02 | A small movement on an unbound axis doesn't show the unbound-key message.
func test_dz_02_small_axis_movement_is_ignored() -> void:
	var small: InputEventJoypadMotion = _joy_axis(
		JOY_AXIS_RIGHT_X, Settings.AXIS_DEADZONE_THRESHOLD - 0.01
	)
	_unbind_axis(JOY_AXIS_RIGHT_X)

	_main_scene._input(small)

	assert_false(_main_scene._showing_unbound_key_message, "flag not set")
	assert_false(_main_scene.message_label.visible, "no message")


## DZ-03 | A deliberate movement on the same unbound axis shows the message.
func test_dz_03_large_axis_movement_on_unbound_axis_warns() -> void:
	var large: InputEventJoypadMotion = _joy_axis(
		JOY_AXIS_RIGHT_X, Settings.AXIS_DEADZONE_THRESHOLD + 0.1
	)
	_unbind_axis(JOY_AXIS_RIGHT_X)
	assert_false(Settings.is_event_bound(large), "precondition: the axis is unbound")

	_main_scene._input(large)

	assert_true(_main_scene._showing_unbound_key_message, "flag set")
	assert_true(_main_scene.message_label.visible, "message shown")
