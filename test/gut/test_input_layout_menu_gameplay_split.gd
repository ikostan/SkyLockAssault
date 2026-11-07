## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_input_layout_menu_gameplay_split.gd
## GUT regression tests for the menu/gameplay input split.
##
## Bug: after the first save, the menu arrows showed "Unbound" on the Key Mapping screen and
## the "Unbound Controls" dialog appeared on start. Causes: keycode-only arrow events were
## saved as "key:0", and the arrow keys and left stick were bound to both flight and menu
## actions, so the load-time conflict check stripped one side.
##
## Covers: one default per action per device, project.godot matching Settings defaults,
## the agreed layout, scoped conflict groups, keycode fallback in serialize_event,
## save/reload keeping both sides, and the one-time v3 migration of broken saves.
## :references: settings.gd, project.godot [input]

extends GutTest

const TEST_CONFIG_PATH: String = "user://test_input_layout_split.cfg"

## Agreed default layout: [action, keyboard label, gamepad label].
const LAYOUT: Array = [
	["speed_up", "W", "Left Stick (Up)"],
	["speed_down", "S", "Left Stick (Down)"],
	["move_left", "A", "Left Stick (Left)"],
	["move_right", "D", "Left Stick (Right)"],
	["fire", "Space", "A"],
	["next_weapon", "Q", "Y"],
	["pause", "Escape", "Start"],
	["ui_up", "Up", "D-Pad Up"],
	["ui_down", "Down", "D-Pad Down"],
	["ui_left", "Left", "D-Pad Left"],
	["ui_right", "Right", "D-Pad Right"],
	["ui_accept", "Enter", "A"],
	["ui_focus_next", "Tab", "RB"],
	["ui_focus_prev", "Shift+Tab", "LB"],
]

var _saved_events: Dictionary = {}
var _saved_device: String = ""
var _had_v2_flag: bool = false
var _had_v3_flag: bool = false


## Per-test: Snapshot InputMap, device and migration flags, then start from project defaults.
func before_each() -> void:
	_saved_events.clear()
	for action: String in Settings.ACTIONS:
		var copies: Array[InputEvent] = []
		for ev: InputEvent in InputMap.action_get_events(action):
			copies.append(ev.duplicate())
		_saved_events[action] = copies
	_saved_device = Globals.current_input_device
	_had_v2_flag = Globals.has_meta(Settings.LEGACY_MIGRATION_KEY)
	_had_v3_flag = Globals.has_meta(Settings.INPUT_LAYOUT_MIGRATION_KEY)
	_remove_file(TEST_CONFIG_PATH)
	_load_project_defaults()
	Settings.set_needs_save_for_test(false)


## Per-test: Restore InputMap, device, flags and remove the temp config.
func after_each() -> void:
	for action: String in _saved_events:
		InputMap.action_erase_events(action)
		for ev: InputEvent in _saved_events[action]:
			InputMap.action_add_event(action, ev)
	Globals.current_input_device = _saved_device
	_set_flag(Settings.LEGACY_MIGRATION_KEY, _had_v2_flag)
	_set_flag(Settings.INPUT_LAYOUT_MIGRATION_KEY, _had_v3_flag)
	Settings.set_needs_save_for_test(false)
	_remove_file(TEST_CONFIG_PATH)
	await get_tree().process_frame


# ── Helpers ──────────────────────────────────────────────────────────────────


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _set_flag(key: String, value: bool) -> void:
	if value:
		Globals.set_meta(key, true)
	elif Globals.has_meta(key):
		Globals.remove_meta(key)


## Resets the managed actions to project.godot [input] without touching other actions.
func _load_project_defaults() -> void:
	for action: String in Settings.ACTIONS:
		InputMap.action_erase_events(action)
		var setting: Dictionary = ProjectSettings.get_setting("input/" + action, {})
		for ev: InputEvent in setting.get("events", []):
			InputMap.action_add_event(action, ev.duplicate())


func _events_for(action: String, device: String) -> Array[InputEvent]:
	var found: Array[InputEvent] = []
	for ev: InputEvent in InputMap.action_get_events(action):
		if Settings.get_event_device_type(ev) == device:
			found.append(ev)
	return found


func _labels_for(action: String, device: String) -> Array[String]:
	var labels: Array[String] = []
	for ev: InputEvent in _events_for(action, device):
		labels.append(Settings.get_event_label(ev))
	return labels


func _key(code: Key, shift: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.shift_pressed = shift
	return ev


## A key event the way Godot's built-in actions store it: keycode only, physical 0.
func _keycode_only(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	return ev


func _button(index: JoyButton) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = index
	ev.device = -1
	return ev


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	ev.device = -1
	return ev


func _set_events(action: String, events: Array) -> void:
	InputMap.action_erase_events(action)
	for ev: InputEvent in events:
		InputMap.action_add_event(action, ev)


func _write_config(bindings: Dictionary) -> void:
	var config := ConfigFile.new()
	for action: String in bindings:
		config.set_value("input", action, bindings[action])
	var err: int = config.save_encrypted_pass(TEST_CONFIG_PATH, Globals.save_encryption_pass)
	assert_eq(err, OK, "Precondition: encrypted fixture written")


## Recreates InputMap exactly as the pre-fix layout left it on first launch: built-in
## keycode-only menu keys plus left stick on the ui_* actions, and hidden arrow keys on flight.
func _apply_pre_fix_layout() -> void:
	_set_events("speed_up", [_key(KEY_W), _axis(JOY_AXIS_LEFT_Y, -1.0), _key(KEY_UP)])
	_set_events("speed_down", [_key(KEY_X), _axis(JOY_AXIS_LEFT_Y, 1.0), _key(KEY_DOWN)])
	_set_events("move_left", [_key(KEY_A), _axis(JOY_AXIS_LEFT_X, -1.0), _key(KEY_LEFT)])
	_set_events("move_right", [_key(KEY_D), _axis(JOY_AXIS_LEFT_X, 1.0), _key(KEY_RIGHT)])
	_set_events(
		"ui_up", [_keycode_only(KEY_UP), _button(JOY_BUTTON_DPAD_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)]
	)
	_set_events(
		"ui_down",
		[_keycode_only(KEY_DOWN), _button(JOY_BUTTON_DPAD_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)]
	)
	_set_events(
		"ui_left",
		[_keycode_only(KEY_LEFT), _button(JOY_BUTTON_DPAD_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)]
	)
	_set_events(
		"ui_right",
		[_keycode_only(KEY_RIGHT), _button(JOY_BUTTON_DPAD_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)]
	)


# ── Defaults ─────────────────────────────────────────────────────────────────


## LAYOUT-01 | Every action has exactly one keyboard and one gamepad default in project.godot.
func test_layout_01_project_has_one_binding_per_device(
	action: String = use_parameters(Settings.ACTIONS)
) -> void:
	assert_eq(_events_for(action, "keyboard").size(), 1, "%s: one keyboard binding" % action)
	assert_eq(_events_for(action, "gamepad").size(), 1, "%s: one gamepad binding" % action)


## LAYOUT-02 | project.godot [input] and Settings.DEFAULT_* describe the same layout.
func test_layout_02_project_matches_settings_defaults(
	action: String = use_parameters(Settings.ACTIONS)
) -> void:
	for device: String in ["keyboard", "gamepad"]:
		var expected: InputEvent = Settings.InputDefaults.make_event(action, device)
		assert_not_null(expected, "%s has a %s default" % [action, device])
		var actual: Array[InputEvent] = _events_for(action, device)
		assert_eq(actual.size(), 1, "%s: one %s binding" % [action, device])
		if expected == null or actual.size() != 1:
			continue
		assert_true(
			Settings.events_match(actual[0], expected),
			(
				"%s %s: project.godot %s != Settings %s"
				% [
					action,
					device,
					Settings.get_event_label(actual[0]),
					Settings.get_event_label(expected)
				]
			)
		)


## LAYOUT-03 | The defaults are the agreed layout (labels as the Key Mapping screen shows them).
func test_layout_03_agreed_default_layout(row: Array = use_parameters(LAYOUT)) -> void:
	var action: String = row[0]
	assert_eq(_labels_for(action, "keyboard"), [row[1]] as Array[String], action + " keyboard")
	assert_eq(_labels_for(action, "gamepad"), [row[2]] as Array[String], action + " gamepad")


## LAYOUT-04 | No default conflicts with another default in its conflict group.
func test_layout_04_defaults_have_no_group_conflicts(
	action: String = use_parameters(Settings.ACTIONS)
) -> void:
	for device: String in ["keyboard", "gamepad"]:
		var ev: InputEvent = Settings.InputDefaults.make_event(action, device)
		assert_eq(
			Settings.get_conflicting_actions(ev, action),
			[] as Array[String],
			"%s %s default is free in its group" % [action, device]
		)


## LAYOUT-05 | With project defaults, no critical action is unbound on either device.
func test_layout_05_no_unbound_critical_on_either_device() -> void:
	for device: String in ["keyboard", "gamepad"]:
		Globals.current_input_device = device
		assert_false(
			Settings.has_unbound_critical_actions_for_current_device(),
			"no Unbound Controls dialog for " + device
		)


# ── Conflict groups ──────────────────────────────────────────────────────────


## GROUP-01 | Gameplay actions are scoped to gameplay, menu actions to menus.
func test_group_01_conflict_scope() -> void:
	assert_eq(
		Settings.InputDefaults.conflict_scope("speed_up", Settings.ACTIONS),
		Settings.GAMEPLAY_ACTIONS
	)
	assert_eq(
		Settings.InputDefaults.conflict_scope("ui_accept", Settings.ACTIONS), Settings.MENU_ACTIONS
	)


## GROUP-02 | Pause, empty and unknown actions are checked against every managed action.
func test_group_02_pause_empty_unknown_scope_all(
	action: String = use_parameters(["pause", "", "not_a_real_action"])
) -> void:
	assert_eq(Settings.InputDefaults.conflict_scope(action, Settings.ACTIONS), Settings.ACTIONS)


## GROUP-03 | A menu action may share an input with a gameplay action (A = Fire and Accept).
func test_group_03_menu_and_gameplay_may_share() -> void:
	assert_eq(
		Settings.get_conflicting_actions(_button(JOY_BUTTON_A), "ui_accept"),
		[] as Array[String],
		"Accept on A does not conflict with Fire"
	)
	assert_eq(
		Settings.get_conflicting_actions(_key(KEY_UP), "speed_up"),
		[] as Array[String],
		"Speed Up on the Up arrow does not conflict with Menu Up"
	)


## GROUP-04 | Conflicts inside a group are still reported.
func test_group_04_same_group_still_conflicts() -> void:
	assert_eq(
		Settings.get_conflicting_actions(_key(KEY_SPACE), "next_weapon"),
		["fire"] as Array[String],
		"two flight actions cannot share Space"
	)
	assert_eq(
		Settings.get_conflicting_actions(_key(KEY_TAB), "ui_accept"),
		["ui_focus_next"] as Array[String],
		"two menu actions cannot share Tab"
	)


## GROUP-05 | Pause conflicts with both groups: it is pressed in flight and in menus.
func test_group_05_pause_conflicts_with_both_groups() -> void:
	assert_eq(
		Settings.get_conflicting_actions(_key(KEY_ESCAPE), "fire"),
		["pause"] as Array[String],
		"a flight action cannot take Escape"
	)
	assert_eq(
		Settings.get_conflicting_actions(_button(JOY_BUTTON_START), "ui_accept"),
		["pause"] as Array[String],
		"a menu action cannot take Start"
	)
	assert_eq(
		Settings.get_conflicting_actions(_button(JOY_BUTTON_A), "pause"),
		["fire", "ui_accept"] as Array[String],
		"pause cannot take A from either group"
	)


# ── Serialization ────────────────────────────────────────────────────────────


## SER-01 | A keycode-only key (Godot built-in style) is saved by its keycode, not as key:0.
func test_ser_01_keycode_only_event_is_not_saved_as_zero(
	code: int = use_parameters([KEY_UP, KEY_ENTER, KEY_TAB, KEY_W])
) -> void:
	var serialized: String = Settings.serialize_event(_keycode_only(code))
	assert_eq(serialized, "key:%d" % code)
	var restored: InputEvent = Settings.deserialize_event(serialized)
	assert_not_null(restored, "the saved key loads back")
	if restored:
		assert_eq(restored.physical_keycode, code, "loads back as the same physical key")


## SER-02 | Modifiers are kept for keycode-only events (built-in Shift+Tab).
func test_ser_02_keycode_only_keeps_modifiers() -> void:
	var ev: InputEventKey = _keycode_only(KEY_TAB)
	ev.shift_pressed = true
	assert_eq(Settings.serialize_event(ev), "key:%d:shift" % KEY_TAB)


## SER-03 | physical_keycode still wins when both are set.
func test_ser_03_physical_keycode_preferred() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.keycode = KEY_Z
	assert_eq(Settings.serialize_event(ev), "key:%d" % KEY_W)


# ── Save / reload regression (the reported bug) ──────────────────────────────


## REG-01 | Save then reload keeps menu arrows and flight sticks bound (the original bug).
func test_reg_01_save_reload_keeps_menu_and_flight_bindings() -> void:
	_apply_pre_fix_layout()
	Settings.save_input_mappings(TEST_CONFIG_PATH)
	Settings.load_input_mappings(TEST_CONFIG_PATH)

	for row: Array in [["ui_up", "Up"], ["ui_down", "Down"], ["ui_left", "Left"]]:
		assert_eq(
			_labels_for(row[0], "keyboard"), [row[1]] as Array[String], row[0] + " keeps its key"
		)
	assert_eq(
		_labels_for("ui_right", "keyboard"), ["Right"] as Array[String], "ui_right keeps its key"
	)
	assert_eq(
		_labels_for("speed_up", "gamepad"),
		["Left Stick (Up)"] as Array[String],
		"speed_up keeps its stick"
	)
	assert_eq(
		_labels_for("move_left", "gamepad"),
		["Left Stick (Left)"] as Array[String],
		"move_left keeps its stick"
	)
	for device: String in ["keyboard", "gamepad"]:
		Globals.current_input_device = device
		assert_false(
			Settings.has_unbound_critical_actions_for_current_device(),
			"no Unbound Controls dialog for " + device
		)


## REG-02 | A save of the project defaults reloads unchanged, with no re-save needed.
func test_reg_02_default_layout_round_trip() -> void:
	Settings.save_input_mappings(TEST_CONFIG_PATH)
	Settings.load_input_mappings(TEST_CONFIG_PATH)
	assert_false(Settings.needs_save(), "nothing to repair after a clean round trip")
	for row: Array in LAYOUT:
		assert_eq(_labels_for(row[0], "keyboard"), [row[1]] as Array[String], row[0] + " keyboard")
		assert_eq(_labels_for(row[0], "gamepad"), [row[2]] as Array[String], row[0] + " gamepad")


# ── Migration v3 ─────────────────────────────────────────────────────────────


## MIG-01 | A save broken by the old layout is repaired: menu arrows and flight sticks return.
func test_mig_01_repairs_broken_save() -> void:
	# Exactly what the pre-fix code saved after one save + reload.
	_write_config(
		{
			"speed_up": ["key:%d" % KEY_W, "key:%d" % KEY_UP],
			"speed_down": ["key:%d" % KEY_X, "key:%d" % KEY_DOWN, "joyaxis:3:1.0:-1"],
			"move_left": ["key:%d" % KEY_A, "key:%d" % KEY_LEFT],
			"move_right": ["key:%d" % KEY_D, "key:%d" % KEY_RIGHT],
			"ui_up": ["joybtn:11:-1", "joyaxis:1:-1.0:-1"],
			"ui_down": ["joybtn:12:-1", "joyaxis:1:1.0:-1"],
			"ui_left": ["joybtn:13:-1", "joyaxis:0:-1.0:-1"],
			"ui_right": ["joybtn:14:-1", "joyaxis:0:1.0:-1"],
		}
	)
	Settings.load_input_mappings(TEST_CONFIG_PATH)
	Settings.set_needs_save_for_test(false)
	_set_flag(Settings.INPUT_LAYOUT_MIGRATION_KEY, false)

	Settings._migrate_input_layout_v3()

	assert_eq(_labels_for("ui_up", "keyboard"), ["Up"] as Array[String], "menu arrow restored")
	assert_eq(_labels_for("ui_up", "gamepad"), ["D-Pad Up"] as Array[String], "stick trimmed")
	assert_eq(_labels_for("ui_right", "keyboard"), ["Right"] as Array[String])
	assert_eq(_labels_for("speed_up", "keyboard"), ["W"] as Array[String], "hidden Up removed")
	assert_eq(
		_labels_for("speed_up", "gamepad"),
		["Left Stick (Up)"] as Array[String],
		"flight stick restored"
	)
	assert_eq(
		_labels_for("speed_down", "gamepad"),
		["Right Stick (Down)"] as Array[String],
		"a saved gamepad binding is kept, not replaced"
	)
	assert_eq(_labels_for("speed_down", "keyboard"), ["X"] as Array[String], "saved X is kept")
	assert_true(Settings.needs_save(), "repair is persisted on the next save")
	assert_true(Globals.has_meta(Settings.INPUT_LAYOUT_MIGRATION_KEY), "runs once")


## MIG-02 | The migration flag is saved and restored on the next load.
func test_mig_02_flag_persists_across_save_and_load() -> void:
	Settings._migrate_input_layout_v3()
	Settings.save_input_mappings(TEST_CONFIG_PATH)
	_set_flag(Settings.INPUT_LAYOUT_MIGRATION_KEY, false)

	Settings.load_input_mappings(TEST_CONFIG_PATH)

	assert_true(Globals.has_meta(Settings.INPUT_LAYOUT_MIGRATION_KEY), "flag restored from config")


## MIG-03 | A clean default layout is left untouched.
func test_mig_03_noop_on_clean_layout() -> void:
	Settings._migrate_input_layout_v3()
	assert_false(Settings.needs_save(), "nothing changed, nothing to save")
	for row: Array in LAYOUT:
		assert_eq(_labels_for(row[0], "keyboard"), [row[1]] as Array[String], row[0] + " keyboard")
		assert_eq(_labels_for(row[0], "gamepad"), [row[2]] as Array[String], row[0] + " gamepad")


## MIG-04 | A default is not restored if another action in the same group already uses it.
func test_mig_04_does_not_steal_from_same_group() -> void:
	_set_events("speed_up", [_key(KEY_W)])
	_set_events("next_weapon", [_key(KEY_Q), _axis(JOY_AXIS_LEFT_Y, -1.0)])

	Settings._migrate_input_layout_v3()

	assert_eq(_events_for("speed_up", "gamepad").size(), 0, "speed_up stays unbound on gamepad")
	assert_eq(
		_labels_for("next_weapon", "gamepad"),
		["Left Stick (Up)"] as Array[String],
		"the player's choice is kept"
	)


## MIG-05 | A stripped slot is restored even if an action in the other group uses the input.
func test_mig_05_restores_across_groups() -> void:
	_set_events("speed_up", [_key(KEY_W)])  # left stick stripped by the bug
	_set_events("ui_up", [_key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)])  # player's own choice

	Settings._migrate_input_layout_v3()

	assert_eq(
		_labels_for("speed_up", "gamepad"),
		["Left Stick (Up)"] as Array[String],
		"menu and flight may share the left stick"
	)
	assert_eq(
		_labels_for("ui_up", "gamepad"),
		["Left Stick (Up)"] as Array[String],
		"the only gamepad binding of ui_up is kept"
	)


## MIG-06 | A remap made on top of a legacy extra wins over the legacy binding (review fix).
## The remap button erases the first key and appends the new one, so the legacy Up was first.
func test_mig_06_keeps_remap_over_legacy_extra() -> void:
	_set_events("speed_up", [_axis(JOY_AXIS_LEFT_Y, -1.0), _key(KEY_UP), _key(KEY_I)])

	Settings._migrate_input_layout_v3()

	assert_eq(_labels_for("speed_up", "keyboard"), ["I"] as Array[String], "the remap survives")
	assert_true(Settings.needs_save(), "the removal is persisted")


## MIG-07 | Extra bindings that are not legacy defaults are left alone.
func test_mig_07_keeps_non_legacy_extras() -> void:
	_set_events("fire", [_key(KEY_SPACE), _key(KEY_F), _button(JOY_BUTTON_A)])
	_set_events("ui_up", [_key(KEY_UP), _button(JOY_BUTTON_DPAD_UP), _button(JOY_BUTTON_Y)])

	Settings._migrate_input_layout_v3()

	assert_eq(_labels_for("fire", "keyboard"), ["Space", "F"] as Array[String])
	assert_eq(_labels_for("ui_up", "gamepad"), ["D-Pad Up", "Y"] as Array[String])
	assert_false(Settings.needs_save(), "nothing changed")


## MIG-08 | A legacy binding that is the only one for its device is kept: the player chose it.
func test_mig_08_keeps_legacy_binding_when_it_is_the_only_one() -> void:
	_set_events("speed_up", [_key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_set_events("ui_up", [_key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)])

	Settings._migrate_input_layout_v3()

	assert_eq(_labels_for("speed_up", "keyboard"), ["Up"] as Array[String])
	assert_eq(_labels_for("ui_up", "gamepad"), ["Left Stick (Up)"] as Array[String])
	assert_false(Settings.needs_save(), "nothing changed")


## MIG-09 | A device unbind outside the slots the bug stripped is kept (review fix).
func test_mig_09_keeps_explicit_device_unbind(
	row: Array = use_parameters(
		[
			["next_weapon", "keyboard", [_button(JOY_BUTTON_Y)]],
			["fire", "gamepad", [_key(KEY_SPACE)]],
			["ui_accept", "gamepad", [_key(KEY_ENTER)]],
			["ui_focus_next", "keyboard", [_button(JOY_BUTTON_RIGHT_SHOULDER)]],
		]
	)
) -> void:
	_set_events(row[0], row[2])

	Settings._migrate_input_layout_v3()

	assert_eq(_events_for(row[0], row[1]).size(), 0, "%s stays unbound on %s" % [row[0], row[1]])
	assert_false(Settings.needs_save(), "nothing changed")


## MIG-10 | A fully unbound action (saved as []) stays unbound, even in a stripped slot.
func test_mig_10_keeps_fully_unbound_action(
	action: String = use_parameters(["speed_up", "ui_up"])
) -> void:
	_set_events(action, [])

	Settings._migrate_input_layout_v3()

	assert_true(InputMap.action_get_events(action).is_empty(), action + " stays unbound")
	assert_false(Settings.needs_save(), "nothing changed")


## MIG-11 | Explicit unbinds survive a full load: saved config through migration.
func test_mig_11_explicit_unbinds_survive_load_and_migration() -> void:
	_write_config(
		{
			"next_weapon": ["joybtn:%d:-1" % JOY_BUTTON_Y],
			"fire": [],
		}
	)
	Settings.load_input_mappings(TEST_CONFIG_PATH)
	Settings.set_needs_save_for_test(false)

	Settings._migrate_input_layout_v3()

	assert_eq(_events_for("next_weapon", "keyboard").size(), 0, "keyboard unbind kept")
	assert_true(InputMap.action_get_events("fire").is_empty(), "full unbind kept")
