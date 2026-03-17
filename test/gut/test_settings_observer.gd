## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_settings_observer.gd
##
## TEST SUITE: Verifies the Observer Pattern implementation for game settings.
## This suite ensures that UI-driven changes to GameSettingsResource correctly 
## emit signals and that Globals.gd reacts by persisting data, thereby 
## decoupling UI logic from the persistence layer.
extends GutTest

var _resource: GameSettingsResource
var _test_config_path: String = "user://test_settings.cfg"


func before_each() -> void:
	_resource = GameSettingsResource.new()
	# Ensure the Singleton uses our local test resource to avoid 
	# cross-test contamination and production file overwrites.
	Globals.settings = _resource 
	
	if FileAccess.file_exists(_test_config_path):
		DirAccess.remove_absolute(_test_config_path)


## PHASE 1: Signal Integrity (The "Subject")
func test_resource_emits_signal_on_difficulty_change() -> void:
	watch_signals(_resource)
	_resource.difficulty = 1.5
	
	assert_signal_emitted(_resource, "setting_changed", "Signal should fire when difficulty is set.")
	assert_signal_emitted_with_parameters(_resource, "setting_changed", ["difficulty", 1.5], 0)


func test_resource_emits_signal_on_log_level_change() -> void:
	watch_signals(_resource)
	_resource.current_log_level = Globals.LogLevel.DEBUG
	
	assert_signal_emitted(_resource, "setting_changed", "Signal should fire when log level is set.")
	assert_signal_emitted_with_parameters(_resource, "setting_changed", ["current_log_level", Globals.LogLevel.DEBUG], 0)


## PHASE 2: Data Validation & Clamping
func test_difficulty_clamping_emits_correct_value() -> void:
	watch_signals(_resource)
	# Difficulty is clamped between 0.5 and 2.0
	_resource.difficulty = 5.0 
	
	# Fix: Use exactly 4 arguments. 
	# Parameters are: (object, signal_name, expected_params, emission_index)
	assert_signal_emitted_with_parameters(_resource, "setting_changed", ["difficulty", 2.0], 0)


## PHASE 3: Persistence (The "Observer")
func test_globals_saves_to_disk_on_signal() -> void:
	# Use the test-specific path consistently
	_resource.setting_changed.connect(
		func(key: String, val: Variant) -> void: 
			Globals._save_settings(_test_config_path)
	)
	
	# Force reset state before changing
	_resource.difficulty = 0.85
	
	var config := ConfigFile.new()
	var err := config.load(_test_config_path)
	assert_eq(err, OK, "Config file should be created.")
	assert_eq(config.get_value("Settings", "difficulty"), 0.85)


## PHASE 3.1: Verify Globals connection (The "Observer")
func test_globals_saves_when_resource_changes() -> void:
	# Manually connect the observer logic to the test resource
	# This bypasses the _ready() logic that would overwrite our test setup
	_resource.setting_changed.connect(
		func(_k: String, _v: Variant) -> void: 
			Globals._save_settings(_test_config_path)
	)
	
	# Trigger the change
	_resource.difficulty = 0.8
	
	# Verify persistence to the test config path
	var config := ConfigFile.new()
	var err := config.load(_test_config_path)
	assert_eq(err, OK, "Config file should be created by the observer.")
	assert_eq(config.get_value("Settings", "difficulty"), 0.8, "Value on disk should be updated.")


## PHASE 3.2: Persistence Verification
func test_difficulty_persists_to_config_file() -> void:
	# We must intercept the signal to force the TEST path, 
	# otherwise Globals uses the production path by default.
	_resource.setting_changed.connect(
		func(_k: String, _v: Variant) -> void: 
			Globals._save_settings(_test_config_path)
	)
	
	_resource.difficulty = 0.75 
	
	var config := ConfigFile.new()
	var err := config.load(_test_config_path)
	assert_eq(err, OK, "Config file should exist after change.")
	assert_eq(config.get_value("Settings", "difficulty"), 0.75)


## PHASE 4: UI Synchronization (Mocking the UI Layer)
func test_ui_logic_can_update_resource_without_globals_call() -> void:
	# This simulates what advanced_settings.gd or gameplay_settings.gd will do [cite: 14, 33]
	# The goal is to verify that setting the value is the ONLY thing the UI needs to do.
	_resource.difficulty = 1.2
	assert_eq(_resource.difficulty, 1.2, "UI should successfully update the resource state.")


## PHASE 5: UI Reactivity
func test_ui_slider_syncs_with_resource() -> void:
	var gameplay_menu: Node = load("res://scenes/gameplay_settings.tscn").instantiate()
	add_child_autofree(gameplay_menu)
	
	Globals.settings.difficulty = 1.8 # Change resource directly
	assert_eq(gameplay_menu.difficulty_slider.value, 1.8, "UI Slider should update automatically.")


## PHASE 6: Debug Logging Persistence
func test_enable_debug_logging_emits_signal() -> void:
	watch_signals(_resource)
	_resource.enable_debug_logging = true
	
	assert_signal_emitted_with_parameters(_resource, "setting_changed", ["enable_debug_logging", true], 0)

func test_enable_debug_logging_persists_to_disk() -> void:
	# Connect signal to the test path for verification
	_resource.setting_changed.connect(
		func(_k: String, _v: Variant) -> void: 
			Globals._save_settings(_test_config_path)
	)
	
	# Act: Toggle the flag
	_resource.enable_debug_logging = true
	
	# Assert: Verify file contents
	var config := ConfigFile.new()
	var err := config.load(_test_config_path)
	assert_eq(err, OK, "Config file should be created for debug_logging change.")
	assert_eq(config.get_value("Settings", "enable_debug_logging"), true, "Flag should persist as true.")

func test_enable_debug_logging_restores_from_disk() -> void:
	# Setup: Manually create a config with the flag enabled
	var config := ConfigFile.new()
	config.set_value("Settings", "enable_debug_logging", true)
	config.save(_test_config_path)
	
	# Act: Load via Globals logic
	Globals._load_settings(_test_config_path)
	
	# Assert: Resource should now match the disk state
	assert_eq(_resource.enable_debug_logging, true, "Resource should reflect loaded debug flag.")
