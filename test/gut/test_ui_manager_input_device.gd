## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_ui_manager_input_device.gd
##
## UiManager switches the current input device through Settings when the player uses another
## device, except on mouse motion and while the Key Mapping screen is open, where that
## screen's Keyboard/Gamepad toggle picks the device (#1101, #619).

extends GutTest

var _saved_device: String = ""


func before_each() -> void:
	_saved_device = Settings.get_input_device()
	assert_null(
		get_tree().get_first_node_in_group(UiManager.KEY_MAPPING_GROUP),
		"Precondition: no Key Mapping screen is open"
	)


func after_each() -> void:
	Settings.set_input_device(_saved_device)
	await get_tree().process_frame


func _key_press(keycode: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.pressed = true
	return ev


func _joy_button(button: JoyButton) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.pressed = true
	return ev


func _mouse_motion() -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.relative = Vector2(12.0, 7.0)
	ev.position = Vector2(100.0, 100.0)
	return ev


## UIDEV-01 | A key press switches gamepad to keyboard.
func test_uidev_01_key_press_selects_keyboard() -> void:
	Settings.set_input_device("gamepad")
	UiManager._track_input_device(_key_press(KEY_F12))
	assert_eq(Settings.get_input_device(), "keyboard")


## UIDEV-02 | A joypad button or axis switches keyboard to gamepad.
func test_uidev_02_joypad_selects_gamepad() -> void:
	Settings.set_input_device("keyboard")
	UiManager._track_input_device(_joy_button(JOY_BUTTON_A))
	assert_eq(Settings.get_input_device(), "gamepad", "button")

	Settings.set_input_device("keyboard")
	var axis := InputEventJoypadMotion.new()
	axis.axis = JOY_AXIS_LEFT_X
	axis.axis_value = 1.0
	UiManager._track_input_device(axis)
	assert_eq(Settings.get_input_device(), "gamepad", "axis")


## UIDEV-03 | A mouse click still selects keyboard.
func test_uidev_03_mouse_button_selects_keyboard() -> void:
	Settings.set_input_device("gamepad")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	UiManager._track_input_device(click)
	assert_eq(Settings.get_input_device(), "keyboard")


## UIDEV-04 | Mouse motion never switches the device.
func test_uidev_04_mouse_motion_keeps_device() -> void:
	Settings.set_input_device("gamepad")
	watch_signals(Settings)
	UiManager._track_input_device(_mouse_motion())
	assert_eq(Settings.get_input_device(), "gamepad")
	assert_signal_not_emitted(Settings, "input_device_changed")


## UIDEV-05 | Input from the device that is already current emits nothing.
func test_uidev_05_same_device_input_does_not_emit() -> void:
	Settings.set_input_device("keyboard")
	watch_signals(Settings)
	UiManager._track_input_device(_key_press(KEY_F12))
	assert_signal_not_emitted(Settings, "input_device_changed")


## UIDEV-06 | Regression (#619): with Key Mapping open on "gamepad", moving the mouse or
## pressing a key does not switch the device; the screen's toggle stays on Gamepad. The events
## go through the real input pipeline, so UiManager._input() handles them.
func test_uidev_06_key_mapping_open_keeps_gamepad() -> void:
	Settings.set_input_device("gamepad")
	var menu: CanvasLayer = (load(GamePaths.KEY_MAPPING_SCENE) as PackedScene).instantiate()
	add_child_autofree(menu)
	await wait_process_frames(1)
	assert_true(menu.gamepad.button_pressed, "Precondition: the screen shows Gamepad")

	Input.parse_input_event(_mouse_motion())
	Input.flush_buffered_events()
	await wait_process_frames(2)
	assert_eq(Settings.get_input_device(), "gamepad", "mouse motion keeps gamepad")

	UiManager._track_input_device(_key_press(KEY_F12))
	UiManager._track_input_device(_mouse_motion())
	assert_eq(Settings.get_input_device(), "gamepad", "a key press keeps gamepad too")
	assert_true(menu.gamepad.button_pressed, "the toggle still shows Gamepad")
	assert_false(menu.keyboard.button_pressed, "Keyboard is not selected")


## UIDEV-07 | The Key Mapping toggle still switches the device while the screen is open.
func test_uidev_07_key_mapping_toggle_switches_device() -> void:
	Settings.set_input_device("gamepad")
	var menu: CanvasLayer = (load(GamePaths.KEY_MAPPING_SCENE) as PackedScene).instantiate()
	add_child_autofree(menu)
	await wait_process_frames(1)

	menu._on_keyboard_toggled(true)

	assert_eq(Settings.get_input_device(), "keyboard", "the toggle picks the device")
	# The toggle saves the device to Settings.CONFIG_PATH; put the saved value back.
	Settings.save_last_input_device(_saved_device)


## UIDEV-08 | Once Key Mapping is closed, input switches the device again.
func test_uidev_08_tracking_resumes_after_key_mapping_closes() -> void:
	Settings.set_input_device("gamepad")
	var menu: CanvasLayer = (load(GamePaths.KEY_MAPPING_SCENE) as PackedScene).instantiate()
	add_child(menu)
	await wait_process_frames(1)
	menu.queue_free()
	await wait_process_frames(1)
	assert_false(is_instance_valid(menu), "Precondition: the screen is freed")

	UiManager._track_input_device(_key_press(KEY_F12))

	assert_eq(Settings.get_input_device(), "keyboard")
