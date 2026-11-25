## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_input_remap_esc_cancel.gd
##
## GUT tests for Esc cancelling keyboard remapping in input_remap_button.gd (#1168).
##
## Esc while a keyboard remap button is listening stops listening and keeps the current binding.
## It doesn't touch InputMap, doesn't save, and marks the input handled so the Key Mapping menu
## stays open and the menu cancel sound doesn't play. Esc can't be bound by remapping, and Reset
## to defaults still restores Pause to Esc.
##
## Issue: https://github.com/ikostan/SkyLockAssault/issues/1168

extends GutTest

const TEST_ACTION: String = "test_esc_cancel_action"


## Records every event that reaches _input() or _unhandled_input(). Moved to the front of the
## root's children, so it gets _input() after every other node: an event handled earlier never
## reaches it.
class InputProbe:
	extends Node
	var input_events: Array[InputEvent] = []
	var unhandled_events: Array[InputEvent] = []

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _input(event: InputEvent) -> void:
		input_events.append(event)

	func _unhandled_input(event: InputEvent) -> void:
		unhandled_events.append(event)

	## Returns true if any recorded event in [param events] is an Esc key press.
	static func has_escape(events: Array[InputEvent]) -> bool:
		for ev: InputEvent in events:
			if ev is InputEventKey and ev.pressed and ev.physical_keycode == KEY_ESCAPE:
				return true
		return false


## Stand-in for the Key Mapping menu while its conflict dialog waits for this button.
class FakeKeyMappingMenu:
	extends Node
	var current_remap_button: InputRemapButton = null
	var dialog_calls: int = 0

	func _ready() -> void:
		add_to_group("key_mapping_menu")

	func show_conflict_dialog(
		_btn: InputRemapButton, _new_event: InputEvent, _conflicts: Array[String]
	) -> void:
		dialog_calls += 1


var button: InputRemapButton
var _original_input_map: Dictionary = {}
var _config_existed: bool = false
var _config_bytes: PackedByteArray = PackedByteArray()


func before_all() -> void:
	for act: StringName in InputMap.get_actions():
		_original_input_map[act] = InputMap.action_get_events(act)


func after_all() -> void:
	for act: StringName in InputMap.get_actions():
		if not _original_input_map.has(act):
			InputMap.erase_action(act)
	for act: StringName in _original_input_map:
		if not InputMap.has_action(act):
			InputMap.add_action(act)
		InputMap.action_erase_events(act)
		for ev: InputEvent in _original_input_map[act]:
			InputMap.action_add_event(act, ev)


func before_each() -> void:
	_config_existed = FileAccess.file_exists(Settings.CONFIG_PATH)
	_config_bytes = (
		FileAccess.get_file_as_bytes(Settings.CONFIG_PATH) if _config_existed else PackedByteArray()
	)

	if InputMap.has_action(TEST_ACTION):
		InputMap.erase_action(TEST_ACTION)
	InputMap.add_action(TEST_ACTION)
	var prior_key: InputEventKey = InputEventKey.new()
	prior_key.physical_keycode = KEY_A
	InputMap.action_add_event(TEST_ACTION, prior_key)
	var prior_pad: InputEventJoypadButton = InputEventJoypadButton.new()
	prior_pad.button_index = JOY_BUTTON_A
	prior_pad.device = -1
	InputMap.action_add_event(TEST_ACTION, prior_pad)

	button = InputRemapButton.new()
	button.action = TEST_ACTION
	button.current_device = InputRemapButton.DeviceType.KEYBOARD
	add_child_autofree(button)


func after_each() -> void:
	if InputMap.has_action(TEST_ACTION):
		InputMap.erase_action(TEST_ACTION)
	_restore_config()
	await get_tree().process_frame


func _restore_config() -> void:
	if _config_existed:
		var file: FileAccess = FileAccess.open(Settings.CONFIG_PATH, FileAccess.WRITE)
		file.store_buffer(_config_bytes)
		file.close()
	elif FileAccess.file_exists(Settings.CONFIG_PATH):
		DirAccess.remove_absolute(Settings.CONFIG_PATH)


## Returns true if the settings file is the same as before the test (or still missing).
func _config_unchanged() -> bool:
	if not _config_existed:
		return not FileAccess.file_exists(Settings.CONFIG_PATH)
	return FileAccess.get_file_as_bytes(Settings.CONFIG_PATH) == _config_bytes


func _start_listening(btn: InputRemapButton) -> void:
	btn.button_pressed = true
	btn.pressed.emit()
	assert_true(btn.listening, "Precondition: the button must be listening.")


func _key_press(keycode: Key) -> InputEventKey:
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = keycode
	ev.keycode = keycode
	ev.pressed = true
	return ev


func _keyboard_keys(action_name: String) -> Array[Key]:
	var keys: Array[Key] = []
	for ev: InputEvent in InputMap.action_get_events(action_name):
		if ev is InputEventKey:
			keys.append((ev as InputEventKey).physical_keycode)
	return keys


func _gamepad_buttons(action_name: String) -> Array[JoyButton]:
	var buttons: Array[JoyButton] = []
	for ev: InputEvent in InputMap.action_get_events(action_name):
		if ev is InputEventJoypadButton:
			buttons.append((ev as InputEventJoypadButton).button_index)
	return buttons


## Confirm-first case from #1168: before the fix, Esc was bound like any other key.
## Esc while listening on keyboard stops listening, keeps the binding, saves nothing and restores
## the button text.
func test_esc_cancels_keyboard_listening_and_keeps_binding() -> void:
	_start_listening(button)
	assert_eq(button.text, Globals.settings.remap_prompt_keyboard)

	button._input(_key_press(KEY_ESCAPE))

	assert_false(button.listening, "Esc must stop listening.")
	assert_false(button.button_pressed, "Esc must release the toggle button.")
	assert_eq(_keyboard_keys(TEST_ACTION), [KEY_A] as Array[Key], "Esc must keep the binding.")
	assert_eq(
		_gamepad_buttons(TEST_ACTION),
		[JOY_BUTTON_A] as Array[JoyButton],
		"Esc must not touch the gamepad binding."
	)
	assert_eq(button.text, "A", "Esc must restore the button text to the current binding.")
	assert_true(_config_unchanged(), "Esc must not save the input mappings.")


## Esc without an Esc keycode on the logical key (physical only) still cancels.
func test_esc_cancels_with_physical_keycode_only() -> void:
	_start_listening(button)
	var esc: InputEventKey = InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true

	button._input(esc)

	assert_false(button.listening)
	assert_eq(_keyboard_keys(TEST_ACTION), [KEY_A] as Array[Key])


## Esc with modifiers held still cancels and is never bound.
func test_esc_with_modifier_still_cancels() -> void:
	_start_listening(button)
	var esc: InputEventKey = _key_press(KEY_ESCAPE)
	esc.shift_pressed = true

	button._input(esc)

	assert_false(button.listening)
	assert_eq(_keyboard_keys(TEST_ACTION), [KEY_A] as Array[Key])


## Releasing Esc (pressed = false) while listening does nothing: only a press cancels.
func test_esc_release_does_not_cancel() -> void:
	_start_listening(button)
	var esc_up: InputEventKey = _key_press(KEY_ESCAPE)
	esc_up.pressed = false

	button._input(esc_up)

	assert_true(button.listening, "An Esc release must not cancel listening.")
	assert_eq(_keyboard_keys(TEST_ACTION), [KEY_A] as Array[Key])


## Esc while not listening does nothing.
func test_esc_when_not_listening_is_ignored() -> void:
	assert_false(button.listening)
	button._input(_key_press(KEY_ESCAPE))
	assert_false(button.listening)
	assert_eq(_keyboard_keys(TEST_ACTION), [KEY_A] as Array[Key])
	assert_eq(button.text, "A")
	assert_true(_config_unchanged())


## cancel_listening() marks the input handled.
func test_cancel_listening_marks_input_handled() -> void:
	_start_listening(button)
	button.cancel_listening()
	assert_true(
		get_viewport().is_input_handled(), "cancel_listening() must mark the input handled."
	)
	assert_false(button.listening)
	assert_eq(_keyboard_keys(TEST_ACTION), [KEY_A] as Array[Key])
	assert_true(_config_unchanged(), "cancel_listening() must not save.")


## A real Esc event is consumed by the listening button: no later _input() or
## _unhandled_input() sees it (UIManager's cancel sound, the pause toggle, menus).
func test_esc_event_is_handled_and_not_propagated() -> void:
	var probe: InputProbe = InputProbe.new()
	get_tree().root.add_child(probe)
	get_tree().root.move_child(probe, 0)
	_start_listening(button)

	Input.parse_input_event(_key_press(KEY_ESCAPE))
	await get_tree().process_frame
	await get_tree().process_frame

	assert_false(button.listening, "Esc must stop listening.")
	assert_eq(_keyboard_keys(TEST_ACTION), [KEY_A] as Array[Key])
	assert_false(
		InputProbe.has_escape(probe.input_events), "Handled Esc must not reach later _input()."
	)
	assert_false(
		InputProbe.has_escape(probe.unhandled_events),
		"Handled Esc must not reach _unhandled_input()."
	)
	probe.queue_free()


## Control case for the probe: with the button not listening, Esc isn't handled by it and does
## reach the probe. Proves the propagation checks above can fail.
func test_probe_sees_esc_when_button_not_listening() -> void:
	var probe: InputProbe = InputProbe.new()
	get_tree().root.add_child(probe)
	get_tree().root.move_child(probe, 0)

	Input.parse_input_event(_key_press(KEY_ESCAPE))
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(InputProbe.has_escape(probe.input_events), "An unhandled Esc must reach the probe.")
	probe.queue_free()


## In the real Key Mapping menu, Esc cancels a keyboard remap and the menu stays open.
func test_esc_in_key_mapping_menu_keeps_menu_open() -> void:
	Settings._add_missing_defaults(ConfigFile.new())
	var menu: CanvasLayer = load(GamePaths.KEY_MAPPING_SCENE).instantiate()
	add_child(menu)
	var keyboard_btn: CheckButton = menu.get_node("Panel/Options/DeviceTypeContainer/Keyboard")
	var gamepad_btn: CheckButton = menu.get_node("Panel/Options/DeviceTypeContainer/Gamepad")
	# Select Keyboard without emitting toggled: _on_keyboard_toggled() would save the device
	# preference and break the "nothing saved" check below.
	keyboard_btn.set_pressed_no_signal(true)
	gamepad_btn.set_pressed_no_signal(false)
	menu.update_all_remap_buttons()
	var left_btn: InputRemapButton = menu.get_node(
		"Panel/Options/KeyMapContainer/PlayerKeyMap/KeyMappingLeft/LeftInputRemap"
	)
	assert_eq(
		left_btn.current_device,
		InputRemapButton.DeviceType.KEYBOARD,
		"Precondition: the remap buttons must be in keyboard mode."
	)
	var keys_before: Array[Key] = _keyboard_keys(left_btn.action)
	var text_before: String = left_btn.text
	var probe: InputProbe = InputProbe.new()
	get_tree().root.add_child(probe)
	get_tree().root.move_child(probe, 0)

	_start_listening(left_btn)
	Input.parse_input_event(_key_press(KEY_ESCAPE))
	await get_tree().process_frame
	await get_tree().process_frame

	assert_false(left_btn.listening, "Esc must stop listening in the Key Mapping menu.")
	assert_eq(_keyboard_keys(left_btn.action), keys_before, "Esc must keep the binding.")
	assert_eq(left_btn.text, text_before, "Esc must restore the button text.")
	assert_true(is_instance_valid(menu), "The Key Mapping menu must stay open.")
	assert_true(menu.is_inside_tree(), "The Key Mapping menu must stay in the tree.")
	assert_false(menu.is_queued_for_deletion(), "Esc must not close the Key Mapping menu.")
	assert_false(InputProbe.has_escape(probe.unhandled_events))
	assert_true(_config_unchanged(), "Esc must not save the input mappings.")

	probe.queue_free()
	menu.queue_free()


## Esc while listening on gamepad does nothing, as before: the button keeps listening.
func test_esc_while_listening_on_gamepad_does_nothing() -> void:
	button.current_device = InputRemapButton.DeviceType.GAMEPAD
	_start_listening(button)
	assert_eq(button.text, Globals.settings.remap_prompt_gamepad)

	button._input(_key_press(KEY_ESCAPE))

	assert_true(button.listening, "Esc must not cancel gamepad listening.")
	assert_eq(_keyboard_keys(TEST_ACTION), [KEY_A] as Array[Key])
	assert_eq(_gamepad_buttons(TEST_ACTION), [JOY_BUTTON_A] as Array[JoyButton])
	assert_true(_config_unchanged())


## Other keys still bind, and pure modifiers are still ignored.
func test_other_keys_still_bind_and_modifiers_ignored() -> void:
	_start_listening(button)

	button._input(_key_press(KEY_SHIFT))
	assert_true(button.listening, "A pure modifier must not end listening.")
	assert_eq(_keyboard_keys(TEST_ACTION), [KEY_A] as Array[Key])

	button._input(_key_press(KEY_Z))
	assert_false(button.listening)
	assert_eq(_keyboard_keys(TEST_ACTION), [KEY_Z] as Array[Key], "KEY_Z must replace KEY_A.")
	assert_eq(button.text, "Z")


## Clicking the button again still cancels, through _on_pressed().
func test_clicking_again_still_cancels() -> void:
	_start_listening(button)
	button.button_pressed = false
	button.pressed.emit()

	assert_false(button.listening)
	assert_eq(_keyboard_keys(TEST_ACTION), [KEY_A] as Array[Key])
	assert_eq(button.text, "A")


## While the conflict dialog waits for this button, Esc is left to the dialog: the button keeps
## listening and nothing is bound or saved.
func test_esc_does_not_affect_pending_conflict() -> void:
	var fake_menu: FakeKeyMappingMenu = FakeKeyMappingMenu.new()
	add_child_autofree(fake_menu)
	_start_listening(button)
	fake_menu.current_remap_button = button

	button._input(_key_press(KEY_ESCAPE))

	assert_true(button.listening, "Esc must leave a pending conflict to the dialog.")
	assert_eq(fake_menu.current_remap_button, button, "The pending conflict must stay.")
	assert_eq(fake_menu.dialog_calls, 0, "Esc must not open another conflict dialog.")
	assert_eq(_keyboard_keys(TEST_ACTION), [KEY_A] as Array[Key])
	assert_true(_config_unchanged())


## With a conflict pending for another button, Esc still cancels this one.
func test_esc_cancels_when_conflict_pending_for_other_button() -> void:
	var fake_menu: FakeKeyMappingMenu = FakeKeyMappingMenu.new()
	add_child_autofree(fake_menu)
	var other: InputRemapButton = InputRemapButton.new()
	other.action = TEST_ACTION
	add_child_autofree(other)
	fake_menu.current_remap_button = other
	_start_listening(button)

	button._input(_key_press(KEY_ESCAPE))

	assert_false(button.listening)
	assert_eq(fake_menu.current_remap_button, other)


## Pause can't be bound to Esc through remapping, and Reset to defaults restores it to Esc.
func test_pause_cannot_be_bound_to_esc_and_reset_restores_it() -> void:
	assert_true(InputMap.has_action("pause"), "Precondition: the pause action must exist.")
	var pause_btn: InputRemapButton = InputRemapButton.new()
	pause_btn.action = "pause"
	pause_btn.current_device = InputRemapButton.DeviceType.KEYBOARD
	add_child_autofree(pause_btn)

	# Move Pause off Esc first (KEY_F9 is unbound by default).
	_start_listening(pause_btn)
	pause_btn._input(_key_press(KEY_F9))
	assert_eq(_keyboard_keys("pause"), [KEY_F9] as Array[Key], "Precondition: Pause on F9.")

	# Esc can't bring it back through remapping.
	_start_listening(pause_btn)
	pause_btn._input(_key_press(KEY_ESCAPE))
	assert_false(pause_btn.listening)
	assert_eq(_keyboard_keys("pause"), [KEY_F9] as Array[Key], "Esc must not be bound to Pause.")

	# Reset to defaults restores Esc.
	Settings.reset_to_defaults("keyboard")
	assert_eq(
		_keyboard_keys("pause"),
		[KEY_ESCAPE] as Array[Key],
		"Reset to defaults must restore Pause to Esc."
	)


## A held Esc (echo) while listening on keyboard is never bound and doesn't cancel: the button
## keeps listening and nothing is saved. Happens when listening starts while Esc is held.
func test_esc_echo_is_not_bound() -> void:
	_start_listening(button)
	var esc_echo: InputEventKey = _key_press(KEY_ESCAPE)
	esc_echo.echo = true

	button._input(esc_echo)

	assert_true(button.listening, "An Esc echo must not end listening.")
	assert_eq(_keyboard_keys(TEST_ACTION), [KEY_A] as Array[Key], "An Esc echo must not be bound.")
	assert_true(_config_unchanged(), "An Esc echo must not save the input mappings.")

	# A real Esc press afterwards still cancels.
	button._input(_key_press(KEY_ESCAPE))
	assert_false(button.listening, "A non-echo Esc press must still cancel.")
	assert_eq(_keyboard_keys(TEST_ACTION), [KEY_A] as Array[Key])
