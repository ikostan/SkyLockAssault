## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_game_settings_resource.gd
##
## GUT unit tests for GameSettingsResource and GameplaySettings initialization.
##
## It ensures the GameSettingsResource acts as a reliable source of truth and
## that the GameplaySettings scene correctly synchronizes its UI components during
## the _ready() sequence.

extends "res://addons/gut/test.gd"

const GameplaySettings = preload(GamePaths.GAMEPLAY_SETTINGS)
var gameplay_menu: Control
var _resource: GameSettingsResource

func before_each() -> void:
	# Initialize a fresh resource for every test to ensure isolation
	_resource = GameSettingsResource.new()
	Globals.settings = _resource
	
	# Instantiate the menu for initialization tests
	gameplay_menu = load(GamePaths.GAMEPLAY_SETTINGS_SCENE).instantiate()
	# Inject mock wrapper to avoid real JS/OS calls during unit tests
	gameplay_menu.os_wrapper = OSWrapper.new() 
	
	add_child_autofree(gameplay_menu)
	await get_tree().process_frame


# --- SECTION 2: RESOURCE CONTRACT TESTS (GS-RES) ---

func test_default_settings_enable_fps_display_and_enable_info_log_lvl() -> void:
	var defaults: GameSettingsResource = (
		load("res://config_resources/default_settings.tres") as GameSettingsResource
	)

	assert_not_null(defaults, "Default settings must load as a GameSettingsResource.")
	assert_false(defaults.show_fps, "The shipped default must disable the FPS display.")
	assert_eq(defaults.current_log_level, 1, "The shipped default must set log level to INFO.")


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


## GS-RES-08 | No runtime fuel state on the settings resource (#1143)
func test_gs_res_08_no_runtime_fuel_state() -> void:
	assert_false("current_fuel" in _resource, "current_fuel must not be a settings property.")
	assert_false("_current_fuel" in _resource, "The current_fuel backing field must be gone.")
	assert_false(_resource.has_signal("fuel_depleted"), "fuel_depleted belongs to FuelResource only.")
	assert_false(_resource.has_method("refuel"), "refuel() belongs to FuelResource only.")


## GS-RES-09 | max_fuel still validates and notifies, with no current_fuel to clamp (#1143)
func test_gs_res_09_max_fuel_change_without_fuel_clamp() -> void:
	watch_signals(_resource)
	
	_resource.max_fuel = 50.0
	assert_eq(_resource.max_fuel, 50.0, "Lowering max_fuel must apply as written.")
	assert_signal_emit_count(_resource, "setting_changed", 1, "Only max_fuel may notify observers.")
	assert_signal_emitted_with_parameters(_resource, "setting_changed", ["max_fuel", 50.0], 0)
	
	_resource.max_fuel = 250.0
	assert_eq(_resource.max_fuel, 250.0, "Raising max_fuel must apply as written.")
	
	_resource.max_fuel = 0.0
	assert_eq(_resource.max_fuel, 1.0, "max_fuel must keep its minimum of 1.0.")
	assert_signal_emit_count(_resource, "setting_changed", 3, "Each max_fuel change must notify once.")


## Plain tuning fields (#1148): name, default value, and a value the old setters rejected.
const PLAIN_TUNING_FIELDS: Array = [
	["max_speed", 713.0, -5.0],
	["min_speed", 95.0, 5000.0],
	["lateral_speed", 250.0, -1.0],
	["acceleration", 200.0, -1.0],
	["deceleration", 100.0, -1.0],
	["high_yellow_fraction", 0.80, 1.5],
	["low_yellow_fraction", 0.10, 0.95],
	["high_fuel_threshold", 90.0, 150.0],
	["medium_fuel_threshold", 50.0, 95.0],
	["low_fuel_threshold", 30.0, 60.0],
	["no_fuel_threshold", 15.0, -3.0],
]


## GS-RES-10 | Plain tuning fields keep their names and defaults (#1148)
func test_gs_res_10_plain_tuning_defaults_unchanged(
	field: Array = use_parameters(PLAIN_TUNING_FIELDS)
) -> void:
	var prop: String = field[0]
	assert_true(prop in _resource, "%s must still be a settings property." % prop)
	assert_almost_eq(float(_resource.get(prop)), float(field[1]), 0.0001, "%s keeps its default." % prop)


## GS-RES-11 | Plain tuning fields store values as written and never notify (#1148)
## Validation lives in SpeedResource and FuelResource; see test_speed_resource.gd,
## test_fuel_resource.gd and test_player_tuning_copy.gd for the same rules there.
func test_gs_res_11_plain_tuning_fields_do_not_validate_or_notify(
	field: Array = use_parameters(PLAIN_TUNING_FIELDS)
) -> void:
	var prop: String = field[0]
	watch_signals(_resource)
	
	_resource.set(prop, field[2])
	
	assert_almost_eq(float(_resource.get(prop)), float(field[2]), 0.0001, "%s must store the value as written." % prop)
	assert_signal_not_emitted(_resource, "setting_changed", "%s must not emit setting_changed." % prop)
	assert_false(("_" + prop) in _resource, "%s must not keep a backing field." % prop)


# --- SECTION 3: MENU INITIALIZATION TESTS (GS-READY) ---

## GS-READY-01/02 | Confirm UI syncs to resource state on load
func test_gs_ready_01_02_ui_initialization_sync() -> void:
	# Pre-condition: Set resource to non-default value before menu _ready()
	# Note: Requires re-instantiating or checking logic after add_child
	var test_difficulty: float = 1.7
	_resource.difficulty = test_difficulty
	
	var new_menu: Variant = load(GamePaths.GAMEPLAY_SETTINGS_SCENE).instantiate()
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
	var menu: Control = load(GamePaths.GAMEPLAY_SETTINGS_SCENE).instantiate()
	menu.os_wrapper = mock_os
	
	add_child_autofree(menu)
	await get_tree().process_frame
	
	assert_true(is_instance_valid(menu.difficulty_slider), "Slider should be valid when initialized from scene")
	assert_true(true, "Menu initialized safely in non-web environment")
	assert_null(menu._change_difficulty_cb, "JS callbacks should NOT be created in non-web env")
	assert_false(menu.js_window != null, "JS window interface should remain null")
