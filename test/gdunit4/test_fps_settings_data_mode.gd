## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_fps_settings_data_model.gd
##
## GdUnit4 automated unit test suite for FPS settings data model and signal contracts.

extends GdUnitTestSuite

const PATH_TEST_SETTINGS: String = "user://test_fps_settings.cfg"

var _orig_settings: GameSettingsResource
var _orig_save_encryption_pass: String


func before_test() -> void:
	# Backup globals to prevent test bleeding
	_orig_settings = Globals.settings
	_orig_save_encryption_pass = Globals.save_encryption_pass
	
	# Reset for isolated tests with a deterministic encryption key
	Globals.settings = GameSettingsResource.new()
	Globals.save_encryption_pass = "deterministic_test_key_123"


func after_test() -> void:
	# Clean up disk I/O artifacts
	if FileAccess.file_exists(PATH_TEST_SETTINGS):
		DirAccess.remove_absolute(PATH_TEST_SETTINGS)
		
	# Restore the global state for subsequent suites
	Globals.settings = _orig_settings
	Globals.save_encryption_pass = _orig_save_encryption_pass


## Test 1: Verify Default State
## Objective: Ensure the settings data model initializes correctly.
## Description: Check the initial default value of the `show_fps` property on a newly instantiated settings resource.
## Expected Result: The `show_fps` variable strictly initializes as `false`.
func test_verify_default_state() -> void:
	var settings: GameSettingsResource = auto_free(GameSettingsResource.new())
	assert_bool(settings.show_fps).is_false()


## Test 2: Verify Bidirectional State Transitions
## Objective: Confirm the settings data model accurately registers mutations in both directions.
## Description: Programmatically set `show_fps` to `true`, assert the change, then set it to `false` and assert again.
## Expected Result: The stored variable reflects `true`, then successfully updates to `false`.
func test_verify_bidirectional_state_transitions() -> void:
	var settings: GameSettingsResource = auto_free(GameSettingsResource.new())
	
	assert_bool(settings.show_fps).is_false()
	
	# Transition False -> True
	settings.show_fps = true
	assert_bool(settings.show_fps).is_true()
	
	# Transition True -> False
	settings.show_fps = false
	assert_bool(settings.show_fps).is_false()


## Test 3: Verify Signal Emission Contract
## Objective: Ensure exact Observer pattern notifications without redundant emissions.
## Description: Watch the `setting_changed` signal. Transition `show_fps` from `false` -> `true`, then `true` -> `true`, then `true` -> `false`.
## Expected Result: The signal emits exactly twice with arguments `("show_fps", true)` and `("show_fps", false)`. No emission occurs when the value remains unchanged.
func test_verify_signal_emission_contract() -> void:
	var settings: GameSettingsResource = auto_free(GameSettingsResource.new())
	settings.show_fps = false  # Explicitly reset before tracking
	
	# Isolate the signal observer AFTER the fresh object is fully instantiated
	var emissions: Array[Array] = []
	settings.setting_changed.connect(func(setting_name: String, new_value: Variant) -> void:
		if setting_name == "show_fps":
			emissions.push_back([setting_name, new_value])
	)
	
	# Trigger transitions
	settings.show_fps = true   # False -> True (Expected emission 1)
	settings.show_fps = true   # True -> True (Should NOT emit)
	settings.show_fps = false  # True -> False (Expected emission 2)
	
	# Verify exactly two emissions occurred
	assert_int(emissions.size()).is_equal(2)
	assert_array(emissions[0]).contains_exactly(["show_fps", true])
	assert_array(emissions[1]).contains_exactly(["show_fps", false])
