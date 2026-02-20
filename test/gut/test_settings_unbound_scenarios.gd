## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_settings_unbound_scenarios.gd
## GUT unit tests for settings.gd unbound/missing scenarios.
## Covers first load/missing → defaults; explicit [] → unbound;
## load errors → fallback defaults; type mismatches/invalid → log + defaults if critical.
## References: settings.gd, key_mapping.gd, input_remap_button.gd,
##             test_integration_key_mapping.gd, test_key_mapping_menu.gd.
## Uses temp config path; instantiates menu for GUI checks.
## Expected: Fail initially on current code (e.g., missing → unbound instead of defaults).

extends GutTest

const TEST_CONFIG_PATH: String = "user://test_settings_unbound.cfg"
const TEST_ACTION: String = "speed_up"  # Real action from Settings.ACTIONS.
const CRITICAL_ACTION: String = "fire"  # Real critical from Settings.CRITICAL_ACTIONS.
const DEFAULT_KEY_CODE: int = KEY_W  # From Settings.DEFAULT_KEYBOARD[speed_up].
const DEFAULT_GAMEPAD_TYPE: String = "axis"  # From Settings.DEFAULT_GAMEPAD[speed_up].
const DEFAULT_GAMEPAD_AXIS: int = JOY_AXIS_TRIGGER_RIGHT
const DEFAULT_GAMEPAD_VALUE: float = 1.0

var menu: CanvasLayer = null
var config: ConfigFile = ConfigFile.new()
var speed_up_btn: InputRemapButton = null


## Per-suite: Backup real config.
func before_all() -> void:
	if FileAccess.file_exists(Settings.CONFIG_PATH):
		DirAccess.copy_absolute(Settings.CONFIG_PATH, "user://settings_backup_unbound.cfg")


## Per-test: Reset InputMap, delete temp config, load menu.
func before_each() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)

	# Reset legacy-migration meta so tests are independent.
	if Globals.has_meta(Settings.LEGACY_MIGRATION_KEY):
		Globals.remove_meta(Settings.LEGACY_MIGRATION_KEY)

	for action: String in Settings.ACTIONS:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action)
	menu = load("res://scenes/key_mapping_menu.tscn").instantiate()
	add_child(menu)
	speed_up_btn = menu.get_node("Panel/Options/KeyMapContainer/PlayerKeyMap/KeyMappingSpeedUp/SpeedUpInputRemap")
	# Default keyboard
	Globals.current_input_device = "keyboard"
	menu.keyboard.button_pressed = true
	menu.update_all_remap_buttons()


## Per-test: Free menu, delete temp.
func after_each() -> void:
	if is_instance_valid(menu):
		menu.queue_free()
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)
	await get_tree().process_frame


## Per-suite: Restore real config.
func after_all() -> void:
	if FileAccess.file_exists("user://settings_backup_unbound.cfg"):
		DirAccess.copy_absolute("user://settings_backup_unbound.cfg", Settings.CONFIG_PATH)
		DirAccess.remove_absolute("user://settings_backup_unbound.cfg")


## SCN-01 | First load/missing keys → set defaults in InputMap/GUI, save events.
func test_scn_01_first_load_missing_defaults() -> void:
	# No config → missing keys.
	Settings.load_input_mappings(TEST_CONFIG_PATH)  # Non-existent path.
	# InputMap: defaults added.
	var events: Array[InputEvent] = InputMap.action_get_events(TEST_ACTION)
	assert_eq(events.size(), 2, "Defaults: key + gamepad")
	var key_ev: InputEvent = events.filter(func(ev: InputEvent) -> bool: return ev is InputEventKey)[0]
	assert_eq(key_ev.physical_keycode, DEFAULT_KEY_CODE)
	var motion_ev: InputEvent = events.filter(func(ev: InputEvent) -> bool: return ev is InputEventJoypadMotion)[0]
	assert_eq(motion_ev.axis, DEFAULT_GAMEPAD_AXIS)
	assert_eq(motion_ev.axis_value, DEFAULT_GAMEPAD_VALUE)
	# GUI: "W" (not "Unbound")
	menu.update_all_remap_buttons()
	assert_eq(speed_up_btn.text, "W")
	# Save: events array (not [])
	Settings.save_input_mappings(TEST_CONFIG_PATH)
	config.load(TEST_CONFIG_PATH)
	var saved: Array = config.get_value("input", TEST_ACTION, [])
	assert_false(saved.is_empty(), "Saved defaults")


## SCN-02 | Explicit empty [] → unbound in InputMap/GUI, save [].
func test_scn_02_explicit_empty_unbound() -> void:
	# Config with [] for action.
	config.set_value("input", TEST_ACTION, [])
	config.save(TEST_CONFIG_PATH)
	Settings.load_input_mappings(TEST_CONFIG_PATH)
	# InputMap: no events.
	assert_true(InputMap.action_get_events(TEST_ACTION).is_empty())
	# GUI: "Unbound"
	menu.update_all_remap_buttons()
	assert_eq(speed_up_btn.text, "Unbound")
	# Save: still []
	Settings.save_input_mappings(TEST_CONFIG_PATH)
	config.load(TEST_CONFIG_PATH)
	var saved: Array = config.get_value("input", TEST_ACTION, [])
	assert_true(saved.is_empty(), "Saved unbound")


## SCN-03 | Load error (invalid path/corrupt) → log error, fallback defaults.
func test_scn_03_load_error_fallback() -> void:
	# Invalid path (non-existent, but simulate corrupt by writing junk).
	var file: FileAccess = FileAccess.open(TEST_CONFIG_PATH, FileAccess.WRITE)
	file.store_string("invalid_config_data")  # Not valid ConfigFile.
	file.close()
	Settings.load_input_mappings(TEST_CONFIG_PATH)
	# Log: error (assume printed; no direct assert).
	# Fallback: defaults in InputMap.
	var events: Array[InputEvent] = InputMap.action_get_events(TEST_ACTION)
	assert_eq(events.size(), 2, "Fallback defaults")


## SCN-04 | Type mismatch (non-array) → log warning, default if critical.
func test_scn_04_type_mismatch_default_critical() -> void:
	# Non-array for critical.
	config.set_value("input", CRITICAL_ACTION, "string_instead_of_array")
	config.save(TEST_CONFIG_PATH)
	Settings.load_input_mappings(TEST_CONFIG_PATH)
	# Log: warning.
	# Critical: default added.
	var events: Array[InputEvent] = InputMap.action_get_events(CRITICAL_ACTION)
	assert_false(events.is_empty(), "Default for critical mismatch")


## SCN-05 | Invalid entries (bad strings) → skip invalid, default if needed.
func test_scn_05_invalid_entries_skip() -> void:
	# Bad string in array.
	config.set_value("input", TEST_ACTION, ["invalid:event"])
	config.save(TEST_CONFIG_PATH)
	Settings.load_input_mappings(TEST_CONFIG_PATH)
	# "invalid:event" has no recognised prefix ("key:", "joybtn:", "joyaxis:"),
	# so _add_missing_defaults treats it as an explicit unbind for both devices — no defaults added.
	assert_true(InputMap.action_get_events(TEST_ACTION).is_empty())
	# GUI: "Unbound"
	menu.update_all_remap_buttons()
	assert_eq(speed_up_btn.text, "Unbound")


## SCN-06 | Legacy migration critical empty → force defaults.
func test_scn_06_legacy_migration_defaults() -> void:
	Globals.set_meta(Settings.LEGACY_MIGRATION_KEY, false)
	config.set_value("input", CRITICAL_ACTION, [])
	config.save(TEST_CONFIG_PATH)
	Settings.load_input_mappings(TEST_CONFIG_PATH)
	Settings._migrate_legacy_unbound_states()  # Manual call for test.
	Globals.set_meta(Settings.LEGACY_MIGRATION_KEY, true)  # Mimic.
	var events: Array[InputEvent] = InputMap.action_get_events(CRITICAL_ACTION)
	assert_eq(events.size(), 2, "Migration defaults")


## SCN-07 | Legacy migration critical empty adds defaults.
func test_scn_07_legacy_critical_empty_adds_defaults() -> void:
	Globals.set_meta(Settings.LEGACY_MIGRATION_KEY, false)
	config.set_value("input", TEST_ACTION, [])  # Empty.
	config.save(TEST_CONFIG_PATH)
	Settings.load_input_mappings(TEST_CONFIG_PATH)
	Settings._migrate_legacy_unbound_states()  # Manual call for test.
	Globals.set_meta(Settings.LEGACY_MIGRATION_KEY, true)  # Mimic.
	var events: Array[InputEvent] = InputMap.action_get_events(TEST_ACTION)
	assert_eq(events.size(), 2, "Critical legacy empty adds defaults")
	menu.update_all_remap_buttons()
	assert_ne(speed_up_btn.text, "Unbound")
	assert_true(Globals.has_meta(Settings.LEGACY_MIGRATION_KEY))


## SCN-08 | Legacy menu controls empty → force defaults after migration (mimic screenshot bug).
func test_scn_08_legacy_menu_unbound_defaults() -> void:
	# Simulate legacy: explicit [] for unbound menu actions (ui_accept, ui_up, etc.), default for pause/player.
	Globals.set_meta(Settings.LEGACY_MIGRATION_KEY, false)
	# Set [] for unbound in screenshot.
	var menu_actions: Array[String] = ["ui_accept", "ui_up", "ui_down", "ui_left", "ui_right"]
	for act: String in menu_actions:
		config.set_value("input", act, [])
	# Set default for pause (bound in screenshot).
	var pause_ev: Array = ["key:" + str(KEY_ESCAPE)]  # Assume string serialization.
	config.set_value("input", "pause", pause_ev)
	# Player defaults (bound).
	for act: String in ["speed_up", "move_left"]:  # Sample.
		var key_code: int = Settings.DEFAULT_KEYBOARD[act]
		config.set_value("input", act, ["key:" + str(key_code)])
	config.save(TEST_CONFIG_PATH)
	Settings.load_input_mappings(TEST_CONFIG_PATH)
	Settings._migrate_legacy_unbound_states()  # Manual call.
	Globals.set_meta(Settings.LEGACY_MIGRATION_KEY, true)
	# Update GUI.
	menu.update_all_remap_buttons()
	# Assert unbound in screenshot are now defaults (fails now, passes after fix).
	var accept_btn: InputRemapButton = menu.get_node("Panel/Options/KeyMapContainer/MenuKeyMap/KeyMappingAccept/AcceptInputRemap")
	assert_eq(accept_btn.text, "Enter", "Accept should default to Enter")
	var menu_up_btn: InputRemapButton = menu.get_node("Panel/Options/KeyMapContainer/MenuKeyMap/KeyMappingMenuUp/MenuUpInputRemap")
	assert_eq(menu_up_btn.text, "Up", "Menu Up should default to Up")
	var menu_down_btn: InputRemapButton = menu.get_node("Panel/Options/KeyMapContainer/MenuKeyMap/KeyMappingMenuDown/MenuDownInputRemap")
	assert_eq(menu_down_btn.text, "Down", "Menu Down should default to Down")
	var menu_left_btn: InputRemapButton = menu.get_node("Panel/Options/KeyMapContainer/MenuKeyMap/KeyMappingMenuLeft/MenuLeftInputRemap")
	assert_eq(menu_left_btn.text, "Left", "Menu Left should default to Left")
	var menu_right_btn: InputRemapButton = menu.get_node("Panel/Options/KeyMapContainer/MenuKeyMap/KeyMappingMenuRight/MenuRightInputRemap")
	assert_eq(menu_right_btn.text, "Right", "Menu Right should default to Right")
	# Pause remains bound.
	var pause_btn: InputRemapButton = menu.get_node("Panel/Options/KeyMapContainer/MenuKeyMap/KeyMappingPause/PauseInputRemap")
	assert_eq(pause_btn.text, "Escape", "Pause remains Esc")
	# Sample player bound.
	assert_eq(speed_up_btn.text, "W", "Speed Up remains W")


## SCN-09 | Verify updated CRITICAL_ACTIONS includes menu navigation.
func test_scn_09_critical_actions_includes_menu() -> void:
	var crit: Array[String] = Settings.CRITICAL_ACTIONS
	assert_true(crit.has("ui_accept"))
	assert_true(crit.has("ui_up"))
	assert_true(crit.has("ui_down"))
	assert_true(crit.has("ui_left"))
	assert_true(crit.has("ui_right"))
	assert_true(crit.has("fire"))  # Sample original.


## SCN-10 | Verify old CRITICAL_ACTIONS subset (pre-update).
func test_scn_10_old_critical_actions() -> void:
	var old_expected: Array[String] = ["fire", "speed_up", "speed_down", "move_left", "move_right", "next_weapon", "pause"]
	for act: String in old_expected:
		assert_true(Settings.CRITICAL_ACTIONS.has(act), act + " in old critical")


## SCN-11 | Verify new menu actions added to CRITICAL_ACTIONS.
func test_scn_11_new_menu_critical_actions() -> void:
	var new_expected: Array[String] = ["ui_accept", "ui_up", "ui_down", "ui_left", "ui_right"]
	for act: String in new_expected:
		assert_true(Settings.CRITICAL_ACTIONS.has(act), act + " added to critical")
	assert_eq(Settings.CRITICAL_ACTIONS.size(), 12, "Total critical actions")


## SCN-15 | Joypad labels simplified without " / ".
func test_scn_15_joypad_labels_simplified() -> void:
	var ev: InputEventJoypadButton = InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_A
	assert_eq(Settings.get_event_label(ev), "A", "Simplified A")
	ev.button_index = JOY_BUTTON_B
	assert_eq(Settings.get_event_label(ev), "B", "Simplified B")
	ev.button_index = JOY_BUTTON_X
	assert_eq(Settings.get_event_label(ev), "X", "Simplified X")
	ev.button_index = JOY_BUTTON_Y
	assert_eq(Settings.get_event_label(ev), "Y", "Simplified Y")
	ev.button_index = JOY_BUTTON_LEFT_SHOULDER
	assert_eq(Settings.get_event_label(ev), "LB", "Simplified LB")
	ev.button_index = JOY_BUTTON_RIGHT_SHOULDER
	assert_eq(Settings.get_event_label(ev), "RB", "Simplified RB")


## SCN-16 | Migration flag persists in config.
func test_scn_16_migration_flag_persists() -> void:
	# Run migration against TEST config
	Settings.load_input_mappings(TEST_CONFIG_PATH)
	Settings._migrate_legacy_unbound_states()
	Settings.save_input_mappings(TEST_CONFIG_PATH)

	var cfg := ConfigFile.new()
	cfg.load(TEST_CONFIG_PATH)

	assert_true(
		cfg.get_value("meta", Settings.LEGACY_MIGRATION_KEY, false),
		"Migration flag must persist in test config"
	)


## SCN-17 | Unbound critical stays unbound after restart simulation.
func test_scn_17_unbound_critical_persists() -> void:
	InputMap.action_erase_events(CRITICAL_ACTION)
	Settings.save_input_mappings(TEST_CONFIG_PATH)
	Settings.load_input_mappings(TEST_CONFIG_PATH)
	assert_true(InputMap.action_get_events(CRITICAL_ACTION).is_empty(), "Unbound persists")
