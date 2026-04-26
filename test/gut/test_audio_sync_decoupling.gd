## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_audio_sync_decoupling.gd
##
## TEST SUITE: Verifies Signal Decoupling for Web and UI Sync (Issue #567).
## Ensures that programmatic volume updates from the Web Bridge or AudioManager
## do not trigger the slider's value_changed signal, preventing audio feedback
## loops and redundant disk I/O.

extends "res://addons/gut/test.gd"

var audio_scene: PackedScene = load(GamePaths.AUDIO_SETTINGS_SCENE)
var audio_instance: Control
var test_config_path: String = "user://test_audio_sync.cfg"

# State snapshot variables to prevent cross-suite leakage
var _orig_config_path: String
var _orig_master_volume: float
var _orig_sfx_volume: float


## Per-test setup: Instantiate audio scene, snapshot singleton, and reset state
## :rtype: void
func before_each() -> void:
	# Capture original AudioManager state
	_orig_config_path = AudioManager.current_config_path
	_orig_master_volume = AudioManager.master_volume
	_orig_sfx_volume = AudioManager.sfx_volume
	
	if FileAccess.file_exists(test_config_path):
		DirAccess.remove_absolute(test_config_path)
		
	# Apply isolated test state
	AudioManager.current_config_path = test_config_path
	AudioManager.master_volume = 1.0
	AudioManager.sfx_volume = 1.0
	
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)


## Per-test cleanup: Free audio_instance safely and restore singleton state.
## :rtype: void
func after_each() -> void:
	if is_instance_valid(audio_instance):
		if is_instance_valid(audio_instance.master_warning_dialog):
			audio_instance.master_warning_dialog.hide()
		if is_instance_valid(audio_instance.sfx_warning_dialog):
			audio_instance.sfx_warning_dialog.hide()
		remove_child(audio_instance)
		audio_instance.queue_free()
	
	if FileAccess.file_exists(test_config_path):
		DirAccess.remove_absolute(test_config_path)
		
	# Restore original AudioManager state to prevent leakage
	AudioManager.current_config_path = _orig_config_path
	AudioManager.master_volume = _orig_master_volume
	AudioManager.sfx_volume = _orig_sfx_volume
	
	await get_tree().process_frame


## Verifies that global volume changes (e.g., from Web Bridge) update the UI 
## without firing the value_changed signal.
## :rtype: void
func test_global_volume_changed_bypasses_signals() -> void:
	# Precondition: Ensure the timer is stopped
	assert_true(audio_instance.master_slider.save_debounce_timer.is_stopped(), "Timer should be stopped initially.")
	
	# Act: Simulate an incoming Web Bridge sync event
	var new_volume: float = 0.35
	audio_instance._on_global_volume_changed(AudioConstants.BUS_MASTER, new_volume)
	
	# Assert: The slider visually updated, but the timer (and thus SFX) was NOT triggered
	assert_eq(audio_instance.master_slider.value, new_volume, "Slider value should reflect the global change.")
	assert_true(
		audio_instance.master_slider.save_debounce_timer.is_stopped(), 
		"Debounce timer MUST remain stopped. If it started, set_value_no_signal() was not used, risking an audio feedback loop."
	)


## Verifies that syncing the UI from the AudioManager (e.g., during Reset)
## updates all sliders without firing their signals.
## :rtype: void
func test_sync_ui_from_manager_bypasses_signals() -> void:
	# Precondition: Ensure the timer is stopped
	assert_true(audio_instance.sfx_slider.save_debounce_timer.is_stopped(), "Timer should be stopped initially.")
	
	# Setup: Change the backend AudioManager state silently
	var new_sfx_volume: float = 0.8
	AudioManager.sfx_volume = new_sfx_volume
	
	# Act: Force the UI to pull the latest state
	audio_instance._sync_ui_from_manager()
	
	# Assert: The slider updated, but no signals were emitted
	assert_eq(audio_instance.sfx_slider.value, new_sfx_volume, "SFX Slider should sync to the new AudioManager value.")
	assert_true(
		audio_instance.sfx_slider.save_debounce_timer.is_stopped(), 
		"Debounce timer MUST remain stopped during a full UI sync. Ensures no initialization sound storms."
	)
