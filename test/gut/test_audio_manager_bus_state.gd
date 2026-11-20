## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_audio_manager_bus_state.gd
##
## TEST SUITE: AudioManager's per-bus state API, driven by AudioConstants.BUS_CONFIG.
## Issue #1153: get_volume(), set_volume(), get_muted() and set_muted() look the bus up in
## BUS_CONFIG instead of four per-bus match blocks. These tests pin the mapping, the
## signals and the unknown-bus behavior, so a BUS_CONFIG entry that drifts from the
## variables fails here instead of at runtime.
## Issue #1154: get_parent_bus(), get_muted_ancestor() and is_effectively_muted() read the
## "parent" field of BUS_CONFIG. These tests pin the hierarchy against an independent table,
## against the sends in default_bus_layout.tres, and over all 64 mute combinations.
## Uses a fresh AudioManager instance outside the scene tree, so _ready() never loads user
## settings and the autoload's state is untouched.

extends "res://addons/gut/test.gd"

const AudioManagerScript: GDScript = preload("res://scripts/managers/audio_manager.gd")

## Expected variable names per bus, kept independent of BUS_CONFIG so a wrong mapping
## there is caught instead of being used by both sides of the check.
const BUS_VARS: Dictionary = {
	"Master": ["master_volume", "master_muted"],
	"Music": ["music_volume", "music_muted"],
	"SFX": ["sfx_volume", "sfx_muted"],
	"SFX_Weapon": ["weapon_volume", "weapon_muted"],
	"SFX_Rotors": ["rotors_volume", "rotors_muted"],
	"SFX_Menu": ["menu_volume", "menu_muted"],
}
## Expected parent per bus, kept independent of BUS_CONFIG for the same reason.
const PARENTS: Dictionary = {
	"Master": "",
	"Music": "Master",
	"SFX": "Master",
	"SFX_Weapon": "SFX",
	"SFX_Rotors": "SFX",
	"SFX_Menu": "SFX",
}
const SFX_CHILDREN: Array = ["SFX_Weapon", "SFX_Rotors", "SFX_Menu"]
const ALL_BUSES: Array = ["Master", "Music", "SFX", "SFX_Weapon", "SFX_Rotors", "SFX_Menu"]
const UNKNOWN_BUS: String = "NotABus"
## A value no bus starts with in before_each(), so a write is always a visible change.
const NEW_VOLUME: float = 0.77


## Collects every logged line while it is added with OS.add_logger().
class LogCapture:
	extends Logger
	var lines: Array[String] = []
	var _mutex: Mutex = Mutex.new()

	func _log_message(message: String, _error: bool) -> void:
		_mutex.lock()
		lines.append(message)
		_mutex.unlock()

	## Returns true if any captured line contains [param text].
	func has_text(text: String) -> bool:
		_mutex.lock()
		var found: bool = false
		for line: String in lines:
			if line.contains(text):
				found = true
				break
		_mutex.unlock()
		return found


var _manager: Node


## Starts every bus at its own volume, with alternating mute flags, so a write to the wrong
## variable always shows up as a changed value.
## :rtype: void
func before_each() -> void:
	_manager = autofree(AudioManagerScript.new())
	var index: int = 0
	for bus: String in ALL_BUSES:
		_manager.set_bus_state(bus, 0.2 + index * 0.1, index % 2 == 0)
		index += 1


## Returns every bus's volume and mute state, read straight from the variables.
## :rtype: Dictionary
func _raw_snapshot() -> Dictionary:
	var states: Dictionary = {}
	for bus: String in ALL_BUSES:
		states[bus] = [_manager.get(BUS_VARS[bus][0]), _manager.get(BUS_VARS[bus][1])]
	return states


## Returns the declared type of a script variable on the manager, or TYPE_NIL if missing.
## :rtype: int
func _property_type(property_name: String) -> int:
	for property: Dictionary in _manager.get_property_list():
		if property["name"] == property_name:
			return int(property["type"])
	return TYPE_NIL


# ==========================================================================
# 1. BUS_CONFIG MATCHES THE VARIABLES
# ==========================================================================


## BUS_CONFIG covers exactly the six buses this suite expects.
## :rtype: void
func test_bus_config_lists_the_six_buses() -> void:
	var config_buses: Array = AudioConstants.BUS_CONFIG.keys()
	config_buses.sort()
	var expected: Array = ALL_BUSES.duplicate()
	expected.sort()
	assert_eq(config_buses, expected, "BUS_CONFIG must list exactly the six mixer buses.")


## Every BUS_CONFIG entry names the expected variables, and they exist with the right type.
## :rtype: void
func test_bus_config_vars_exist_with_correct_types(bus: String = use_parameters(ALL_BUSES)) -> void:
	var entry: Dictionary = AudioConstants.BUS_CONFIG[bus]
	assert_eq(entry["volume_var"], BUS_VARS[bus][0], "%s volume_var mismatch." % bus)
	assert_eq(entry["muted_var"], BUS_VARS[bus][1], "%s muted_var mismatch." % bus)
	assert_eq(
		_property_type(entry["volume_var"]),
		TYPE_FLOAT,
		"%s: '%s' must be a float variable on AudioManager." % [bus, entry["volume_var"]]
	)
	assert_eq(
		_property_type(entry["muted_var"]),
		TYPE_BOOL,
		"%s: '%s' must be a bool variable on AudioManager." % [bus, entry["muted_var"]]
	)


## The bus state variables are plain vars, not editor exports (the autoload has no scene).
## :rtype: void
func test_bus_state_vars_are_not_exported(bus: String = use_parameters(ALL_BUSES)) -> void:
	for property: Dictionary in _manager.get_property_list():
		if property["name"] in BUS_VARS[bus]:
			assert_eq(
				int(property["usage"]) & PROPERTY_USAGE_EDITOR,
				0,
				"%s: '%s' must not be an @export variable." % [bus, property["name"]]
			)


# ==========================================================================
# 2. GETTERS AND SETTERS
# ==========================================================================


## set_volume() writes the bus's own variable, and get_volume() reads it back.
## :rtype: void
func test_volume_round_trip(bus: String = use_parameters(ALL_BUSES)) -> void:
	_manager.set_volume(bus, NEW_VOLUME)
	assert_almost_eq(_manager.get_volume(bus), NEW_VOLUME, 0.0001, "%s get_volume." % bus)
	assert_almost_eq(
		float(_manager.get(BUS_VARS[bus][0])), NEW_VOLUME, 0.0001, "%s variable." % bus
	)


## get_volume() reads the bus's own variable when it is assigned directly.
## :rtype: void
func test_get_volume_reads_the_variable(bus: String = use_parameters(ALL_BUSES)) -> void:
	_manager.set(BUS_VARS[bus][0], 0.123)
	assert_almost_eq(_manager.get_volume(bus), 0.123, 0.0001, "%s get_volume." % bus)


## set_muted() writes the bus's own variable both ways, and get_muted() reads it back.
## :rtype: void
func test_mute_round_trip(bus: String = use_parameters(ALL_BUSES)) -> void:
	for muted: bool in [true, false, true]:
		_manager.set_muted(bus, muted)
		assert_eq(_manager.get_muted(bus), muted, "%s get_muted after %s." % [bus, muted])
		assert_eq(_manager.get(BUS_VARS[bus][1]), muted, "%s variable after %s." % [bus, muted])


## get_muted() reads the bus's own variable when it is assigned directly.
## :rtype: void
func test_get_muted_reads_the_variable(bus: String = use_parameters(ALL_BUSES)) -> void:
	var flipped: bool = not bool(_manager.get(BUS_VARS[bus][1]))
	_manager.set(BUS_VARS[bus][1], flipped)
	assert_eq(_manager.get_muted(bus), flipped, "%s get_muted." % bus)


## Setting one bus's volume and mute leaves every other bus unchanged.
## :rtype: void
func test_setting_one_bus_leaves_the_others(bus: String = use_parameters(ALL_BUSES)) -> void:
	var before: Dictionary = _raw_snapshot()
	_manager.set_volume(bus, NEW_VOLUME)
	_manager.set_muted(bus, not bool(before[bus][1]))
	var after: Dictionary = _raw_snapshot()
	for other: String in ALL_BUSES:
		if other == bus:
			continue
		assert_eq(after[other], before[other], "Setting %s must not change %s." % [bus, other])
	assert_ne(after[bus], before[bus], "%s itself must change." % bus)


## set_volume() and set_muted() emit their signal once, with the bus and the new value.
## :rtype: void
func test_setters_emit_once_with_arguments(bus: String = use_parameters(ALL_BUSES)) -> void:
	var new_muted: bool = not _manager.get_muted(bus)
	watch_signals(_manager)
	_manager.set_volume(bus, NEW_VOLUME)
	_manager.set_muted(bus, new_muted)
	assert_signal_emit_count(_manager, "volume_changed", 1, "%s volume_changed count." % bus)
	assert_signal_emit_count(_manager, "mute_toggled", 1, "%s mute_toggled count." % bus)
	assert_signal_emitted_with_parameters(_manager, "volume_changed", [bus, NEW_VOLUME])
	assert_signal_emitted_with_parameters(_manager, "mute_toggled", [bus, new_muted])


## The setters still emit when the value is unchanged (documented signal contract).
## :rtype: void
func test_setters_emit_for_unchanged_values(bus: String = use_parameters(ALL_BUSES)) -> void:
	var volume: float = _manager.get_volume(bus)
	var muted: bool = _manager.get_muted(bus)
	watch_signals(_manager)
	_manager.set_volume(bus, volume)
	_manager.set_muted(bus, muted)
	assert_signal_emit_count(_manager, "volume_changed", 1)
	assert_signal_emit_count(_manager, "mute_toggled", 1)


# ==========================================================================
# 3. UNKNOWN BUSES
# ==========================================================================


## Unknown buses: getters return 0.0 / false, setters change nothing and emit nothing,
## and every call logs a warning naming the function and the bus.
## :rtype: void
func test_unknown_bus_is_rejected_with_warnings() -> void:
	var before: Dictionary = _raw_snapshot()
	var original_settings: GameSettingsResource = Globals.settings
	# A fresh settings resource logs WARNING and above, whatever the user's saved level is.
	Globals.settings = GameSettingsResource.new()
	var log_capture: LogCapture = LogCapture.new()
	watch_signals(_manager)
	OS.add_logger(log_capture)
	var volume: float = _manager.get_volume(UNKNOWN_BUS)
	var muted: bool = _manager.get_muted(UNKNOWN_BUS)
	_manager.set_volume(UNKNOWN_BUS, NEW_VOLUME)
	_manager.set_muted(UNKNOWN_BUS, true)
	OS.remove_logger(log_capture)
	Globals.settings = original_settings

	assert_eq(volume, 0.0, "get_volume() returns 0.0 for an unknown bus.")
	assert_false(muted, "get_muted() returns false for an unknown bus.")
	assert_eq(_raw_snapshot(), before, "Unknown buses must not change any bus.")
	assert_signal_not_emitted(_manager, "volume_changed")
	assert_signal_not_emitted(_manager, "mute_toggled")
	for function_name: String in ["get_volume", "get_muted", "set_volume", "set_muted"]:
		assert_true(
			log_capture.has_text("[WARNING] Unknown bus for %s: %s" % [function_name, UNKNOWN_BUS]),
			"%s must log a warning for an unknown bus." % function_name
		)


# ==========================================================================
# 4. BUS HIERARCHY (Issue #1154)
# ==========================================================================


## Unmutes every bus, then mutes only [param muted_buses].
## :rtype: void
func _set_mutes(muted_buses: Array) -> void:
	for bus: String in ALL_BUSES:
		_manager.set_muted(bus, bus in muted_buses)


## Reference rule from the table above: the muted ancestor nearest Master, or "".
## :rtype: String
func _expected_ancestor(bus: String, muted_buses: Array) -> String:
	var locked_by: String = ""
	var ancestor: String = PARENTS[bus]
	while not ancestor.is_empty():
		if ancestor in muted_buses:
			locked_by = ancestor
		ancestor = PARENTS[ancestor]
	return locked_by


## Every BUS_CONFIG entry has a String "parent" that names another BUS_CONFIG bus, or "".
## :rtype: void
func test_bus_config_parent_field(bus: String = use_parameters(ALL_BUSES)) -> void:
	var entry: Dictionary = AudioConstants.BUS_CONFIG[bus]
	assert_true(entry.has("parent"), "%s must have a 'parent' field." % bus)
	assert_true(entry.get("parent") is String, "%s parent must be a String." % bus)
	var parent: String = String(entry.get("parent", ""))
	assert_true(
		parent.is_empty() or AudioConstants.BUS_CONFIG.has(parent),
		"%s parent '%s' must be a BUS_CONFIG bus." % [bus, parent]
	)


## get_parent_bus() returns the expected parent for each bus.
## :rtype: void
func test_get_parent_bus(bus: String = use_parameters(ALL_BUSES)) -> void:
	assert_eq(_manager.get_parent_bus(bus), PARENTS[bus], "%s parent." % bus)


## An unknown bus has no parent, no muted ancestor and is not effectively muted; each call
## logs a warning, and nothing changes.
## :rtype: void
func test_hierarchy_unknown_bus() -> void:
	_set_mutes(ALL_BUSES)
	var before: Dictionary = _raw_snapshot()
	var original_settings: GameSettingsResource = Globals.settings
	Globals.settings = GameSettingsResource.new()
	var log_capture: LogCapture = LogCapture.new()
	OS.add_logger(log_capture)
	var parent: String = _manager.get_parent_bus(UNKNOWN_BUS)
	var ancestor: String = _manager.get_muted_ancestor(UNKNOWN_BUS)
	var effectively_muted: bool = _manager.is_effectively_muted(UNKNOWN_BUS)
	OS.remove_logger(log_capture)
	Globals.settings = original_settings

	assert_eq(parent, "", "get_parent_bus() returns '' for an unknown bus.")
	assert_eq(ancestor, "", "get_muted_ancestor() returns '' for an unknown bus.")
	assert_false(effectively_muted, "An unknown bus is never effectively muted.")
	assert_eq(_raw_snapshot(), before, "Hierarchy queries must not change any bus.")
	assert_true(
		log_capture.has_text("[WARNING] Unknown bus for get_parent_bus: " + UNKNOWN_BUS),
		"get_parent_bus() must log a warning for an unknown bus."
	)


## Each BUS_CONFIG parent matches the bus's send in the shipped default_bus_layout.tres, so
## the lock hierarchy follows the real signal path. Master sends nowhere.
## :rtype: void
func test_parent_matches_layout_send(bus: String = use_parameters(ALL_BUSES)) -> void:
	var layout: AudioBusLayout = load("res://default_bus_layout.tres") as AudioBusLayout
	assert_not_null(layout, "The shipped default audio layout must load.")
	if layout == null:
		return
	var bus_idx: int = _layout_bus_index(layout, bus)
	assert_gt(bus_idx, -1, "Bus '%s' must exist in default_bus_layout.tres." % bus)
	if bus_idx == -1:
		return
	var send: String = String(layout.get("bus/%d/send" % bus_idx))
	if bus == "Master":
		assert_eq(bus_idx, 0, "Master must be the first bus.")
		assert_eq(_manager.get_parent_bus(bus), "", "Master has no parent.")
	else:
		assert_eq(
			_manager.get_parent_bus(bus),
			send,
			"%s parent must match its send in default_bus_layout.tres." % bus
		)


## Finds a bus index in the serialized layout by name.
## :rtype: int
func _layout_bus_index(layout: AudioBusLayout, bus_name: String) -> int:
	for property: Dictionary in layout.get_property_list():
		var property_name: String = property["name"]
		if property_name.begins_with("bus/") and property_name.ends_with("/name"):
			if String(layout.get(property_name)) == bus_name:
				return int(property_name.split("/")[1])
	return -1


## With nothing muted, no bus has a muted ancestor or is effectively muted.
## :rtype: void
func test_nothing_muted(bus: String = use_parameters(ALL_BUSES)) -> void:
	_set_mutes([])
	assert_eq(_manager.get_muted_ancestor(bus), "", "%s ancestor." % bus)
	assert_false(_manager.is_effectively_muted(bus), "%s effectively muted." % bus)


## A bus's own mute makes it effectively muted, but is not a muted ancestor of itself.
## :rtype: void
func test_own_mute_only(bus: String = use_parameters(ALL_BUSES)) -> void:
	_set_mutes([bus])
	assert_eq(_manager.get_muted_ancestor(bus), "", "%s own mute is not an ancestor." % bus)
	assert_true(_manager.is_effectively_muted(bus), "%s is muted itself." % bus)


## A muted Master locks every other bus.
## :rtype: void
func test_master_mute_locks_all_children(bus: String = use_parameters(ALL_BUSES)) -> void:
	_set_mutes(["Master"])
	var expected: String = "" if bus == "Master" else "Master"
	assert_eq(_manager.get_muted_ancestor(bus), expected, "%s ancestor." % bus)
	assert_true(_manager.is_effectively_muted(bus), "%s effectively muted." % bus)


## A muted SFX locks its three sub-buses, not Master or Music.
## :rtype: void
func test_sfx_mute_locks_only_sfx_children(bus: String = use_parameters(ALL_BUSES)) -> void:
	_set_mutes(["SFX"])
	var expected: String = "SFX" if bus in SFX_CHILDREN else ""
	assert_eq(_manager.get_muted_ancestor(bus), expected, "%s ancestor." % bus)
	assert_eq(
		_manager.is_effectively_muted(bus),
		bus == "SFX" or bus in SFX_CHILDREN,
		"%s effectively muted." % bus
	)


## With Master and SFX both muted, an SFX sub-bus reports Master: the warning both callers
## show today, and the bus the player must unmute first.
## :rtype: void
func test_master_wins_over_sfx(bus: String = use_parameters(SFX_CHILDREN)) -> void:
	_set_mutes(["Master", "SFX"])
	assert_eq(_manager.get_muted_ancestor(bus), "Master", "%s ancestor." % bus)


## Muted siblings and children never lock a bus.
## :rtype: void
func test_siblings_and_children_do_not_lock() -> void:
	_set_mutes(["Music", "SFX_Weapon"])
	for bus: String in ["Master", "SFX", "SFX_Rotors", "SFX_Menu"]:
		assert_eq(_manager.get_muted_ancestor(bus), "", "%s ancestor." % bus)
		assert_false(_manager.is_effectively_muted(bus), "%s effectively muted." % bus)


## Every one of the 64 mute combinations matches the reference rule for every bus.
## :rtype: void
func test_all_mute_combinations_match_reference() -> void:
	for mask: int in range(1 << ALL_BUSES.size()):
		var muted_buses: Array = []
		for index: int in range(ALL_BUSES.size()):
			if mask & (1 << index):
				muted_buses.append(ALL_BUSES[index])
		_set_mutes(muted_buses)
		for bus: String in ALL_BUSES:
			var expected: String = _expected_ancestor(bus, muted_buses)
			assert_eq(
				_manager.get_muted_ancestor(bus),
				expected,
				"%s ancestor with %s muted." % [bus, muted_buses]
			)
			assert_eq(
				_manager.is_effectively_muted(bus),
				bus in muted_buses or not expected.is_empty(),
				"%s effectively muted with %s muted." % [bus, muted_buses]
			)


## The hierarchy queries are read-only: no state change and no signals.
## :rtype: void
func test_hierarchy_queries_are_read_only() -> void:
	_set_mutes(["Master", "SFX_Menu"])
	var before: Dictionary = _raw_snapshot()
	watch_signals(_manager)
	for bus: String in ALL_BUSES:
		_manager.get_parent_bus(bus)
		_manager.get_muted_ancestor(bus)
		_manager.is_effectively_muted(bus)
	assert_eq(_raw_snapshot(), before, "Queries must not change any bus.")
	assert_signal_not_emitted(_manager, "volume_changed")
	assert_signal_not_emitted(_manager, "mute_toggled")
