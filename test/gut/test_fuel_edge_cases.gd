## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_fuel_edge_cases.gd
## GUT unit tests for the Fuel System edge cases.
##
## Covers signal emission constraints and disk persistence logic.

extends GutTest

const TEST_CONFIG_PATH: String = "user://test_fuel_edge_cases.cfg"

## Per-test setup: Isolate the filesystem and ensure a clean memory state.
## :rtype: void
var original_settings: GameSettingsResource

func before_each() -> void:
	original_settings = Globals.settings
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)
	
	# Stub log_message to keep the test output console clean
	stub(Globals, 'log_message').to_do_nothing()
	
	# Reset global settings to a fresh instance to prevent state leakage
	Globals.settings = GameSettingsResource.new()


## Per-test cleanup: Remove temporary configuration files.
## :rtype: void
func after_each() -> void:
	Globals.settings = original_settings
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)


## test_fuel_depleted_signal_fires_once | Signal Constraints | Verify fuel_depleted does not spam | Single emission
## :rtype: void
func test_fuel_depleted_signal_fires_once() -> void:
	gut.p("Testing: 'fuel_depleted' signal must emit exactly once when reaching zero.")
	
	watch_signals(Globals.settings)
	
	# 1. Start with a positive amount
	Globals.settings.current_fuel = 10.0
	
	# 2. Drain to exactly zero (this should trigger the first and only emission)
	Globals.settings.current_fuel = 0.0
	
	assert_signal_emitted(Globals.settings, "fuel_depleted", "Signal should fire when transitioning to zero.")
	
	# 3. Simulate continued consumption attempts while already empty 
	# The setter should clamp this and prevent further signal emissions
	Globals.settings.current_fuel -= 5.0
	Globals.settings.current_fuel -= 5.0
	
	assert_signal_emit_count(Globals.settings, "fuel_depleted", 1, "Signal must not spam when fuel is already depleted.")


## test_fuel_persistence | Config Save/Load | Verify current_fuel is saved and restored | Value matches after load
## :rtype: void
func test_fuel_persistence() -> void:
	gut.p("Testing: Fuel level is correctly saved to and loaded from disk.")
	
	# 1. Set a distinct fuel value and explicitly save to the isolated test path
	var target_fuel: float = 45.0
	Globals.settings.current_fuel = target_fuel
	Globals._save_settings(TEST_CONFIG_PATH)
	
	assert_true(FileAccess.file_exists(TEST_CONFIG_PATH), "Config file must be created on save.")
	
	# 2. Corrupt the memory state to guarantee we are actually reading from disk
	Globals.settings.current_fuel = 100.0
	
	# 3. Load the settings back from the test file
	Globals._load_settings(TEST_CONFIG_PATH)
	
	# 4. Assert the value was successfully restored
	assert_eq(Globals.settings.current_fuel, target_fuel, "current_fuel must accurately restore from the config file.")
