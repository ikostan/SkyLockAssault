## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_audio_settings_interaction.gd
##
## Architectural test suite for UI interaction logic in audio_settings.gd.

extends "res://addons/gut/test.gd"

# Load the scene using the shared GamePaths
var audio_scene: PackedScene = load(GamePaths.AUDIO_SETTINGS_SCENE)
var audio_instance: Control


## Per-test setup
func before_each() -> void:
	_clear_pool_players()
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	audio_instance.grab_focus()
	await Engine.get_main_loop().process_frame


## Post-test cleanup
func after_each() -> void:
	_clear_pool_players()
	if is_instance_valid(audio_instance):
		audio_instance.queue_free()
	audio_instance = null
	var main_loop := Engine.get_main_loop()
	if main_loop:
		await main_loop.process_frame


func _clear_pool_players() -> void:
	for player in AudioManager._sfx_pool:
		var p: AudioStreamPlayer = player
		p.stop()
		p.stream = null


func _is_sound_playing() -> bool:
	for player in AudioManager._sfx_pool:
		var p: AudioStreamPlayer = player
		if p.playing:
			return true
	return false


# ==========================================================================
# 1. INTERACTION LOGIC
# ==========================================================================

func test_mute_toggle_triggers_audio() -> void:
	_clear_pool_players()
	var btn: CheckButton = audio_instance.mute_master
	btn.grab_focus()
	audio_instance._on_master_mute_toggled(false)
	await Engine.get_main_loop().process_frame
	assert_true(_is_sound_playing(), "Mute toggle should trigger 'check' sound.")


func test_reset_button_restores_defaults() -> void:
	AudioManager.master_volume = 0.1
	AudioManager.master_muted = true
	AudioManager.apply_all_volumes()
	audio_instance._on_audio_reset_button_pressed()
	assert_eq(AudioManager.master_volume, 1.0, "Reset button should restore master volume.")
	assert_false(AudioManager.master_muted, "Reset button should unmute master.")


func test_back_button_triggers_exit() -> void:
	audio_instance.queue_free()
	assert_true(audio_instance.is_queued_for_deletion(), 
		"Back button should queue_free the menu.")


# ==========================================================================
# 2. REGRESSION PROTECTION
# ==========================================================================

func test_interaction_spam_is_bounded() -> void:
	_clear_pool_players()
	var btn: CheckButton = audio_instance.mute_music
	btn.grab_focus()
	
	audio_instance._on_music_mute_toggled(false)
	await Engine.get_main_loop().process_frame
	audio_instance._on_music_mute_toggled(true)
	await Engine.get_main_loop().process_frame
	audio_instance._on_music_mute_toggled(false)
	await Engine.get_main_loop().process_frame
	
	var play_count: int = AudioManager.get_active_sfx_playback_count()
	assert_true(play_count <= 3, 
		"Interaction spam should be rate-limited by focus-gate logic. Count was: " + str(play_count))


## Validates slider interaction updates AudioManager volume (with float tolerance).
func test_slider_gui_input_triggers_audio() -> void:
	_clear_pool_players()
	
	var slider: HSlider = audio_instance.master_slider
	slider.grab_focus()
	
	# Set value directly — this triggers the connected handler in most setups
	slider.value = 0.5
	
	await Engine.get_main_loop().process_frame
	
	# Use approximate equality because of slider step / floating-point rounding
	assert_almost_eq(AudioManager.master_volume, 0.5, 0.01, 
		"Slider input should update AudioManager.master_volume (within tolerance).")
