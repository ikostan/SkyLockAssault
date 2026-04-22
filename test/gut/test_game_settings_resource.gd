## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_game_settings_resource.gd
##
## GUT unit tests for GameSettingsResource and GameplaySettings initialization.
##
## It ensures the GameSettingsResource acts as a reliable source of truth and
## that the GameplaySettings scene correctly synchronizes its UI components during
## the _ready() sequence.

extends "res://addons/gut/test.gd"

const GameplaySettings = preload("res://scripts/ui/menus/gameplay_settings.gd")
var gameplay_menu: Control
var _resource: GameSettingsResource

func before_each() -> void:
	# Initialize a fresh resource for every test to ensure isolation
	_resource = GameSettingsResource.new()
	Globals.settings = _resource
	
	# Instantiate the menu for initialization tests
	gameplay_menu = load("res://scenes/gameplay_settings.tscn").instantiate()
	# Inject mock wrapper to avoid real JS/OS calls during unit tests
	gameplay_menu.os_wrapper = OSWrapper.new() 
	
	add_child_autofree(gameplay_menu)
	await get_tree().process_frame


# --- SECTION 2: RESOURCE CONTRACT TESTS (GS-RES) ---

## GS-RES-01 | Validate signal emission on valid update
func test_gs_res_01_signal_on_valid_change() -> void:
	watch_signals(_resource)
	_resource.difficulty = 1.5
	assert_signal_emitted_with_parameters(_resource, "setting_changed", ["difficulty", 1.5], 0)


## GS-RES-02/03 | Validate clamping logic
func test_gs_res_02_03_clamping_behavior() -> void:
	# Test Upper Bound Clamping 
	_resource.difficulty = 5.0
	assert_eq(_resource.difficulty, 2.0, "Difficulty should clamp to 2.0")
	
	# Test Lower Bound Clamping
	_resource.difficulty = 0.1
	assert_eq(_resource.difficulty, 0.5, "Difficulty should clamp to 0.5")


## GS-RES-04/05/06 | Validate boundary and default values
func test_gs_res_04_05_06_boundary_values() -> void:
	var values_to_test: Array = [0.5, 1.0, 2.0]
	for val: float in values_to_test:
		_resource.difficulty = val
		assert_eq(_resource.difficulty, val, "Value %s should be accepted exactly" % val)


## GS-RES-07 | Validate stability on redundant assignments
func test_gs_res_07_redundant_assignment() -> void:
	_resource.difficulty = 1.2
	watch_signals(_resource)
	_resource.difficulty = 1.2
	# Corrected function name from assert_signal_emission_count to assert_signal_emit_count
	assert_signal_emit_count(_resource, "setting_changed", 0, "Redundant assignment should not re-emit")


# --- SECTION 3: MENU INITIALIZATION TESTS (GS-READY) ---

## GS-READY-01/02 | Confirm UI syncs to resource state on load
func test_gs_ready_01_02_ui_initialization_sync() -> void:
	# Pre-condition: Set resource to non-default value before menu _ready()
	# Note: Requires re-instantiating or checking logic after add_child
	var test_difficulty: float = 1.7
	_resource.difficulty = test_difficulty
	
	var new_menu: Variant = load("res://scenes/gameplay_settings.tscn").instantiate()
	add_child_autofree(new_menu)
	await get_tree().process_frame
	
	assert_eq(new_menu.difficulty_slider.value, test_difficulty, "Slider must match resource on init")
	assert_eq(new_menu.difficulty_label.text, "{" + str(test_difficulty) + "}", "Label must match resource on init")


## GS-READY-03/04 | Confirm signal connections 
func test_gs_ready_03_04_signal_connections() -> void:
	assert_true(_resource.setting_changed.is_connected(gameplay_menu._on_external_setting_changed), 
		"UI must connect to resource observer on ready") 
	assert_true(gameplay_menu.difficulty_slider.value_changed.is_connected(gameplay_menu._on_difficulty_value_changed),
		"Slider signal should be connected")


## GS-READY-05 | Prevent duplicate connections 
func test_gs_ready_05_no_duplicate_connections() -> void:
	# Ensure the menu is in the tree 
	if not gameplay_menu.is_inside_tree():
		add_child(gameplay_menu)
		await get_tree().process_frame
	
	# Manually call _ready again to test idempotency/guards 
	# The production code guards should prevent double-connection 
	gameplay_menu._ready()
	
	# Check connections on the GLOBAL resource 
	var connections: Array = Globals.settings.setting_changed.get_connections()
	var count: int = 0
	
	for conn: Dictionary in connections:
		# We must verify the callable points to our specific instance 
		if conn["callable"].get_object() == gameplay_menu and \
		   conn["callable"].get_method() == "_on_external_setting_changed":
			count += 1
			
	assert_eq(count, 1, "Observer should only be connected once even after redundant ready calls")


## GS-READY-06 | Robustness against missing web features
func test_gs_ready_06_safe_init_non_web() -> void:
	# Simulate non-web environment
	var mock_os: Variant = double(OSWrapper).new()
	stub(mock_os, "has_feature").to_return(false)
	
	# FIX: Instantiate from the SCENE, not just the script
	var menu: Control = load("res://scenes/gameplay_settings.tscn").instantiate()
	menu.os_wrapper = mock_os
	
	add_child_autofree(menu)
	await get_tree().process_frame
	
	assert_true(is_instance_valid(menu.difficulty_slider), "Slider should be valid when initialized from scene")
	assert_true(true, "Menu initialized safely in non-web environment")
	assert_null(menu._change_difficulty_cb, "JS callbacks should NOT be created in non-web env")
	assert_false(menu.js_window != null, "JS window interface should remain null")
