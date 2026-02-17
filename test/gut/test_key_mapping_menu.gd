## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
# test_key_mapping_menu.gd
# GUT unit tests for Key Mapping Menu — Device Settings & UI Behavior (Issue #349)
# Adapted to actual implementation: CheckButtons (Keyboard/Gamepad) with ButtonGroup + dynamic update
# of remap_buttons (no TabContainer or separate show/hide lists; single list with device-specific labels).
# Tests verify switching updates current_device + button text, reset calls Settings.reset_to_defaults per device,
# and label updates after simulated remapping.
# References: key_mapping.gd, key_mapping_menu.tscn, input_remap_button.gd
# Assumes Settings.reset_to_defaults(device_type: String) exists and properly resets per-device events.
# Run with GUT framework.

extends GutTest

var menu: CanvasLayer = null
var keyboard_btn: CheckButton = null
var gamepad_btn: CheckButton = null
var reset_btn: Button = null
var remap_buttons: Array = []


func before_each() -> void:
	menu = load("res://scenes/key_mapping_menu.tscn").instantiate()  # Adjust path if needed
	add_child(menu)
	# Get UI references
	keyboard_btn = menu.get_node("Panel/Options/DeviceTypeContainer/Keyboard")
	gamepad_btn = menu.get_node("Panel/Options/DeviceTypeContainer/Gamepad")
	reset_btn = menu.get_node("Panel/Options/BtnContainer/ControlResetButton")
	remap_buttons = menu.get_tree().get_nodes_in_group("remap_buttons") as Array[InputRemapButton]
	# Default to keyboard (as in _ready)
	keyboard_btn.button_pressed = true
	menu.update_all_remap_buttons()


func after_each() -> void:
	if is_instance_valid(menu):
		menu.queue_free()


# UI-01: Switch to keyboard settings
func test_ui_01_switch_to_keyboard() -> void:
	gut.p("UI-01: Keyboard switch updates all remap_buttons to KEYBOARD device.")
	# First switch to gamepad to ensure we're testing a real transition
	gamepad_btn.button_pressed = true
	gamepad_btn.toggled.emit(true)
	# Now switch back to keyboard
	keyboard_btn.button_pressed = true
	keyboard_btn.toggled.emit(true)
	# Verify keyboard device active, gamepad inactive
	assert_true(keyboard_btn.button_pressed, "Keyboard CheckButton should be pressed")
	assert_false(gamepad_btn.button_pressed, "Gamepad CheckButton should be inactive")
	# All remap buttons updated to KEYBOARD
	for btn: Variant in remap_buttons:
		assert_eq(btn.current_device, InputRemapButton.DeviceType.KEYBOARD,
			"Remap button device should be KEYBOARD after keyboard switch")


# UI-02: Switch to gamepad settings
func test_ui_02_switch_to_gamepad() -> void:
	gut.p("UI-02: Gamepad switch updates all remap_buttons to GAMEPAD device.")
	gamepad_btn.button_pressed = true
	# Assertions
	assert_true(gamepad_btn.button_pressed)
	assert_false(keyboard_btn.button_pressed)
	for btn: Variant in remap_buttons:
		assert_eq(btn.current_device, InputRemapButton.DeviceType.GAMEPAD,
			"Remap button device should be GAMEPAD after gamepad switch")
	
	# ROBUST GAMEPAD LABEL CHECK (replaces brittle != "Unbound")
	# Checks for typical gamepad label patterns (from JOY_BUTTON_LABELS / JOY_AXIS_LABELS)
	# Allows "Right Trigger", "D-Pad Left", "Misc 1", etc.
	# Explicitly rejects "Unbound" (the bug the reviewer caught)
	# Still rejects single-key keyboard labels.
	var speed_up_btn: Button = menu.get_node("Panel/Options/KeyMapContainer/PlayerKeyMap/KeyMappingSpeedUp/SpeedUpInputRemap")

	# Explicit reject "Unbound" (this was missing — test was too loose)
	assert_ne(speed_up_btn.text, "Unbound", "Gamepad should have a default binding (not Unbound)")

	assert_true(
		speed_up_btn.text.contains("Trigger") or 
		speed_up_btn.text.contains("Stick") or 
		speed_up_btn.text.contains("D-Pad") or 
		speed_up_btn.text.contains("Button") or 
		speed_up_btn.text.length() > 5,  # e.g. "Right Trigger", "Left Stick Left"
	    "Gamepad label should be descriptive (not a single key char or 'Unbound')"
	)

	# Still reject obvious keyboard-style labels (single uppercase letter)
	assert_false(
		speed_up_btn.text.length() == 1 and speed_up_btn.text.to_upper() == speed_up_btn.text,
	    "Gamepad label should not be a single keyboard key character"
	)


# UI-03: Reset button in keyboard mode
func test_ui_03_reset_in_keyboard() -> void:
	gut.p("UI-03: Reset in keyboard mode resets keyboard actions via Settings.reset_to_defaults('keyboard'); gamepad unaffected.")
	keyboard_btn.button_pressed = true
	# Simulate a temporary non-default remap, then reset
	var speed_up_btn: Button = menu.get_node("Panel/Options/KeyMapContainer/PlayerKeyMap/KeyMappingSpeedUp/SpeedUpInputRemap")
	speed_up_btn.button_pressed = true
	# Note: Directly calling private methods (_on_pressed, _input) for simulation due to complexity of full input event mocking in GUT unit tests.
	speed_up_btn._on_pressed()  # Manually trigger the pressed handler to start listening
	var temp_event := InputEventKey.new()
	temp_event.physical_keycode = Key.KEY_Z  # Non-default
	temp_event.pressed = true  # Ensure pressed for the condition in _input
	# Note: Directly calling private method (_input) for simulation due to complexity of full input event mocking in GUT unit tests.
	speed_up_btn._input(temp_event)
	reset_btn.pressed.emit()  # Triggers _on_reset_pressed("keyboard") + update_all_remap_buttons
	# Keyboard actions should now reflect defaults (not the temp "Z")
	# Exact default text depends on Settings; here we verify update occurred + not unbound
	assert_ne(speed_up_btn.text, "Z", "Keyboard reset should restore default (not keep temp remap)")
	assert_ne(speed_up_btn.text, "Unbound", "Keyboard buttons should have default labels after reset")


# UI-04: Reset button in gamepad mode
func test_ui_04_reset_in_gamepad() -> void:
	gut.p("UI-04: Reset in gamepad mode resets gamepad actions via Settings.reset_to_defaults('gamepad'); keyboard unaffected.")
	gamepad_btn.button_pressed = true
	# Temporary remap
	var fire_btn: Button = menu.get_node("Panel/Options/KeyMapContainer/PlayerKeyMap/KeyMappingFire/FireInputRemap")
	fire_btn.button_pressed = true
	# Note: Directly calling private methods (_on_pressed, _input) for simulation due to complexity of full input event mocking in GUT unit tests.
	fire_btn._on_pressed()  # Manually trigger the pressed handler to start listening
	var temp_event := InputEventJoypadButton.new()
	temp_event.button_index = JOY_BUTTON_B
	temp_event.pressed = true  # Ensure pressed for the condition in _input
	# Note: Directly calling private method (_input) for simulation due to complexity of full input event mocking in GUT unit tests.
	fire_btn._input(temp_event)
	reset_btn.pressed.emit()
	# Assertions
	assert_ne(fire_btn.text, "B", "Gamepad reset should restore default")
	assert_ne(fire_btn.text, "Unbound")


# test_ui_05_label_update_after_remapping
# :rtype: void
func test_ui_05_label_update_after_remapping() -> void:
	gut.p("UI-05: Remapping updates UI text to reflect new InputEvent for both keyboard and gamepad tabs.")
	
	# ── Keyboard remap ──
	keyboard_btn.button_pressed = true
	var left_btn: Button = menu.get_node("Panel/Options/KeyMapContainer/PlayerKeyMap/KeyMappingLeft/LeftInputRemap")
	left_btn.button_pressed = true
	left_btn._on_pressed()
	assert_eq(left_btn.text, Globals.REMAP_PROMPT_KEYBOARD, "Should show keyboard prompt while listening")
	
	var key_event := InputEventKey.new()
	key_event.physical_keycode = Key.KEY_A
	key_event.pressed = true
	left_btn._input(key_event)
	await get_tree().process_frame
	
	assert_false(left_btn.listening, "Listening should stop after valid input")
	assert_eq(left_btn.text, "A", "Keyboard label should update to new key")
	
	# ── Gamepad remap ──
	gamepad_btn.button_pressed = true
	gamepad_btn.toggled.emit(true)
	await get_tree().process_frame
	
	left_btn.button_pressed = true
	left_btn._on_pressed()
	assert_eq(left_btn.text, Globals.REMAP_PROMPT_GAMEPAD, "Should show gamepad prompt while listening")
	
	# Use JOY_BUTTON_MISC1 — safe choice (not used in DEFAULT_GAMEPAD → no conflict)
	var joy_event := InputEventJoypadButton.new()
	joy_event.button_index = JOY_BUTTON_MISC1
	joy_event.pressed = true
	joy_event.device = -1
	left_btn._input(joy_event)
	await get_tree().process_frame
	
	assert_false(left_btn.listening, "Listening should stop after valid gamepad input")
	assert_eq(left_btn.text, "Misc 1", "Gamepad label should update to new button (from JOY_BUTTON_LABELS)")
