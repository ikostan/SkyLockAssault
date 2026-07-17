## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_all_menus_navigation_regression.gd
##
## Integration regression test suite targeting navigation audio execution
## across every single scene menu layout in SkyLockAssault.
extends GutTest

const ADVANCED_SETTINGS_PATH: String = "res://scenes/advanced_settings.tscn"
const AUDIO_SETTINGS_PATH: String = "res://scenes/audio_settings.tscn"
const GAMEPLAY_SETTINGS_PATH: String = "res://scenes/gameplay_settings.tscn"
const KEY_MAPPING_PATH: String = "res://scenes/key_mapping_menu.tscn"
const MAIN_MENU_PATH: String = "res://scenes/main_menu.tscn"
const OPTIONS_MENU_PATH: String = "res://scenes/options_menu.tscn"
const PAUSE_MENU_PATH: String = "res://scenes/pause_menu.tscn"

var _original_options_open: bool


func before_each() -> void:
	# Snapshot state to guarantee menu context routing
	_original_options_open = Globals.options_open
	Globals.options_open = true
	
	# Clear out any lingering playback frames
	AudioManager.stop_all_sfx()
	if AudioManager.has_method("cleanup_for_test"):
		AudioManager.cleanup_for_test()


func after_each() -> void:
	# Restore global configuration state cleanly
	Globals.options_open = _original_options_open
	
	# UNCONDITIONALLY unpause the tree to prevent test runner hangs
	# This ensures subsequent tests start in a clean, running state
	get_tree().paused = false
	
	var focus_owner := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus_owner):
		focus_owner.release_focus()
		
	AudioManager.stop_all_sfx()


# ==========================================================================
# CORE REGRESSION TESTS
# ==========================================================================

## Test 1: Verify advanced_settings.tscn routes ui_navigation SFX
func test_advanced_settings_navigation_sfx() -> void:
	await _assert_menu_navigation_sfx_trigger(ADVANCED_SETTINGS_PATH)


## Test 2: Verify audio_settings.tscn routes ui_navigation SFX
func test_audio_settings_navigation_sfx() -> void:
	await _assert_menu_navigation_sfx_trigger(AUDIO_SETTINGS_PATH)


## Test 3: Verify gameplay_settings.tscn routes ui_navigation SFX
func test_gameplay_settings_navigation_sfx() -> void:
	await _assert_menu_navigation_sfx_trigger(GAMEPLAY_SETTINGS_PATH)


## Test 4: Verify key_mapping_menu.tscn routes ui_navigation SFX
func test_key_mapping_menu_navigation_sfx() -> void:
	await _assert_menu_navigation_sfx_trigger(KEY_MAPPING_PATH)


## Test 5: Verify main_menu.tscn routes ui_navigation SFX
func test_main_menu_navigation_sfx() -> void:
	await _assert_menu_navigation_sfx_trigger(MAIN_MENU_PATH)


## Test 6: Verify options_menu.tscn routes ui_navigation SFX
func test_options_menu_navigation_sfx() -> void:
	await _assert_menu_navigation_sfx_trigger(OPTIONS_MENU_PATH)


## Test 7: Verify pause_menu.tscn routes ui_navigation SFX
func test_pause_menu_navigation_sfx() -> void:
	await _assert_menu_navigation_sfx_trigger(PAUSE_MENU_PATH)


# ==========================================================================
# HELPER ACTIONS & REFLECTION
# ==========================================================================

## Traverses an instantiated scene tree to isolate the first focusable Control node.
func _find_first_focusable_control(node: Node) -> Control:
	if node is Control and node.focus_mode != Control.FOCUS_NONE and node.visible:
		return node
		
	for child in node.get_children():
		var found := _find_first_focusable_control(child)
		if is_instance_valid(found):
			return found
			
	return null


## Standardized assertion flow validating viewport input consumption and audio routing.
func _assert_menu_navigation_sfx_trigger(scene_path: String) -> void:
	assert_true(FileAccess.file_exists(scene_path), "File integrity validation: Scene path '%s' must exist on disk." % scene_path)
	
	var scene := load(scene_path) as PackedScene
	assert_not_null(scene, "Failed to load menu scene from path: %s" % scene_path)
	
	var instance := scene.instantiate()
	assert_not_null(instance, "Failed to instantiate menu layout: %s" % scene_path)
	add_child_autofree(instance)
	
	# Find a valid control in the layout to receive input focus
	var target_control := _find_first_focusable_control(instance)
	assert_not_null(target_control, "Layout validation failed: Could not locate a focus-compatible Control in: %s" % scene_path)
	
	target_control.grab_focus()
	await get_tree().process_frame
	assert_eq(get_viewport().gui_get_focus_owner(), target_control, "Focus grab confirmation failed for layout: %s" % scene_path)
	
	# Prime viewport and trigger directional UI navigation
	AudioManager.stop_all_sfx()
	var event := InputEventAction.new()
	event.action = "ui_down"
	event.pressed = true
	
	get_viewport().push_input(event)
	await get_tree().process_frame
	
	# Assertions targeting the input consumption regression bug
	assert_true(
		AudioManager.is_any_sfx_playing(),
		"Regression: Focused node in '%s' swallowed navigation event, blocking menu SFX playback." % scene_path
	)
	
	var active_path := AudioManager.get_active_sfx_stream_path()
	assert_true(
		active_path.contains("ui_navigation.wav"),
		"Expected '%s' to play 'ui_navigation.wav', but played '%s' instead." % [scene_path, active_path]
	)


## Test Scenario: Verify that pause_menu.tscn successfully triggers ui_navigation SFX
## even when the SceneTree is actively paused.
func test_pause_menu_navigation_sfx_while_paused() -> void:
	# 1. Load and instantiate the pause menu
	assert_true(FileAccess.file_exists(PAUSE_MENU_PATH), "File integrity validation: Pause menu path must exist.")
	var scene := load(PAUSE_MENU_PATH) as PackedScene
	var instance := scene.instantiate()
	add_child_autofree(instance)
	
	# 2. Find and grab focus on the first interactive button
	var target_control := _find_first_focusable_control(instance)
	assert_not_null(target_control, "Could not locate focus-compatible Control in pause menu.")
	target_control.grab_focus()
	await get_tree().process_frame
	
	# 3. FORCE THE ENGINE TO PAUSE
	get_tree().paused = true
	assert_true(get_tree().paused, "Precondition: SceneTree must be successfully paused.")
	
	# 4. Clear old audio streams and push navigation input
	AudioManager.stop_all_sfx()
	var event := InputEventAction.new()
	event.action = "ui_down"
	event.pressed = true
	
	get_viewport().push_input(event)
	await get_tree().process_frame
	
	# 5. UNPAUSE ENGINE CLEANLY IN TEST LAYER (Crucial to prevent hanging test runner state)
	get_tree().paused = false
	
	# 6. Assertions to verify the pause-state silent failure
	assert_true(
		AudioManager.is_any_sfx_playing(),
		"Regression: Focused node in paused Pause Menu swallowed navigation event or UiManager was frozen."
	)
	
	var active_path := AudioManager.get_active_sfx_stream_path()
	assert_true(
		active_path.contains("ui_navigation.wav"),
		"Expected paused menu to play 'ui_navigation.wav', but played '%s' instead." % active_path
	)
