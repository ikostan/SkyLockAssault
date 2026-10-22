## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_audio_settings_comprehensive.gd
##
## Comprehensive verification suite for Feature Task #724.
## Validates focus-driven auto-mute threshold loops without timing fragility.

extends "res://addons/gut/test.gd"

var audio_scene: PackedScene = load(GamePaths.AUDIO_SETTINGS_SCENE)
var audio_instance: Control


## Pre-test lifecycle configuration ensuring isolated test bounds
## :rtype: void
func before_each() -> void:
	Globals.set_test_encryption_key()
	
	for bus: String in AudioConstants.BUS_CONFIG.keys():
		var bus_name: String = bus
		AudioManager.set_volume(bus_name, 1.0)
		AudioManager.set_muted(bus_name, false)
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
	for player in SfxManager._sfx_pool:
		var p: AudioStreamPlayer = player
		p.stop()
		p.stream = null


## Inspects if any object channel within the player pool is actively streaming audio bytes
## :rtype: bool
func _is_sound_playing() -> bool:
	for player in SfxManager._sfx_pool:
		var p: AudioStreamPlayer = player
		if p.playing:
			return true
	return false


## Helper to dynamically calculate safety wait margins from shared AudioConstants
## :rtype: float
func _get_safety_wait_time() -> float:
	var delay: float = AudioConstants.MUTE_HARDWARE_DELAY
	return delay + 0.05

# ==========================================================================
# 1. MANUAL INTERACTION BOUNDS WITH EPSILON (TC-AM-001 to TC-AM-006)
# ==========================================================================

func test_tc_am_001_master_manual_mute() -> void:
	var slider: HSlider = audio_instance.master_slider
	var button: CheckButton = audio_instance.mute_master
	var wait_time: float = _get_safety_wait_time()
	slider.grab_focus()
	_clear_pool_players()
	
	# Test using the exact epsilon boundary instead of absolute 0.0
	var threshold: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD
	AudioManager.set_volume(AudioConstants.BUS_MASTER, threshold)
	await get_tree().create_timer(wait_time).timeout
	
	assert_true(AudioManager.get_muted(AudioConstants.BUS_MASTER))
	assert_false(button.button_pressed)
	assert_true(_is_sound_playing())


func test_tc_am_002_music_manual_mute() -> void:
	var slider: HSlider = audio_instance.music_slider
	var button: CheckButton = audio_instance.mute_music
	slider.grab_focus()
	_clear_pool_players()
	
	var threshold: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD
	AudioManager.set_volume(AudioConstants.BUS_MUSIC, threshold)
	await get_tree().process_frame
	
	assert_true(AudioManager.get_muted(AudioConstants.BUS_MUSIC))
	assert_false(button.button_pressed)
	assert_true(_is_sound_playing())


func test_tc_am_003_sfx_manual_mute() -> void:
	var slider: HSlider = audio_instance.sfx_slider
	var button: CheckButton = audio_instance.mute_sfx
	slider.grab_focus()
	_clear_pool_players()
	
	var threshold: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD
	AudioManager.set_volume(AudioConstants.BUS_SFX, threshold)
	await get_tree().process_frame
	
	assert_true(AudioManager.get_muted(AudioConstants.BUS_SFX))
	assert_false(button.button_pressed)
	assert_true(_is_sound_playing())


func test_tc_am_004_weapon_manual_mute() -> void:
	var slider: HSlider = audio_instance.weapon_slider
	var button: CheckButton = audio_instance.mute_weapon
	slider.grab_focus()
	_clear_pool_players()
	
	var threshold: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD
	AudioManager.set_volume(AudioConstants.BUS_SFX_WEAPON, threshold)
	await get_tree().process_frame
	
	assert_true(AudioManager.get_muted(AudioConstants.BUS_SFX_WEAPON))
	assert_false(button.button_pressed)
	assert_true(_is_sound_playing())


func test_tc_am_005_rotors_manual_mute() -> void:
	var slider: HSlider = audio_instance.rotor_slider
	var button: CheckButton = audio_instance.mute_rotor
	slider.grab_focus()
	_clear_pool_players()
	
	var threshold: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD
	AudioManager.set_volume(AudioConstants.BUS_SFX_ROTORS, threshold)
	await get_tree().process_frame
	
	assert_true(AudioManager.get_muted(AudioConstants.BUS_SFX_ROTORS))
	assert_false(button.button_pressed)
	assert_true(_is_sound_playing())


func test_tc_am_006_menu_manual_mute() -> void:
	var slider: HSlider = audio_instance.menu_slider
	var button: CheckButton = audio_instance.mute_menu
	slider.grab_focus()
	_clear_pool_players()
	
	var threshold: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD
	AudioManager.set_volume(AudioConstants.BUS_SFX_MENU, threshold)
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
	var wait_time: float = _get_safety_wait_time()
	if slider.has_focus():
		slider.release_focus()
	_clear_pool_players()
	
	var threshold: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD
	AudioManager.set_volume(AudioConstants.BUS_MASTER, threshold)
	await get_tree().create_timer(wait_time).timeout
	
	assert_true(AudioManager.get_muted(AudioConstants.BUS_MASTER))
	assert_false(button.button_pressed)
	assert_false(_is_sound_playing())


func test_tc_am_008_music_automation_silence() -> void:
	var slider: HSlider = audio_instance.music_slider
	var button: CheckButton = audio_instance.mute_music
	if slider.has_focus():
		slider.release_focus()
	_clear_pool_players()
	
	var threshold: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD
	AudioManager.set_volume(AudioConstants.BUS_MUSIC, threshold)
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
	
	var threshold: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD
	AudioManager.set_volume(AudioConstants.BUS_SFX, threshold)
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
	
	var threshold: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD
	AudioManager.set_volume(AudioConstants.BUS_SFX_WEAPON, threshold)
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
	
	var threshold: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD
	AudioManager.set_volume(AudioConstants.BUS_SFX_ROTORS, threshold)
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
	
	var threshold: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD
	AudioManager.set_volume(AudioConstants.BUS_SFX_MENU, threshold)
	await get_tree().process_frame
	
	assert_true(AudioManager.get_muted(AudioConstants.BUS_SFX_MENU))
	assert_false(button.button_pressed)
	assert_false(_is_sound_playing())


# ==========================================================================
# 3. BOUNDARY CONTROL & IDEMPOTENCY (TC-AM-013)
# ==========================================================================

func test_tc_am_013_idempotent_zero_update() -> void:
	var slider: HSlider = audio_instance.master_slider
	var wait_time: float = _get_safety_wait_time()
	if slider.has_focus():
		slider.release_focus()
		
	var threshold: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD
	AudioManager.set_volume(AudioConstants.BUS_MASTER, threshold)
	await get_tree().create_timer(wait_time).timeout
	_clear_pool_players()
	
	# Emit duplicate near-zero update
	AudioManager.volume_changed.emit(AudioConstants.BUS_MASTER, 0.0)
	await get_tree().process_frame
	
	assert_false(_is_sound_playing(), "Redundant threshold signals must remain silent.")


# ==========================================================================
# 4. UPWARD CYCLE TRANSITIONS (TC-AM-014)
# ==========================================================================

func test_tc_am_014_upward_unmute_transition() -> void:
	var slider: HSlider = audio_instance.master_slider
	var button: CheckButton = audio_instance.mute_master
	var wait_time: float = _get_safety_wait_time()
	slider.grab_focus()
	
	var threshold: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD
	AudioManager.set_volume(AudioConstants.BUS_MASTER, threshold)
	await get_tree().create_timer(wait_time).timeout
	_clear_pool_players()
	
	# Transition upward clear of the threshold target limit
	var high_vol: float = threshold + 0.15
	AudioManager.set_volume(AudioConstants.BUS_MASTER, high_vol)
	await get_tree().process_frame
	
	assert_false(AudioManager.get_muted(AudioConstants.BUS_MASTER))
	assert_true(button.button_pressed)


# ==========================================================================
# 5. MASTER FEEDBACK HOLD (TC-AM-015 to TC-AM-016)
# ==========================================================================

func test_tc_am_015_master_feedback_hold_then_silence() -> void:
	var slider: HSlider = audio_instance.master_slider
	var bus_idx: int = AudioServer.get_bus_index(AudioConstants.BUS_MASTER)
	var hold_db: float = linear_to_db(AudioConstants.FEEDBACK_HOLD_VOLUME_LINEAR)
	slider.grab_focus()

	AudioManager.set_volume(AudioConstants.BUS_MASTER, AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD)

	# During the hardware delay the Master bus is held audible for the click
	assert_almost_eq(AudioServer.get_bus_volume_db(bus_idx), hold_db, 0.0001)

	await get_tree().create_timer(_get_safety_wait_time()).timeout

	# After the delay AudioServer is re-synced from AudioManager (Issue #1041): muted, at the
	# stored near-zero volume, instead of a hard-coded 0.0 write
	assert_true(AudioServer.is_bus_mute(bus_idx), "Master is muted in AudioServer")
	assert_almost_eq(
		AudioServer.get_bus_volume_db(bus_idx),
		linear_to_db(AudioManager.get_volume(AudioConstants.BUS_MASTER)),
		0.0001
	)


func test_tc_am_016_master_hold_aborted_by_newer_drag() -> void:
	var slider: HSlider = audio_instance.master_slider
	var bus_idx: int = AudioServer.get_bus_index(AudioConstants.BUS_MASTER)
	var restored_vol: float = 0.5
	slider.grab_focus()

	AudioManager.set_volume(AudioConstants.BUS_MASTER, AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD)
	# Drag back up before the hold expires: the token gate must cancel the zeroing
	AudioManager.set_volume(AudioConstants.BUS_MASTER, restored_vol)

	await get_tree().create_timer(_get_safety_wait_time()).timeout

	assert_false(AudioManager.get_muted(AudioConstants.BUS_MASTER))
	assert_almost_eq(AudioServer.get_bus_volume_db(bus_idx), linear_to_db(restored_vol), 0.0001)
	assert_false(AudioServer.is_bus_mute(bus_idx), "The late re-sync applies the newer drag")


# ==========================================================================
# 6. AUDIOSERVER RE-SYNC (Issue #1041)
# ==========================================================================

## Every bus the menu auto-mutes is muted in AudioServer too, focused or not.
## :rtype: void
func test_menu_auto_mute_syncs_hardware_mute(
	params: Array = use_parameters(
		[
			[AudioConstants.BUS_MASTER, true],
			[AudioConstants.BUS_MASTER, false],
			[AudioConstants.BUS_MUSIC, true],
			[AudioConstants.BUS_SFX, false],
			[AudioConstants.BUS_SFX_WEAPON, true],
			[AudioConstants.BUS_SFX_ROTORS, false],
			[AudioConstants.BUS_SFX_MENU, true],
		]
	)
) -> void:
	var bus: String = params[0]
	var focused: bool = params[1]
	var slider: HSlider = audio_instance._get_slider_for_bus(bus)
	if focused:
		slider.grab_focus()
	elif slider.has_focus():
		slider.release_focus()
	var bus_idx: int = AudioServer.get_bus_index(bus)

	AudioManager.set_volume(bus, 0.0)
	await get_tree().create_timer(_get_safety_wait_time()).timeout

	assert_true(AudioManager.get_muted(bus))
	assert_eq(AudioServer.is_bus_mute(bus_idx), AudioManager.get_muted(bus), bus + " in sync")


## Raising an auto-muted bus clears the AudioServer mute on every bus, not only Master.
## :rtype: void
func test_menu_auto_unmute_clears_hardware_mute(
	bus: String = use_parameters(AudioConstants.BUS_CONFIG.keys())
) -> void:
	var slider: HSlider = audio_instance._get_slider_for_bus(bus)
	if slider.has_focus():
		slider.release_focus()
	var bus_idx: int = AudioServer.get_bus_index(bus)
	AudioManager.set_volume(bus, 0.0)
	await get_tree().create_timer(_get_safety_wait_time()).timeout
	assert_true(AudioServer.is_bus_mute(bus_idx), "Precondition: hardware muted")

	AudioManager.set_volume(bus, 0.4)
	await get_tree().process_frame

	assert_false(AudioManager.get_muted(bus))
	assert_false(AudioServer.is_bus_mute(bus_idx), bus + " must be audible in AudioServer")
	assert_almost_eq(AudioServer.get_bus_volume_db(bus_idx), linear_to_db(0.4), 0.0001)


## The mute button unmuting Master during the hold wins over the stale timer, with no token.
## :rtype: void
func test_menu_master_button_unmute_during_hold_wins() -> void:
	var bus: String = AudioConstants.BUS_MASTER
	var bus_idx: int = AudioServer.get_bus_index(bus)
	audio_instance.master_slider.grab_focus()

	AudioManager.set_volume(bus, 0.0)
	await AudioManager.toggle_mute(bus, false, false)
	await get_tree().create_timer(_get_safety_wait_time()).timeout

	assert_false(AudioManager.get_muted(bus))
	assert_false(AudioServer.is_bus_mute(bus_idx), "Stale hold re-applied the unmuted state")
	assert_gt(AudioServer.get_bus_volume_db(bus_idx), linear_to_db(0.0), "Master is audible")
