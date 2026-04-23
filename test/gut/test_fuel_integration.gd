## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_fuel_integration_gut.gd
## GUT integration tests for Fuel System signals and persistence.

extends "res://addons/gut/test.gd"

const TEST_CONFIG_PATH: String = "user://test_fuel_persistence.cfg"


## Per-test setup: Isolate filesystem and stub logging.
## :rtype: void
func before_each() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)
	stub(Globals, 'log_message').to_do_nothing()
	Globals.settings = GameSettingsResource.new()


## Per-test cleanup: Remove temp config.
## :rtype: void
func after_each() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)

# --- 1. Signal Tests (Observer Pattern) ---

## test_fuel_depletion_signal_emitted_once | Ensure signal fires exactly once
## :rtype: void
func test_fuel_depletion_signal_emitted_once() -> void:
	gut.p("Testing: Depletion signal fires once upon hitting 0.0.")
	watch_signals(Globals.settings)
	
	Globals.settings.current_fuel = 0.1
	Globals.settings.current_fuel = 0.0 # Deplete
	
	assert_signal_emitted(Globals.settings, "fuel_depleted", "Signal should fire at zero")
	
	# Simulate continued consumption attempt to check for signal spam
	Globals.settings.current_fuel = 0.0 
	assert_signal_emit_count(Globals.settings, "fuel_depleted", 1, "Signal should not fire twice")

# --- 2. Persistence Tests ---

## test_persistence_invalid_types_fallback | Ensure robustness against invalid data
## :rtype: void
func test_persistence_invalid_types_fallback() -> void:
	gut.p("Testing: System ignores non-float data in config.")
	var default_max: float = Globals.settings.max_fuel
	
	var config: ConfigFile = ConfigFile.new()
	config.set_value("Settings", "max_fuel", "corrupt_string_value")
	config.save(TEST_CONFIG_PATH)
	
	Globals._load_settings(TEST_CONFIG_PATH)
	assert_eq(Globals.settings.max_fuel, default_max, "System failed to fallback on invalid type")
