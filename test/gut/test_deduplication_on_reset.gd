## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_deduplication_on_reset.gd
## Additional GUT unit test to ensure reset doesn't add duplicates.
## Scenario: Reset with existing defaults → no extras.
## Fails if InputMap has duplicates after reset.
## :references: settings.gd reset_to_defaults(), key_mapping.gd _on_reset_pressed()

extends GutTest

const TEST_ACTION: String = "speed_up"

var menu: CanvasLayer

## Per-test: Setup menu with duplicate defaults manually added.
func before_each() -> void:
	InputMap.action_erase_events(TEST_ACTION)
	InputMap.add_action(TEST_ACTION)
	var def_ev: InputEventKey = InputEventKey.new()
	def_ev.physical_keycode = KEY_W
	InputMap.action_add_event(TEST_ACTION, def_ev)
	InputMap.action_add_event(TEST_ACTION, def_ev.duplicate())  # Duplicate
	menu = load("res://scenes/key_mapping_menu.tscn").instantiate()
	add_child(menu)
	menu.keyboard.button_pressed = true  # Keyboard mode

## Per-test: Free menu.
func after_each() -> void:
	if is_instance_valid(menu):
		menu.queue_free()
	await get_tree().process_frame

## DEDUP-03 | Reset with existing duplicates → dedups to single default | Size 1 (per device)
func test_dedup_03_reset_with_duplicates() -> void:
	var reset_btn: Button = menu.get_node("Panel/Options/BtnContainer/ControlResetButton")
	reset_btn.pressed.emit()
	await get_tree().process_frame
	var events: Array[InputEvent] = InputMap.action_get_events(TEST_ACTION)
	# var key_events: Array = events.filter(func(ev): return ev is InputEventKey)
	var key_events: Array[InputEvent] = events.filter(func(ev: InputEvent) -> bool: return ev is InputEvent)
	assert_eq(key_events.size(), 1, "Reset should dedup to single default key")
