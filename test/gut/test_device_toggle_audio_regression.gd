## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_device_toggle_audio_regression.gd
##
## Regression test suite specifically targeting audio playback failures 
## when toggling input devices in the Key Mapping Options menu.
extends GutTest

const KEY_MAPPING_PATH: String = "res://scenes/key_mapping_menu.tscn"

var _original_options_open: bool
var _original_input_device: String


func before_each() -> void:
	# Snapshot the initial global options state to prevent pollution
	_original_options_open = Globals.options_open
	_original_input_device = Globals.current_input_device
	Globals.options_open = true
	
	# Purge running streams from the shared singleton pool
	AudioManager.stop_all_sfx()
	if AudioManager.has_method("cleanup_for_test"):
		AudioManager.cleanup_for_test()


func after_each() -> void:
	# Restore state cleanly
	Globals.options_open = _original_options_open
	Globals.current_input_device = _original_input_device
	Settings.save_last_input_device(_original_input_device)
	
	var focus_owner := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus_owner):
		focus_owner.release_focus()
		
	AudioManager.stop_all_sfx()


## Test Scenario: Verify that toggling the Keyboard CheckButton in the Key Mapping Menu
## successfully plays the 'check.wav' sound effect.
func test_keyboard_toggle_triggers_check_sfx() -> void:
	# 1. Instantiate the Key Mapping Menu
	assert_true(FileAccess.file_exists(KEY_MAPPING_PATH), "Precondition: Scene path must exist on disk.")
	var scene := load(KEY_MAPPING_PATH) as PackedScene
	var menu := scene.instantiate()
	add_child_autofree(menu)
	await get_tree().process_frame

	# 2. Extract the Keyboard button
	var keyboard_btn: CheckButton = menu.get_node_or_null("Panel/Options/DeviceTypeContainer/Keyboard") as CheckButton
	assert_not_null(keyboard_btn, "Precondition: Keyboard CheckButton must exist in layout.")

	# 3. Simulate toggling the button
	AudioManager.stop_all_sfx()
	keyboard_btn.toggled.emit(true)
	await wait_process_frames(1)

	# 4. Assert that the correct sound played
	assert_true(
		AudioManager.is_any_sfx_playing(),
		"Regression Failure: Toggling the Keyboard button did not trigger any UI audio feedback."
	)
	
	var active_path := AudioManager.get_active_sfx_stream_path()
	assert_true(
		active_path.contains("check.wav"),
		"Regression Failure: Expected 'check.wav' to play, but played '%s' instead." % active_path
	)


## Test Scenario: Verify that toggling the Gamepad CheckButton in the Key Mapping Menu
## successfully plays the 'check.wav' sound effect.
func test_gamepad_toggle_triggers_check_sfx() -> void:
	# 1. Instantiate the Key Mapping Menu
	var scene := load(KEY_MAPPING_PATH) as PackedScene
	var menu := scene.instantiate()
	add_child_autofree(menu)
	await get_tree().process_frame

	# 2. Extract the Gamepad button
	var gamepad_btn: CheckButton = menu.get_node_or_null("Panel/Options/DeviceTypeContainer/Gamepad") as CheckButton
	assert_not_null(gamepad_btn, "Precondition: Gamepad CheckButton must exist in layout.")

	# 3. Simulate toggling the button
	AudioManager.stop_all_sfx()
	gamepad_btn.toggled.emit(true)
	await wait_process_frames(1)

	# 4. Assert that the correct sound played
	assert_true(
		AudioManager.is_any_sfx_playing(),
		"Regression Failure: Toggling the Gamepad button did not trigger any UI audio feedback."
	)
	
	var active_path := AudioManager.get_active_sfx_stream_path()
	assert_true(
		active_path.contains("check.wav"),
		"Regression Failure: Expected 'check.wav' to play, but played '%s' instead." % active_path
	)
