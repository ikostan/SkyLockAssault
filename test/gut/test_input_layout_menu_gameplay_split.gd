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
## the agreed layout, the default event factory, scoped conflict groups, key:/lkey:
## serialization and matching, save/reload keeping both sides, and the one-time v3
## migration of broken saves.
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


## Serialized bindings of every managed action, to check that nothing changed.
func _snapshot() -> Dictionary:
	var snap: Dictionary = {}
	for action: String in Settings.ACTIONS:
		var events: Array[String] = []
		for ev: InputEvent in InputMap.action_get_events(action):
			events.append(Settings.serialize_event(ev))
		snap[action] = events
	return snap


## Reads the saved entries for [param action] straight from the test config file, so a
## test can check what was written before the loader's default backfill runs.
func _saved_entries(action: String) -> Array:
	var config := ConfigFile.new()
	var err: int = config.load_encrypted_pass(TEST_CONFIG_PATH, Globals.save_encryption_pass)
	assert_eq(err, OK, "Precondition: saved config readable")
	return config.get_value("input", action, [])


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
## Special keys are the same key on every layout, so they are stored as physical keys;
## printable keys are stored as logical "lkey:" and restored as a keycode.
func test_ser_01_keycode_only_event_is_not_saved_as_zero(
	row: Array = use_parameters(
		[
			[KEY_UP, "key:%d" % KEY_UP],
			[KEY_ENTER, "key:%d" % KEY_ENTER],
			[KEY_TAB, "key:%d" % KEY_TAB],
			[KEY_W, "lkey:%d" % KEY_W],
		]
	)
) -> void:
	var code: int = row[0]
	var serialized: String = Settings.serialize_event(_keycode_only(code))
	assert_eq(serialized, row[1])
	var restored: InputEvent = Settings.deserialize_event(serialized)
	assert_not_null(restored, "the saved key loads back")
	if restored:
		var physical: bool = row[1].begins_with("key:")
		assert_eq(restored.physical_keycode, code if physical else 0, "physical keycode")
		assert_eq(restored.keycode, 0 if physical else code, "logical keycode")


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
## The saved entries are checked before reload: load_input_mappings backfills missing
## defaults, which would hide a binding that was never written (e.g. "key:0").
func test_reg_01_save_reload_keeps_menu_and_flight_bindings() -> void:
	_apply_pre_fix_layout()
	Settings.save_input_mappings(TEST_CONFIG_PATH)

	for row: Array in [
		["ui_up", KEY_UP], ["ui_down", KEY_DOWN], ["ui_left", KEY_LEFT], ["ui_right", KEY_RIGHT]
	]:
		var saved: Array = _saved_entries(row[0])
		assert_has(saved, "key:%d" % row[1], row[0] + " arrow is written to the save")
		assert_does_not_have(saved, "key:0", row[0] + " has no invalid key:0 entry")
	for row: Array in [
		["speed_up", "joyaxis:1:-1.0:-1"],
		["speed_down", "joyaxis:1:1.0:-1"],
		["move_left", "joyaxis:0:-1.0:-1"],
		["move_right", "joyaxis:0:1.0:-1"],
	]:
		assert_has(_saved_entries(row[0]), row[1], row[0] + " stick is written to the save")

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
	# Guard: the loader's backfill must not have filled these yet, or the asserts below would
	# pass without the migration. If this fails, the loader changed; see MIG-13 for the
	# migration-only check.
	assert_eq(_events_for("ui_up", "keyboard").size(), 0, "Precondition: ui_up arrow missing")
	assert_eq(_events_for("speed_up", "gamepad").size(), 0, "Precondition: speed_up stick missing")

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
	var before: Dictionary = _snapshot()
	Settings._migrate_input_layout_v3()
	assert_eq(_snapshot(), before, "nothing changed")
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

	var before: Dictionary = _snapshot()
	Settings._migrate_input_layout_v3()

	assert_eq(_labels_for("fire", "keyboard"), ["Space", "F"] as Array[String])
	assert_eq(_labels_for("ui_up", "gamepad"), ["D-Pad Up", "Y"] as Array[String])
	assert_eq(_snapshot(), before, "nothing changed")


## MIG-08 | A legacy binding that is the only one for its device is kept: the player chose it.
func test_mig_08_keeps_legacy_binding_when_it_is_the_only_one() -> void:
	_set_events("speed_up", [_key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_set_events("ui_up", [_key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)])

	var before: Dictionary = _snapshot()
	Settings._migrate_input_layout_v3()

	assert_eq(_labels_for("speed_up", "keyboard"), ["Up"] as Array[String])
	assert_eq(_labels_for("ui_up", "gamepad"), ["Left Stick (Up)"] as Array[String])
	assert_eq(_snapshot(), before, "nothing changed")


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

	var before: Dictionary = _snapshot()
	Settings._migrate_input_layout_v3()

	assert_eq(_events_for(row[0], row[1]).size(), 0, "%s stays unbound on %s" % [row[0], row[1]])
	assert_eq(_snapshot(), before, "nothing changed")


## MIG-10 | A fully unbound action (saved as []) stays unbound, even in a stripped slot.
func test_mig_10_keeps_fully_unbound_action(
	action: String = use_parameters(["speed_up", "ui_up"])
) -> void:
	_set_events(action, [])

	var before: Dictionary = _snapshot()
	Settings._migrate_input_layout_v3()

	assert_true(InputMap.action_get_events(action).is_empty(), action + " stays unbound")
	assert_eq(_snapshot(), before, "nothing changed")


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


## MIG-12 | A migration that changes nothing still flags a save, so the run-once flag is
## persisted and the migration does not run again on the next launch (review fix).
func test_mig_12_noop_migration_still_persists_flag() -> void:
	_set_flag(Settings.INPUT_LAYOUT_MIGRATION_KEY, false)
	var before: Dictionary = _snapshot()

	Settings._migrate_input_layout_v3()

	assert_eq(_snapshot(), before, "nothing changed")
	assert_true(Settings.needs_save(), "a save is flagged anyway")
	Settings.save_input_mappings(TEST_CONFIG_PATH)
	var config := ConfigFile.new()
	assert_eq(config.load_encrypted_pass(TEST_CONFIG_PATH, Globals.save_encryption_pass), OK)
	assert_true(
		config.get_value("meta", Settings.INPUT_LAYOUT_MIGRATION_KEY, false),
		"the flag is in the saved config"
	)


# ── Logical keys (review fix) ────────────────────────────────────────────────


## SER-04 | A logical printable key round-trips as a keycode, so it keeps following the
## keyboard layout instead of becoming the physical key at that position.
func test_ser_04_logical_key_round_trip(
	row: Array = use_parameters(
		[
			[KEY_W, false, "lkey:%d" % KEY_W],
			[KEY_Z, true, "lkey:%d:shift" % KEY_Z],
			[KEY_1, false, "lkey:%d" % KEY_1],
		]
	)
) -> void:
	var ev: InputEventKey = _keycode_only(row[0])
	ev.shift_pressed = row[1]
	var serialized: String = Settings.serialize_event(ev)
	assert_eq(serialized, row[2])
	var restored: InputEvent = Settings.deserialize_event(serialized)
	assert_not_null(restored, "lkey loads back")
	if restored:
		assert_eq(restored.keycode, row[0], "restored as a logical keycode")
		assert_eq(restored.physical_keycode, 0, "not turned into a physical key")
		assert_eq(restored.shift_pressed, row[1], "modifier kept")
		assert_true(Settings.events_match(restored, ev), "matches the original")


## SER-05 | lkey follows the same validation as key: no zero code, known modifiers only.
func test_ser_05_invalid_lkey_rejected(
	serialized: String = use_parameters(
		["lkey:0", "lkey:", "lkey:abc", "lkey:87:bogus", "lkey:87:shift:shift"]
	)
) -> void:
	assert_null(Settings.deserialize_event(serialized), serialized + " is rejected")


## SER-06 | Matching: physical vs physical and logical vs logical compare codes; a logical and
## a physical printable key never match; special keys match whichever form they come in.
func test_ser_06_key_matching_rules() -> void:
	assert_true(Settings.events_match(_keycode_only(KEY_W), _keycode_only(KEY_W)), "logical W")
	assert_false(
		Settings.events_match(_keycode_only(KEY_W), _key(KEY_W)),
		"logical W is not physical W: layouts can differ"
	)
	assert_true(
		Settings.events_match(_keycode_only(KEY_UP), _key(KEY_UP)),
		"Up is the same key in either form"
	)
	assert_false(
		Settings.events_match(_keycode_only(KEY_TAB), _key(KEY_TAB, true)),
		"modifiers still distinguish Tab and Shift+Tab"
	)


## SER-07 | The reviewer's scenario end to end: a logical binding saved and reloaded is still
## the logical key, not the physical key at that position.
func test_ser_07_logical_binding_survives_save_and_load() -> void:
	_set_events("next_weapon", [_keycode_only(KEY_Z), _button(JOY_BUTTON_Y)])
	Settings.save_input_mappings(TEST_CONFIG_PATH)
	_load_project_defaults()

	Settings.load_input_mappings(TEST_CONFIG_PATH)

	var keys: Array[InputEvent] = _events_for("next_weapon", "keyboard")
	assert_eq(keys.size(), 1, "one keyboard binding")
	if keys.size() == 1:
		assert_eq(keys[0].keycode, KEY_Z, "still logical Z")
		assert_eq(keys[0].physical_keycode, 0, "not physical Z")


## MIG-13 | The migration alone repairs the post-bug state: InputMap is set directly, so the
## loader's default backfill cannot supply any binding (review fix).
func test_mig_13_repairs_post_bug_input_map_without_loader() -> void:
	# What the InputMap held after the bug, with no defaults backfilled.
	_set_events("speed_up", [_key(KEY_W), _key(KEY_UP)])
	_set_events("speed_down", [_key(KEY_S), _key(KEY_DOWN)])
	_set_events("move_left", [_key(KEY_A), _key(KEY_LEFT)])
	_set_events("move_right", [_key(KEY_D), _key(KEY_RIGHT)])
	_set_events("ui_up", [_button(JOY_BUTTON_DPAD_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_set_events("ui_down", [_button(JOY_BUTTON_DPAD_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)])
	_set_events("ui_left", [_button(JOY_BUTTON_DPAD_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_set_events("ui_right", [_button(JOY_BUTTON_DPAD_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_set_flag(Settings.INPUT_LAYOUT_MIGRATION_KEY, false)

	Settings._migrate_input_layout_v3()

	var expected: Array = [
		["speed_up", "W", "Left Stick (Up)"],
		["speed_down", "S", "Left Stick (Down)"],
		["move_left", "A", "Left Stick (Left)"],
		["move_right", "D", "Left Stick (Right)"],
		["ui_up", "Up", "D-Pad Up"],
		["ui_down", "Down", "D-Pad Down"],
		["ui_left", "Left", "D-Pad Left"],
		["ui_right", "Right", "D-Pad Right"],
	]
	for row: Array in expected:
		assert_eq(_labels_for(row[0], "keyboard"), [row[1]] as Array[String], row[0] + " keyboard")
		assert_eq(_labels_for(row[0], "gamepad"), [row[2]] as Array[String], row[0] + " gamepad")


## SER-08 | A saved keyboard entry that fails to load is backfilled with the default for both
## prefixes: an "lkey:" entry counts as a saved keyboard binding, not an explicit unbind.
func test_ser_08_corrupt_saved_key_is_backfilled(
	entry: String = use_parameters(["key:0", "lkey:0"])
) -> void:
	_write_config({"fire": [entry, "joybtn:%d:-1" % JOY_BUTTON_A]})

	Settings.load_input_mappings(TEST_CONFIG_PATH)

	assert_eq(
		_labels_for("fire", "keyboard"),
		["Space"] as Array[String],
		entry + " is replaced by the default, not treated as an unbind"
	)
	assert_eq(_labels_for("fire", "gamepad"), ["A"] as Array[String], "gamepad entry kept")


## DEF-01 | Default factories must not share mutable events between actions, resets or callers.
func test_default_events_are_independent(
	row: Array = use_parameters(
		[["ui_focus_prev", "keyboard"], ["fire", "gamepad"], ["speed_up", "gamepad"]]
	)
) -> void:
	var first: InputEvent = Settings.InputDefaults.make_event(row[0], row[1])
	var second: InputEvent = Settings.InputDefaults.make_event(row[0], row[1])
	var expected: String = Settings.serialize_event(second)
	assert_ne(first.get_instance_id(), second.get_instance_id(), "each call creates an event")
	if first is InputEventKey:
		first.physical_keycode = KEY_F
		first.shift_pressed = false
	elif first is InputEventJoypadButton:
		first.button_index = JOY_BUTTON_Y
		first.device = 3
	elif first is InputEventJoypadMotion:
		first.axis_value = 1.0
		first.device = 3
	assert_eq(Settings.serialize_event(second), expected, "existing events are independent")
	assert_eq(
		Settings.serialize_event(Settings.InputDefaults.make_event(row[0], row[1])),
		expected,
		"mutating an event does not change future defaults"
	)


## DEF-02 | Unknown actions/devices have no default; they must not silently select a device.
func test_default_factory_rejects_unknown_inputs(
	row: Array = use_parameters(
		[["unknown", "keyboard"], ["unknown", "gamepad"], ["fire", ""], ["fire", "mouse"]]
	)
) -> void:
	assert_null(Settings.InputDefaults.make_event(row[0], row[1]))


## GROUP-06 | Scope respects the caller's subset and ordering, including Pause's group union.
func test_conflict_scope_preserves_subset_order(
	row: Array = use_parameters(
		[
			["fire", ["pause", "fire", "move_left"]],
			["ui_up", ["ui_down", "pause", "ui_up"]],
			["pause", ["ui_down", "pause", "fire", "ui_up", "move_left"]],
			["unknown", ["ui_down", "pause", "fire", "ui_up", "move_left", "custom"]],
		]
	)
) -> void:
	var actions: Array[String] = ["ui_down", "pause", "fire", "ui_up", "move_left", "custom"]
	var original: Array[String] = actions.duplicate()
	var scope: Array[String] = Settings.InputDefaults.conflict_scope(row[0], actions)
	assert_eq(scope, row[1] as Array[String])
	scope.clear()
	assert_eq(actions, original, "returned scopes must not alias the caller's array")
	assert_true(Settings.InputDefaults.conflict_scope(row[0], [] as Array[String]).is_empty())


## SER-09 | Every modifier combination survives serialization of logical printable keys.
func test_logical_key_round_trip_all_modifiers(mask: int = use_parameters(range(16))) -> void:
	var original: InputEventKey = _keycode_only(KEY_Z)
	original.shift_pressed = bool(mask & 1)
	original.ctrl_pressed = bool(mask & 2)
	original.alt_pressed = bool(mask & 4)
	original.meta_pressed = bool(mask & 8)
	var serialized: String = Settings.serialize_event(original)
	assert_true(serialized.begins_with("lkey:"), "printable keys remain logical")
	var restored: InputEventKey = Settings.deserialize_event(serialized) as InputEventKey
	assert_not_null(restored)
	if restored == null:
		return
	assert_eq(restored.keycode, KEY_Z)
	assert_eq(restored.physical_keycode, 0)
	assert_eq(restored.shift_pressed, original.shift_pressed)
	assert_eq(restored.ctrl_pressed, original.ctrl_pressed)
	assert_eq(restored.alt_pressed, original.alt_pressed)
	assert_eq(restored.meta_pressed, original.meta_pressed)
	assert_true(Settings.events_match(original, restored))
	assert_eq(Settings.serialize_event(restored), serialized, "encoding is stable")


## SER-10 | Each modifier is part of a logical key's identity when checking conflicts.
func test_logical_key_modifiers_distinguish_conflicts(
	modifier: String = use_parameters(
		["shift_pressed", "ctrl_pressed", "alt_pressed", "meta_pressed"]
	)
) -> void:
	var plain: InputEventKey = _keycode_only(KEY_Z)
	var modified: InputEventKey = _keycode_only(KEY_Z)
	modified.set(modifier, true)
	_set_events("fire", [modified])
	assert_false(Settings.events_match(plain, modified))
	assert_false(Settings.events_match(modified, plain), "matching is symmetric")
	assert_eq(Settings.get_conflicting_actions(plain, "next_weapon"), [] as Array[String])
	assert_eq(Settings.get_conflicting_actions(modified, "next_weapon"), ["fire"] as Array[String])


## MIG-14 | Repair all hidden extras, then prove another migration cannot change the repaired map.
func test_migration_trims_all_legacy_extras_and_is_idempotent() -> void:
	_apply_pre_fix_layout()
	var migration = Settings.InputLayoutMigration
	assert_true(migration.migrate(Settings), "the legacy layout needs repair")
	for action: String in ["speed_up", "speed_down", "move_left", "move_right"]:
		assert_eq(_events_for(action, "keyboard").size(), 1, action + " loses its hidden arrow")
		assert_eq(_events_for(action, "gamepad").size(), 1, action + " keeps its flight stick")
	assert_eq(_labels_for("speed_down", "keyboard"), ["X"] as Array[String], "keep old remaps")
	for action: String in ["ui_up", "ui_down", "ui_left", "ui_right"]:
		var pads: Array[InputEvent] = _events_for(action, "gamepad")
		assert_eq(pads.size(), 1, action + " loses its hidden stick")
		if pads.size() == 1:
			assert_true(pads[0] is InputEventJoypadButton, action + " keeps its D-pad button")
	var repaired: Dictionary = _snapshot()
	assert_false(migration.migrate(Settings), "a second repair reports no changes")
	assert_eq(_snapshot(), repaired, "a second repair preserves all bindings")


## MIG-15 | A lookalike legacy arrow with a modifier is a custom binding, even beside another key.
func test_migration_preserves_modified_legacy_arrows(
	row: Array = use_parameters(
		[
			["speed_up", KEY_UP],
			["speed_down", KEY_DOWN],
			["move_left", KEY_LEFT],
			["move_right", KEY_RIGHT],
		]
	)
) -> void:
	var action: String = row[0]
	_set_events(action, [_key(row[1], true), _key(KEY_I), _button(JOY_BUTTON_Y)])
	var before: Dictionary = _snapshot()
	assert_false(Settings.InputLayoutMigration.migrate(Settings))
	assert_eq(_snapshot(), before, "modified legacy keys are player remaps")
