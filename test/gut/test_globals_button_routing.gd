## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_globals_button_routing.gd
##
## Automation test suite verifying that centralized button click interceptors
## in Globals route menu audio feedback strictly to the presentation Menu SFX bus.

extends GutTest

const GAMEPLAY_BUS: String = AudioConstants.BUS_SFX
const MENU_BUS: String = AudioConstants.BUS_SFX_MENU


func before_all() -> void:
	# FAIL-FAST / BOOTSTRAP: Ensure the test runner environment possesses the required audio buses.
	# This guarantees the test suite passes flawlessly on stripped headless CI/CD systems.
	var required_buses: Array[String] = [
		AudioConstants.BUS_MASTER,
		AudioConstants.BUS_MUSIC,
		GAMEPLAY_BUS,
		MENU_BUS
	]
	
	for bus_name in required_buses:
		var idx: int = AudioServer.get_bus_index(bus_name)
		if idx == -1:
			AudioServer.add_bus()
			var new_idx: int = AudioServer.get_bus_count() - 1
			AudioServer.set_bus_name(new_idx, bus_name)


func before_each() -> void:
	AudioManager.stop_all_sfx()
	AudioManager.reset_volumes()


func after_each() -> void:
	AudioManager.stop_all_sfx()
	if AudioManager.has_method("cleanup_for_test"):
		AudioManager.cleanup_for_test()
	AudioManager.reset_volumes()


## Test Case 1: Verifies that standard UI button presses route confirmation SFX to the Menu bus.
## FAILURE MODE (Before Fix): Routes to AudioConstants.BUS_SFX ("SFX"), causing the assertion to fail.
## SUCCESS MODE (After Fix): Routes to AudioConstants.BUS_SFX_MENU ("SFX_Menu"), passing successfully.
func test_global_button_press_routes_to_menu_sfx_bus() -> void:
	# 1. Instantiate a standard menu button to invoke the interceptor track
	var dummy_btn := Button.new()
	add_child_autofree(dummy_btn)
	
	# Await deferred scene tree hookups (CONNECT_DEFERRED connection setup)
	await wait_process_frames(1)

	# 2. Act: Simulate standard UI press interaction
	dummy_btn.pressed.emit()
	await wait_process_frames(1)

	# 3. Assert: Identify the allocated pool player and inspect its target bus
	var targeted_bus: String = ""
	for player: AudioStreamPlayer in AudioManager._sfx_pool:
		if player.playing:
			targeted_bus = player.bus
			break

	assert_true(AudioManager.is_any_sfx_playing(), "A pool channel must be actively streaming the confirmation click.")
	assert_eq(targeted_bus, MENU_BUS, "Centralized button click confirmation audio must route over the dedicated Menu SFX layer.")


## Test Case 2: Verifies that flat buttons and explicit metadata suppression flags remain silent.
func test_button_suppression_gating_is_respected() -> void:
	var flat_btn := Button.new()
	flat_btn.flat = true
	add_child_autofree(flat_btn)
	
	var muted_btn := Button.new()
	muted_btn.set_meta("no_global_sound", true)
	add_child_autofree(muted_btn)
	
	await wait_process_frames(1)

	# Act: Trigger both suppressed elements
	flat_btn.pressed.emit()
	await wait_process_frames(1)
	assert_false(AudioManager.is_any_sfx_playing(), "Flat buttons must bypass the global interceptor and remain silent.")

	muted_btn.pressed.emit()
	await wait_process_frames(1)
	assert_false(AudioManager.is_any_sfx_playing(), "Buttons with explicit 'no_global_sound' metadata must remain silent.")


## Test Case 3: Verifies that standard engine Dialog components do not trigger global interceptor sounds.
func test_dialog_internal_buttons_are_excluded() -> void:
	var dialog := AcceptDialog.new()
	add_child_autofree(dialog)
	
	# Extract or simulate an internal dialog submission button interaction
	var ok_button := dialog.get_ok_button()
	await wait_process_frames(1)

	ok_button.pressed.emit()
	await wait_process_frames(1)

	assert_false(AudioManager.is_any_sfx_playing(), "Internal dialog controls must be excluded from centralized button sound loops.")
