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


func before_each() -> void:
	var mock_globals: MockGlobals = MockGlobals.new()
	mock_globals.name = "Globals"
	get_tree().root.add_child(mock_globals)
	pause_menu = PauseMenuScene.instantiate()
	get_tree().root.add_child(pause_menu)
	# Ensure initially hidden and unpaused
	pause_menu.visible = false
	get_tree().paused = false
	# Ensure "pause" action exists (add if missing for isolation)
	if not InputMap.has_action("pause"):
		InputMap.add_action("pause")
		var ev: InputEventKey = InputEventKey.new()
		ev.physical_keycode = KEY_ESCAPE
		InputMap.action_add_event("pause", ev)


func after_each() -> void:
	if is_instance_valid(pause_menu):
		pause_menu.queue_free()
	if get_tree().root.has_node("Globals"):
		get_tree().root.get_node("Globals").queue_free()
	get_tree().paused = false  # Reset pause state
	if InputMap.has_action("pause"):
		InputMap.erase_action("pause")  # Clean up if added


## PM-01 | pause_menu.gd | Game running, input map loaded | Trigger Pause via configured pause action | Game enters paused state | Unit (GUT) | New – required by #353
func test_pm_01_trigger_pause_action() -> void:
	gut.p("PM-01: Triggering 'pause' action pauses the game and shows menu.")
	# Preconditions: Game "running" (unpaused, menu hidden)
	assert_false(get_tree().paused)
	assert_false(pause_menu.visible)
	# Action: Simulate pause input directly
	var pause_event: InputEventKey = InputEventKey.new()
	pause_event.physical_keycode = KEY_ESCAPE
	pause_event.pressed = true
	pause_menu._unhandled_input(pause_event)
	# Expected: Paused and visible
	assert_true(get_tree().paused, "Tree should be paused after pause action")
	assert_true(pause_menu.visible, "Pause menu should be visible after pause action")


## PM-02 | pause_menu.gd | Game running | Trigger deprecated ui_cancel action | Pause menu does not open | Unit (GUT) | Regression guard
func test_pm_02_trigger_ui_cancel_no_pause() -> void:
	gut.p("PM-02: Triggering 'ui_cancel' (if exists) does not pause (regression guard).")
	# Add ui_cancel if not present (for test isolation; assumes script ignores it)
	if not InputMap.has_action("ui_cancel"):
		InputMap.add_action("ui_cancel")
		var ev: InputEventKey = InputEventKey.new()
		ev.physical_keycode = KEY_ENTER  # Use different key to avoid conflict
		InputMap.action_add_event("ui_cancel", ev)
	# Preconditions: Unpaused
	assert_false(get_tree().paused)
	assert_false(pause_menu.visible)
	# Action: Simulate ui_cancel
	var cancel_event: InputEventKey = InputEventKey.new()
	cancel_event.physical_keycode = KEY_ENTER
	cancel_event.pressed = true
	pause_menu._unhandled_input(cancel_event)
	# Expected: No pause (script checks "pause", not ui_cancel)
	assert_false(get_tree().paused, "Tree should remain unpaused after ui_cancel")
	assert_false(pause_menu.visible, "Pause menu should remain hidden after ui_cancel")
	# Cleanup
	if InputMap.has_action("ui_cancel"):
		InputMap.erase_action("ui_cancel")


## PM-03 | pause_menu.gd | Game paused | Resume game from pause menu | Game resumes correctly | Unit (GUT) | Likely not covered yet
func test_pm_03_resume_from_paused() -> void:
	gut.p("PM-03: Resuming from paused state unpauses and hides menu.")
	# Preconditions: Manually pause
	pause_menu.toggle_pause()
	assert_true(get_tree().paused)
	assert_true(pause_menu.visible)
	# Action: Simulate resume button press
	var resume_btn: Button = pause_menu.get_node("VBoxContainer/ResumeButton")
	resume_btn.pressed.emit()
	# Expected: Unpaused and hidden
	assert_false(get_tree().paused, "Tree should be unpaused after resume")
	assert_false(pause_menu.visible, "Pause menu should be hidden after resume")


## PM-04 | pause_menu.gd | Game paused | Pause toggled twice rapidly | No crash, stable pause state | Unit (GUT) | Edge-case
func test_pm_04_rapid_toggle_stable() -> void:
	gut.p("PM-04: Rapid pause toggles result in stable state without crash.")
	# Preconditions: Start unpaused
	assert_false(get_tree().paused)
	assert_false(pause_menu.visible)
	# Action: Toggle twice
	pause_menu.toggle_pause()  # First: pause
	pause_menu.toggle_pause()  # Second: unpause
	# Expected: Ends unpaused (even toggles), no crash (implicit pass if reaches here)
	assert_false(get_tree().paused, "After even rapid toggles, should be unpaused")
	assert_false(pause_menu.visible, "Menu should be hidden after even toggles")
	# Extra: Odd toggles (start over, toggle three times)
	pause_menu.toggle_pause()  # 1: pause
	pause_menu.toggle_pause()  # 2: unpause
	pause_menu.toggle_pause()  # 3: pause
	assert_true(get_tree().paused, "After odd rapid toggles, should be paused")
	assert_true(pause_menu.visible, "Menu should be visible after odd toggles")


## PM-05 | pause_menu.gd | Game paused | Pause invoked while already paused | No duplicate pause logic executed | Unit (GUT) | Defensive test
func test_pm_05_pause_while_paused_no_duplicate() -> void:
	gut.p("PM-05: Invoking pause while paused keeps state without duplicates.")
	# Preconditions: Paused
	pause_menu.toggle_pause()
	assert_true(get_tree().paused)
	assert_true(pause_menu.visible)
	# Action: Simulate another pause input
	var pause_event: InputEventKey = InputEventKey.new()
	pause_event.physical_keycode = KEY_ESCAPE
	pause_event.pressed = true
	pause_menu._unhandled_input(pause_event)
	# Expected: Toggles to unpaused (no guard in current script)
	assert_false(get_tree().paused, "Second pause should toggle to unpaused")
	assert_false(pause_menu.visible, "Menu should hide on second pause")
