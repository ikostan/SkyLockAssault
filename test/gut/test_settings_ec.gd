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
	Settings.load_input_mappings(test_config_path)
	
	# NEW: Backup real config before EC-09 (if exists)
	var real_path: String = Settings.CONFIG_PATH
	if FileAccess.file_exists(real_path):
		var backup_path: String = "user://settings_backup.cfg"
		DirAccess.copy_absolute(real_path, backup_path)
	else:
		var backup_path: String = ""  # No backup if missing


func after_each() -> void:
	if FileAccess.file_exists(test_config_path):
		DirAccess.remove_absolute(test_config_path)
	
	# NEW: Restore real config after EC-09
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
	cfg.save(test_config_path)
	Settings.load_input_mappings(test_config_path)

	# speed_up should have migrated from old int
	var events := InputMap.action_get_events(TEST_ACTION)
	assert_true(events.any(func(e: InputEvent) -> bool:
		return e is InputEventKey and e.physical_keycode == 87
	))
	# defaults backfilled where missing
	assert_true(InputMap.action_get_events("pause").any(func(e: InputEvent) -> bool: return e is InputEventKey))


## EC-05 | Config unreadable | Corrupt JSON/parse error | Load defaults | Log error
func test_ec_05_corrupt_parse_error() -> void:
	# Simulate corrupt cfg file
	var f := FileAccess.open(test_config_path, FileAccess.WRITE)
	f.store_string("{invalid cfg data\n[broken")
	f.close()

	Settings.load_input_mappings(test_config_path)  # should still fall back to defaults

	var events := InputMap.action_get_events(TEST_ACTION)
	assert_eq(events.size(), 2)
	assert_true(events.any(func(e: InputEvent) -> bool: return e is InputEventKey and e.physical_keycode == Settings.DEFAULT_KEYBOARD[TEST_ACTION]))
	assert_true(events.any(func(e: InputEvent) -> bool: return e is InputEventJoypadMotion and e.axis == Settings.DEFAULT_GAMEPAD[TEST_ACTION]["axis"] and e.axis_value == Settings.DEFAULT_GAMEPAD[TEST_ACTION]["value"]))


## EC-06 | Save fails | Disk full / permission denied | Report error, no crash
func test_ec_06_save_fails_gracefully() -> void:
	# Force failure path
	Settings.save_input_mappings(invalid_path)

	# No crash occurred, InputMap is still valid
	assert_true(InputMap.has_action(TEST_ACTION))
	# File was not created
	assert_false(FileAccess.file_exists(invalid_path))


## EC-07 | Partial config types | Extra unknown keys | Only known entries loaded
func test_ec_07_extra_unknown_keys_ignored() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", TEST_ACTION, ["key:87"])
	cfg.set_value("input", "non_existent_action", ["key:999"])  # not in ACTIONS
	cfg.set_value("other_section", "foo", "bar")
	cfg.save(test_config_path)

	Settings.load_input_mappings(test_config_path)
	Settings.save_input_mappings(test_config_path)  # round-trip

	cfg = ConfigFile.new()
	cfg.load(test_config_path)
	assert_true(cfg.has_section("other_section"))  # preserved
	assert_false(InputMap.has_action("non_existent_action"))  # ignored


## EC-08 | Conflict unbind | FIRE unbound via conflict → saved as [] → reload → stays unbound | NEXT_WEAPON keeps Space.
## Catches PR#409 regression: unbound must persist across restarts.
## :rtype: void
func test_ec_08_conflict_unbind_persists_after_reload() -> void:
	# Clean defaults (before_each already did this, but we keep it explicit)
	Settings.load_input_mappings(test_config_path)

	# Simulate conflict: unbind FIRE (erase its keyboard event)
	var fire_events: Array[InputEvent] = InputMap.action_get_events("fire")
	for ev: InputEvent in fire_events:
		if ev is InputEventKey and ev.physical_keycode == Settings.DEFAULT_KEYBOARD["fire"]:
			InputMap.action_erase_event("fire", ev)
			break

	# Bind the conflicting event to NEXT_WEAPON (Space)
	var space_key: InputEventKey = InputEventKey.new()
	space_key.physical_keycode = KEY_SPACE
	InputMap.action_add_event("next_weapon", space_key)

	# Force the unbound state into the config file (this is the exact case we must protect)
	# This replaces the normal save_input_mappings so we 100% guarantee [] for FIRE
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(test_config_path)
	cfg.set_value("input", "fire", [])  # <-- explicit unbound

	# NEXT_WEAPON now has its original Q + the new Space
	var next_serials: Array[String] = []
	for ev: InputEvent in InputMap.action_get_events("next_weapon"):
		next_serials.append(Settings.serialize_event(ev))
	cfg.set_value("input", "next_weapon", next_serials)

	cfg.save(test_config_path)

	# Reload (exact game-restart simulation)
	Settings.load_input_mappings(test_config_path)

	# FIRE must stay unbound (no events at all)
	var fire_after: Array[InputEvent] = InputMap.action_get_events("fire")
	assert_eq(fire_after.size(), 0, "FIRE must stay unbound after reload (no keyboard event)")

	# NEXT_WEAPON must keep the Space we gave it
	var next_weapon_after: Array[InputEvent] = InputMap.action_get_events("next_weapon")
	assert_true(
		next_weapon_after.any(
			func(e: InputEvent) -> bool: return e is InputEventKey and e.physical_keycode == KEY_SPACE
		),
		"NEXT_WEAPON must keep Space"
	)

	# Bonus: RESET must restore defaults (it bypasses the unbound flag)
	Settings.reset_to_defaults("keyboard")
	var fire_reset: Array[InputEvent] = InputMap.action_get_events("fire")
	assert_true(
		fire_reset.any(
			func(e: InputEvent) -> bool: return e is InputEventKey and e.physical_keycode == Settings.DEFAULT_KEYBOARD["fire"]
		),
		"RESET must restore FIRE=Space"
	)

	Globals.log_message("EC-08 PASSED – unbound FIRE persisted, RESET works", Globals.LogLevel.DEBUG)


## EC-09 | Last device validation | Corrupted "last_input_device" in config | Falls back to "keyboard"
## Prevents bad config from breaking device state.
## Uses test_config_path + backup/restore of real config to avoid mutation.
## :rtype: void
func test_ec_09_last_input_device_validation() -> void:
	# Backup real config (protects your local settings.cfg)
	var real_path: String = Settings.CONFIG_PATH
	var backup_path: String = "user://settings_backup.cfg"
	if FileAccess.file_exists(real_path):
		DirAccess.copy_absolute(real_path, backup_path)
	
	# Use test_config_path for isolation
	if FileAccess.file_exists(test_config_path):
		DirAccess.remove_absolute(test_config_path)
	
	# Corrupted case
	var cfg := ConfigFile.new()
	cfg.set_value("input", "last_input_device", "mouse")  # Invalid!
	cfg.save(test_config_path)
	
	# Copy test config to real path for load (temp override)
	DirAccess.copy_absolute(test_config_path, real_path)
	Settings.load_last_input_device()
	assert_eq(Globals.current_input_device, "keyboard", "Corrupted device must default to keyboard")
	
	# Valid case
	cfg.set_value("input", "last_input_device", "gamepad")
	cfg.save(test_config_path)
	DirAccess.copy_absolute(test_config_path, real_path)
	Settings.load_last_input_device()
	assert_eq(Globals.current_input_device, "gamepad", "Valid device must load")
	
	# Missing key
	cfg.erase_section_key("input", "last_input_device")
	cfg.save(test_config_path)
	DirAccess.copy_absolute(test_config_path, real_path)
	Settings.load_last_input_device()
	assert_eq(Globals.current_input_device, "keyboard", "Missing key must default")
	
	# Restore original config
	if FileAccess.file_exists(backup_path):
		DirAccess.copy_absolute(backup_path, real_path)
		DirAccess.remove_absolute(backup_path)
	else:
		DirAccess.remove_absolute(real_path)  # No original existed
	
	Globals.log_message("EC-09 PASSED – device validation works", Globals.LogLevel.DEBUG)


## EC-10 | Legacy migration | Old config with empty critical actions | Forces defaults once | "Unbound" labels fixed.
## :rtype: void
func test_ec_10_legacy_migration() -> void:
	# Simulate old config with unbound critical (FIRE = [])
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("input", "fire", [])  # Legacy unbound
	cfg.save(test_config_path)
	
	# Load the [] into InputMap (critical step)
	Settings.load_input_mappings(test_config_path)
	
	# Force migration (bypass has_meta)
	Globals.remove_meta(Settings.LEGACY_MIGRATION_KEY)
	Settings._migrate_legacy_unbound_states()
	
	# FIRE now has default (migration worked)
	var fire_events: Array[InputEvent] = InputMap.action_get_events("fire")
	assert_true(
		fire_events.any(func(e: InputEvent) -> bool: return e is InputEventKey and e.physical_keycode == Settings.DEFAULT_KEYBOARD["fire"]),
		"Migration must force FIRE=Space"
	)
	
	# Flag set (won't re-run) -- now inside the helper
	assert_true(Globals.has_meta(Settings.LEGACY_MIGRATION_KEY))
	
	Globals.log_message("EC-10 PASSED – legacy migration forces defaults", Globals.LogLevel.DEBUG)


## EC-11 | Event labels | Keyboard keys | Correct string (e.g., "SPACE")
## :rtype: void
func test_ec_11_keyboard_event_label() -> void:
	var ev: InputEventKey = InputEventKey.new()
	# 1
	ev.physical_keycode = KEY_SPACE
	print("expected ev: " + str(ev.physical_keycode) + " actual ev: " + Settings.get_event_label(ev))
	assert_eq(Settings.get_event_label(ev), "Space", "Keyboard label must be 'Space'")
	# 2
	ev.physical_keycode = KEY_ESCAPE
	print("expected ev: " + str(ev.physical_keycode) + " actual ev: " + Settings.get_event_label(ev))
	assert_eq(Settings.get_event_label(ev), "Escape", "Keyboard label must be 'Escape'")  # Adjust if your logic uses short form


## EC-12 | Event labels | Gamepad buttons | Cross-platform (e.g., "A / X")
## :rtype: void
func test_ec_12_gamepad_button_label() -> void:
	var ev: InputEventJoypadButton = InputEventJoypadButton.new()
	# 1
	ev.button_index = JOY_BUTTON_A
	print("expected ev: " + str(ev.button_index) + " actual ev: " + Settings.get_event_label(ev))
	assert_eq(Settings.get_event_label(ev), "A", "Button A must be 'A'")
	# 2
	ev.button_index = JOY_BUTTON_START
	print("expected ev: " + str(ev.button_index) + " actual ev: " + Settings.get_event_label(ev))
	assert_eq(Settings.get_event_label(ev), "Start", "Start button label is not correct")


## EC-13 | Event labels | Gamepad axes | Direction-aware (e.g., "RT (+)")
## :rtype: void
func test_ec_13_gamepad_axis_label() -> void:
	var ev: InputEventJoypadMotion = InputEventJoypadMotion.new()
	# 1
	ev.axis = JOY_AXIS_TRIGGER_RIGHT
	ev.axis_value = 1.0
	assert_eq(Settings.get_event_label(ev), "RT (+)", "Positive RT axis label correct")
	# 2
	ev.axis_value = -1.0
	assert_eq(Settings.get_event_label(ev), "RT (-)", "Negative RT axis label correct")
	# 3
	ev.axis = JOY_AXIS_LEFT_X
	ev.axis_value = 1.0
	assert_eq(Settings.get_event_label(ev), "Left Stick (Right)", "Left Stick right label correct")


## EC-14 | Pause label | Per device | Uppercase, unbound fallback
## :rtype: void
func test_ec_14_pause_binding_label_for_device() -> void:
	# Keyboard
	Globals.current_input_device = "keyboard"
	print("actual ev: " + Settings.get_pause_binding_label_for_device("keyboard"))
	assert_eq(Settings.get_pause_binding_label_for_device("keyboard"), "ESCAPE", "Keyboard pause label should be 'ESCAPE'")
	# Gamepad
	Globals.current_input_device = "gamepad"
	print("actual ev: " + Settings.get_pause_binding_label_for_device("gamepad"))
	assert_eq(Settings.get_pause_binding_label_for_device("gamepad"), "START", "Gamepad pause label is not correct")
	# Unbound case (erase pause events)
	InputMap.action_erase_events("pause")
	print("actual ev: " + Settings.get_pause_binding_label_for_device("pause"))
	assert_eq(Settings.get_pause_binding_label_for_device("keyboard"), "UNBOUND", "Unbound fallback should be 'UNBOUND'")
