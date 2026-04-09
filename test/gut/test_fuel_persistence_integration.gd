## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_fuel_persistence_integration.gd
## GUT unit tests covering fuel system persistence, fallback behaviors, and UI reactivity.

extends "res://addons/gut/test.gd"

const TEST_CONFIG_PATH: String = "user://test_fuel_integration_settings.cfg"

## Per-test setup: Isolate the filesystem and ensure a clean memory state.
## :rtype: void
func before_each() -> void:
	# Ensure a clean slate by deleting any leftover test config files
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)
	
	# Reset global settings to a fresh instance to prevent state leakage between tests
	Globals.settings = GameSettingsResource.new()


## Per-test cleanup: Remove temporary configuration files.
## :rtype: void
func after_each() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)


## test_fuel_persistence | Config Save/Load | Verify valid current_fuel and max_fuel persist correctly
## :rtype: void
func test_fuel_persistence() -> void:
	gut.p("Testing: Saving and loading valid fuel configuration values.")
	
	# 1. Set specific valid values and explicitly save to the isolated test path
	Globals.settings.max_fuel = 150.0
	Globals.settings.current_fuel = 75.0
	Globals._save_settings(TEST_CONFIG_PATH)
	
	assert_true(FileAccess.file_exists(TEST_CONFIG_PATH), "Config file must be created on save.")
	
	# 2. Alter the memory state to guarantee we are actually reading from the disk
	Globals.settings.max_fuel = 100.0
	Globals.settings.current_fuel = 100.0
	
	# 3. Load the settings back from the test file
	Globals._load_settings(TEST_CONFIG_PATH)
	
	# 4. Assert the values were successfully restored
	assert_eq(Globals.settings.max_fuel, 150.0, "max_fuel should restore correctly from the config file.")
	assert_eq(Globals.settings.current_fuel, 75.0, "current_fuel should restore correctly from the config file.")


## test_persistence_invalid_types_fallback | Config Save/Load | Verify corrupted types fall back safely
## :rtype: void
func test_persistence_invalid_types_fallback() -> void:
	gut.p("Testing: Loading invalid data types falls back to defaults safely without crashing.")
	
	# 1. Manually create a corrupted config file with invalid data types
	var config: ConfigFile = ConfigFile.new()
	config.set_value("Settings", "max_fuel", "invalid_string_data") # Should be float/int
	config.set_value("Settings", "current_fuel", [1, 2, 3])         # Should be float/int
	config.save(TEST_CONFIG_PATH)
	
	# 2. Establish known safe baseline defaults in memory
	Globals.settings.max_fuel = 100.0
	Globals.settings.current_fuel = 100.0
	
	# 3. Attempt to load the corrupted file
	Globals._load_settings(TEST_CONFIG_PATH)
	
	# 4. Assert that the invalid types were rejected and memory remained intact
	assert_eq(Globals.settings.max_fuel, 100.0, "max_fuel must reject string values and retain the safe memory default.")
	assert_eq(Globals.settings.current_fuel, 100.0, "current_fuel must reject array values and retain the safe memory default.")


## test_persistence_missing_keys_fallback | Config Save/Load | Verify missing keys do not overwrite memory
## :rtype: void
func test_persistence_missing_keys_fallback() -> void:
	gut.p("Testing: Missing config keys fall back to resource defaults.")
	
	# 1. Create a valid config file that completely omits the fuel settings
	var config: ConfigFile = ConfigFile.new()
	config.set_value("Settings", "difficulty", 2.0) # Include a valid unrelated key
	config.save(TEST_CONFIG_PATH)
	
	# 2. Establish a known memory state for the fuel system
	Globals.settings.max_fuel = 120.0
	Globals.settings.current_fuel = 60.0
	Globals.settings.difficulty = 1.0
	
	# 3. Load the incomplete config file
	Globals._load_settings(TEST_CONFIG_PATH)
	
	# 4. Assert that missing keys did not wipe out the current memory state, but present keys loaded
	assert_eq(Globals.settings.max_fuel, 120.0, "max_fuel should retain memory default if missing in config file.")
	assert_eq(Globals.settings.current_fuel, 60.0, "current_fuel should retain memory default if missing in config file.")
	assert_eq(Globals.settings.difficulty, 2.0, "Present keys (difficulty) should still load successfully.")


## test_ui_updates_on_fuel_change_signal | Integration | Verify UI elements react to global signals
## :rtype: void
func test_ui_updates_on_fuel_change_signal() -> void:
	gut.p("Testing: UI ProgressBar updates reactively via setting_changed signal.")
	
	# 1. Create a mock UI ProgressBar and safely queue it for deletion to prevent orphans
	var progress_bar: ProgressBar = ProgressBar.new()
	add_child_autoqfree(progress_bar)
	
	# 2. Define a local lambda to act as the Observer pattern UI handler
	var _on_setting_changed := func(setting_name: String, new_value: Variant) -> void:
		# NEW: Add a safety check to ensure the lambda doesn't try to access a freed node
		if is_instance_valid(progress_bar):
			if setting_name == "current_fuel":
				progress_bar.value = new_value
			elif setting_name == "max_fuel":
				progress_bar.max_value = new_value
			
	# 3. Connect the signal
	Globals.settings.setting_changed.connect(_on_setting_changed)
	
	# 4. Mutate the global resource, which should implicitly fire the signals
	Globals.settings.max_fuel = 200.0
	Globals.settings.current_fuel = 150.0
	
	# 5. Assert the UI element automatically synchronized with the backend data
	assert_eq(progress_bar.max_value, 200.0, "ProgressBar max_value should react automatically to the max_fuel signal.")
	assert_eq(progress_bar.value, 150.0, "ProgressBar value should react automatically to the current_fuel signal.")

	# NEW: Explicitly disconnect the signal at the end of the test.
	# This prevents the lambda from becoming a "ghost" listener that crashes subsequent tests.
	if Globals.settings.setting_changed.is_connected(_on_setting_changed):
		Globals.settings.setting_changed.disconnect(_on_setting_changed)
