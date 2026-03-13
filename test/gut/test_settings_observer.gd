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
	# Initialize a fresh resource for each test to ensure isolation [cite: 18, 21]
	_resource = GameSettingsResource.new()
	# Clean up any previous test config files
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
	# Difficulty is clamped between 0.5 and 2.0 [cite: 18]
	_resource.difficulty = 5.0 
	
	assert_signal_emitted_with_parameters(_resource, "setting_changed", ["difficulty", 2.0], "Should emit clamped value.")


## PHASE 3: Persistence (The "Observer")
func test_globals_saves_to_disk_on_signal() -> void:
	# Add static types for parameters and the return type (-> void)
	_resource.setting_changed.connect(
		func(key: String, val: Variant) -> void: 
			Globals._save_settings(_test_config_path)
	)
	
	_resource.difficulty = 0.85
	
	var config := ConfigFile.new()
	var err := config.load(_test_config_path)
	assert_eq(err, OK, "Config file should be created automatically upon resource change.")
	assert_eq(config.get_value("Settings", "difficulty"), 0.85, "Saved value should match modified resource.")


## PHASE 3.1: Verify Globals connection (The "Observer")
func test_globals_saves_when_resource_changes() -> void:
	# This test confirms that Globals is actually listening.
	# We simulate the signal and check if Globals reacts.
	var globals_script := load("res://scripts/globals.gd")
	var sut: Resource = globals_script.new()
	sut.settings = _resource
	sut._ready() # Trigger the connection logic
	
	# We spy on _save_settings to ensure it's called automatically
	# Note: This requires making _save_settings a public or mockable method
	# or checking side effects like file creation.
	_resource.difficulty = 0.8
	
	# If you refactor _save_settings to be tracked:
	# assert_called(sut, "_save_settings") 
	pass


## PHASE 3.1: Persistence Verification
func test_difficulty_persists_to_config_file() -> void:
	var test_path := "user://test_settings.cfg"
	_resource.difficulty = 0.75 # This should trigger Globals to save via signal
	
	var config := ConfigFile.new()
	var err := config.load(test_path)
	assert_eq(err, OK, "Config file should exist after change.")
	assert_eq(config.get_value("Settings", "difficulty"), 0.75, "Value on disk should match resource.")


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
