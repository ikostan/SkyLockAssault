## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_ui_mute_logic.gd
##
## TEST SUITE: Verifies UI Mute Signal Propagation (Issue #711).

extends "res://addons/gut/test.gd"

var audio_scene: PackedScene = load(GamePaths.AUDIO_SETTINGS_SCENE)
var audio_instance: Control
var _bus_created_by_test: bool = false


## Per-test setup: Reset AudioManager to default values and prepare the Menu/UI audio bus.
## :rtype: void
func before_each() -> void:
	AudioManager._init_to_defaults()
	AudioManager.apply_all_volumes()
	
	# Initialize the Menu bus for headless testing if it doesn't already exist
	if AudioServer.get_bus_index(AudioConstants.BUS_SFX_MENU) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, AudioConstants.BUS_SFX_MENU)
		_bus_created_by_test = true


## Per-test cleanup: Safely dispose of the audio scene instance, clean up references, and clear test buses.
## :rtype: void
func after_each() -> void:
	if is_instance_valid(audio_instance):
		if "master_warning_dialog" in audio_instance and is_instance_valid(audio_instance.get("master_warning_dialog")):
			(audio_instance.get("master_warning_dialog") as Window).hide()
		if "sfx_warning_dialog" in audio_instance and is_instance_valid(audio_instance.get("sfx_warning_dialog")):
			(audio_instance.get("sfx_warning_dialog") as Window).hide()
		if audio_instance.get_parent() == self:
			remove_child(audio_instance)
		audio_instance.queue_free()
	audio_instance = null
	
	# Restore AudioServer bus layout state
	if _bus_created_by_test:
		var bus_idx: int = AudioServer.get_bus_index(AudioConstants.BUS_SFX_MENU)
		if bus_idx != -1:
			AudioServer.remove_bus(bus_idx)
		_bus_created_by_test = false
		
	await get_tree().process_frame


## TC-Mute-01 | Verifies that toggling the Menu/UI mute button accurately propagates the mute state
## to the AudioServer and updates the slider's interactive editability state.
## :rtype: void
func test_ui_menu_mute_signal_propagation() -> void:
	# 1. Instantiate a test instance of the audio settings menu.
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	await get_tree().process_frame
	
	# 2. Locate the Menu/UI volume control and its mute toggle.
	var menu_slider: HSlider = audio_instance.menu_slider as HSlider
	var mute_toggle: BaseButton = audio_instance.mute_menu as BaseButton
	
	# 3. Ensure the Menu/UI slider is initially editable.
	assert_true(menu_slider.editable, "Menu slider should be initially editable when unmuted.")
	
	# 4. Retrieve the Menu/UI bus index from AudioServer and check the initial state.
	var bus_index: int = AudioServer.get_bus_index(AudioConstants.BUS_SFX_MENU)
	assert_ne(bus_index, -1, "The Menu/UI audio bus must exist on the AudioServer.")
	assert_false(
		AudioServer.is_bus_mute(bus_index), 
		"Precondition failed: Menu/UI bus must start unmuted before testing toggle logic."
	)
	
	# 5. Simulate user interaction with the mute control (mute the bus).
	mute_toggle.button_pressed = false
	mute_toggle.toggled.emit(false)
	
	# 6. Allow any signal handlers to execute.
	await get_tree().process_frame
	
	# 7. Assertions for the muted state.
	assert_true(AudioServer.is_bus_mute(bus_index), "The AudioServer bus must be muted.")
	assert_false(menu_slider.editable, "The corresponding Menu/UI slider must become non-editable.")
	
	# 8. Simulate user interaction to unmute the control.
	mute_toggle.button_pressed = true
	mute_toggle.toggled.emit(true)
	await get_tree().process_frame
	
	# 9. Assertions for the unmuted state (slider can be re-enabled after unmuting).
	assert_false(AudioServer.is_bus_mute(bus_index), "The AudioServer bus must be unmuted.")
	assert_true(menu_slider.editable, "The slider must become editable again after unmuting.")
