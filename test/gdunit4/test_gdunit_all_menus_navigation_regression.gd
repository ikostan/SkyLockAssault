## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
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
var _original_next_scene: String
var _original_current_scene: Node


func before_test() -> void:
	_original_next_scene = Globals.next_scene
	_original_current_scene = get_tree().current_scene


func after_test() -> void:
	Globals.next_scene = _original_next_scene
	_free_scene_installed_by_test()


## Frees a scene a test installed as the SceneTree's current scene and restores the previous
## one. LS-TRANS-03 adds a real main menu to the root, and LS-FALLBACK-03/04 reach
## change_scene_to_file(); left alive, that main menu's intro (intro_delay + fade_duration)
## ends in Globals.ensure_initial_focus(start_button) and takes focus from whatever suite is
## running about 4 s later. In CI that was test_options_menu_navigation_sfx (focus owner
## "<Button>" at test_gdunit_all_menus_navigation_regression.gd:159), depending on suite order.
## free() rather than queue_free(): the menu's pending timer and deferred calls die with it.
func _free_scene_installed_by_test() -> void:
	var current: Node = get_tree().current_scene
	if not is_instance_valid(current) or current == _original_current_scene:
		return
	if is_instance_valid(_original_current_scene):
		get_tree().current_scene = _original_current_scene
	else:
		get_tree().current_scene = null
	current.free()


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
	# Let deferred focus grabs settle first (menus call ensure_initial_focus(), which uses
	# call_deferred("grab_focus")), so they cannot steal focus after the test grabs it.
	await await_idle_frame()
	
	var target_control: Control = _find_first_focusable_control(instance)
	assert_object(target_control).is_not_null()
	if target_control == null:
		return
	target_control.grab_focus()
	await await_idle_frame()
	
	get_tree().paused = true
	assert_bool(get_tree().paused).is_true()
	
	SfxManager.stop_all_sfx()
	var event: InputEventAction = InputEventAction.new()
	event.action = "ui_down"
	event.pressed = true
	
	get_viewport().push_input(event)
	await await_idle_frame()
	
	assert_bool(SfxManager.is_any_sfx_playing()).is_true()
	var active_path: String = SfxManager.get_active_sfx_stream_path()
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
	# Let deferred focus grabs settle first (menus call ensure_initial_focus(), which uses
	# call_deferred("grab_focus")), so they cannot steal focus after the test grabs it.
	await await_idle_frame()
	
	var target_control: Control = _find_first_focusable_control(instance)
	assert_object(target_control).is_not_null()
	if target_control == null:
		return
	
	target_control.grab_focus()
	await await_idle_frame()
	assert_object(get_viewport().gui_get_focus_owner()).is_equal(target_control)
	
	SfxManager.stop_all_sfx()
	var event: InputEventAction = InputEventAction.new()
	event.action = "ui_down"
	event.pressed = true
	
	get_viewport().push_input(event)
	await await_idle_frame()
	
	assert_bool(SfxManager.is_any_sfx_playing()).is_true()
	var active_path: String = SfxManager.get_active_sfx_stream_path()
	assert_bool(active_path.contains("ui_navigation.wav")).is_true()
