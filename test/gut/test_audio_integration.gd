## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_audio_integration.gd
##
## Comprehensive GUT integration test suite verifying that UI interaction events
## routed through Globals correctly invoke AudioManager, allocate pooled streams,
## and propagate logical mute states down to Godot's native AudioServer.

extends GutTest

const TARGET_BUS: String = AudioConstants.BUS_SFX
const MENU_BUS: String = AudioConstants.BUS_SFX_MENU


func before_each() -> void:
	# Reset to standard defaults before each run to ensure parity
	AudioManager.reset_volumes()


func after_each() -> void:
	# Sanitize the active channels and purge LRU memory caches
	AudioManager.stop_all_sfx()
	if AudioManager.has_method("cleanup_for_test"):
		AudioManager.cleanup_for_test()
	AudioManager.reset_volumes()


## Scenario A: Verify that when the parent SFX bus is muted, UI button presses
## still allocate streams in the pool, but the native hardware bus remains muted.
func test_sfx_mute_silences_ui_accept_at_audioserver_level() -> void:
	# 1. ARRANGE & WATCH
	watch_signals(AudioManager)

	AudioManager.set_muted(TARGET_BUS, true)
	AudioManager.apply_volume_to_bus(TARGET_BUS, AudioManager.get_volume(TARGET_BUS), true)

	var bus_idx: int = AudioServer.get_bus_index(TARGET_BUS)

	# Verify reactive UI signal payload (set_muted() must emit reactive UI signal with exact payload)
	assert_signal_emitted_with_parameters(
		AudioManager,
		"mute_toggled",
		[TARGET_BUS, true]
	)

	# 2. ACT (Account for CONNECT_DEFERRED race condition)
	var dummy_btn := Button.new()
	add_child_autofree(dummy_btn)
	await wait_frames(1)  # Allow Globals._on_node_added deferred connection to attach

	dummy_btn.pressed.emit()
	await wait_frames(1)  # Allow asynchronous audio stream allocation to process

	# 3. ASSERT LOGICAL VS HARDWARE SURVIVAL
	assert_true(AudioManager.get_muted(TARGET_BUS), "Logical: Manager must track bus as muted.")
	assert_true(AudioServer.is_bus_mute(bus_idx), "Hardware: Native AudioServer bus must be muted.")

	# 4. ASSERT ALLOCATION (Verifies stream allocation, not audible output)
	assert_true(
		AudioManager.is_any_sfx_playing(),
		"Pool should successfully allocate stream despite downstream hardware mute."
	)
	assert_eq(
		AudioManager.get_active_sfx_playback_count(),
		1,
		"Exactly one AudioStreamPlayer should be active in the pool."
	)


## Scenario B (Control Case): Verify that unmuted UI interactions audibly play
## and leave the hardware server unmuted.
func test_sfx_unmuted_plays_audibly_at_audioserver_level() -> void:
	# 1. ARRANGE
	AudioManager.set_muted(TARGET_BUS, false)
	AudioManager.apply_volume_to_bus(TARGET_BUS, AudioManager.get_volume(TARGET_BUS), false)

	var bus_idx: int = AudioServer.get_bus_index(TARGET_BUS)

	var dummy_btn := Button.new()
	add_child_autofree(dummy_btn)
	await wait_frames(1)

	# 2. ACT
	dummy_btn.pressed.emit()
	await wait_frames(1)

	# 3. ASSERT
	assert_false(AudioServer.is_bus_mute(bus_idx), "Hardware: Native AudioServer bus must be unmuted.")
	assert_true(AudioManager.is_any_sfx_playing(), "Pool should actively play allocated stream.")


## Scenario C: Verify navigation SFX routing and focus-gating.
## Arrow key navigation should only trigger audio when a valid Control has focus.
func test_ui_navigation_sfx_requires_gui_focus() -> void:
	# 1. ARRANGE: Ensure UI context is active but NO control has focus
	Globals.options_open = true
	var unfocused_slider := HSlider.new()
	add_child_autofree(unfocused_slider)
	unfocused_slider.release_focus()
	await wait_frames(1)

	# Simulate ui_down event
	var nav_event := InputEventAction.new()
	nav_event.action = "ui_down"
	nav_event.pressed = true
	Globals._input(nav_event)
	await wait_frames(1)

	# Should not play because nothing was focused
	assert_false(
		AudioManager.is_any_sfx_playing(),
		"Navigation audio should be blocked when no GUI element has focus."
	)

	# 2. ACT: Grab focus and re-fire
	unfocused_slider.grab_focus()
	await wait_frames(1)
	Globals._input(nav_event)
	await wait_frames(1)

	# 3. ASSERT
	assert_true(
		AudioManager.is_any_sfx_playing(),
		"Navigation audio should trigger when GUI element has active focus."
	)
	assert_true(
		AudioManager.get_active_sfx_stream_path().contains("ui_navigation"),
		"Active stream path should point to ui_navigation asset."
	)

	Globals.options_open = false


## Scenario D: Verify hardware cutoff safety window.
## When muting via UI panels, the hardware cutoff is slightly deferred (0.15s)
## so the user can audibly hear the checkbox confirmation click.
func test_ui_mute_toggle_defers_hardware_cutoff_for_click_feedback() -> void:
	# 1. ARRANGE: Instantiate Audio Settings scene to execute UI pipeline
	var audio_settings_scene := preload("res://scenes/audio_settings.tscn")
	var audio_menu: Control = audio_settings_scene.instantiate()
	add_child_autofree(audio_menu)
	await wait_frames(1)

	var sfx_mute_btn: CheckButton = audio_menu.get_node("Panel/VolumeControls/SFX/Mute")
	var bus_idx: int = AudioServer.get_bus_index(TARGET_BUS)

	# Ensure starting unmuted
	AudioManager.set_muted(TARGET_BUS, false)
	AudioManager.apply_volume_to_bus(TARGET_BUS, 1.0, false)
	sfx_mute_btn.grab_focus()
	await wait_frames(1)

	# 2. ACT: Toggle mute ON (button pressed = false in your UI mapping)
	# This invokes _execute_bus_mute_toggle asynchronously
	sfx_mute_btn.toggled.emit(false)

	# 3. ASSERT IMMEDIATE LOGICAL FLIP
	assert_true(AudioManager.get_muted(TARGET_BUS), "Logical state should flip immediately.")
	
	# Hardware bus should NOT be muted yet due to MUTE_HARDWARE_DELAY (0.15s)
	assert_false(
		AudioServer.is_bus_mute(bus_idx),
		"Hardware cutoff should be deferred to allow click audio to stream out."
	)
	assert_true(AudioManager.is_any_sfx_playing(), "Confirmation click SFX should be playing.")

	# 4. AWAIT HARDWARE CUTOFF WINDOW (0.15s + buffer)
	await wait_seconds(0.2)

	# Hardware bus must now be safely silenced
	assert_true(
		AudioServer.is_bus_mute(bus_idx),
		"Hardware bus must be muted after safety cutoff timer expires."
	)
