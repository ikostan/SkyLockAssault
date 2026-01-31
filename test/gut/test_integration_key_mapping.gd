## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_integration_key_mapping.gd
## GUT unit tests for integration of key mapping load, remap, persistence, and reset.
## Covers INT-01 to INT-03 from test plan.
## Test Plan:
## https://github.com/ikostan/SkyLockAssault/issues/350
## References: test_key_mapping_menu.gd, test_input_remap_button.gd, input_remap_button.gd, key_mapping.gd
## Assumes Settings.load_input_mappings() loads [input] section from config to InputMap.
## Assumes Settings.save_input_mappings() saves InputMap events to [input] as arrays of strings (e.g., ["key:87"] for KEY_W).
## Assumes Settings.reset_to_defaults(device_type) resets InputMap for that device and saves.
## Uses test config path to isolate; focuses on keyboard for brevity (extend for gamepad if needed).
## Uses "speed_up" as test action (from UI paths); assumes default keyboard is KEY_W ("W").
## Simulates remap via direct calls to private methods due to input event mocking complexity in GUT.

extends GutTest

const InputRemapButton: Script = preload("res://scripts/input_remap_button.gd")
const TEST_ACTION: String = "speed_up"  # Example action from UI; adjust if needed.
const TEST_CONFIG_PATH: String = "user://test_integration_settings.cfg"
const KEY_W_CODE: int = Key.KEY_W  # 87, default assumed.
const KEY_Z_CODE: int = Key.KEY_Z  # 90, custom for tests.

var menu: CanvasLayer = null
var Settings := preload("res://scripts/settings.gd")  # Assume path; adjust if autoload.
var settings_inst: Settings


## Per-test setup: Delete test config, reset InputMap for test action.
## :rtype: void
func before_each() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		var err: Error = DirAccess.remove_absolute(TEST_CONFIG_PATH)
		assert_eq(err, OK)
	if InputMap.has_action(TEST_ACTION):
		InputMap.erase_action(TEST_ACTION)
	InputMap.add_action(TEST_ACTION)
	# Assume Settings uses a configurable path; set it here if applicable.
	# Settings.current_config_path = TEST_CONFIG_PATH
	settings_inst = Settings.new()  # Create instance


## Per-test cleanup: Free menu, delete test config.
## :rtype: void
func after_each() -> void:
	if is_instance_valid(menu):
		menu.queue_free()
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		var err: Error = DirAccess.remove_absolute(TEST_CONFIG_PATH)
		assert_eq(err, OK)
	if settings_inst:
		settings_inst = null
	await get_tree().process_frame


## INT-01 | Load mappings → UI | Pre-saved config | UI shows correct mappings | Matches config file
## :rtype: void
func test_int_01_load_to_ui() -> void:
	gut.p("INT-01: Pre-saved config loads to InputMap and UI shows correct labels matching config.")
	# Setup: Create config with custom keyboard mapping (e.g., "Z" instead of default "W")
	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", TEST_ACTION, ["key:" + str(KEY_Z_CODE)])  # Assume string format "key:<code>"
	config.save(TEST_CONFIG_PATH)
	# Load mappings to InputMap
	# Assume loads from TEST_CONFIG_PATH if set
	settings_inst.load_input_mappings()  # Call on instance
	# Verify InputMap loaded correctly
	var events: Array[InputEvent] = InputMap.action_get_events(TEST_ACTION)
	assert_eq(events.size(), 1, "Should have one event after load")
	assert_true(events[0] is InputEventKey, "Loaded event should be InputEventKey")
	assert_eq(events[0].physical_keycode, KEY_Z_CODE, "Loaded keycode should match config")
	# Instantiate menu and add to tree (UI updates in _ready via update_button_text)
	menu = load("res://scenes/key_mapping_menu.tscn").instantiate()
	add_child(menu)
	# Get specific remap button for test action (keyboard default)
	var speed_up_btn: InputRemapButton = menu.get_node("Panel/Options/KeyMapContainer/PlayerKeyMap/KeyMappingSpeedUp/SpeedUpInputRemap")
	assert_not_null(speed_up_btn, "SpeedUp remap button should exist")
	# Validation: UI matches config/loaded mapping
	assert_eq(speed_up_btn.text, "Z", "UI label should show loaded custom key 'Z'")
	# Double-check config unchanged
	config = ConfigFile.new()
	config.load(TEST_CONFIG_PATH)
	assert_eq(config.get_value("input", TEST_ACTION), ["key:" + str(KEY_Z_CODE)], "Config should match")


## INT-02 | Remap + persist | Change action then save | Reload restores mapping | Disk & UI sync
## :rtype: void
func test_int_02_remap_persist() -> void:
	gut.p("INT-02: Remap updates InputMap/UI, saves to config; reload restores to disk/UI sync.")
	# Setup: Default mapping (assume reset sets to "W"); instantiate menu
	settings_inst.reset_to_defaults("keyboard")  # Ensure defaults loaded
	menu = load("res://scenes/key_mapping_menu.tscn").instantiate()
	add_child(menu)
	var speed_up_btn: InputRemapButton = menu.get_node("Panel/Options/KeyMapContainer/PlayerKeyMap/KeyMappingSpeedUp/SpeedUpInputRemap")
	assert_eq(speed_up_btn.text, "W", "Should start with default 'W'")
	# Simulate remap to "Z" (direct calls as in ref tests)
	speed_up_btn.button_pressed = true
	speed_up_btn._on_pressed()  # Start listening
	var temp_event := InputEventKey.new()
	temp_event.physical_keycode = KEY_Z_CODE
	temp_event.pressed = true
	speed_up_btn._input(temp_event)  # Triggers erase/add/save
	# Verify immediate UI/InputMap update
	assert_eq(speed_up_btn.text, "Z", "UI label should update to new key 'Z'")
	var events: Array[InputEvent] = InputMap.action_get_events(TEST_ACTION)
	assert_eq(events.size(), 1, "Should have one event after remap")
	assert_eq(events[0].physical_keycode, KEY_Z_CODE, "InputMap should have new keycode")
	# Verify saved to config (persist)
	var config: ConfigFile = ConfigFile.new()
	config.load(TEST_CONFIG_PATH)
	assert_true(config.has_section_key("input", TEST_ACTION), "Config should have input section after save")
	assert_eq(config.get_value("input", TEST_ACTION), ["key:" + str(KEY_Z_CODE)], "Config should match new mapping")
	# Simulate reload: Erase InputMap, load from config, update UI
	InputMap.action_erase_events(TEST_ACTION)
	settings_inst.load_input_mappings()
	speed_up_btn.update_button_text()  # Or reinstantiate, but update suffices
	assert_eq(speed_up_btn.text, "Z", "UI should restore loaded mapping after reload")
	events = InputMap.action_get_events(TEST_ACTION)
	assert_eq(events[0].physical_keycode, KEY_Z_CODE, "InputMap restored from disk")


## INT-03 | Reset via UI | Click reset | Mappings + config reset | Defaults in UI & file
## :rtype: void
func test_int_03_reset_via_ui() -> void:
	gut.p("INT-03: Reset button resets InputMap/config to defaults; UI/file show defaults.")
	# Setup: Set custom mapping in config/InputMap, then instantiate menu
	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", TEST_ACTION, ["key:" + str(KEY_Z_CODE)])
	config.save(TEST_CONFIG_PATH)
	settings_inst.load_input_mappings()
	menu = load("res://scenes/key_mapping_menu.tscn").instantiate()
	add_child(menu)
	var speed_up_btn: InputRemapButton = menu.get_node("Panel/Options/KeyMapContainer/PlayerKeyMap/KeyMappingSpeedUp/SpeedUpInputRemap")
	assert_eq(speed_up_btn.text, "Z", "Should start with custom 'Z'")
	# Get reset button
	var reset_btn: Button = menu.get_node("Panel/Options/BtnContainer/ControlResetButton")
	# Simulate reset (keyboard mode default)
	reset_btn.pressed.emit()  # Triggers _on_reset_pressed → Settings.reset_to_defaults("keyboard") → update_all_remap_buttons
	# Verify UI/InputMap reset to default
	assert_eq(speed_up_btn.text, "W", "UI label should reset to default 'W'")
	var events: Array[InputEvent] = InputMap.action_get_events(TEST_ACTION)
	assert_eq(events.size(), 1, "Should have default event after reset")
	assert_eq(events[0].physical_keycode, KEY_W_CODE, "InputMap should reset to default keycode")
	# Verify config reset (assume reset saves defaults)
	config = ConfigFile.new()
	config.load(TEST_CONFIG_PATH)
	assert_eq(config.get_value("input", TEST_ACTION), ["key:" + str(KEY_W_CODE)], "Config should reset to default mapping")
