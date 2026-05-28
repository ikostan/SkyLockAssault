## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_audio_settings_comprehensive.gd
##
## Comprehensive verification suite for Feature Task #724.
## Validates the user focus-driven auto-mute threshold loops, 
## idempotency constraints, and upward unmute state machine cycles.

extends "res://addons/gut/test.gd"

var audio_scene: PackedScene = load(GamePaths.AUDIO_SETTINGS_SCENE)
var audio_instance: Control


## Pre-test lifecycle configuration ensuring isolated test bounds
## :rtype: void
func before_each() -> void:
	Globals.set_test_encryption_key()
	
	# Force baseline reset on all global tracking parameters
	for bus: String in AudioConstants.BUS_CONFIG.keys():
		AudioManager.set_volume(bus, 1.0)
		AudioManager.set_muted(bus, false)
	AudioManager.apply_all_volumes()
	
	_clear_pool_players()
	
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	await get_tree().process_frame


## Post-test lifecycle cleanup routine
## :rtype: void
func after_each() -> void:
	_clear_pool_players()
	if is_instance_valid(audio_instance):
		audio_instance.queue_free()
	audio_instance = null
	await get_tree().process_frame


## Silences active audio signals and strips streams from the reuse pool
## :rtype: void
func _clear_pool_players() -> void:
	for player: AudioStreamPlayer in AudioManager._sfx_pool:
		player.stop()
		player.stream = null


## Inspects if any object channel within the player pool is actively streaming audio bytes
## :rtype: bool
func _is_sound_playing() -> bool:
	for player: AudioStreamPlayer in AudioManager._sfx_pool:
		if player.playing:
			return true
	return false


# ==========================================================================
# 1. MANUAL INTERACTION BOUNDS (TC-AM-001 to TC-AM-006)
# ==========================================================================

func test_tc_am_001_master_manual_mute() -> void:
	var slider: HSlider = audio_instance.master_slider
	var button: CheckButton = audio_instance.mute_master
	slider.grab_focus()
	_clear_pool_players()
	
	AudioManager.set_volume(AudioConstants.BUS_MASTER, 0.0)
	await get_tree().create_timer(0.2).timeout
	
	assert_true(AudioManager.get_muted(AudioConstants.BUS_MASTER))
	assert_false(button.button_pressed)
	assert_true(_is_sound_playing())


func test_tc_am_002_music_manual_mute() -> void:
	var slider: HSlider = audio_instance.music_slider
	var button: CheckButton = audio_instance.mute_music
	slider.grab_focus()
	_clear_pool_players()
	
	AudioManager.set_volume(AudioConstants.BUS_MUSIC, 0.0)
	await get_tree().process_frame
	
	assert_true(AudioManager.get_muted(AudioConstants.BUS_MUSIC))
	assert_false(button.button_pressed)
	assert_true(_is_sound_playing())


func test_tc_am_003_sfx_manual_mute() -> void:
	var slider: HSlider = audio_instance.sfx_slider
	var button: CheckButton = audio_instance.mute_sfx
	slider.grab_focus()
	_clear_pool_players()
	
	AudioManager.set_volume(AudioConstants.BUS_SFX, 0.0)
	await get_tree().process_frame
	
	assert_true(AudioManager.get_muted(AudioConstants.BUS_SFX))
	assert_false(button.button_pressed)
	assert_true(_is_sound_playing())


func test_tc_am_004_weapon_manual_mute() -> void:
	var slider: HSlider = audio_instance.weapon_slider
	var button: CheckButton = audio_instance.mute_weapon
	slider.grab_focus()
	_clear_pool_players()
	
	AudioManager.set_volume(AudioConstants.BUS_SFX_WEAPON, 0.0)
	await get_tree().process_frame
	
	assert_true(AudioManager.get_muted(AudioConstants.BUS_SFX_WEAPON))
	assert_false(button.button_pressed)
	assert_true(_is_sound_playing())


func test_tc_am_005_rotors_manual_mute() -> void:
	var slider: HSlider = audio_instance.rotor_slider
	var button: CheckButton = audio_instance.mute_rotor
	slider.grab_focus()
	_clear_pool_players()
	
	AudioManager.set_volume(AudioConstants.BUS_SFX_ROTORS, 0.0)
	await get_tree().process_frame
	
	assert_true(AudioManager.get_muted(AudioConstants.BUS_SFX_ROTORS))
	assert_false(button.button_pressed)
	assert_true(_is_sound_playing())


func test_tc_am_006_menu_manual_mute() -> void:
	var slider: HSlider = audio_instance.menu_slider
	var button: CheckButton = audio_instance.mute_menu
	slider.grab_focus()
	_clear_pool_players()
	
	AudioManager.set_volume(AudioConstants.BUS_SFX_MENU, 0.0)
	await get_tree().process_frame
	
	assert_true(AudioManager.get_muted(AudioConstants.BUS_SFX_MENU))
	assert_false(button.button_pressed)
	assert_true(_is_sound_playing())


# ==========================================================================
# 2. AUTOMATION SYNC ISOLATION (TC-AM-007 to TC-AM-012)
# ==========================================================================

func test_tc_am_007_master_automation_silence() -> void:
	var slider: HSlider = audio_instance.master_slider
	var button: CheckButton = audio_instance.mute_master
	if slider.has_focus():
		slider.release_focus()
	_clear_pool_players()
	
	AudioManager.set_volume(AudioConstants.BUS_MASTER, 0.0)
	await get_tree().create_timer(0.2).timeout
	
	assert_true(AudioManager.get_muted(AudioConstants.BUS_MASTER))
	assert_false(button.button_pressed)
	assert_false(_is_sound_playing())


func test_tc_am_008_music_automation_silence() -> void:
	var slider: HSlider = audio_instance.music_slider
	var button: CheckButton = audio_instance.mute_music
	if slider.has_focus():
		slider.release_focus()
	_clear_pool_players()
	
	AudioManager.set_volume(AudioConstants.BUS_MUSIC, 0.0)
	await get_tree().process_frame
	
	assert_true(AudioManager.get_muted(AudioConstants.BUS_MUSIC))
	assert_false(button.button_pressed)
	assert_false(_is_sound_playing())


func test_tc_am_009_sfx_automation_silence() -> void:
	var slider: HSlider = audio_instance.sfx_slider
	var button: CheckButton = audio_instance.mute_sfx
	if slider.has_focus():
		slider.release_focus()
	_clear_pool_players()
	
	AudioManager.set_volume(AudioConstants.BUS_SFX, 0.0)
	await get_tree().process_frame
	
	assert_true(AudioManager.get_muted(AudioConstants.BUS_SFX))
	assert_false(button.button_pressed)
	assert_false(_is_sound_playing())


func test_tc_am_010_weapon_automation_silence() -> void:
	var slider: HSlider = audio_instance.weapon_slider
	var button: CheckButton = audio_instance.mute_weapon
	if slider.has_focus():
		slider.release_focus()
	_clear_pool_players()
	
	AudioManager.set_volume(AudioConstants.BUS_SFX_WEAPON, 0.0)
	await get_tree().process_frame
	
	assert_true(AudioManager.get_muted(AudioConstants.BUS_SFX_WEAPON))
	assert_false(button.button_pressed)
	assert_false(_is_sound_playing())


func test_tc_am_011_rotors_automation_silence() -> void:
	var slider: HSlider = audio_instance.rotor_slider
	var button: CheckButton = audio_instance.mute_rotor
	if slider.has_focus():
		slider.release_focus()
	_clear_pool_players()
	
	AudioManager.set_volume(AudioConstants.BUS_SFX_ROTORS, 0.0)
	await get_tree().process_frame
	
	assert_true(AudioManager.get_muted(AudioConstants.BUS_SFX_ROTORS))
	assert_false(button.button_pressed)
	assert_false(_is_sound_playing())


func test_tc_am_012_menu_automation_silence() -> void:
	var slider: HSlider = audio_instance.menu_slider
	var button: CheckButton = audio_instance.mute_menu
	if slider.has_focus():
		slider.release_focus()
	_clear_pool_players()
	
	AudioManager.set_volume(AudioConstants.BUS_SFX_MENU, 0.0)
	await get_tree().process_frame
	
	assert_true(AudioManager.get_muted(AudioConstants.BUS_SFX_MENU))
	assert_false(button.button_pressed)
	assert_false(_is_sound_playing())


# ==========================================================================
# 3. BOUNDARY CONTROL & IDEMPOTENCY (TC-AM-013)
# ==========================================================================

func test_tc_am_013_idempotent_zero_update() -> void:
	var slider: HSlider = audio_instance.master_slider
	if slider.has_focus():
		slider.release_focus()
		
	# Initial auto-mute transition
	AudioManager.set_volume(AudioConstants.BUS_MASTER, 0.0)
	await get_tree().create_timer(0.2).timeout
	_clear_pool_players()
	
	# Emit duplicate/redundant programmatic 0.0 value event payload
	AudioManager.volume_changed.emit(AudioConstants.BUS_MASTER, 0.0)
	await get_tree().process_frame
	
	assert_false(_is_sound_playing(), "Redundant zero signals must not fire audio clips.")


# ==========================================================================
# 4. UPWARD CYCLE TRANSITIONS (TC-AM-014)
# ==========================================================================

func test_tc_am_014_upward_unmute_transition() -> void:
	var slider: HSlider = audio_instance.master_slider
	var button: CheckButton = audio_instance.mute_master
	slider.grab_focus()
	
	# Drive to absolute zero to trip the initial auto-mute condition
	AudioManager.set_volume(AudioConstants.BUS_MASTER, 0.0)
	await get_tree().create_timer(0.2).timeout
	_clear_pool_players()
	
	# Slide the tracker back upward past the zero threshold boundary
	AudioManager.set_volume(AudioConstants.BUS_MASTER, 0.15)
	await get_tree().process_frame
	
	assert_false(AudioManager.get_muted(AudioConstants.BUS_MASTER), "Upward volume change must naturally unset the mute state.")
	assert_true(button.button_pressed, "The CheckButton widget must visually toggle back to checked.")
