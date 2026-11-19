## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_main_menu_audio.gd
##
## Integration test suite ensuring that Main Menu scene buttons successfully
## trigger the confirmation click audio asset over the presentation layer.

extends GutTest

const MAIN_MENU_SCENE_PATH = "res://scenes/main_menu.tscn"
const MENU_BUS: String = AudioConstants.BUS_SFX_MENU

# Lifecycle tracking references to prevent scene leakage between test runs
var _initial_root_children: Array[Node] = []
var _initial_current_scene: Node = null
# Input state a test changed; after_each() restores it, even if the test stopped partway.
var _saved_input_device: String = ""
var _saved_critical_events: Dictionary = {}


func before_all() -> void:
	# REFACTOR: Offload bus setup configurations entirely to shared test utilities
	var required_buses: Array[String] = [
		AudioConstants.BUS_MASTER,
		AudioConstants.BUS_MUSIC,
		AudioConstants.BUS_SFX,
		MENU_BUS
	]
	GutTestHelper.bootstrap_headless_audio_buses(required_buses)


func before_each() -> void:
	# Snapshot the baseline scene state before interactions modify the tree footprint
	_initial_root_children = get_tree().root.get_children()
	_initial_current_scene = get_tree().current_scene
	
	SfxManager.stop_all_sfx()
	AudioManager.reset_volumes()


func after_each() -> void:
	# 0. Restore the input bindings and device a test changed (empty when untouched)
	if not _saved_critical_events.is_empty():
		_restore_critical_actions(_saved_critical_events)
		Globals.current_input_device = _saved_input_device
		_saved_critical_events = {}

	# 1. Reset global menu state toggles to prevent cross-contamination
	if is_instance_valid(Globals.options_instance):
		Globals.options_instance.queue_free()
		Globals.options_instance = null
	Globals.options_open = false
	Globals.hidden_menus.clear()

	# 2. Revert scene tree transitions back to pristine baseline test states
	if is_instance_valid(get_tree().current_scene) and get_tree().current_scene != _initial_current_scene:
		var leaked_scene := get_tree().current_scene
		
		# Create an empty node space to safely swap back to 
		var blank_placeholder := Node.new()
		blank_placeholder.name = "TestPlaceholderScene"
		get_tree().root.add_child(blank_placeholder)
		get_tree().current_scene = blank_placeholder
		
		# Erase the active gameplay loop rendering in the background
		leaked_scene.queue_free()

	# 3. Clean up any standalone canvas layers or popups pushed straight to the root window
	for child in get_tree().root.get_children():
		if is_instance_valid(child) and child not in _initial_root_children and child != get_tree().current_scene:
			child.queue_free()

	# 4. Flush all hardware audio registers completely
	SfxManager.stop_all_sfx()
	if AudioManager.has_method("cleanup_for_test"):
		AudioManager.cleanup_for_test()
	AudioManager.reset_volumes()


## Scenario: Verifies that Main Menu buttons play the accept sound despite the 'no_global_sound' metadata shield.
func test_main_menu_buttons_execute_accept_audio() -> void:
	# 1. Load and instantiate the main menu scene
	var scene_resource := load(MAIN_MENU_SCENE_PATH)
	assert_not_null(scene_resource, "Fail-Fast: Main menu scene asset could not be loaded from project paths.")
	
	var menu_instance := scene_resource.instantiate() as Control
	add_child_autofree(menu_instance)
	await wait_process_frames(1)

	# 2. Setup testing guards to prevent engine exit/quit loops
	menu_instance.bypass_quit_for_testing = true

	# --- TEST START GAME BUTTON ---
	var start_btn: Button = menu_instance.start_button
	assert_not_null(start_btn, "Layout Validation: Start Button is missing from scene tree.")
	
	start_btn.pressed.emit()
	
	# FIX: Await the exact moment deferred signals are flushed, but BEFORE the 
	# end-of-frame scene transition destroys the tree and kills the audio.
	await get_tree().process_frame
	
	assert_true(SfxManager.is_any_sfx_playing(), "Start Game button must trigger confirmation audio.")
	assert_string_contains(SfxManager.get_active_sfx_stream_path(), "ui_accept", "Start Game button must play the 'ui_accept' sound effect asset.")
	
	SfxManager.stop_all_sfx()

	# --- TEST OPTIONS BUTTON ---
	var options_btn: Button = menu_instance.options_button
	assert_not_null(options_btn, "Layout Validation: Options Button is missing from scene tree.")
	
	options_btn.pressed.emit()
	
	await get_tree().process_frame
	
	assert_true(SfxManager.is_any_sfx_playing(), "Options button must trigger confirmation audio.")
	assert_string_contains(SfxManager.get_active_sfx_stream_path(), "ui_accept", "Options button must play the 'ui_accept' sound effect asset.")
	
	SfxManager.stop_all_sfx()

	# --- TEST QUIT BUTTON ---
	var quit_btn: Button = menu_instance.quit_button
	assert_not_null(quit_btn, "Layout Validation: Quit Button is missing from scene tree.")
	
	quit_btn.pressed.emit()
	
	await get_tree().process_frame
	
	assert_true(SfxManager.is_any_sfx_playing(), "Quit button must trigger confirmation audio.")
	assert_string_contains(SfxManager.get_active_sfx_stream_path(), "ui_accept", "Quit button must play the 'ui_accept' sound effect asset.")


## Scenario: A second Start press before the menu is freed (double click or JS burst) is
## ignored: no second transition request and no second accept sound. Binds every critical
## action for the keyboard first, so Start always loads the game instead of opening the
## Unbound Controls dialog; after_each() restores the bindings and device.
func test_start_burst_requests_one_transition() -> void:
	_saved_input_device = Globals.current_input_device
	_saved_critical_events = _bind_critical_actions_for_keyboard()
	var menu_instance := (load(MAIN_MENU_SCENE_PATH) as PackedScene).instantiate() as Control
	add_child_autofree(menu_instance)
	await wait_process_frames(1)
	assert_false(
		Settings.has_unbound_critical_actions_for_current_device(),
		"The fixture binds every critical action, so Start loads the game."
	)
	var start_btn: Button = menu_instance.start_button
	# Prove the first press requests gameplay: load_scene_with_loading() replaces this value.
	Globals.next_scene = "res://first_request_sentinel.tscn"

	start_btn.pressed.emit()

	assert_true(menu_instance._start_transition_requested, "First press requests the transition.")
	assert_eq(
		Globals.next_scene, "res://scenes/main_scene.tscn", "First press requests gameplay."
	)
	SfxManager.stop_all_sfx()
	# Detect a second request: load_scene_with_loading() would overwrite this value.
	Globals.next_scene = "res://second_request_sentinel.tscn"

	start_btn.pressed.emit()

	assert_eq(
		Globals.next_scene,
		"res://second_request_sentinel.tscn",
		"Second press must not request another transition."
	)
	assert_false(SfxManager.is_any_sfx_playing(), "Second press must not play the accept sound.")
	# Restore the accepted request before the loading screen reads it at the end of the frame.
	Globals.next_scene = "res://scenes/main_scene.tscn"
	await get_tree().process_frame


## Selects the keyboard and gives every critical action without a key a test key binding.
## Returns each critical action's original events, for after_each() to restore.
func _bind_critical_actions_for_keyboard() -> Dictionary:
	var saved: Dictionary = {}
	Globals.current_input_device = "keyboard"
	for action: String in Settings.CRITICAL_ACTIONS:
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		saved[action] = events.duplicate()
		if not events.any(func(ev: InputEvent) -> bool: return ev is InputEventKey):
			var key := InputEventKey.new()
			key.physical_keycode = KEY_F12
			InputMap.action_add_event(action, key)
	return saved


## Puts back the critical actions' original events.
func _restore_critical_actions(saved: Dictionary) -> void:
	for action: String in saved:
		InputMap.action_erase_events(action)
		for ev: InputEvent in saved[action]:
			InputMap.action_add_event(action, ev)
