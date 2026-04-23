## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_gameplay_settings_ui.gd
##
## GUT unit tests for GameplaySettings UI interactions and Observer reactivity.
## Covers GS-UI-01 to GS-UI-06 and GS-OBS-01 to GS-OBS-05.

extends "res://addons/gut/test.gd"

const GameplaySettings = preload(GamePaths.GAMEPLAY_SETTINGS)
var gameplay_menu: Control
var _resource: GameSettingsResource

func before_each() -> void:
	# Ensure a fresh resource for every test to isolate state
	_resource = GameSettingsResource.new()
	Globals.settings = _resource
	
	gameplay_menu = load(GamePaths.GAMEPLAY_SETTINGS_SCENE).instantiate()
	# Inject mock wrapper to bypass real web/OS calls
	gameplay_menu.os_wrapper = OSWrapper.new() 
	
	add_child_autofree(gameplay_menu)
	await get_tree().process_frame


# --- SECTION 4: LOCAL UI INTERACTION TESTS (GS-UI) ---

## GS-UI-01/03 | User changes slider updates resource and label
func test_gs_ui_01_03_slider_updates_resource_and_label() -> void:
	var test_val: float = 1.5
	# Simulate user sliding the control
	gameplay_menu.difficulty_slider.value = test_val
	gameplay_menu._on_difficulty_value_changed(test_val) 
	
	assert_eq(_resource.difficulty, test_val, "Resource should update from slider input")
	assert_eq(gameplay_menu.difficulty_label.text, "{" + str(test_val) + "}", "Label should reflect new value")


## GS-UI-04/05 | Reset button returns to default state
func test_gs_ui_04_05_reset_functionality() -> void:
	# Pre-condition: Set to non-default
	gameplay_menu.difficulty_slider.value = 2.0
	gameplay_menu._on_gameplay_reset_button_pressed()
	
	assert_eq(_resource.difficulty, 1.0, "Resource should reset to 1.0")
	assert_eq(gameplay_menu.difficulty_slider.value, 1.0, "Slider UI should reset to 1.0")


## GS-UI-06 | Change propagation occurs exactly once
func test_gs_ui_06_no_duplicate_propagation() -> void:
	watch_signals(_resource)
	gameplay_menu._on_difficulty_value_changed(1.8)
	
	# Verify the resource was only updated once to prevent event loops
	assert_signal_emit_count(_resource, "setting_changed", 1, "Change should propagate exactly once")


# --- SECTION 5: EXTERNAL RESOURCE REACTIVITY TESTS (GS-OBS) ---

## GS-OBS-01/02/04 | UI tracks external resource changes (Observer Pattern)
func test_gs_obs_01_02_04_external_reactivity() -> void:
	var external_val: float = 1.3
	# Simulate external code changing the global resource
	_resource.setting_changed.emit("difficulty", external_val)
	
	assert_eq(gameplay_menu.difficulty_slider.value, external_val, "Slider must sync with external changes")
	assert_eq(gameplay_menu.difficulty_label.text, "{" + str(external_val) + "}", "Label must sync with external changes")


## GS-OBS-03 | set_value_no_signal prevents feedback loops
func test_gs_obs_03_no_recursion_on_external_update() -> void:
	watch_signals(gameplay_menu.difficulty_slider)
	# Trigger the observer
	_resource.setting_changed.emit("difficulty", 0.7)
	
	# Verify the slider updated without re-emitting its own value_changed signal
	assert_signal_emit_count(gameplay_menu.difficulty_slider, "value_changed", 0, "Observer must use set_value_no_signal to avoid loops")


## GS-OBS-05 | Observer filters unrelated keys
func test_gs_obs_05_filters_unrelated_settings() -> void:
	var initial_val: float = gameplay_menu.difficulty_slider.value
	# Emit a signal for a different setting
	_resource.setting_changed.emit("sfx_volume", 0.1)
	
	assert_eq(gameplay_menu.difficulty_slider.value, initial_val, "Difficulty UI should ignore unrelated setting signals")
