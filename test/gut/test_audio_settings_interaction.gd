## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_audio_settings_interaction.gd
##
## Architectural test suite for UI interaction logic in audio_settings.gd.
## Validates mute toggles, reset functionality, and back navigation 
## via direct controller method invocation.

extends "res://addons/gut/test.gd"

# Load the scene using the shared GamePaths
var audio_scene: PackedScene = load(GamePaths.AUDIO_SETTINGS_SCENE)
var audio_instance: Control


## Per-test setup: Instantiate scene and ensure initial focus state.
## :rtype: void
func before_each() -> void:
	_clear_pool_players()
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	audio_instance.grab_focus()
	await Engine.get_main_loop().process_frame


## Post-test cleanup: Free nodes and synchronize with engine loop.
## :rtype: void
func after_each() -> void:
	_clear_pool_players()
	if is_instance_valid(audio_instance):
		audio_instance.queue_free()
	audio_instance = null
	var main_loop := Engine.get_main_loop()
	if main_loop:
		await main_loop.process_frame


## Silences active audio signals via public API.
## @return void
func _clear_pool_players() -> void:
	AudioManager.stop_all_sfx()


## Helper: Checks if any sound is actively streaming using public API.
## @return bool
func _is_sound_playing() -> bool:
	return AudioManager.is_sfx_playing()


## Helper: Inspects the pool via public API to find the playing stream's resource path.
## @return String
func _get_playing_stream_path() -> String:
	return AudioManager.get_active_sfx_stream_path()


# ==========================================================================
# 1. INTERACTION LOGIC
# ==========================================================================

## Validates that toggling the mute button triggers the expected SFX.
## :rtype: void
func test_mute_toggle_triggers_audio() -> void:
	_clear_pool_players()
	var btn: CheckButton = audio_instance.mute_master
	btn.grab_focus()
	
	audio_instance._on_master_mute_toggled(false)
	await Engine.get_main_loop().process_frame
	
	var path := _get_playing_stream_path()
	assert_true("check" in path, "Expected 'check' sound, but played: " + path)


## Validates that the Reset button reverts AudioManager to default state.
## :rtype: void
func test_reset_button_restores_defaults() -> void:
	AudioManager.master_volume = 0.1
	AudioManager.master_muted = true
	AudioManager.apply_all_volumes()
	audio_instance._on_audio_reset_button_pressed()
	assert_eq(AudioManager.master_volume, 1.0, "Reset button should restore master volume.")
	assert_false(AudioManager.master_muted, "Reset button should unmute master.")


## Validates that mute toggles do NOT emit audio when unfocused (Focus-Gate).
## :rtype: void
func test_mute_toggled_unfocused_is_silent() -> void:
	_clear_pool_players()
	# Focus something else
	audio_instance.audio_back_button.grab_focus()
	
	audio_instance._on_master_mute_toggled(false)
	await Engine.get_main_loop().process_frame
	
	assert_false(_is_sound_playing(), "Mute toggle when unfocused should be silent.")


# ==========================================================================
# 2. REGRESSION PROTECTION
# ==========================================================================

## Validates that rapid UI toggles do not overwhelm the audio playback pool.
## Verifies the focus-gate logic prevents sound spam.
## :rtype: void
func test_interaction_spam_is_bounded() -> void:
	_clear_pool_players()
	var btn: CheckButton = audio_instance.mute_music
	btn.grab_focus()
	
	# Rapid calls — in real UI these are spaced by input frames.
	# We manually await frames to mimic the engine's event processing.
	audio_instance._on_music_mute_toggled(false)
	await Engine.get_main_loop().process_frame
	audio_instance._on_music_mute_toggled(true)
	await Engine.get_main_loop().process_frame
	audio_instance._on_music_mute_toggled(false)
	await Engine.get_main_loop().process_frame
	
	var play_count: int = AudioManager.get_active_sfx_playback_count()
	
	# Assert exact count instead of inequality
	assert_eq(play_count, 3, "Interaction spam should result in exactly 3 requests. Was: " + str(play_count))


## Validates that GUI input interaction on volume sliders triggers the expected audio state update.
## Uses approximate equality for floating-point volume thresholds.
## :rtype: void
func test_slider_gui_input_triggers_audio() -> void:
	_clear_pool_players()
	
	# Target: Master Slider
	var slider: HSlider = audio_instance.master_slider
	slider.grab_focus()
	
	# Act: Simulate a GUI value change
	# We invoke the handler directly as it is the controller's public API
	slider.value = 0.5
	await Engine.get_main_loop().process_frame
	
	# Assert: Check if AudioManager reflects the value change and audio was processed
	assert_almost_eq(AudioManager.master_volume, 0.5, 0.01,
		"Slider input should update AudioManager.master_volume (within tolerance).")


# ==========================================================================
# 3. REGRESSION & RESILIENCE
# ==========================================================================

## Validates extreme volume values are handled correctly (boundary testing).
## :rtype: void
func test_slider_extreme_values() -> void:
	_clear_pool_players()
	var slider: HSlider = audio_instance.master_slider
	
	slider.value = 0.0
	await Engine.get_main_loop().process_frame
	assert_almost_eq(AudioManager.master_volume, 0.0, 0.01)
	
	slider.value = 1.0
	await Engine.get_main_loop().process_frame
	assert_almost_eq(AudioManager.master_volume, 1.0, 0.01)


## Validates resilience to invalid / out-of-range slider inputs.
## :rtype: void
func test_slider_invalid_input_resilience() -> void:
	_clear_pool_players()
	var slider: HSlider = audio_instance.master_slider
	
	slider.value = -1.0
	await Engine.get_main_loop().process_frame
	assert_true(AudioManager.master_volume >= 0.0)
	
	slider.value = 999.0
	await Engine.get_main_loop().process_frame
	assert_true(AudioManager.master_volume <= 1.0)


## Validates that Reset button recovers from corrupted AudioManager state.
## :rtype: void
func test_reset_after_corrupted_state() -> void:
	AudioManager.master_volume = -5.0
	AudioManager.master_muted = true
	AudioManager.apply_all_volumes()
	
	audio_instance._on_audio_reset_button_pressed()
	
	assert_eq(AudioManager.master_volume, 1.0, "Reset should restore master volume.")
	assert_false(AudioManager.master_muted, "Reset should unmute master.")


## Validates audio pool does not leak under heavy interaction stress.
## :rtype: void
func test_audio_pool_no_leak_under_stress() -> void:
	_clear_pool_players()
	var initial_count := AudioManager.get_active_sfx_playback_count()
	
	for i in range(20):
		audio_instance._on_music_mute_toggled(i % 2 == 0)
		await Engine.get_main_loop().process_frame
	
	var final_count := AudioManager.get_active_sfx_playback_count()
	assert_true(final_count <= initial_count + 3, 
		"Pool should not grow unbounded under stress. Final: " + str(final_count))


## Validates that focus transitions alone do not generate audio requests.
func test_focus_change_is_silent() -> void:
	_clear_pool_players()
	
	# Focus Master
	audio_instance.mute_master.grab_focus()
	await Engine.get_main_loop().process_frame
	
	# Focus Music
	audio_instance.mute_music.grab_focus()
	await Engine.get_main_loop().process_frame
	
	assert_false(_is_sound_playing(), "Changing focus alone should not trigger audio.")


## Validates resilience when an invalid/corrupt SFX key is requested.
## @return void
func test_play_invalid_sfx_key_is_resilient() -> void:
	_clear_pool_players()
	
	# Attempt to play a non-existent sound key
	AudioManager.play_sfx("INVALID_CORRUPT_KEY_999")
	await Engine.get_main_loop().process_frame
	
	# Assert system is still functional and didn't crash
	assert_false(_is_sound_playing(), "System should handle invalid keys gracefully without crashing.")
