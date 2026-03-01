## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_audio_reset_button.gd
## GUT unit tests for audio_settings.gd reset button functionality.
## Covers TC-Reset-01 to TC-Reset-06 from test plan.
## Test Plan:
## https://github.com/ikostan/SkyLockAssault/issues/294

extends "res://addons/gut/test.gd"

var audio_scene: PackedScene = load("res://scenes/audio_settings.tscn")
var audio_instance: Control
var test_config_path: String = "user://test_reset.cfg"


## Per-test setup: Reset state, load defaults
## :rtype: void
func before_each() -> void:
	if FileAccess.file_exists(test_config_path):
		DirAccess.remove_absolute(test_config_path)
	AudioManager.master_muted = false
	AudioManager.music_muted = false
	AudioManager.sfx_muted = false
	AudioManager.weapon_muted = false
	AudioManager.rotors_muted = false
	AudioManager.master_volume = 1.0
	AudioManager.music_volume = 1.0
	AudioManager.sfx_volume = 1.0
	AudioManager.weapon_volume = 1.0
	AudioManager.rotors_volume = 1.0
	AudioManager.apply_all_volumes()  # Sync buses early
	AudioManager.load_volumes(test_config_path)  # Load if exists (should be defaults)
	AudioManager.current_config_path = test_config_path  # Add this line
	# Add audio buses if not exist
	if AudioServer.get_bus_index(AudioConstants.BUS_MASTER) == -1:
		AudioServer.add_bus(0)
		AudioServer.set_bus_name(0, AudioConstants.BUS_MASTER)
	if AudioServer.get_bus_index(AudioConstants.BUS_MUSIC) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, AudioConstants.BUS_MUSIC)
	if AudioServer.get_bus_index(AudioConstants.BUS_SFX) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, AudioConstants.BUS_SFX)
	if AudioServer.get_bus_index(AudioConstants.BUS_SFX_WEAPON) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, AudioConstants.BUS_SFX_WEAPON)
	if AudioServer.get_bus_index(AudioConstants.BUS_SFX_ROTORS) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, AudioConstants.BUS_SFX_ROTORS)


## Per-test cleanup: Remove test config if exists
## :rtype: void
func after_each() -> void:
	if is_instance_valid(audio_instance):
		if is_instance_valid(audio_instance.master_warning_dialog):
			audio_instance.master_warning_dialog.hide()
		if is_instance_valid(audio_instance.sfx_warning_dialog):
			audio_instance.sfx_warning_dialog.hide()
		if audio_instance.get_parent() == self:
			remove_child(audio_instance)  # If not already
		audio_instance.queue_free()
	audio_instance = null
	if FileAccess.file_exists(test_config_path):
		DirAccess.remove_absolute(test_config_path)
	await get_tree().process_frame  # Wait for free to process


## TC-Reset-01 | All audio buses muted; All volumes set to 0.5; UI reflects this. | Click the Reset button. | All muted flags false; All volumes 1.0; apply_all_volumes/save_volumes called; UI updated: all mute buttons pressed, all sliders 1.0 and editable; _update_other_controls_ui called; Log message.
## :rtype: void
func test_tc_reset_01() -> void:
	AudioManager.master_muted = true
	AudioManager.music_muted = true
	AudioManager.sfx_muted = true
	AudioManager.weapon_muted = true
	AudioManager.rotors_muted = true
	AudioManager.master_volume = 0.5
	AudioManager.music_volume = 0.5
	AudioManager.sfx_volume = 0.5
	AudioManager.weapon_volume = 0.5
	AudioManager.rotors_volume = 0.5
	AudioManager.apply_all_volumes()
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	await get_tree().process_frame
	# Verify initial UI
	assert_false(audio_instance.mute_master.button_pressed)
	assert_eq(audio_instance.master_slider.value, 0.5)
	assert_false(audio_instance.master_slider.editable)
	assert_false(audio_instance.mute_sfx.button_pressed)
	assert_false(audio_instance.weapon_slider.editable)
	# Simulate reset button press
	audio_instance._on_audio_reset_button_pressed()
	# Check AudioManager states
	assert_false(AudioManager.master_muted)
	assert_false(AudioManager.music_muted)
	assert_false(AudioManager.sfx_muted)
	assert_false(AudioManager.weapon_muted)
	assert_false(AudioManager.rotors_muted)
	assert_eq(AudioManager.master_volume, 1.0)
	assert_eq(AudioManager.music_volume, 1.0)
	assert_eq(AudioManager.sfx_volume, 1.0)
	assert_eq(AudioManager.weapon_volume, 1.0)
	assert_eq(AudioManager.rotors_volume, 1.0)
	# Check AudioServer
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index(AudioConstants.BUS_MASTER)))
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(AudioConstants.BUS_MASTER)), linear_to_db(1.0), 0.0001)
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index(AudioConstants.BUS_MUSIC)))
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(AudioConstants.BUS_MUSIC)), linear_to_db(1.0), 0.0001)
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index(AudioConstants.BUS_SFX)))
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(AudioConstants.BUS_SFX)), linear_to_db(1.0), 0.0001)
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index(AudioConstants.BUS_SFX_WEAPON)))
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(AudioConstants.BUS_SFX_WEAPON)), linear_to_db(1.0), 0.0001)
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index(AudioConstants.BUS_SFX_ROTORS)))
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(AudioConstants.BUS_SFX_ROTORS)), linear_to_db(1.0), 0.0001)
	# Check save called (file exists)
	assert_true(FileAccess.file_exists(test_config_path))
	# Check UI updated
	assert_true(audio_instance.mute_master.button_pressed)
	assert_eq(audio_instance.master_slider.value, 1.0)
	assert_true(audio_instance.master_slider.editable)
	assert_true(audio_instance.mute_music.button_pressed)
	assert_eq(audio_instance.music_slider.value, 1.0)
	assert_true(audio_instance.music_slider.editable)
	assert_true(audio_instance.mute_sfx.button_pressed)
	assert_eq(audio_instance.sfx_slider.value, 1.0)
	assert_true(audio_instance.sfx_slider.editable)
	assert_true(audio_instance.mute_weapon.button_pressed)
	assert_eq(audio_instance.weapon_slider.value, 1.0)
	assert_true(audio_instance.weapon_slider.editable)
	assert_true(audio_instance.mute_rotor.button_pressed)
	assert_eq(audio_instance.rotor_slider.value, 1.0)
	assert_true(audio_instance.rotor_slider.editable)
	# Check child controls enabled
	assert_false(audio_instance.mute_weapon.disabled)
	assert_false(audio_instance.mute_rotor.disabled)


## TC-Reset-02 | Mixed states: Master unmuted, Music muted, SFX unmuted, Weapon muted, Rotors unmuted; Volumes varied; UI reflects this. | Click the Reset button. | All muted flags false; All volumes 1.0; apply_all_volumes/save_volumes called; UI updated: all mute buttons pressed, all sliders 1.0 and editable; _update_other_controls_ui called; Log message.
## :rtype: void
func test_tc_reset_02() -> void:
	AudioManager.master_muted = false
	AudioManager.music_muted = true
	AudioManager.sfx_muted = false
	AudioManager.weapon_muted = true
	AudioManager.rotors_muted = false
	AudioManager.master_volume = 0.8
	AudioManager.music_volume = 0.3
	AudioManager.sfx_volume = 0.6
	AudioManager.weapon_volume = 0.4
	AudioManager.rotors_volume = 0.7
	AudioManager.apply_all_volumes()
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	await get_tree().process_frame
	# Verify initial
	assert_true(audio_instance.mute_master.button_pressed)
	assert_false(audio_instance.mute_music.button_pressed)
	assert_true(audio_instance.mute_sfx.button_pressed)
	assert_false(audio_instance.mute_weapon.button_pressed)
	assert_true(audio_instance.mute_rotor.button_pressed)
	assert_eq(audio_instance.master_slider.value, 0.8)
	assert_eq(audio_instance.music_slider.value, 0.3)
	assert_eq(audio_instance.sfx_slider.value, 0.6)
	assert_eq(audio_instance.weapon_slider.value, 0.4)
	assert_eq(audio_instance.rotor_slider.value, 0.7)
	assert_false(audio_instance.weapon_slider.editable)
	assert_true(audio_instance.rotor_slider.editable)
	# Reset
	audio_instance._on_audio_reset_button_pressed()
	# Checks
	assert_false(AudioManager.master_muted)
	assert_false(AudioManager.music_muted)
	assert_false(AudioManager.sfx_muted)
	assert_false(AudioManager.weapon_muted)
	assert_false(AudioManager.rotors_muted)
	assert_eq(AudioManager.master_volume, 1.0)
	assert_eq(AudioManager.music_volume, 1.0)
	assert_eq(AudioManager.sfx_volume, 1.0)
	assert_eq(AudioManager.weapon_volume, 1.0)
	assert_eq(AudioManager.rotors_volume, 1.0)
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index(AudioConstants.BUS_MASTER)))
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(AudioConstants.BUS_MASTER)), linear_to_db(1.0), 0.0001)
	assert_true(FileAccess.file_exists(test_config_path))
	assert_true(audio_instance.mute_master.button_pressed)
	assert_eq(audio_instance.master_slider.value, 1.0)
	assert_true(audio_instance.master_slider.editable)
	assert_false(audio_instance.mute_weapon.disabled)
	assert_false(audio_instance.mute_rotor.disabled)


## TC-Reset-03 | All already at defaults: All muted=false, all volumes=1.0; UI reflects this. | Click the Reset button. | No state changes; apply_all_volumes/save_volumes called; UI unchanged; _update_other_controls_ui called; Log message.
## :rtype: void
func test_tc_reset_03() -> void:
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	await get_tree().process_frame
	# Initial defaults
	assert_false(AudioManager.master_muted)
	assert_eq(AudioManager.master_volume, 1.0)
	assert_true(audio_instance.mute_master.button_pressed)
	assert_eq(audio_instance.master_slider.value, 1.0)
	assert_true(audio_instance.master_slider.editable)
	# Reset
	audio_instance._on_audio_reset_button_pressed()
	# Still same
	assert_false(AudioManager.master_muted)
	assert_eq(AudioManager.master_volume, 1.0)
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index(AudioConstants.BUS_MASTER)))
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(AudioConstants.BUS_MASTER)), linear_to_db(1.0), 0.0001)
	assert_true(FileAccess.file_exists(test_config_path))
	assert_true(audio_instance.mute_master.button_pressed)
	assert_eq(audio_instance.master_slider.value, 1.0)
	assert_true(audio_instance.master_slider.editable)


## TC-Reset-04 | Master muted, disabling others; Others mixed; Volumes 0.5; UI: master mute unpressed, master slider not editable, others disabled/not editable. | Click the Reset button. | All muted false; All volumes 1.0; apply/save called; UI: all mute pressed, sliders 1.0 editable; child controls enabled; Log message.
## :rtype: void
func test_tc_reset_04() -> void:
	AudioManager.master_muted = true
	AudioManager.music_muted = false
	AudioManager.sfx_muted = true
	AudioManager.weapon_muted = false
	AudioManager.rotors_muted = true
	AudioManager.master_volume = 0.5
	AudioManager.music_volume = 0.5
	AudioManager.sfx_volume = 0.5
	AudioManager.weapon_volume = 0.5
	AudioManager.rotors_volume = 0.5
	AudioManager.apply_all_volumes()
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	await get_tree().process_frame
	# Initial
	assert_false(audio_instance.mute_master.button_pressed)
	assert_false(audio_instance.master_slider.editable)
	assert_true(audio_instance.mute_music.disabled)
	assert_false(audio_instance.music_slider.editable)
	assert_true(audio_instance.mute_sfx.disabled)
	assert_false(audio_instance.sfx_slider.editable)
	# Reset
	audio_instance._on_audio_reset_button_pressed()
	# Checks
	assert_false(AudioManager.master_muted)
	assert_true(audio_instance.mute_master.button_pressed)
	assert_true(audio_instance.master_slider.editable)
	assert_false(audio_instance.mute_music.disabled)
	assert_true(audio_instance.music_slider.editable)


## TC-Reset-05 | SFX muted, disabling weapon/rotors; Master unmuted, Music unmuted; Volumes 0.2; UI: sfx mute unpressed, sfx slider not editable, weapon/rotors disabled/not editable. | Click the Reset button. | All reset to unmuted 1.0; apply/save called; UI enabled; Log message.
## :rtype: void
func test_tc_reset_05() -> void:
	AudioManager.master_muted = false
	AudioManager.music_muted = false
	AudioManager.sfx_muted = true
	AudioManager.weapon_muted = false
	AudioManager.rotors_muted = false
	AudioManager.master_volume = 0.2
	AudioManager.music_volume = 0.2
	AudioManager.sfx_volume = 0.2
	AudioManager.weapon_volume = 0.2
	AudioManager.rotors_volume = 0.2
	AudioManager.apply_all_volumes()
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	await get_tree().process_frame
	# Initial
	assert_false(audio_instance.mute_sfx.button_pressed)
	assert_false(audio_instance.sfx_slider.editable)
	assert_true(audio_instance.mute_weapon.disabled)
	assert_false(audio_instance.weapon_slider.editable)
	assert_true(audio_instance.mute_rotor.disabled)
	assert_false(audio_instance.rotor_slider.editable)
	# Reset
	audio_instance._on_audio_reset_button_pressed()
	# Checks
	assert_false(AudioManager.sfx_muted)
	assert_eq(AudioManager.sfx_volume, 1.0)
	assert_true(audio_instance.mute_sfx.button_pressed)
	assert_true(audio_instance.sfx_slider.editable)
	assert_false(audio_instance.mute_weapon.disabled)
	assert_true(audio_instance.weapon_slider.editable)


## TC-Reset-06 | Config has non-defaults; Initial reflects config. | Click Reset. | Defaults override; save overwrites config; UI/AudioServer updated; Log message.
## :rtype: void
func test_tc_reset_06() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "master_muted", true)
	config.set_value("audio", "music_muted", true)
	config.set_value("audio", "sfx_muted", true)
	config.set_value("audio", "weapon_muted", true)
	config.set_value("audio", "rotors_muted", true)
	config.set_value("audio", "master_volume", 0.4)
	config.set_value("audio", "music_volume", 0.4)
	config.set_value("audio", "sfx_volume", 0.4)
	config.set_value("audio", "weapon_volume", 0.4)
	config.set_value("audio", "rotors_volume", 0.4)
	config.save(test_config_path)
	AudioManager.load_volumes(test_config_path)
	AudioManager.apply_all_volumes()
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	await get_tree().process_frame
	# Verify initial from config
	assert_true(AudioManager.master_muted)
	assert_eq(AudioManager.master_volume, 0.4)
	assert_false(audio_instance.mute_master.button_pressed)
	assert_eq(audio_instance.master_slider.value, 0.4)
	# Reset
	audio_instance._on_audio_reset_button_pressed()
	# Checks
	assert_false(AudioManager.master_muted)
	assert_eq(AudioManager.master_volume, 1.0)
	# Check config overwritten
	config = ConfigFile.new()
	config.load(test_config_path)
	assert_false(config.get_value("audio", "master_muted", true))
	assert_eq(config.get_value("audio", "master_volume", 0.0), 1.0)
