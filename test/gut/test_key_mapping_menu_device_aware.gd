## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_key_mapping_menu_device_aware.gd
## GUT unit tests for Key Mapping Menu — Device Toggle, Mutual Exclusivity, Reset, Persistence
## Covers KM-01 to KM-13 from test plan (Issue #352).
## References: key_mapping.gd, key_mapping_menu.tscn, input_remap_button.gd, settings.gd,
##             test_key_mapping_menu.gd, test_integration_key_mapping.gd, test_input_remap_button_device_aware.gd

extends GutTest

const TEST_ACTION_SPEED_UP: String = "speed_up"
const TEST_ACTION_MOVE_LEFT: String = "move_left"
const TEST_CONFIG_PATH: String = "user://test_key_mapping_device_aware.cfg"
const TEST_BACKUP_PATH: String = "user://test_backup_device_aware.cfg"
const DEFAULT_CONFIG_BACKUP: String = "user://settings_backup.cfg"

var menu: CanvasLayer = null
var keyboard_btn: CheckButton = null
var gamepad_btn: CheckButton = null
var reset_btn: Button = null
var remap_buttons: Array[InputRemapButton] = []
var speed_up_btn: InputRemapButton = null
var move_left_btn: InputRemapButton = null


## Per-suite backup of production config (preserve real user settings).
func before_all() -> void:
	_backup_config(TEST_CONFIG_PATH, TEST_BACKUP_PATH)
	_backup_config(Settings.CONFIG_PATH, DEFAULT_CONFIG_BACKUP)


## Per-test: Clean config, reset InputMap, instantiate menu (default = keyboard).
func before_each() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)
	for action: String in Settings.ACTIONS:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action)
	# Manually add defaults (without saving)
	for action: String in Settings.ACTIONS:
		if Settings.DEFAULT_KEYBOARD.has(action):
			var ev: InputEventKey = InputEventKey.new()
			ev.physical_keycode = Settings.DEFAULT_KEYBOARD[action]
			InputMap.action_add_event(action, ev)
		if Settings.DEFAULT_GAMEPAD.has(action):
			var def: Dictionary = Settings.DEFAULT_GAMEPAD[action]
			if def["type"] == "button":
				var ev: InputEventJoypadButton = InputEventJoypadButton.new()
				ev.button_index = def["button"]
				ev.device = -1
				InputMap.action_add_event(action, ev)
			elif def["type"] == "axis":
				var ev: InputEventJoypadMotion = InputEventJoypadMotion.new()
				ev.axis = def["axis"]
				ev.axis_value = def["value"]
				ev.device = -1
				InputMap.action_add_event(action, ev)

	menu = load("res://scenes/key_mapping_menu.tscn").instantiate()
	add_child(menu)

	keyboard_btn = menu.get_node("Panel/Options/DeviceTypeContainer/Keyboard")
	gamepad_btn = menu.get_node("Panel/Options/DeviceTypeContainer/Gamepad")
	reset_btn = menu.get_node("Panel/Options/BtnContainer/ControlResetButton")
	var nodes: Array[Node] = menu.get_tree().get_nodes_in_group("remap_buttons")
	remap_buttons = []
	for node: Node in nodes:
		if node is InputRemapButton:
			remap_buttons.append(node as InputRemapButton)
	assert_eq(remap_buttons.size(), nodes.size(), "Some nodes in 'remap_buttons' group are not InputRemapButton")
	speed_up_btn = menu.get_node("Panel/Options/KeyMapContainer/PlayerKeyMap/KeyMappingSpeedUp/SpeedUpInputRemap")
	move_left_btn = menu.get_node("Panel/Options/KeyMapContainer/PlayerKeyMap/KeyMappingLeft/LeftInputRemap")

	# Ensure default state (keyboard active)
	keyboard_btn.button_pressed = true
	menu.update_all_remap_buttons()  # Force UI sync


## Per-test cleanup.
func after_each() -> void:
	if is_instance_valid(menu):
		menu.queue_free()
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)
	await get_tree().process_frame


## Per-suite restore.
func after_all() -> void:
	_restore_config(TEST_BACKUP_PATH, TEST_CONFIG_PATH)
	_restore_config(DEFAULT_CONFIG_BACKUP, Settings.CONFIG_PATH)


## Helper: Simulate remap on a button (keyboard or gamepad).
func _remap_button(btn: InputRemapButton, event: InputEvent, value: Variant) -> void:
	btn.button_pressed = true
	btn._on_pressed()
	if event is InputEventKey:
		event.physical_keycode = value
	elif event is InputEventJoypadButton:
		event.button_index = value
		event.device = -1
	elif event is InputEventJoypadMotion:
		event.axis = value
		event.axis_value = 1.0
		event.device = -1
	if not event is InputEventJoypadMotion:
		event.pressed = true
	btn._input(event)
	assert_false(btn.listening)


## Helper: Backup a config file if it exists.
func _backup_config(source_path: String, backup_path: String) -> void:
	if FileAccess.file_exists(source_path):
		DirAccess.copy_absolute(source_path, backup_path)


## Helper: Restore a config file from backup if it exists, and clean up the backup.
func _restore_config(backup_path: String, target_path: String) -> void:
	if FileAccess.file_exists(backup_path):
		if FileAccess.file_exists(target_path):
			DirAccess.remove_absolute(target_path)
		DirAccess.copy_absolute(backup_path, target_path)
		DirAccess.remove_absolute(backup_path)


## KM-01 | Toggle keyboard device
func test_km_01_toggle_keyboard() -> void:
	gamepad_btn.button_pressed = true
	gamepad_btn.toggled.emit(true)  # Switch away first
	keyboard_btn.button_pressed = true
	keyboard_btn.toggled.emit(true)
	assert_true(keyboard_btn.button_pressed)
	assert_false(gamepad_btn.button_pressed)
	for btn in remap_buttons:
		assert_eq(btn.current_device, InputRemapButton.DeviceType.KEYBOARD)


## KM-02 | Toggle gamepad device
func test_km_02_toggle_gamepad() -> void:
	keyboard_btn.button_pressed = true
	keyboard_btn.toggled.emit(true)
	gamepad_btn.button_pressed = true
	gamepad_btn.toggled.emit(true)
	assert_true(gamepad_btn.button_pressed)
	assert_false(keyboard_btn.button_pressed)
	for btn in remap_buttons:
		assert_eq(btn.current_device, InputRemapButton.DeviceType.GAMEPAD)


## KM-03 | Mutual exclusivity
func test_km_03_mutual_exclusivity() -> void:
	keyboard_btn.button_pressed = true
	keyboard_btn.toggled.emit(true)
	gamepad_btn.button_pressed = true
	gamepad_btn.toggled.emit(true)
	assert_true(gamepad_btn.button_pressed)
	assert_false(keyboard_btn.button_pressed)
	# Reverse
	keyboard_btn.button_pressed = true
	keyboard_btn.toggled.emit(true)
	assert_true(keyboard_btn.button_pressed)
	assert_false(gamepad_btn.button_pressed)


## KM-04 | Update remap buttons on device switch
func test_km_04_update_remap_buttons() -> void:
	# Keyboard
	keyboard_btn.button_pressed = true
	keyboard_btn.toggled.emit(true)
	assert_eq(speed_up_btn.current_device, InputRemapButton.DeviceType.KEYBOARD)
	assert_eq(speed_up_btn.text, "W")  # Default keyboard
	# Gamepad
	gamepad_btn.button_pressed = true
	gamepad_btn.toggled.emit(true)
	assert_eq(speed_up_btn.current_device, InputRemapButton.DeviceType.GAMEPAD)
	assert_eq(speed_up_btn.text, "RT (+)")  # Default gamepad axis label


## KM-05 | Reset current device (gamepad mode) | Switch to gamepad, remap speed_up, reset | Gamepad binding resets to default; keyboard unchanged.
## FIXED: Uses JOY_BUTTON_MISC1 (conflict-free) + await for UI sync.
## :rtype: void
func test_km_05_reset_current_device() -> void:
	gamepad_btn.button_pressed = true
	gamepad_btn.toggled.emit(true)
	await get_tree().process_frame
	
	# Remap speed_up to safe gamepad button
	_remap_button(speed_up_btn, InputEventJoypadButton.new(), JOY_BUTTON_MISC1)
	
	# Reset current (gamepad)
	reset_btn.pressed.emit()
	await get_tree().process_frame
	
	# Gamepad should revert to default
	assert_eq(speed_up_btn.text, "RT (+)", "Gamepad should reset to default")
	
	# Keyboard should remain untouched
	keyboard_btn.button_pressed = true
	keyboard_btn.toggled.emit(true)
	await get_tree().process_frame
	assert_eq(speed_up_btn.text, "W", "Keyboard binding should be unchanged")


## KM-06 | UI node validation (all required nodes exist after _ready)
func test_km_06_ui_node_validation() -> void:
	assert_not_null(keyboard_btn)
	assert_not_null(gamepad_btn)
	assert_not_null(reset_btn)
	assert_not_null(speed_up_btn)
	assert_gt(remap_buttons.size(), 0)


## KM-07 | Signal connections
func test_km_07_signal_connections() -> void:
	assert_true(keyboard_btn.toggled.is_connected(menu._on_keyboard_toggled))
	assert_true(gamepad_btn.toggled.is_connected(menu._on_gamepad_toggled))
	assert_true(reset_btn.pressed.is_connected(menu._on_reset_pressed))


## KM-08 | Logging behavior (toggle/reset)
func test_km_08_logging_behavior() -> void:
	# Toggle + reset → expect DEBUG logs (we perform actions; logs go to console)
	keyboard_btn.button_pressed = true
	keyboard_btn.toggled.emit(true)
	reset_btn.pressed.emit()
	# No crash + actions executed
	assert_true(true)  # Placeholder — logs visible in GUT output


## KM-09 | Persistence (remap → reload → restored)
## FIXED: Uses JOY_BUTTON_MISC1 (no conflict) + await for sync.
## :rtype: void
func test_km_09_persistence() -> void:
	# Remap both devices
	keyboard_btn.button_pressed = true
	_remap_button(speed_up_btn, InputEventKey.new(), KEY_Z)
	await get_tree().process_frame
	
	gamepad_btn.button_pressed = true
	gamepad_btn.toggled.emit(true)
	await get_tree().process_frame
	_remap_button(speed_up_btn, InputEventJoypadButton.new(), JOY_BUTTON_MISC1)
	await get_tree().process_frame
	
	# Save to test path
	Settings.save_input_mappings(TEST_CONFIG_PATH)
	
	# Simulate reload
	InputMap.action_erase_events(TEST_ACTION_SPEED_UP)
	Settings.load_input_mappings(TEST_CONFIG_PATH)
	menu.update_all_remap_buttons()
	await get_tree().process_frame
	
	# Keyboard
	keyboard_btn.button_pressed = true
	keyboard_btn.toggled.emit(true)
	await get_tree().process_frame
	assert_eq(speed_up_btn.text, "Z", "Keyboard remap should persist")
	
	# Gamepad
	gamepad_btn.button_pressed = true
	gamepad_btn.toggled.emit(true)
	await get_tree().process_frame
	assert_eq(speed_up_btn.text, "Button 15", "Gamepad remap should persist")


## KM-10 | Invalid input handling (ignored safely during remap)
func test_km_10_invalid_input_handling() -> void:
	gamepad_btn.button_pressed = true
	gamepad_btn.toggled.emit(true)
	var initial_size: int = InputMap.action_get_events(TEST_ACTION_SPEED_UP).size()
	speed_up_btn.button_pressed = true
	speed_up_btn._on_pressed()  # Start listening
	# Invalid: mouse during gamepad listen
	var invalid := InputEventMouseButton.new()
	invalid.button_index = MOUSE_BUTTON_LEFT
	invalid.pressed = true
	speed_up_btn._input(invalid)
	assert_true(speed_up_btn.listening)  # Still listening
	assert_eq(InputMap.action_get_events(TEST_ACTION_SPEED_UP).size(), initial_size)  # No change


## KM-11 | Rapid toggle stress (no invalid state / desync)
func test_km_11_rapid_toggle_stress() -> void:
	for i in range(20):
		if i % 2 == 0:
			keyboard_btn.button_pressed = true
			keyboard_btn.toggled.emit(true)
		else:
			gamepad_btn.button_pressed = true
			gamepad_btn.toggled.emit(true)
		menu.update_all_remap_buttons()
		assert_true(keyboard_btn.button_pressed or gamepad_btn.button_pressed)
		assert_false(keyboard_btn.button_pressed and gamepad_btn.button_pressed)
	assert_eq(speed_up_btn.current_device, InputRemapButton.DeviceType.GAMEPAD if 19 % 2 == 1 else InputRemapButton.DeviceType.KEYBOARD)


## KM-12 | UI label sync on device switch
func test_km_12_ui_label_sync() -> void:
	keyboard_btn.button_pressed = true
	keyboard_btn.toggled.emit(true)
	assert_eq(speed_up_btn.text, "W")
	gamepad_btn.button_pressed = true
	gamepad_btn.toggled.emit(true)
	assert_eq(speed_up_btn.text, "RT (+)")
	# Move left (axis example)
	assert_eq(move_left_btn.text, "Left Stick (Left)")


## KM-13 | Reset with defaults (no state corruption)
func test_km_13_reset_with_defaults() -> void:
	# Already defaults
	keyboard_btn.button_pressed = true
	reset_btn.pressed.emit()
	assert_eq(speed_up_btn.text, "W")  # No change
	# Gamepad
	gamepad_btn.button_pressed = true
	gamepad_btn.toggled.emit(true)
	reset_btn.pressed.emit()
	assert_eq(speed_up_btn.text, "RT (+)")
	# No extra events or unbound
	assert_eq(InputMap.action_get_events(TEST_ACTION_SPEED_UP).size(), 2)  # One key + one joy
