## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_pause_menu.gd
##
## GdUnit4 automated unit test suite for pause_menu.gd.
## Validates button signal bindings, pause state toggles, input event handlers,
## and callback execution across all menu actions.

extends GdUnitTestSuite

const PAUSE_MENU_PATH: String = "res://scenes/pause_menu.tscn"

var _orig_globals_script: Script
var _original_next_scene: String


## Test-only mock to prevent get_tree().change_scene_to_file from evicting the GdUnit runner.
class MockGlobals extends "res://scripts/core/globals.gd":
	func _init() -> void:
		settings = load("res://config_resources/default_settings.tres") as GameSettingsResource

	func load_scene_with_loading(target_path: String) -> void:
		next_scene = target_path


func before_test() -> void:
	_orig_globals_script = Globals.get_script()
	_original_next_scene = Globals.next_scene
	Globals.set_script(MockGlobals)


func after_test() -> void:
	Globals.next_scene = _original_next_scene
	if _orig_globals_script:
		Globals.set_script(_orig_globals_script)
		Globals.settings = load("res://config_resources/default_settings.tres") as GameSettingsResource
	if is_instance_valid(Globals.options_instance):
		Globals.options_instance.queue_free()
		Globals.options_instance = null
	Globals.options_open = false
	Globals.hidden_menus.clear()
	get_tree().paused = false


func _create_pause_menu() -> CanvasLayer:
	var scene: PackedScene = load(PAUSE_MENU_PATH) as PackedScene
	var menu: CanvasLayer = auto_free(scene.instantiate()) as CanvasLayer
	return menu


## PM-01 | Test initialization and signal wiring on _ready.
func test_pm_01_ready_initialization() -> void:
	var menu: CanvasLayer = _create_pause_menu()
	add_child(menu)
	await await_idle_frame()

	assert_int(menu.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)
	assert_bool(menu.visible).is_false()
	assert_bool(menu.resume_button.pressed.is_connected(menu._on_resume_button_pressed)).is_true()
	assert_bool(menu.back_to_main_button.pressed.is_connected(menu._on_back_to_main_button_pressed)).is_true()
	assert_bool(menu.options_button.pressed.is_connected(menu._on_options_button_pressed)).is_true()


## PM-02 | Test toggle_pause toggles visibility and tree pause state.
func test_pm_02_toggle_pause() -> void:
	var menu: CanvasLayer = _create_pause_menu()
	add_child(menu)
	await await_idle_frame()

	# Initial state
	assert_bool(menu.visible).is_false()
	assert_bool(get_tree().paused).is_false()

	# Toggle ON
	menu.toggle_pause()
	assert_bool(menu.visible).is_true()
	assert_bool(get_tree().paused).is_true()

	# Toggle OFF
	menu.toggle_pause()
	assert_bool(menu.visible).is_false()
	assert_bool(get_tree().paused).is_false()


## PM-03 | Test _on_js_toggle_pause callback execution.
func test_pm_03_js_toggle_pause_callback() -> void:
	var menu: CanvasLayer = _create_pause_menu()
	add_child(menu)
	await await_idle_frame()

	menu._on_js_toggle_pause([])
	assert_bool(menu.visible).is_true()
	assert_bool(get_tree().paused).is_true()

	menu._on_js_toggle_pause([])
	assert_bool(menu.visible).is_false()
	assert_bool(get_tree().paused).is_false()


## PM-04 | Test resume button press handler and signal trigger.
func test_pm_04_resume_button_pressed() -> void:
	var menu: CanvasLayer = _create_pause_menu()
	add_child(menu)
	await await_idle_frame()

	# Put menu in paused state first
	menu.toggle_pause()
	assert_bool(menu.visible).is_true()
	assert_bool(get_tree().paused).is_true()

	# Trigger via button signal
	menu.resume_button.pressed.emit()
	assert_bool(menu.visible).is_false()
	assert_bool(get_tree().paused).is_false()

	# Trigger directly with arguments
	menu.toggle_pause()
	menu._on_resume_button_pressed(["dummy_arg"])
	assert_bool(menu.visible).is_false()
	assert_bool(get_tree().paused).is_false()


## PM-05 | Test back to main menu button press handler.
func test_pm_05_back_to_main_button_pressed() -> void:
	var menu: CanvasLayer = _create_pause_menu()
	add_child(menu)
	await await_idle_frame()

	menu.toggle_pause()
	assert_bool(get_tree().paused).is_true()

	menu._on_back_to_main_button_pressed([])
	assert_bool(get_tree().paused).is_false()
	assert_bool(menu.visible).is_false()
	assert_str(Globals.next_scene).is_equal("res://scenes/main_menu.tscn")


## PM-06 | Test options button press handler.
func test_pm_06_options_button_pressed() -> void:
	var menu: CanvasLayer = _create_pause_menu()
	add_child(menu)
	await await_idle_frame()

	menu._on_options_button_pressed([])
	assert_bool(Globals.options_open).is_true()


## PM-07 | Test unhandled input and mouse click debug handler.
func test_pm_07_input_events() -> void:
	var menu: CanvasLayer = _create_pause_menu()
	add_child(menu)
	await await_idle_frame()

	# Mouse click input
	var mouse_event := InputEventMouseButton.new()
	mouse_event.button_index = MOUSE_BUTTON_LEFT
	mouse_event.pressed = true
	mouse_event.position = Vector2(100, 200)
	menu._input(mouse_event)

	# Non-matching mouse input (ignored)
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	menu._input(right_click)

	# Pause action when options are open (early return guard)
	Globals.options_open = true
	menu.visible = false
	var pause_event := InputEventAction.new()
	pause_event.action = "pause"
	pause_event.pressed = true
	menu._unhandled_input(pause_event)
	assert_bool(menu.visible).is_false()

	# Pause action when options are closed (toggles pause)
	Globals.options_open = false
	menu._unhandled_input(pause_event)
	assert_bool(menu.visible).is_true()
