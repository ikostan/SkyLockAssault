## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_fuel_edge_cases.gd
## GUT unit tests for the Fuel System edge cases.
##
## Covers signal emission constraints.

extends GutTest

const TEST_CONFIG_PATH: String = "user://test_fuel_edge_cases.cfg"

var original_settings: GameSettingsResource

## Per-test setup: Isolate the filesystem and ensure a clean memory state.
## :rtype: void
func before_each() -> void:
	original_settings = Globals.settings
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)
	
	# Reset global settings to a fresh instance to prevent state leakage
	Globals.settings = GameSettingsResource.new()
	
	# NEW: Silence logs the correct way (without stubbing a real Singleton).
	# This prevents the "Instance of a Double was expected" error.
	Globals.settings.current_log_level = Globals.LogLevel.NONE


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

# NOTE: The test_fuel_persistence test was removed from this file. 
# current_fuel is volatile and no longer saved to disk. 
# Proper persistence testing for max_fuel is handled in test_fuel_persistence_integration.gd.
