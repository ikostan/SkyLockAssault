## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_gameplay_settings_audio.gd
##
## Automated verification suite for Epic #728.
## Validates focus-gated audio feedback patterns, silent programmatic updates,
## web-bridge interaction override states, and isolated execution safety.

extends "res://addons/gut/test.gd"

var gameplay_scene: PackedScene = load("res://scenes/gameplay_settings.tscn")
var gameplay_instance: Control
var _audio_manager: Object


## Captures environmental state and handles defensive isolation mocks before every execution step.
## :rtype: void
func before_each() -> void:
	Globals.set_test_encryption_key()

	# Establish isolated deterministic settings state using a clean resource instance
	# This avoids triggering core filesystem hash matching checks and MD5 corruption errors
	Globals.settings = GameSettingsResource.new()
	Globals.settings.difficulty = 1.0

	# Defensively locate or fallback mock the AudioManager singleton to shield headless runners
	_audio_manager = get_tree().root.get_node_or_null("AudioManager")
	if not is_instance_valid(_audio_manager):
		_audio_manager = DummyAudioManager.new()

	gameplay_instance = gameplay_scene.instantiate() as Control
	gameplay_instance.os_wrapper = OSWrapper.new()
	add_child_autofree(gameplay_instance)

	await get_tree().process_frame


## Clears active player channels and breaks layout nodes to prevent cross-contamination.
## :rtype: void
func after_each() -> void:
	_clear_pool_players()

	if is_instance_valid(gameplay_instance):
		gameplay_instance.queue_free()

	gameplay_instance = null
	_audio_manager = null

	await get_tree().process_frame


## Safely silences all active sound players via the public manager API.
## :rtype: void
func _clear_pool_players() -> void:
	_audio_manager.stop_all_sfx()


## Inspects channel layers to check if any active player is streaming audio payloads.
## :rtype: bool
func _is_sound_playing() -> bool:
	return _audio_manager.is_any_sfx_playing()


# --- Automated Test Cases ---

## TC-GUT-DIFF-01 — Initialization Remains Silent
## Verifies that scene instantiation and initial ready pipelines trigger completely silently.
## :rtype: void
func test_initialization_remains_silent() -> void:
	assert_false(_is_sound_playing(), "Scene instantiation and ready initialization must not play audio.")
	assert_eq(gameplay_instance.difficulty_slider.value, 1.0, "Slider configuration value must initialize synced with settings state.")


## TC-GUT-DIFF-02 — Focus-Gated Local Interaction
## Verifies that native user updates to the slider emit audio confirmations when focused.
## :rtype: void
func test_focus_gated_local_interaction_emits_audio() -> void:
	_clear_pool_players()
	
	# Simulate native UI control focus acquisition
	gameplay_instance.difficulty_slider.grab_focus()
	
	# Trigger the unified value change tracking path
	gameplay_instance._on_difficulty_value_changed(1.5)
	
	assert_true(_is_sound_playing(), "Value updates originating from focused slider controls must trigger audio feedback.")


## TC-GUT-DIFF-03 — Non-Focused Programmatic Mutation Remains Silent
## Verifies that background synchronization pipelines update layouts with total silence.
## :rtype: void
func test_non_focused_programmatic_mutation_remains_silent() -> void:
	_clear_pool_players()
	
	# Ensure focus state is clean
	if gameplay_instance.difficulty_slider.has_focus():
		gameplay_instance.difficulty_slider.release_focus()
		
	# Scenario A: Scripted local mutation without focus parameter or override token
	gameplay_instance._on_difficulty_value_changed(1.2)
	assert_false(_is_sound_playing(), "Programmatic setting changes lacking control focus must remain silent.")
	
	# Scenario B: Resource serialization lifecycle synchronization tracking loop
	_clear_pool_players()
	Globals.settings.setting_changed.emit("difficulty", 1.8)
	
	assert_false(_is_sound_playing(), "Automated resource model synchronization events must update the UI silently.")
	assert_eq(gameplay_instance.difficulty_slider.value, 1.8, "Slider node value position should sync correctly during silence.")


## TC-GUT-DIFF-04 — Reset Button Emits Audio
## Verifies that layout reset clicks restore configurations and fire exactly one audio drop.
## :rtype: void
func test_reset_button_emits_audio_exactly_once() -> void:
	# Offset value state from default first
	gameplay_instance.difficulty_slider.value = 1.5
	_clear_pool_players()
	
	# Act: Trigger the native layout reset handler
	gameplay_instance._on_gameplay_reset_button_pressed()
	
	assert_eq(gameplay_instance.difficulty_slider.value, 1.0, "Gameplay reset action must restore default configuration bounds.")
	assert_true(_is_sound_playing(), "Reset interaction pathway must fire audio affirmation.")
	
	# Verify that the public interface returns exactly 1 active playing channel
	var active_play_count: int = _audio_manager.get_active_sfx_playback_count()
	assert_eq(active_play_count, 1, "Reset loop must register exactly one playback instance configuration event.")


## TC-GUT-DIFF-05 — JS Interaction Override Path
## Verifies that external JS window signals bypass viewport focus gates using override tokens.
## :rtype: void
func test_js_interaction_override_path_triggers_playback() -> void:
	_clear_pool_players()
	
	# Force clean environmental isolation (no UI focus)
	if gameplay_instance.difficulty_slider.has_focus():
		gameplay_instance.difficulty_slider.release_focus()
		
	# Act: Simulate a verified incoming callback from the WebAssembly bridge abstraction layer
	gameplay_instance._on_change_difficulty_js([1.5])
	
	assert_eq(Globals.settings.difficulty, 1.5, "Slider state must conform to valid external JS instructions.")
	assert_true(_is_sound_playing(), "Verified external WebAssembly overlay interface triggers must bypass focus gate checks to emit sound.")


## TC-GUT-DIFF-06 — Invalid JS Input Rejection
## Verifies that defensive type-checking layers catch malformed payloads silently.
## :rtype: void
func test_invalid_js_input_rejection_remains_silent() -> void:
	Globals.settings.difficulty = 1.0
	_clear_pool_players()
	
	# Scenario A: Empty inner payload structure arrays matching project validation conventions (GS-JS-10/11)
	gameplay_instance._on_change_difficulty_js([[]])
	assert_false(_is_sound_playing(), "Empty nested array inputs must reject audio calls.")
	assert_eq(Globals.settings.difficulty, 1.0, "Configuration data properties must maintain bounds tracking state integrity on structural type errors.")
	
	# Scenario B: Non-numeric malicious injection string parsing attempts (GS-JS-12/14)
	_clear_pool_players()
	gameplay_instance._on_change_difficulty_js(["invalid_text_payload"])
	assert_false(_is_sound_playing(), "Non-numeric parsing formats must fail silently without sound leakage.")
	assert_eq(Globals.settings.difficulty, 1.0, "Difficulty state must remain unchanged.")
	
	# Scenario C: Unsupported primitives (GS-JS-22/25)
	_clear_pool_players()
	gameplay_instance._on_change_difficulty_js([null])
	assert_false(_is_sound_playing(), "Unsupported primitive types must not trigger audio feedback loops.")
	assert_eq(Globals.settings.difficulty, 1.0, "Defensive data safety constraints must block value leakage completely across testing boundaries.")


# --- Defensive Test Infrastructure Fallbacks ---

## Isolated dummy placeholder class used to prevent null reference errors 
## when running tests inside bare environments lacking Autoload initializations.
class DummyAudioManager:
	
	## Mock interface matching production playing state evaluation.
	## :rtype: bool
	func is_any_sfx_playing() -> bool:
		return false
	
	## Mock interface matching production concurrent playback calculation.
	## :rtype: int
	func get_active_sfx_playback_count() -> int:
		return 0
	
	## Mock interface matching production channel teardown routine execution.
	## :rtype: void
	func stop_all_sfx() -> void:
		pass
