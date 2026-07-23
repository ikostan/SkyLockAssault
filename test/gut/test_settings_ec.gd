## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_settings_ec.gd
## Covers EC-01, EC-04, EC-05, EC-06, EC-07 from #351

extends "res://addons/gut/test.gd"

const TEST_ACTION: String = "speed_up"
var test_config_path: String = "user://test_settings_ec.cfg"
var invalid_path: String = "res://invalid/unwritable.cfg"  # Simulate permission/disk-full
var original_input_map: Dictionary = {}


func before_all() -> void:
	for act: String in InputMap.get_actions():
		original_input_map[act] = InputMap.action_get_events(act)


func after_all() -> void:
	for act in InputMap.get_actions():
		InputMap.action_erase_events(act)
	for act: String in original_input_map:
		if not InputMap.has_action(act):
			InputMap.add_action(act)
		for ev: InputEvent in original_input_map[act]:
			InputMap.action_add_event(act, ev)


func before_each() -> void:
	if FileAccess.file_exists(test_config_path):
		DirAccess.remove_absolute(test_config_path)
	for act: String in Settings.ACTIONS:
		if InputMap.has_action(act):
			InputMap.action_erase_events(act)
		else:
			InputMap.add_action(act)

	# Explicitly backfill defaults without setting _needs_save
	Settings._add_missing_defaults(ConfigFile.new())
	Settings._needs_save = false


func after_each() -> void:
	if FileAccess.file_exists(test_config_path):
		DirAccess.remove_absolute(test_config_path)

	# Restore real config after tests touching Settings.CONFIG_PATH
	var real_path: String = Settings.CONFIG_PATH
	var backup_path: String = "user://settings_backup.cfg"
	if FileAccess.file_exists(backup_path):
		DirAccess.copy_absolute(backup_path, real_path)
		DirAccess.remove_absolute(backup_path)
	await get_tree().process_frame


## EC-04 | Legacy config formats | Mixed old/new types | Backfill defaults, preserve valid
func test_ec_04_legacy_mixed_formats() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", TEST_ACTION, 87)                    # old int
	cfg.set_value("input", "speed_down", "key:88")             # old string key
	cfg.set_value("input", "fire", ["joybtn:0:-1"])            # new format
	cfg.set_value("input", "move_left", ["key:65", "key:66"])  # valid new

	# 1. Apply in-memory custom config
	Settings.apply_config_to_input_map(cfg)

	# 2. Explicitly trigger default backfilling for unmentioned actions
	Settings._add_missing_defaults(cfg)

	# speed_up should have migrated from old int
	var events := InputMap.action_get_events(TEST_ACTION)
	assert_true(events.any(func(e: InputEvent) -> bool:
		return e is InputEventKey and e.physical_keycode == 87
	))
	# defaults backfilled where missing
	assert_true(InputMap.action_get_events("pause").any(func(e: InputEvent) -> bool: return e is InputEventKey))


func test_ec_05_corrupt_parse_error() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", TEST_ACTION, ["invalid_format", "key:not_a_number", "joybtn:999:too:many:colons"])

	InputMap.action_erase_events(TEST_ACTION)

	# 1. Pure parse rejects garbage data (leaving speed_up empty)
	Settings.apply_config_to_input_map(cfg)
	assert_true(InputMap.action_get_events(TEST_ACTION).is_empty(), "Pure parser discards corrupt strings")

	# 2. Backfill fallback step restores default KEY_W
	Settings._add_missing_defaults(cfg)
	assert_false(InputMap.action_get_events(TEST_ACTION).is_empty(), "Defaults backfilled after corrupt reject")


## EC-06 | Save fails | Disk full / permission denied | Report error, no crash
func test_ec_06_save_fails_gracefully() -> void:
	Settings.save_input_mappings(invalid_path)

	assert_true(InputMap.has_action(TEST_ACTION))
	assert_false(FileAccess.file_exists(invalid_path))


## EC-07 | Partial config types | Extra unknown keys | Only known entries loaded
func test_ec_07_extra_unknown_keys_ignored() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", TEST_ACTION, ["key:87"])
	cfg.set_value("input", "non_existent_action", ["key:999"])  # not in ACTIONS
	cfg.set_value("other_section", "foo", "bar")

	Settings.apply_config_to_input_map(cfg)

	assert_true(cfg.has_section("other_section"))
	assert_false(InputMap.has_action("non_existent_action"))
	var events := InputMap.action_get_events(TEST_ACTION)
	assert_true(events.any(func(e: InputEvent) -> bool: return e is InputEventKey and e.physical_keycode == 87))


## EC-08 | Conflict unbind | FIRE unbound via conflict → saved as [] → reload → stays unbound
func test_ec_08_conflict_unbind_persists_after_reload() -> void:
	var fire_events: Array[InputEvent] = InputMap.action_get_events("fire")
	for ev: InputEvent in fire_events:
		if ev is InputEventKey and ev.physical_keycode == Settings.DEFAULT_KEYBOARD["fire"]:
			InputMap.action_erase_event("fire", ev)
			break

	var space_key: InputEventKey = InputEventKey.new()
	space_key.physical_keycode = KEY_SPACE
	InputMap.action_add_event("next_weapon", space_key)

	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("input", "fire", [])

	var next_serials: Array[String] = []
	for ev: InputEvent in InputMap.action_get_events("next_weapon"):
		next_serials.append(Settings.serialize_event(ev))
	cfg.set_value("input", "next_weapon", next_serials)

	Settings.apply_config_to_input_map(cfg)

	var fire_after: Array[InputEvent] = InputMap.action_get_events("fire")
	assert_eq(fire_after.size(), 0, "FIRE must stay unbound (no keyboard event)")


## EC-09 | Last device validation | Corrupted "last_input_device" in config | Falls back to "keyboard"
func test_ec_09_last_input_device_validation() -> void:
	var real_path: String = Settings.CONFIG_PATH
	var backup_path: String = "user://settings_backup.cfg"
	if FileAccess.file_exists(real_path):
		DirAccess.copy_absolute(real_path, backup_path)

	if FileAccess.file_exists(test_config_path):
		DirAccess.remove_absolute(test_config_path)

	var cfg := ConfigFile.new()
	cfg.set_value("input", "last_input_device", "mouse")
	cfg.save_encrypted_pass(test_config_path, Globals.ensure_encryption_key())

	DirAccess.copy_absolute(test_config_path, real_path)
	Settings.load_last_input_device()
	assert_eq(Globals.current_input_device, "keyboard", "Corrupted device must default to keyboard")

	cfg.set_value("input", "last_input_device", "gamepad")
	cfg.save_encrypted_pass(test_config_path, Globals.ensure_encryption_key())

	DirAccess.copy_absolute(test_config_path, real_path)
	Settings.load_last_input_device()
	assert_eq(Globals.current_input_device, "gamepad", "Valid device must load")

	cfg.erase_section_key("input", "last_input_device")
	cfg.set_value("meta", "empty", true)
	cfg.save_encrypted_pass(test_config_path, Globals.ensure_encryption_key())

	DirAccess.copy_absolute(test_config_path, real_path)
	Settings.load_last_input_device()
	assert_eq(Globals.current_input_device, "keyboard", "Missing key must default")

	if FileAccess.file_exists(backup_path):
		DirAccess.copy_absolute(backup_path, real_path)
		DirAccess.remove_absolute(backup_path)
	else:
		DirAccess.remove_absolute(real_path)


## EC-10 | Legacy migration | Old config with empty critical actions | Forces defaults once
func test_ec_10_legacy_migration() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("input", "fire", [])

	Settings.apply_config_to_input_map(cfg)

	Globals.remove_meta(Settings.LEGACY_MIGRATION_KEY)
	Settings._migrate_legacy_unbound_states()

	var fire_events: Array[InputEvent] = InputMap.action_get_events("fire")
	assert_true(
		fire_events.any(func(e: InputEvent) -> bool: return e is InputEventKey and e.physical_keycode == Settings.DEFAULT_KEYBOARD["fire"]),
		"Migration must force FIRE=Space"
	)


## EC-11 | Event labels | Keyboard keys | Correct string (e.g., "SPACE")
func test_ec_11_keyboard_event_label() -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = KEY_SPACE
	assert_eq(Settings.get_event_label(ev), "Space", "Keyboard label must be 'Space'")

	ev.physical_keycode = KEY_ESCAPE
	assert_eq(Settings.get_event_label(ev), "Escape", "Keyboard label must be 'Escape'")


## EC-12 | Event labels | Gamepad buttons | Cross-platform
func test_ec_12_gamepad_button_label() -> void:
	var ev: InputEventJoypadButton = InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_A
	assert_eq(Settings.get_event_label(ev), "A", "Button A must be 'A'")

	ev.button_index = JOY_BUTTON_START
	assert_eq(Settings.get_event_label(ev), "Start", "Start button label is not correct")


## EC-13 | Event labels | Gamepad axes | Direction-aware
func test_ec_13_gamepad_axis_label() -> void:
	var ev: InputEventJoypadMotion = InputEventJoypadMotion.new()
	ev.axis = JOY_AXIS_TRIGGER_RIGHT
	ev.axis_value = 1.0
	assert_eq(Settings.get_event_label(ev), "Right Trigger (+)", "Positive RT axis label correct")

	ev.axis_value = -1.0
	assert_eq(Settings.get_event_label(ev), "Right Trigger (-)", "Negative RT axis label correct")

	ev.axis = JOY_AXIS_LEFT_X
	ev.axis_value = 1.0
	assert_eq(Settings.get_event_label(ev), "Left Stick (Right)", "Left Stick right label correct")


## EC-14 | Pause label | Per device | Uppercase, unbound fallback
func test_ec_14_pause_binding_label_for_device() -> void:
	Globals.current_input_device = "keyboard"
	assert_eq(Settings.get_pause_binding_label_for_device("keyboard"), "ESCAPE", "Keyboard pause label should be 'ESCAPE'")

	Globals.current_input_device = "gamepad"
	assert_eq(Settings.get_pause_binding_label_for_device("gamepad"), "START", "Gamepad pause label is not correct")

	InputMap.action_erase_events("pause")
	assert_eq(Settings.get_pause_binding_label_for_device("keyboard"), "UNBOUND", "Unbound fallback should be 'UNBOUND'")
