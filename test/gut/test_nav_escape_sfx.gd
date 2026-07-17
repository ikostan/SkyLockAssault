## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_nav_escape_sfx.gd
# FIX: Swapped out explicit path inheritance for the global class name token to ensure test runner discovery
extends GutTest

var globals_instance: Node
var original_audio_script: Script
var original_scene_name: String = ""
var dummy_scene_node: Node = null

## Suite setup: Double the AudioManager using a decoupled script to bypass lifecycle destruction guards.
## :rtype: void
func before_all() -> void:
	if is_instance_valid(AudioManager):
		original_audio_script = AudioManager.get_script()
		var mock_script := GDScript.new()
		mock_script.source_code = """
extends Node
var sfx_calls: Array = []
func play_sfx(key: String, extra: Variant = null) -> void:
	sfx_calls.append([key, extra])
"""
		mock_script.reload()
		AudioManager.set_script(mock_script)


## Suite cleanup: Safely restore original production script after all tests execute.
## :rtype: void
func after_all() -> void:
	if original_audio_script and is_instance_valid(AudioManager):
		AudioManager.set_script(original_audio_script)
		# Re-populate and rebuild the internal variable states wiped by set_script()
		if AudioManager.has_method("cleanup_for_test"):
			AudioManager.cleanup_for_test()


## Per-test setup: Snapshot the shared SceneTree state and reset mock logs.
## :rtype: void
func before_each() -> void:
	globals_instance = Globals
	
	# Securely snapshot the active root scene name before any mutations occur
	if get_tree().current_scene:
		original_scene_name = get_tree().current_scene.name
		dummy_scene_node = null
	else:
		# FIX: If running headlessly/CI, create a temporary dummy node to safely act as current_scene
		dummy_scene_node = Node.new()
		get_tree().root.add_child(dummy_scene_node)
		get_tree().current_scene = dummy_scene_node
		original_scene_name = ""
			
	if AudioManager.get("sfx_calls") != null:
		AudioManager.set("sfx_calls", [])
		
	await get_tree().process_frame


## Per-test cleanup: Restore the shared engine scene tree name wrapper cleanly.
## :rtype: void
func after_each() -> void:
	# FIX: Cleanly teardown and unmount the dummy scene tracker if initialized
	if dummy_scene_node and is_instance_valid(dummy_scene_node):
		if get_tree().current_scene == dummy_scene_node:
			get_tree().current_scene = null
		dummy_scene_node.queue_free()
		dummy_scene_node = null
	elif original_scene_name != "" and get_tree().current_scene:
		get_tree().current_scene.name = original_scene_name
		
	original_scene_name = ""
	await get_tree().process_frame


## Helper assertions for tracking explicit mock array triggers
func _assert_sfx_called(key: String) -> void:
	var found := false
	var calls: Array = AudioManager.get("sfx_calls")
	for c: Array in calls:
		if c[0] == key:
			found = true
			break
	assert_true(found, "Expected play_sfx to be called with: " + key)


func _assert_sfx_call_count(count: int) -> void:
	var actual_count: int = AudioManager.get("sfx_calls").size() 
	# FIX: Combined split string literal into a single line to resolve the engine compilation crash
	assert_eq(actual_count, count, "Expected play_sfx to be called %d times. Got %d." % [count, actual_count])


func _assert_sfx_not_called() -> void:
	var actual_count: int = AudioManager.get("sfx_calls").size()
	assert_eq(actual_count, 0, "Expected zero play_sfx calls. Got %d." % actual_count)


## Helper to safely mutate menu context layout titles to engage the debug feature gates.
## :rtype: void
func _set_menu_context(value: bool) -> void:
	if get_tree().current_scene:
		get_tree().current_scene.name = "MainMenu" if value else "GameLevel"


## Helper to feed simulated inputs safely and directly through the pipeline contexts.
## :rtype: void
func _simulate_input(event: InputEvent) -> void:
	# Route simulated input events directly into the new decoupled UiManager (Issue #490)
	if is_instance_valid(UiManager) and UiManager.has_method("_unhandled_input"):
		UiManager._unhandled_input(event)


## Assert that simulating a ui_cancel input event when inside a menu context triggers cancel audio.
## :rtype: void
func test_global_cancellation_in_menu_context() -> void:
	_set_menu_context(true)
	
	var event: InputEventAction = InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	
	_simulate_input(event)
	_assert_sfx_called("ui_cancel")
	_assert_sfx_call_count(1)


## Assert that no interface audio streams are triggered if input events occur outside menu contexts.
## :rtype: void
func test_global_out_of_context_suppression() -> void:
	_set_menu_context(false)
	
	var event_cancel: InputEventAction = InputEventAction.new()
	event_cancel.action = "ui_cancel"
	event_cancel.pressed = true
	
	var event_nav: InputEventAction = InputEventAction.new()
	event_nav.action = "ui_up"
	event_nav.pressed = true
	
	_simulate_input(event_cancel)
	_simulate_input(event_nav)
	_assert_sfx_not_called()


## Assert that immediately after leaving a menu context, subsequent cancel inputs do not trigger audio.
## :rtype: void
func test_menu_context_exit_cleanup() -> void:
	_set_menu_context(true)
	_set_menu_context(false) 
	
	var event: InputEventAction = InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	
	_simulate_input(event)
	_assert_sfx_not_called()


## Assert that repeated input instances flagged as echo completely bypass the audio frame.
## :rtype: void
func test_input_repeat_gate_echo_mitigation() -> void:
	_set_menu_context(true)
	
	var event: InputEventKey = InputEventKey.new()
	event.echo = true
	event.pressed = true
	event.physical_keycode = KEY_UP
	
	_simulate_input(event)
	_assert_sfx_not_called()


## Assert that directional actions successfully trigger the navigation tick when components are focused.
## :rtype: void
func test_navigation_positive_case() -> void:
	_set_menu_context(true)
	
	var dummy_btn: Button = Button.new()
	add_child_autofree(dummy_btn)
	dummy_btn.grab_focus()
	await get_tree().process_frame 
	
	var event: InputEventAction = InputEventAction.new()
	event.action = "ui_up"
	event.pressed = true
	
	_simulate_input(event)
	_assert_sfx_called("ui_navigation")


## Assert that a single discrete navigation input event produces exactly one audio trigger request.
## :rtype: void
func test_single_dispatch_guarantee() -> void:
	_set_menu_context(true)
	
	var dummy_btn: Button = Button.new()
	add_child_autofree(dummy_btn)
	dummy_btn.grab_focus()
	await get_tree().process_frame
	
	var event: InputEventAction = InputEventAction.new()
	event.action = "ui_down"
	event.pressed = true
	
	_simulate_input(event)
	_assert_sfx_call_count(1)


## Assert that when a LineEdit control node holds active focus, global interface sound is suppressed.
## :rtype: void
func test_value_editing_text_gate() -> void:
	_set_menu_context(true)
	
	var line_edit: LineEdit = LineEdit.new()
	add_child_autofree(line_edit)
	line_edit.grab_focus() 
	await get_tree().process_frame
	
	var event: InputEventAction = InputEventAction.new()
	# FIX: Swapped from ui_accept to ui_cancel to properly challenge the text control bypass branch
	event.action = "ui_cancel"
	event.pressed = true
	
	_simulate_input(event)
	_assert_sfx_not_called()


## Assert that when a Slider control holds active focus, horizontal directional inputs are bypassed.
## :rtype: void
func test_slider_double_audio_gate() -> void:
	_set_menu_context(true)
	
	var slider: HSlider = HSlider.new()
	add_child_autofree(slider)
	slider.grab_focus() 
	await get_tree().process_frame
	
	var event_left: InputEventAction = InputEventAction.new()
	event_left.action = "ui_left"
	event_left.pressed = true
	
	var event_right: InputEventAction = InputEventAction.new()
	event_right.action = "ui_right"
	event_right.pressed = true
	
	_simulate_input(event_left)
	_simulate_input(event_right)
	_assert_sfx_not_called()


## Assert that unrelated input actions never trigger interface selection, navigation, or cancellation audio.
## :rtype: void
func test_unrelated_action_integrity() -> void:
	_set_menu_context(true)
	
	var actions: Array[String] = ["weapon_fire", "pause_toggle", "move_left"]
	for act: String in actions:
		var event: InputEventAction = InputEventAction.new()
		event.action = act
		event.pressed = true
		_simulate_input(event)
		
	_assert_sfx_not_called()
