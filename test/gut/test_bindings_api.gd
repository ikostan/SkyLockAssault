## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_bindings_api.gd
##
## Bindings API (#1102): Settings.rebind() and Settings.reset_to_defaults() are the only code
## that changes bindings for the UI, and both emit Settings.bindings_changed. MainScene reacts
## to that signal (and to input_device_changed) instead of polling every frame, and Key Mapping
## no longer calls into MainScene.

extends GutTest

const GutHelper = preload("res://test/gut/gut_test_helper.gd")
const InputDefaults = preload("res://scripts/core/input_defaults.gd")
const UNBOUND_WARNING_PREFIX: String = "{SOME=CONTROLS=ARE=UNBOUND}"
const UI_SCRIPTS_DIR: String = "res://scripts/ui/"
const KEY_MAPPING_SCRIPT: String = "res://scripts/ui/menus/key_mapping.gd"
## UI scripts must not write InputMap directly (#1102).
const FORBIDDEN_UI_CALLS: Array[String] = [
	"InputMap.action_add_event",
	"InputMap.action_erase_event",
	"InputMap.action_erase_events",
]

var _saved_events: Dictionary = {}
var _saved_device: String = ""
var _had_config: bool = false
var _saved_config: PackedByteArray = PackedByteArray()
var _main_scene: MainScene = null
var _menu: CanvasLayer = null


func before_each() -> void:
	_saved_events.clear()
	for action: String in Settings.ACTIONS:
		_saved_events[action] = InputMap.action_get_events(action).duplicate()
	_saved_device = Settings.get_input_device()
	# reset_to_defaults() and finish_remap() save to the real config; put it back afterwards.
	_had_config = FileAccess.file_exists(Settings.CONFIG_PATH)
	_saved_config = (
		FileAccess.get_file_as_bytes(Settings.CONFIG_PATH) if _had_config else PackedByteArray()
	)
	Settings.set_input_device("keyboard")
	Settings.reset_to_defaults("keyboard")
	Settings.reset_to_defaults("gamepad")


func after_each() -> void:
	get_tree().paused = false
	if is_instance_valid(_menu):
		_menu.free()
	_menu = null
	if is_instance_valid(_main_scene):
		GutHelper.safe_hard_free(_main_scene)
	_main_scene = null
	await get_tree().process_frame

	for action: String in _saved_events:
		InputMap.action_erase_events(action)
		for ev: InputEvent in _saved_events[action]:
			InputMap.action_add_event(action, ev)
	Settings.set_input_device(_saved_device)
	if _had_config:
		var f: FileAccess = FileAccess.open(Settings.CONFIG_PATH, FileAccess.WRITE)
		f.store_buffer(_saved_config)
		f.close()
	elif FileAccess.file_exists(Settings.CONFIG_PATH):
		DirAccess.remove_absolute(Settings.CONFIG_PATH)


# ── Helpers ──────────────────────────────────────────────────────────────────


func _events_for(action: String, device: String) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	for ev: InputEvent in InputMap.action_get_events(action):
		if InputEventCodec.get_event_device_type(ev) == device:
			out.append(ev)
	return out


func _has_event(action: String, event: InputEvent) -> bool:
	for ev: InputEvent in InputMap.action_get_events(action):
		if InputEventCodec.events_match(ev, event):
			return true
	return false


func _key(keycode: Key) -> InputEventKey:
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = keycode
	return ev


func _joy_button(index: JoyButton) -> InputEventJoypadButton:
	var ev: InputEventJoypadButton = InputEventJoypadButton.new()
	ev.button_index = index
	ev.device = -1
	return ev


func _joy_axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var ev: InputEventJoypadMotion = InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	ev.device = -1
	return ev


func _unbind(action: String, device: String) -> void:
	for ev: InputEvent in _events_for(action, device):
		InputMap.action_erase_event(action, ev)


func _spawn_main_scene() -> MainScene:
	_main_scene = preload(GamePaths.MAIN_SCENE).instantiate()
	add_child(_main_scene)
	await get_tree().process_frame
	return _main_scene


func _warning_visible(scene: MainScene) -> bool:
	return (
		scene.message_label.visible
		and scene.message_label.text.begins_with(UNBOUND_WARNING_PREFIX)
	)


func _hide_message(scene: MainScene) -> void:
	scene.message_label.visible = false
	scene.message_label.text = ""


func _ui_script_paths(dir_path: String) -> Array[String]:
	var paths: Array[String] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return paths
	for file_name: String in dir.get_files():
		if file_name.ends_with(".gd"):
			paths.append(dir_path.path_join(file_name))
	for sub: String in dir.get_directories():
		paths.append_array(_ui_script_paths(dir_path.path_join(sub)))
	return paths


# ── Settings.rebind() ────────────────────────────────────────────────────────


## BIND-01 | rebind replaces only the event's device binding and emits bindings_changed once.
func test_bind_01_rebind_replaces_same_device_only() -> void:
	var pad_before: Array[InputEvent] = _events_for("fire", "gamepad")
	watch_signals(Settings)

	Settings.rebind("fire", _key(KEY_F))

	var keys: Array[InputEvent] = _events_for("fire", "keyboard")
	assert_eq(keys.size(), 1, "one keyboard binding, the old one is replaced")
	assert_eq(keys[0].physical_keycode, KEY_F, "the new key is bound")
	assert_eq(_events_for("fire", "gamepad"), pad_before, "gamepad binding is untouched")
	assert_signal_emit_count(Settings, "bindings_changed", 1)


## BIND-02 | rebind adds the event when the action had no binding for that device.
func test_bind_02_rebind_unbound_device_adds_event() -> void:
	_unbind("fire", "gamepad")

	Settings.rebind("fire", _joy_button(JOY_BUTTON_MISC1))

	var pads: Array[InputEvent] = _events_for("fire", "gamepad")
	assert_eq(pads.size(), 1, "gamepad binding added")
	assert_eq(pads[0].button_index, JOY_BUTTON_MISC1)
	assert_eq(_events_for("fire", "keyboard").size(), 1, "keyboard binding kept")


## BIND-03 | unbind_from removes the exact input from those actions before binding it.
func test_bind_03_rebind_unbinds_listed_conflicts() -> void:
	var fire_key: InputEvent = _events_for("fire", "keyboard")[0]
	var fire_pad: Array[InputEvent] = _events_for("fire", "gamepad")
	var old_next_key: InputEvent = _events_for("next_weapon", "keyboard")[0]
	watch_signals(Settings)

	Settings.rebind("next_weapon", fire_key.duplicate(), ["fire"])

	assert_true(_has_event("next_weapon", fire_key), "next_weapon now uses fire's key")
	assert_false(_has_event("next_weapon", old_next_key), "next_weapon's old key is replaced")
	assert_eq(_events_for("fire", "keyboard").size(), 0, "fire lost its keyboard binding")
	assert_eq(_events_for("fire", "gamepad"), fire_pad, "fire keeps its gamepad binding")
	assert_signal_emit_count(Settings, "bindings_changed", 1, "one rebind, one signal")


## BIND-04 | Without unbind_from, other actions keep the same input, as before #1102.
func test_bind_04_rebind_without_unbind_from_leaves_others() -> void:
	var fire_key: InputEvent = _events_for("fire", "keyboard")[0]

	Settings.rebind("next_weapon", fire_key.duplicate())

	assert_true(_has_event("fire", fire_key), "fire keeps its key")
	assert_true(_has_event("next_weapon", fire_key), "next_weapon gets the key too")


## BIND-05 | Invalid rebinds change nothing and emit nothing.
func test_bind_05_invalid_rebind_is_ignored() -> void:
	var fire_before: Array[InputEvent] = InputMap.action_get_events("fire").duplicate()
	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	watch_signals(Settings)

	Settings.rebind("fire", null)
	Settings.rebind("no_such_action_1102", _key(KEY_F))
	Settings.rebind("fire", mouse)

	assert_eq(InputMap.action_get_events("fire"), fire_before, "fire is unchanged")
	assert_false(InputMap.has_action("no_such_action_1102"), "no action is created")
	assert_signal_not_emitted(Settings, "bindings_changed")


## BIND-06 | rebind works for actions outside Settings.ACTIONS (e.g. test actions).
func test_bind_06_rebind_unmanaged_action() -> void:
	InputMap.add_action("test_bind_06")

	Settings.rebind("test_bind_06", _key(KEY_K))

	var events: Array[InputEvent] = InputMap.action_get_events("test_bind_06")
	assert_eq(events.size(), 1)
	assert_eq(events[0].physical_keycode, KEY_K)
	InputMap.erase_action("test_bind_06")


## BIND-07 | Listeners see the complete transfer, even if a named conflict no longer exists.
func test_bind_07_axis_transfer_resolves_only_exact_listed_conflicts() -> void:
	var moved_axis := _joy_axis(JOY_AXIS_RIGHT_X, -1.0)
	var opposite_axis := _joy_axis(JOY_AXIS_RIGHT_X, 1.0)
	var old_fire_pad: InputEvent = _events_for("fire", "gamepad")[0]
	var fire_keys: Array[InputEvent] = _events_for("fire", "keyboard")
	InputMap.action_add_event("move_left", moved_axis.duplicate())
	InputMap.action_add_event("move_right", moved_axis.duplicate())
	InputMap.action_add_event("move_right", opposite_axis)
	InputMap.action_add_event("ui_left", moved_axis.duplicate())
	var signal_states: Array[Array] = []
	var observe := func() -> void:
		signal_states.append([
			_has_event("fire", moved_axis),
			_has_event("move_left", moved_axis),
			_has_event("move_right", moved_axis),
		])
	Settings.bindings_changed.connect(observe)

	Settings.rebind("fire", moved_axis, ["stale_binding_action", "move_left", "move_right"])

	Settings.bindings_changed.disconnect(observe)
	assert_eq(signal_states, [[true, false, false]], "one notification after the full transfer")
	assert_false(_has_event("fire", old_fire_pad), "the old gamepad button is replaced")
	assert_eq(_events_for("fire", "keyboard"), fire_keys, "fire's keyboard binding is kept")
	assert_true(_has_event("move_right", opposite_axis), "the opposite direction is kept")
	assert_true(_has_event("ui_left", moved_axis), "an unlisted action can keep the same input")


## BIND-08 | Remapping replaces the displayed binding and leaves extra bindings and disk alone.
func test_bind_08_rebind_keeps_secondary_key_and_does_not_save() -> void:
	var old_key: InputEvent = _events_for("fire", "keyboard")[0]
	var secondary_key := _key(KEY_F9)
	var new_key := _key(KEY_F10)
	InputMap.action_add_event("fire", secondary_key)
	Settings.save_input_mappings()
	assert_file_exists(Settings.CONFIG_PATH)
	var saved_before := FileAccess.get_file_as_bytes(Settings.CONFIG_PATH)

	Settings.rebind("fire", new_key)

	assert_eq(_events_for("fire", "keyboard").size(), 2)
	assert_false(_has_event("fire", old_key), "the displayed key is replaced")
	assert_true(_has_event("fire", secondary_key), "the secondary key is kept")
	assert_true(_has_event("fire", new_key), "the requested key is applied")
	assert_eq(FileAccess.get_file_as_bytes(Settings.CONFIG_PATH), saved_before, "caller saves")


# ── Settings.reset_to_defaults() ─────────────────────────────────────────────


## RESET-01 | reset_to_defaults restores the device's defaults and emits bindings_changed once.
func test_reset_01_reset_emits_bindings_changed() -> void:
	Settings.rebind("fire", _key(KEY_F))
	var pad_before: Array[InputEvent] = _events_for("fire", "gamepad")
	watch_signals(Settings)

	Settings.reset_to_defaults("keyboard")

	var keys: Array[InputEvent] = _events_for("fire", "keyboard")
	assert_eq(keys.size(), 1)
	assert_true(
		InputEventCodec.events_match(keys[0], InputDefaults.make_event("fire", "keyboard")),
		"fire is back on its default key"
	)
	assert_eq(_events_for("fire", "gamepad"), pad_before, "gamepad is untouched")
	assert_signal_emit_count(Settings, "bindings_changed", 1)


## RESET-02 | An unknown device is ignored: nothing changes and nothing is emitted.
func test_reset_02_unknown_device_is_ignored() -> void:
	Settings.rebind("fire", _key(KEY_F))
	watch_signals(Settings)

	Settings.reset_to_defaults("mouse")

	assert_eq(_events_for("fire", "keyboard")[0].physical_keycode, KEY_F, "binding kept")
	assert_signal_not_emitted(Settings, "bindings_changed")


## RESET-03 | A gamepad reset removes custom buttons and axes and saves before notifying.
func test_reset_03_gamepad_reset_persists_before_notification() -> void:
	var custom_key := _key(KEY_F)
	var custom_button := _joy_button(JOY_BUTTON_MISC1)
	var custom_axis := _joy_axis(JOY_AXIS_RIGHT_X, -1.0)
	Settings.rebind("fire", custom_key)
	Settings.rebind("fire", custom_button)
	InputMap.action_add_event("fire", custom_axis)
	Settings.save_input_mappings()
	var saved_on_signal: Array[ConfigFile] = []
	var observe := func() -> void:
		# Read the file the way Settings does: encrypted, or plaintext when there is no key.
		var load_data: Dictionary = Globals.safe_load_config(Settings.CONFIG_PATH)
		assert_eq(load_data["err"], OK, "an observer can read the saved settings")
		saved_on_signal.append(load_data["config"])
	Settings.bindings_changed.connect(observe)
	watch_signals(Settings)

	Settings.reset_to_defaults("gamepad")

	Settings.bindings_changed.disconnect(observe)
	var default_pad: InputEvent = InputDefaults.make_event("fire", "gamepad")
	assert_eq(_events_for("fire", "gamepad").size(), 1, "all custom gamepad inputs are removed")
	assert_true(_has_event("fire", default_pad), "the gamepad default is restored")
	assert_true(_has_event("fire", custom_key), "the custom keyboard binding survives")
	assert_eq(saved_on_signal.size(), 1, "the observer read the file once")
	var saved_events: Array = saved_on_signal[0].get_value("input", "fire", [])
	assert_eq(saved_events.size(), 2, "only the custom key and default gamepad input are saved")
	assert_has(saved_events, InputEventCodec.serialize_event(custom_key))
	assert_has(saved_events, InputEventCodec.serialize_event(default_pad))
	assert_signal_emit_count(Settings, "bindings_changed", 1)


# ── Device checks through InputEventCodec ────────────────────────────────────


## DEV-01 | The unbound check and the pause label follow the current device.
func test_dev_01_device_checks_follow_current_device() -> void:
	_unbind("fire", "gamepad")
	var pause_pad: InputEvent = _events_for("pause", "gamepad")[0]
	var pause_key: InputEvent = _events_for("pause", "keyboard")[0]

	Settings.set_input_device("keyboard")
	assert_false(Settings.has_unbound_critical_actions_for_current_device(), "keyboard bound")
	Settings.set_input_device("gamepad")
	assert_true(Settings.has_unbound_critical_actions_for_current_device(), "fire unbound")

	assert_eq(
		Settings.get_pause_binding_label_for_device("keyboard"),
		InputEventCodec.get_event_label(pause_key).to_upper()
	)
	assert_eq(
		Settings.get_pause_binding_label_for_device("gamepad"),
		InputEventCodec.get_event_label(pause_pad).to_upper()
	)


# ── UI scripts ───────────────────────────────────────────────────────────────


## UI-01 | No UI script writes InputMap directly.
func test_ui_01_no_direct_input_map_writes_in_ui_scripts() -> void:
	var paths: Array[String] = _ui_script_paths(UI_SCRIPTS_DIR)
	assert_gt(paths.size(), 0, "UI scripts found")
	for path: String in paths:
		var source: String = FileAccess.get_file_as_string(path)
		for call: String in FORBIDDEN_UI_CALLS:
			assert_false(
				source.contains(call + "("), "%s must not call %s" % [path, call]
			)


## UI-02 | Key Mapping no longer calls into MainScene (comments may still mention it).
func test_ui_02_key_mapping_does_not_call_main_scene() -> void:
	var code: String = ""
	for line: String in FileAccess.get_file_as_string(KEY_MAPPING_SCRIPT).split("\n"):
		if not line.strip_edges().begins_with("#"):
			code += line + "\n"
	assert_false(code.contains("MainScene"), "no MainScene reference")
	assert_false(code.contains("current_scene"), "no lookup of the current scene")
	assert_false(code.contains("clear_unbound_warning"), "no clear_unbound_warning call")


## UI-03 | Confirming the conflict dialog moves the input and emits bindings_changed once.
func test_ui_03_conflict_confirm_rebinds_through_settings() -> void:
	_menu = load(GamePaths.KEY_MAPPING_SCENE).instantiate()
	add_child(_menu)
	await get_tree().process_frame
	var next_btn: InputRemapButton = null
	for node: Node in get_tree().get_nodes_in_group("remap_buttons"):
		if node is InputRemapButton and (node as InputRemapButton).action == "next_weapon":
			next_btn = node
			break
	assert_not_null(next_btn, "next_weapon remap button found")
	var fire_key: InputEvent = _events_for("fire", "keyboard")[0]
	watch_signals(Settings)

	_menu.show_conflict_dialog(next_btn, fire_key.duplicate(), ["fire"] as Array[String])
	_menu._on_conflict_confirmed()

	assert_true(_has_event("next_weapon", fire_key), "next_weapon now uses fire's key")
	assert_eq(_events_for("fire", "keyboard").size(), 0, "fire is unbound on keyboard")
	assert_signal_emit_count(Settings, "bindings_changed", 1)
	assert_false(next_btn.listening, "the button stopped listening")
	assert_null(_menu.current_remap_button, "conflict state cleared")


## UI-04 | The Reset button resets through Settings and emits bindings_changed once.
func test_ui_04_reset_button_emits_bindings_changed() -> void:
	_menu = load(GamePaths.KEY_MAPPING_SCENE).instantiate()
	add_child(_menu)
	await get_tree().process_frame
	_menu.keyboard.button_pressed = true
	Settings.rebind("fire", _key(KEY_F))
	watch_signals(Settings)

	_menu.controls_reset_button.pressed.emit()

	assert_true(
		InputEventCodec.events_match(
			_events_for("fire", "keyboard")[0], InputDefaults.make_event("fire", "keyboard")
		),
		"fire is back on its default key"
	)
	assert_signal_emit_count(Settings, "bindings_changed", 1)


## UI-05 | A non-conflicting axis remap publishes once and refreshes the button.
func test_ui_05_direct_axis_remap_emits_bindings_changed() -> void:
	var button := InputRemapButton.new()
	button.action = "fire"
	button.current_device = InputRemapButton.DeviceType.GAMEPAD
	add_child_autofree(button)
	var keys_before: Array[InputEvent] = _events_for("fire", "keyboard")
	button.button_pressed = true
	button._on_pressed()
	watch_signals(Settings)

	button._input(_joy_axis(JOY_AXIS_RIGHT_X, -0.75))

	assert_signal_emit_count(Settings, "bindings_changed", 1)
	assert_eq(_events_for("fire", "gamepad").size(), 1)
	assert_true(_has_event("fire", _joy_axis(JOY_AXIS_RIGHT_X, -1.0)), "axis is normalized")
	assert_eq(_events_for("fire", "keyboard"), keys_before)
	assert_eq(button.text, "Right Stick (Left)")
	assert_false(button.listening, "the button exits capture mode")


# ── MainScene ────────────────────────────────────────────────────────────────


## MS-01 | All critical actions bound: no warning, and no per-frame processing.
func test_ms_01_no_warning_when_bound() -> void:
	var scene: MainScene = await _spawn_main_scene()

	assert_false(scene._showing_unbound_warning, "no warning flag")
	assert_false(_warning_visible(scene), "no warning shown")
	assert_false(scene.is_processing(), "MainScene does not poll every frame")


## MS-02 | A critical action unbound at level start shows the warning once.
func test_ms_02_warning_on_ready_when_unbound() -> void:
	_unbind("fire", "keyboard")

	var scene: MainScene = await _spawn_main_scene()

	assert_true(scene._showing_unbound_warning, "warning flag set")
	assert_true(_warning_visible(scene), "warning shown")


## MS-03 | Fixing the bindings clears the warning flag, and the warning doesn't come back.
func test_ms_03_fixing_bindings_clears_warning() -> void:
	_unbind("fire", "keyboard")
	var scene: MainScene = await _spawn_main_scene()
	_hide_message(scene)

	Settings.rebind("fire", InputDefaults.make_event("fire", "keyboard"))

	assert_false(scene._showing_unbound_warning, "flag cleared after the fix")
	assert_false(_warning_visible(scene), "no new warning: everything is bound")


## MS-04 | A binding change that leaves a critical action unbound shows the warning again.
func test_ms_04_still_unbound_after_change_warns_again() -> void:
	_unbind("fire", "keyboard")
	var scene: MainScene = await _spawn_main_scene()
	_hide_message(scene)

	Settings.rebind("speed_up", _key(KEY_F))

	assert_true(scene._showing_unbound_warning, "flag set again")
	assert_true(_warning_visible(scene), "warning shown again")


## MS-05 | The warning stays once per session: with no binding change, it isn't repeated.
func test_ms_05_warning_not_repeated_without_binding_change() -> void:
	_unbind("fire", "keyboard")
	var scene: MainScene = await _spawn_main_scene()
	_hide_message(scene)

	Settings.set_input_device("gamepad")
	Settings.set_input_device("keyboard")
	await get_tree().process_frame

	assert_false(_warning_visible(scene), "device changes don't repeat a shown warning")


## MS-06 | Switching to a device with an unbound critical action shows the warning.
func test_ms_06_device_change_shows_warning() -> void:
	_unbind("fire", "gamepad")
	var scene: MainScene = await _spawn_main_scene()
	assert_false(scene._showing_unbound_warning, "keyboard is fully bound")

	Settings.set_input_device("gamepad")

	assert_true(scene._showing_unbound_warning, "warning flag set for gamepad")
	assert_true(_warning_visible(scene), "warning shown")


## MS-07 | While paused (Key Mapping open from the pause menu), the check waits for unpause.
func test_ms_07_check_deferred_until_unpaused() -> void:
	_unbind("fire", "keyboard")
	var scene: MainScene = await _spawn_main_scene()
	_hide_message(scene)

	get_tree().paused = true
	Settings.rebind("speed_up", _key(KEY_F))
	assert_false(_warning_visible(scene), "no warning while paused")
	assert_true(scene._unbound_check_pending, "check is pending")

	get_tree().paused = false

	assert_false(scene._unbound_check_pending, "pending check ran")
	assert_true(_warning_visible(scene), "warning shown after unpause")


## MS-08 | Fixed while paused: no warning on unpause.
func test_ms_08_fixed_while_paused_no_warning() -> void:
	_unbind("fire", "keyboard")
	var scene: MainScene = await _spawn_main_scene()
	_hide_message(scene)

	get_tree().paused = true
	Settings.reset_to_defaults("keyboard")
	get_tree().paused = false

	assert_false(scene._showing_unbound_warning, "flag cleared")
	assert_false(_warning_visible(scene), "no warning: bindings were fixed")


## MS-09 | Leaving the tree disconnects MainScene from the Settings signals; re-entering
## reconnects it.
func test_ms_09_exit_tree_disconnects_signals() -> void:
	var scene: MainScene = await _spawn_main_scene()
	assert_true(Settings.bindings_changed.is_connected(scene._on_bindings_changed))
	assert_true(Settings.input_device_changed.is_connected(scene._on_input_device_changed))

	remove_child(scene)

	assert_false(Settings.bindings_changed.is_connected(scene._on_bindings_changed))
	assert_false(Settings.input_device_changed.is_connected(scene._on_input_device_changed))

	add_child(scene)

	assert_true(Settings.bindings_changed.is_connected(scene._on_bindings_changed))
	assert_true(Settings.input_device_changed.is_connected(scene._on_input_device_changed))


## MS-10 | Device changes while paused use the device selected at resume.
func test_ms_10_paused_device_switch_checks_current_device_on_resume() -> void:
	_unbind("fire", "gamepad")
	Settings.rebind("pause", _joy_button(JOY_BUTTON_BACK))
	var scene: MainScene = await _spawn_main_scene()

	get_tree().paused = true
	Settings.set_input_device("gamepad")
	assert_false(_warning_visible(scene), "switching to an unbound device while paused is silent")
	Settings.set_input_device("keyboard")
	get_tree().paused = false
	assert_false(_warning_visible(scene), "the final device is fully bound")

	get_tree().paused = true
	Settings.set_input_device("gamepad")
	assert_false(_warning_visible(scene), "the warning still waits for resume")
	get_tree().paused = false

	assert_true(_warning_visible(scene), "the final device now has an unbound critical action")
	assert_true(scene.message_label.text.contains("PRESS='BACK'"), "uses the gamepad pause label")
