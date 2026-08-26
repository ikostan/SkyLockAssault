## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_gdunit_game_settings_resource.gd
##
## GdUnit4 unit tests for GameSettingsResource and GameplaySettings initialization.
##
## Ensures GameSettingsResource acts as a reliable source of truth and
## that the GameplaySettings scene correctly synchronizes its UI components during
## the _ready() sequence.

extends GdUnitTestSuite

const GameplaySettings = preload(GamePaths.GAMEPLAY_SETTINGS)

var gameplay_menu: Control
var _resource: GameSettingsResource
var _original_settings: GameSettingsResource


func before_test() -> void:
	# Snapshot and isolate global settings for each test run
	_original_settings = Globals.settings
	_resource = GameSettingsResource.new()
	Globals.settings = _resource

	# Instantiate the menu for initialization tests
	gameplay_menu = auto_free(load(GamePaths.GAMEPLAY_SETTINGS_SCENE).instantiate())
	# Inject default wrapper to avoid real JS/OS calls during unit tests
	gameplay_menu.os_wrapper = OSWrapper.new()

	add_child(gameplay_menu)
	await await_idle_frame()


func after_test() -> void:
	if is_instance_valid(gameplay_menu):
		gameplay_menu.queue_free()
	Globals.settings = _original_settings
	_resource = null


# --- SECTION 1: RESOURCE CONTRACT TESTS (GS-RES) ---

## GS-RES-01 | Validate signal emission on valid update
func test_gs_res_01_signal_on_valid_change() -> void:
	_resource.difficulty = 1.5
	await assert_signal(_resource).is_emitted("setting_changed", ["difficulty", 1.5])


## GS-RES-02/03 | Validate clamping logic
func test_gs_res_02_03_clamping_behavior() -> void:
	# Test Upper Bound Clamping
	_resource.difficulty = 5.0
	assert_float(_resource.difficulty).is_equal(2.0)

	# Test Lower Bound Clamping
	_resource.difficulty = 0.1
	assert_float(_resource.difficulty).is_equal(0.5)


## GS-RES-04/05/06 | Validate boundary and default values
func test_gs_res_04_05_06_boundary_values() -> void:
	var values_to_test: Array[float] = [0.5, 1.0, 2.0]
	for val: float in values_to_test:
		_resource.difficulty = val
		assert_float(_resource.difficulty).is_equal(val)


## GS-RES-07 | Validate stability on redundant assignments
func test_gs_res_07_redundant_assignment() -> void:
	var res: GameSettingsResource = GameSettingsResource.new()
	res.difficulty = 1.2
	# Assigning the exact same value must not re-emit the signal
	var redundant_res: GameSettingsResource = GameSettingsResource.new()
	redundant_res.difficulty = redundant_res.difficulty
	await assert_signal(redundant_res).is_not_emitted("setting_changed")


# --- SECTION 2: MENU INITIALIZATION TESTS (GS-READY) ---

## GS-READY-01/02 | Confirm UI syncs to resource state on load
func test_gs_ready_01_02_ui_initialization_sync() -> void:
	var test_difficulty: float = 1.7
	_resource.difficulty = test_difficulty

	var new_menu: Control = auto_free(load(GamePaths.GAMEPLAY_SETTINGS_SCENE).instantiate())
	new_menu.os_wrapper = OSWrapper.new()
	add_child(new_menu)
	await await_idle_frame()

	assert_float(new_menu.difficulty_slider.value).is_equal(test_difficulty)
	assert_str(new_menu.difficulty_label.text).is_equal("{" + str(test_difficulty) + "}")


## GS-READY-03/04 | Confirm signal connections
func test_gs_ready_03_04_signal_connections() -> void:
	assert_bool(_resource.setting_changed.is_connected(gameplay_menu._on_external_setting_changed)).is_true()
	assert_bool(gameplay_menu.difficulty_slider.value_changed.is_connected(gameplay_menu._on_difficulty_value_changed)).is_true()


## GS-READY-05 | Prevent duplicate connections
func test_gs_ready_05_no_duplicate_connections() -> void:
	if not gameplay_menu.is_inside_tree():
		add_child(gameplay_menu)
		await await_idle_frame()

	# Manually call _ready again to test idempotency/guards
	gameplay_menu._ready()

	# Verify connection count on global resource
	var connections: Array[Dictionary] = Globals.settings.setting_changed.get_connections()
	var count: int = 0

	for conn: Dictionary in connections:
		if conn["callable"].get_object() == gameplay_menu and \
		   conn["callable"].get_method() == "_on_external_setting_changed":
			count += 1

	assert_int(count).is_equal(1)


## GS-READY-06 | Robustness against missing web features
func test_gs_ready_06_safe_init_non_web() -> void:
	# Simulate non-web environment using gdUnit4 mock
	var mock_os: OSWrapper = mock(OSWrapper)
	do_return(false).on(mock_os).has_feature(any_string())

	var menu: Control = auto_free(load(GamePaths.GAMEPLAY_SETTINGS_SCENE).instantiate())
	menu.os_wrapper = mock_os

	add_child(menu)
	await await_idle_frame()

	assert_bool(is_instance_valid(menu.difficulty_slider)).is_true()
	assert_object(menu._change_difficulty_cb).is_null()
	assert_bool(menu.js_window == null).is_true()
