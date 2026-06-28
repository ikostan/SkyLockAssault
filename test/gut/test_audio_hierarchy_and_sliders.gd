## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_audio_hierarchy_and_sliders.gd
##
## Integration suite verifying multi-tiered UI interactivity locks and volume
## component tracking security during external focus loss conditions.
extends "res://addons/gut/test.gd"

var audio_scene: PackedScene = load(GamePaths.AUDIO_SETTINGS_SCENE)
var audio_instance: Control


func before_each() -> void:
	AudioManager.reset_volumes()
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(audio_instance):
		audio_instance.queue_free()
	audio_instance = null
	await get_tree().process_frame


## Verifies that muting Master volume actively propagates disabled flags 
## down to the entire downstream audio configuration panel.
func test_master_mute_locks_entire_child_hierarchy() -> void:
	# Act: Enforce master silent block state mutation
	AudioManager.set_muted(AudioConstants.BUS_MASTER, true)
	audio_instance._update_ui_interactivity()
	await get_tree().process_frame
	
	# Assert: Sub-bus interaction nodes must be locked out completely
	assert_true(audio_instance.mute_music.disabled, "Music Mute should lock out when Master is muted.")
	assert_false(audio_instance.music_slider.editable, "Music Slider should be uneditable when Master is muted.")
	assert_true(audio_instance.mute_sfx.disabled, "SFX Mute should lock out when Master is muted.")
	assert_false(audio_instance.weapon_slider.editable, "Weapon Sub-slider must freeze when Master hierarchy closes.")


## Verifies that muting the parent SFX channel selectively locks sub-buses
## while leaving unrelated tracks like Music operational.
func test_sfx_mute_locks_only_sfx_sub_buses() -> void:
	AudioManager.set_muted(AudioConstants.BUS_MASTER, false)
	AudioManager.set_muted(AudioConstants.BUS_SFX, true)
	audio_instance._update_ui_interactivity()
	await get_tree().process_frame
	
	# Core baseline paths check
	assert_false(audio_instance.mute_music.disabled, "Music selection toggle must remain open.")
	assert_true(audio_instance.music_slider.editable, "Music slider scale should remain operational.")
	
	# Sub-buses check
	assert_true(audio_instance.mute_weapon.disabled, "Weapon Mute button must lock down under parent SFX mute conditions.")
	assert_false(audio_instance.weapon_slider.editable, "Weapon volume adjustment track must lock down.")
	assert_true(audio_instance.mute_rotor.disabled, "Rotor structural toggle must lock down.")


## Verifies that dragging tracking states fail-safe instantly if an external event 
## steals application layout window alignment.
func test_slider_drag_state_drops_on_application_focus_loss() -> void:
	var slider: VolumeSlider = audio_instance.master_slider
	slider.grab_focus()
	
	# Simulate an active user click drag sequence input profile
	var mouse_event := InputEventMouseButton.new()
	mouse_event.button_index = MOUSE_BUTTON_LEFT
	mouse_event.pressed = true
	slider._on_gui_input(mouse_event)
	
	assert_true(slider.is_user_dragging(), "Precondition: Slider must actively confirm dragging index status profile.")
	
	# Act: Push an engine window focus exit notification track down into the component loop
	slider._notification(Control.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	
	# Assert: Component state tracking must clear to eliminate stuck runtime operations
	assert_false(
		slider.is_user_dragging(),
		"Slider must instantly drop active drag state tracking when OS window focus drops."
	)
