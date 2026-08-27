## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_gdunit_all_menus_navigation_regression.gd
##
## GdUnit4 integration regression test suite targeting navigation audio execution
## across every scene menu layout in SkyLockAssault.

extends GdUnitTestSuite

const ADVANCED_SETTINGS_PATH: String = "res://scenes/advanced_settings.tscn"
const AUDIO_SETTINGS_PATH: String = "res://scenes/audio_settings.tscn"
const GAMEPLAY_SETTINGS_PATH: String = "res://scenes/gameplay_settings.tscn"
const KEY_MAPPING_PATH: String = "res://scenes/key_mapping_menu.tscn"
const MAIN_MENU_PATH: String = "res://scenes/main_menu.tscn"
const OPTIONS_MENU_PATH: String = "res://scenes/options_menu.tscn"
const PAUSE_MENU_PATH: String = "res://scenes/pause_menu.tscn"

var _original_options_open: bool


func before_test() -> void:
	_original_options_open = Globals.options_open
	Globals.options_open = true
	
	AudioManager.stop_all_sfx()
	if AudioManager.has_method("cleanup_for_test"):
		AudioManager.cleanup_for_test()


func after_test() -> void:
	Globals.options_open = _original_options_open
	get_tree().paused = false
	
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus_owner):
		focus_owner.release_focus()
		
	AudioManager.stop_all_sfx()


## Validates that advanced_settings.tscn triggers ui_navigation SFX on navigation input.
func test_advanced_settings_navigation_sfx() -> void:
	await _assert_menu_navigation_sfx_trigger(ADVANCED_SETTINGS_PATH)


## Validates that audio_settings.tscn triggers ui_navigation SFX on navigation input.
func test_audio_settings_navigation_sfx() -> void:
	await _assert_menu_navigation_sfx_trigger(AUDIO_SETTINGS_PATH)


## Validates that gameplay_settings.tscn triggers ui_navigation SFX on navigation input.
func test_gameplay_settings_navigation_sfx() -> void:
	await _assert_menu_navigation_sfx_trigger(GAMEPLAY_SETTINGS_PATH)


## Validates that key_mapping_menu.tscn triggers ui_navigation SFX on navigation input.
func test_key_mapping_menu_navigation_sfx() -> void:
	await _assert_menu_navigation_sfx_trigger(KEY_MAPPING_PATH)


## Validates that main_menu.tscn triggers ui_navigation SFX on navigation input.
func test_main_menu_navigation_sfx() -> void:
	await _assert_menu_navigation_sfx_trigger(MAIN_MENU_PATH)


## Validates that options_menu.tscn triggers ui_navigation SFX on navigation input.
func test_options_menu_navigation_sfx() -> void:
	await _assert_menu_navigation_sfx_trigger(OPTIONS_MENU_PATH)


## Validates that pause_menu.tscn triggers ui_navigation SFX on navigation input.
func test_pause_menu_navigation_sfx() -> void:
	await _assert_menu_navigation_sfx_trigger(PAUSE_MENU_PATH)


## Verifies that pause_menu.tscn successfully triggers ui_navigation SFX while SceneTree is paused.
func test_pause_menu_navigation_sfx_while_paused() -> void:
	assert_bool(FileAccess.file_exists(PAUSE_MENU_PATH)).is_true()
	var scene: PackedScene = load(PAUSE_MENU_PATH) as PackedScene
	assert_object(scene).is_not_null()
	if scene == null:
		return
	
	var raw_instance: Node = scene.instantiate()
	assert_object(raw_instance).is_not_null()
	if raw_instance == null:
		return
	var instance: Node = auto_free(raw_instance)
	add_child(instance)
	
	var target_control: Control = _find_first_focusable_control(instance)
	assert_object(target_control).is_not_null()
	if target_control == null:
		return
	target_control.grab_focus()
	await await_idle_frame()
	
	get_tree().paused = true
	assert_bool(get_tree().paused).is_true()
	
	AudioManager.stop_all_sfx()
	var event: InputEventAction = InputEventAction.new()
	event.action = "ui_down"
	event.pressed = true
	
	get_viewport().push_input(event)
	await await_idle_frame()
	
	assert_bool(AudioManager.is_any_sfx_playing()).is_true()
	var active_path: String = AudioManager.get_active_sfx_stream_path()
	assert_bool(active_path.contains("ui_navigation.wav")).is_true()
	get_tree().paused = false


## Traverses an instantiated scene tree to find the first focusable Control node.
func _find_first_focusable_control(node: Node) -> Control:
	if node is Control:
		var ctrl: Control = node as Control
		if ctrl.focus_mode != Control.FOCUS_NONE and ctrl.visible:
			return ctrl
			
	for child: Node in node.get_children():
		var found: Control = _find_first_focusable_control(child)
		if is_instance_valid(found):
			return found
			
	return null


## Standardized assertion flow validating viewport input consumption and audio routing.
func _assert_menu_navigation_sfx_trigger(scene_path: String) -> void:
	assert_bool(FileAccess.file_exists(scene_path)).is_true()
	
	var scene: PackedScene = load(scene_path) as PackedScene
	assert_object(scene).is_not_null()
	if scene == null:
		return
	
	var raw_instance: Node = scene.instantiate()
	assert_object(raw_instance).is_not_null()
	if raw_instance == null:
		return
	var instance: Node = auto_free(raw_instance)
	add_child(instance)
	
	var target_control: Control = _find_first_focusable_control(instance)
	assert_object(target_control).is_not_null()
	if target_control == null:
		return
	
	target_control.grab_focus()
	await await_idle_frame()
	assert_object(get_viewport().gui_get_focus_owner()).is_equal(target_control)
	
	AudioManager.stop_all_sfx()
	var event: InputEventAction = InputEventAction.new()
	event.action = "ui_down"
	event.pressed = true
	
	get_viewport().push_input(event)
	await await_idle_frame()
	
	assert_bool(AudioManager.is_any_sfx_playing()).is_true()
	var active_path: String = AudioManager.get_active_sfx_stream_path()
	assert_bool(active_path.contains("ui_navigation.wav")).is_true()
