## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_audio_signal_decoupling.gd
##
## Automation test suite verifying that programmatic audio changes 
## execute in absolute silence without triggering UI feedback sounds.

extends "res://addons/gut/test.gd"

var audio_scene: PackedScene = load(GamePaths.AUDIO_SETTINGS_SCENE)
var audio_instance: Control


## Per-test setup: Initialize environment keys and instantiate UI components
## :rtype: void
func before_each() -> void:
	Globals.set_test_encryption_key()
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	await get_tree().process_frame


## Per-test cleanup: Free instances safely
## :rtype: void
func after_each() -> void:
	if is_instance_valid(audio_instance):
		audio_instance.queue_free()
	audio_instance = null


## Negative Validation | Verifies that programmatic updates via AudioManager execute in complete silence.
## :rtype: void
func test_programmatic_mute_propagation_is_silent() -> void:
	# Release any accidental tree focus to ensure a clean automated state environment
	if get_viewport().gui_get_focus_owner():
		get_viewport().gui_get_focus_owner().release_focus()
		
	# Force silence on the existing player pool tracks
	for player: AudioStreamPlayer in AudioManager._sfx_pool:
		player.stop()

	# Simulate an inbound programmatic sync sequence (like WebBridge or Playwright driver data)
	AudioManager.set_muted(AudioConstants.BUS_MASTER, true)
	await get_tree().process_frame

	var sound_triggered: bool = false
	for player: AudioStreamPlayer in AudioManager._sfx_pool:
		if player.playing:
			sound_triggered = true
			break

	assert_false(sound_triggered, "Decoupling Verification Failed: Programmatic state mutations leaked an audio artifact!")
