## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_pause_menu.gd
## GUT unit tests for pause_menu.gd based on test plan from #353.
## Covers PM-01 to PM-05.
## Test Plan:
## https://github.com/ikostan/SkyLockAssault/issues/353
## References: pause_menu.gd, pause_menu.tscn
## Assumes "pause" action is defined in InputMap (e.g., from Settings).
## Uses direct _unhandled_input calls for simulation.

extends GutTest

var PauseMenuScene: PackedScene = preload("res://scenes/pause_menu.tscn")
var pause_menu: CanvasLayer = null
var original_globals: Node = null
var original_paused: bool = false
var original_input_map: Dictionary = {}  # action: [events]
var added_pause: bool = false
var original_pause_events: Array[InputEvent] = []
var added_ui_cancel: bool = false
var original_ui_cancel_events: Array[InputEvent] = []


## Mock for Globals autoload to avoid errors in button handlers.
class MockGlobals extends Node:
	var load_scene_with_loading_called: bool = false
	var load_options_called: bool = false
	func log_message(_msg: String, _lvl: int) -> void:
		pass
	func load_scene_with_loading(_path: String) -> void:
		load_scene_with_loading_called = true
	func load_options(_node: Node) -> void:
		load_options_called = true


## Sets up suite-wide state capture.
## Captures original InputMap.
## :rtype: void
func before_all() -> void:
	for action: String in InputMap.get_actions():
		original_input_map[action] = InputMap.action_get_events(action)


## Sets up per-test state.
## Captures/restores Globals, paused; instantiates menu; ensures "pause" action.
## :rtype: void
func before_each() -> void:
	original_paused = get_tree().paused
	if get_tree().root.has_node("Globals"):
		original_globals = get_tree().root.get_node("Globals")
		get_tree().root.remove_child(original_globals)
	var mock_globals: MockGlobals = MockGlobals.new()
	mock_globals.name = "Globals"
	get_tree().root.add_child(mock_globals)
	pause_menu = PauseMenuScene.instantiate()
	get_tree().root.add_child(pause_menu)
	pause_menu.visible = false
	get_tree().paused = false
	# Ensure "pause" action exists (add if missing for isolation)
	original_pause_events = []
	added_pause = false
	if InputMap.has_action("pause"):
		original_pause_events = InputMap.action_get_events("pause")
	else:
		added_pause = true
		InputMap.add_action("pause")
		var ev: InputEventKey = InputEventKey.new()
		ev.physical_keycode = KEY_ESCAPE
		InputMap.action_add_event("pause", ev)


## Helper to create a simulated pause event based on current InputMap.
## :rtype: InputEventKey
func create_pause_event() -> InputEventKey:
	var events: Array[InputEvent] = InputMap.action_get_events("pause")
	if events.is_empty() or not events[0] is InputEventKey:
		var ev: InputEventKey = InputEventKey.new()
		ev.physical_keycode = KEY_ESCAPE
		return ev
	var key_ev: InputEventKey = events[0] as InputEventKey
	var sim_ev: InputEventKey = InputEventKey.new()
	sim_ev.physical_keycode = key_ev.physical_keycode
	sim_ev.pressed = true
	return sim_ev


## Cleans up per-test state.
## Frees menu/mock; restores Globals/paused; erases added actions.
## :rtype: void
func after_each() -> void:
	if is_instance_valid(pause_menu):
		pause_menu.queue_free()
	var mock_globals: Node = get_tree().root.get_node_or_null("Globals")
	if mock_globals != null:
		mock_globals.queue_free()
	if original_globals:
		get_tree().root.add_child(original_globals)
		original_globals = null
	get_tree().paused = original_paused
	# Restore "pause" action
	if InputMap.has_action("pause"):
		if added_pause:
			InputMap.erase_action("pause")
		else:
			InputMap.action_erase_events("pause")
			for ev: InputEvent in original_pause_events:
				InputMap.action_add_event("pause", ev)
	# Restore "ui_cancel" action if modified
	if InputMap.has_action("ui_cancel"):
		if added_ui_cancel:
			InputMap.erase_action("ui_cancel")
		else:
			InputMap.action_erase_events("ui_cancel")
			for ev: InputEvent in original_ui_cancel_events:
				InputMap.action_add_event("ui_cancel", ev)


## Restores suite-wide state.
## Erases extra actions; restores original actions/events.
## :rtype: void
func after_all() -> void:
	for action: String in InputMap.get_actions().duplicate():
		if not original_input_map.has(action):
			InputMap.erase_action(action)
	for action: String in original_input_map:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		for ev: InputEvent in original_input_map[action]:
			InputMap.action_add_event(action, ev)


## PM-01 | pause_menu.gd | Game running, input map loaded | Trigger Pause via configured pause action | Game enters paused state | Unit (GUT) | New – required by #353
func test_pm_01_trigger_pause_action() -> void:
	gut.p("PM-01: Triggering 'pause' action pauses the game and shows menu.")
	assert_false(get_tree().paused)
	assert_false(pause_menu.visible)
	var pause_event: InputEventKey = create_pause_event()
	pause_menu._unhandled_input(pause_event)
	assert_true(get_tree().paused, "Tree should be paused after pause action")
	assert_true(pause_menu.visible, "Pause menu should be visible after pause action")


## PM-02 | pause_menu.gd | Game running | Trigger deprecated ui_cancel action | Pause menu does not open | Unit (GUT) | Regression guard
func test_pm_02_trigger_ui_cancel_no_pause() -> void:
	gut.p("PM-02: Triggering 'ui_cancel' (if exists) does not pause (regression guard).")
	original_ui_cancel_events = []
	added_ui_cancel = false
	if InputMap.has_action("ui_cancel"):
		original_ui_cancel_events = InputMap.action_get_events("ui_cancel")
	else:
		added_ui_cancel = true
		InputMap.add_action("ui_cancel")
		var ev: InputEventKey = InputEventKey.new()
		ev.physical_keycode = KEY_ENTER
		InputMap.action_add_event("ui_cancel", ev)
	assert_false(get_tree().paused)
	assert_false(pause_menu.visible)
	var cancel_event: InputEventKey = InputEventKey.new()
	cancel_event.physical_keycode = KEY_ENTER
	cancel_event.pressed = true
	pause_menu._unhandled_input(cancel_event)
	assert_false(get_tree().paused, "Tree should remain unpaused after ui_cancel")
	assert_false(pause_menu.visible, "Pause menu should remain hidden after ui_cancel")


## PM-03 | pause_menu.gd | Game paused | Resume game from pause menu | Game resumes correctly | Unit (GUT) | Likely not covered yet
func test_pm_03_resume_from_paused() -> void:
	gut.p("PM-03: Resuming from paused state unpauses and hides menu.")
	pause_menu.toggle_pause()
	assert_true(get_tree().paused)
	assert_true(pause_menu.visible)
	var resume_btn: Button = pause_menu.resume_button
	resume_btn.pressed.emit()
	assert_false(get_tree().paused, "Tree should be unpaused after resume")
	assert_false(pause_menu.visible, "Pause menu should be hidden after resume")


## PM-04 | pause_menu.gd | Game paused | Pause toggled twice rapidly | No crash, stable pause state | Unit (GUT) | Edge-case
func test_pm_04_rapid_toggle_stable() -> void:
	gut.p("PM-04: Rapid pause toggles result in stable state without crash.")
	assert_false(get_tree().paused)
	assert_false(pause_menu.visible)
	pause_menu.toggle_pause()
	pause_menu.toggle_pause()
	assert_false(get_tree().paused, "After even rapid toggles, should be unpaused")
	assert_false(pause_menu.visible, "Menu should be hidden after even toggles")
	pause_menu.toggle_pause()
	pause_menu.toggle_pause()
	pause_menu.toggle_pause()
	assert_true(get_tree().paused, "After odd rapid toggles, should be paused")
	assert_true(pause_menu.visible, "Menu should be visible after odd toggles")


## PM-05 | pause_menu.gd | Game paused | Pause invoked while already paused | No duplicate pause logic executed | Unit (GUT) | Defensive test
func test_pm_05_pause_while_paused_no_duplicate() -> void:
	gut.p("PM-05: Invoking pause while paused keeps state without duplicates.")
	pause_menu.toggle_pause()
	assert_true(get_tree().paused)
	assert_true(pause_menu.visible)
	var pause_event: InputEventKey = create_pause_event()
	pause_menu._unhandled_input(pause_event)
	assert_false(get_tree().paused, "Second pause should toggle to unpaused")
	assert_false(pause_menu.visible, "Menu should hide on second pause")
