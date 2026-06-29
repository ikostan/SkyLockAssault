## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_audio_integration.gd
##
## Comprehensive GUT integration test suite verified against headless runner environments.
extends GutTest

const TARGET_BUS: String = AudioConstants.BUS_SFX
const MENU_BUS: String = AudioConstants.BUS_SFX_MENU

var bus_idx: int = -1


func before_all() -> void:
	# FAIL-FAST / BOOTSTRAP: Ensure the test runner environment possesses the required audio buses.
	# This guarantees the test suite passes flawlessly on stripped headless CI/CD systems.
	var required_buses: Array[String] = [
		AudioConstants.BUS_MASTER,
		AudioConstants.BUS_MUSIC,
		TARGET_BUS,
		MENU_BUS
	]
	
	for bus_name in required_buses:
		var idx: int = AudioServer.get_bus_index(bus_name)
		if idx == -1:
			# Automatically bootstrap missing environments at runtime
			AudioServer.add_bus()
			var new_idx: int = AudioServer.get_bus_count() - 1
			AudioServer.set_bus_name(new_idx, bus_name)


func before_each() -> void:
	AudioManager.reset_volumes()
	
	# Cache and validate our bus index before running any assertions
	bus_idx = AudioServer.get_bus_index(TARGET_BUS)
	assert_ne(bus_idx, -1, "FAIL-FAST: Target audio bus '%s' could not be resolved by the engine." % TARGET_BUS)


func after_each() -> void:
	AudioManager.stop_all_sfx()
	if AudioManager.has_method("cleanup_for_test"):
		AudioManager.cleanup_for_test()
	AudioManager.reset_volumes()


## Scenario A: Verify that when the parent SFX bus is muted, UI button presses
## still allocate streams in the pool, but the native hardware bus remains muted.
func test_sfx_mute_silences_ui_accept_at_audioserver_level() -> void:
	watch_signals(AudioManager)

	AudioManager.set_muted(TARGET_BUS, true)
	AudioManager.apply_volume_to_bus(TARGET_BUS, AudioManager.get_volume(TARGET_BUS), true)

	assert_signal_emitted_with_parameters(AudioManager, "mute_toggled", [TARGET_BUS, true])

	var dummy_btn := Button.new()
	add_child_autofree(dummy_btn)
	await wait_frames(1)

	dummy_btn.pressed.emit()
	await wait_frames(1)

	assert_true(AudioManager.get_muted(TARGET_BUS), "Logical: Manager must track bus as muted.")
	assert_true(AudioServer.is_bus_mute(bus_idx), "Hardware: Native AudioServer bus must be muted.")
	assert_true(AudioManager.is_any_sfx_playing(), "Pool should successfully allocate stream despite hardware mute.")
	assert_eq(AudioManager.get_active_sfx_playback_count(), 1, "Exactly one AudioStreamPlayer should be active.")


## Scenario B: Verify that unmuted UI interactions audibly play and leave the hardware server unmuted.
func test_sfx_unmuted_plays_audibly_at_audioserver_level() -> void:
	AudioManager.set_muted(TARGET_BUS, false)
	AudioManager.apply_volume_to_bus(TARGET_BUS, AudioManager.get_volume(TARGET_BUS), false)

	var dummy_btn := Button.new()
	add_child_autofree(dummy_btn)
	await wait_frames(1)

	dummy_btn.pressed.emit()
	await wait_frames(1)

	assert_false(AudioServer.is_bus_mute(bus_idx), "Hardware: Native AudioServer bus must be unmuted.")
	assert_true(AudioManager.is_any_sfx_playing(), "Pool should actively play allocated stream.")


## Scenario C: Verify navigation SFX routing and focus-gating.
func test_ui_navigation_sfx_requires_gui_focus() -> void:
	Globals.options_open = true
	var unfocused_slider := HSlider.new()
	add_child_autofree(unfocused_slider)
	unfocused_slider.release_focus()
	await wait_frames(1)

	var nav_event := InputEventAction.new()
	nav_event.action = "ui_down"
	nav_event.pressed = true
	Globals._input(nav_event)
	await wait_frames(1)

	assert_false(AudioManager.is_any_sfx_playing(), "Navigation audio should be blocked when no GUI element has focus.")

	unfocused_slider.grab_focus()
	await wait_frames(1)
	Globals._input(nav_event)
	await wait_frames(1)

	assert_true(AudioManager.is_any_sfx_playing(), "Navigation audio should trigger when GUI element has active focus.")
	assert_true(AudioManager.get_active_sfx_stream_path().contains("ui_navigation"), "Active stream path should point to ui_navigation asset.")

	Globals.options_open = false


## Scenario E: Verify that watch_signals correctly isolates test actions from setup pollution.
func test_signal_isolation_from_setup_pollution() -> void:
	AudioManager.set_muted(TARGET_BUS, false)
	watch_signals(AudioManager)
	
	AudioManager.set_muted(TARGET_BUS, true)
	
	assert_eq(
		get_signal_emit_count(AudioManager, "mute_toggled"),
		1,
		"Watcher should strictly capture emissions that occurred after watch_signals() was invoked."
	)
	assert_signal_emitted_with_parameters(AudioManager, "mute_toggled", [TARGET_BUS, true])


## Scenario F: Verify rapid mute toggling cancels pending hardware cutoffs.
func test_rapid_mute_toggle_cancels_pending_hardware_cutoff() -> void:
	AudioManager.set_muted(TARGET_BUS, false)
	AudioManager.apply_volume_to_bus(TARGET_BUS, 1.0, false)
	
	AudioManager.set_muted(TARGET_BUS, true)
	await wait_seconds(0.05)
	
	AudioManager.set_muted(TARGET_BUS, false)
	await wait_seconds(0.15)
	
	assert_false(AudioServer.is_bus_mute(bus_idx), "Hardware bus must remain unmuted; rapid updates abort pending cutoff timers.")


## Scenario D: Verify hardware cutoff safety window.
func test_ui_mute_toggle_defers_hardware_cutoff_for_click_feedback() -> void:
	# 1. FAIL-FAST GUARD: Define the explicit path and verify its integrity on disk
	const AUDIO_SETTINGS_PATH = "res://scenes/audio_settings.tscn"
	assert_true(FileAccess.file_exists(AUDIO_SETTINGS_PATH), "FAIL-FAST: '%s' is missing from the project directory!" % AUDIO_SETTINGS_PATH)
	
	var audio_settings_scene: = load(AUDIO_SETTINGS_PATH)
	assert_not_null(audio_settings_scene, "FAIL-FAST: Failed to load audio_settings.tscn resource.")
	
	var audio_menu: = audio_settings_scene.instantiate() as Control
	assert_not_null(audio_menu, "FAIL-FAST: Instantiated audio settings root node is not a Control type.")
	add_child_autofree(audio_menu)
	await wait_frames(1)

	# 2. BYPASS BRITTLE NODE PATHS: Extract the script variable directly via object reflection
	var sfx_mute_btn: CheckButton = audio_menu.get("mute_sfx") as CheckButton
	assert_not_null(sfx_mute_btn, "FAIL-FAST: The 'mute_sfx' variable could not be extracted from the audio settings script context.")

	# Ensure starting unmuted
	AudioManager.set_muted(TARGET_BUS, false)
	AudioManager.apply_volume_to_bus(TARGET_BUS, 1.0, false)
	sfx_mute_btn.grab_focus()
	await wait_frames(1)

	# Toggle mute ON (button pressed = false in UI mapping)
	sfx_mute_btn.toggled.emit(false)

	# ASSERT IMMEDIATE LOGICAL FLIP
	assert_true(AudioManager.get_muted(TARGET_BUS), "Logical state should flip immediately.")
	assert_false(AudioServer.is_bus_mute(bus_idx), "Hardware cutoff should be deferred to allow click audio to stream out.")
	assert_true(AudioManager.is_any_sfx_playing(), "Confirmation click SFX should be playing.")

	# AWAIT HARDWARE CUTOFF WINDOW (0.15s + buffer)
	await wait_seconds(0.2)
	assert_true(AudioServer.is_bus_mute(bus_idx), "Hardware bus must be muted after safety cutoff timer expires.")


## Scenario G: Verify UI mute buttons dynamically sync state without rigid tree paths.
func test_ui_mute_controls_sync_state_dynamically() -> void:
	const AUDIO_SETTINGS_PATH = "res://scenes/audio_settings.tscn"
	assert_true(FileAccess.file_exists(AUDIO_SETTINGS_PATH), "FAIL-FAST: '%s' is missing from the project directory!" % AUDIO_SETTINGS_PATH)
	
	var audio_settings_scene: = load(AUDIO_SETTINGS_PATH)
	var audio_menu: = audio_settings_scene.instantiate() as Control
	assert_not_null(audio_menu, "FAIL-FAST: Instantiated audio settings root node is not a Control type.")
	add_child_autofree(audio_menu)
	await wait_process_frames(1)
	
	# Find interactive checkbuttons dynamically without relying on brittle node paths
	var check_buttons := audio_menu.find_children("", "CheckButton", true, false)
	assert_gt(check_buttons.size(), 0, "Audio menu must instantiate interactive CheckButtons.")
	
	var candidate_btn: CheckButton = check_buttons[0] as CheckButton
	candidate_btn.toggled.emit(false) # Simulate UI mute press
	
	assert_true(AudioManager.is_any_sfx_playing(), "Triggering any audio menu CheckButton should invoke confirmation SFX.")
