## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_main_menu_audio.gd
##
## Integration test suite ensuring that Main Menu scene buttons successfully
## trigger the confirmation click audio asset over the presentation layer.

extends GutTest

const MAIN_MENU_SCENE_PATH = "res://scenes/main_menu.tscn"
const MENU_BUS: String = AudioConstants.BUS_SFX_MENU

# Lifecycle tracking references to prevent scene leakage between test runs
var _initial_root_children: Array[Node] = []
var _initial_current_scene: Node = null


func before_all() -> void:
	# REFACTOR: Offload bus setup configurations entirely to shared test utilities
	var required_buses: Array[String] = [
		AudioConstants.BUS_MASTER,
		AudioConstants.BUS_MUSIC,
		AudioConstants.BUS_SFX,
		MENU_BUS
	]
	GutTestHelper.bootstrap_headless_audio_buses(required_buses)


func before_each() -> void:
	# Snapshot the baseline scene state before interactions modify the tree footprint
	_initial_root_children = get_tree().root.get_children()
	_initial_current_scene = get_tree().current_scene
	
	AudioManager.stop_all_sfx()
	AudioManager.reset_volumes()


func after_each() -> void:
	# 1. Reset global menu state toggles to prevent cross-contamination
	if is_instance_valid(Globals.options_instance):
		Globals.options_instance.queue_free()
		Globals.options_instance = null
	Globals.options_open = false
	Globals.hidden_menus.clear()

	# 2. Revert scene tree transitions back to pristine baseline test states
	if is_instance_valid(get_tree().current_scene) and get_tree().current_scene != _initial_current_scene:
		var leaked_scene := get_tree().current_scene
		
		# Create an empty node space to safely swap back to 
		var blank_placeholder := Node.new()
		blank_placeholder.name = "TestPlaceholderScene"
		get_tree().root.add_child(blank_placeholder)
		get_tree().current_scene = blank_placeholder
		
		# Erase the active gameplay loop rendering in the background
		leaked_scene.queue_free()

	# 3. Clean up any standalone canvas layers or popups pushed straight to the root window
	for child in get_tree().root.get_children():
		if is_instance_valid(child) and child not in _initial_root_children and child != get_tree().current_scene:
			child.queue_free()

	# 4. Flush all hardware audio registers completely
	AudioManager.stop_all_sfx()
	if AudioManager.has_method("cleanup_for_test"):
		AudioManager.cleanup_for_test()
	AudioManager.reset_volumes()


## Scenario: Verifies that Main Menu buttons play the accept sound despite the 'no_global_sound' metadata shield.
func test_main_menu_buttons_execute_accept_audio() -> void:
	# 1. Load and instantiate the main menu scene
	var scene_resource := load(MAIN_MENU_SCENE_PATH)
	assert_not_null(scene_resource, "Fail-Fast: Main menu scene asset could not be loaded from project paths.")
	
	var menu_instance := scene_resource.instantiate() as Control
	add_child_autofree(menu_instance)
	await wait_process_frames(1)

	# 2. Setup testing guards to prevent engine exit/quit loops
	menu_instance.bypass_quit_for_testing = true

	# --- TEST START GAME BUTTON ---
	var start_btn: Button = menu_instance.start_button
	assert_not_null(start_btn, "Layout Validation: Start Button is missing from scene tree.")
	
	start_btn.pressed.emit()
	await wait_process_frames(1)
	
	assert_true(AudioManager.is_any_sfx_playing(), "Start Game button must trigger confirmation audio.")
	assert_string_contains(AudioManager.get_active_sfx_stream_path(), "ui_accept", "Start Game button must play the 'ui_accept' sound effect asset.")
	
	AudioManager.stop_all_sfx()

	# --- TEST OPTIONS BUTTON ---
	var options_btn: Button = menu_instance.options_button
	assert_not_null(options_btn, "Layout Validation: Options Button is missing from scene tree.")
	
	options_btn.pressed.emit()
	await wait_process_frames(1)
	
	assert_true(AudioManager.is_any_sfx_playing(), "Options button must trigger confirmation audio.")
	assert_string_contains(AudioManager.get_active_sfx_stream_path(), "ui_accept", "Options button must play the 'ui_accept' sound effect asset.")
	
	AudioManager.stop_all_sfx()

	# --- TEST QUIT BUTTON ---
	var quit_btn: Button = menu_instance.quit_button
	assert_not_null(quit_btn, "Layout Validation: Quit Button is missing from scene tree.")
	
	quit_btn.pressed.emit()
	await wait_process_frames(1)
	
	assert_true(AudioManager.is_any_sfx_playing(), "Quit button must trigger confirmation audio.")
	assert_string_contains(AudioManager.get_active_sfx_stream_path(), "ui_accept", "Quit button must play the 'ui_accept' sound effect asset.")
