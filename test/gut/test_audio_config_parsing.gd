## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## In-memory audio configuration parsing, independent of singleton startup and disk I/O.
extends "res://addons/gut/test.gd"

const AudioManagerScript = preload("res://scripts/managers/audio_manager.gd")
# Keep persisted key expectations independent of BUS_CONFIG's mappings.
const BUS_KEYS: Dictionary = {
	"Master": ["master_volume", "master_muted"],
	"Music": ["music_volume", "music_muted"],
	"SFX": ["sfx_volume", "sfx_muted"],
	"SFX_Weapon": ["weapon_volume", "weapon_muted"],
	"SFX_Rotors": ["rotors_volume", "rotors_muted"],
	"SFX_Menu": ["menu_volume", "menu_muted"],
}

var _manager: Node
var _config: ConfigFile


func before_each() -> void:
	# Keep the instance outside the scene tree so _ready() cannot load user settings.
	_manager = autofree(AudioManagerScript.new())
	_config = ConfigFile.new()
	var index: int = 0
	for bus: String in BUS_KEYS:
		_manager.set_bus_state(bus, 0.2 + index * 0.1, index % 2 == 0)
		index += 1


func _snapshot() -> Dictionary:
	var states: Dictionary = {}
	for bus: String in BUS_KEYS:
		states[bus] = _manager.get_bus_state(bus)
	return states


func _assert_bus_signals(expected: Dictionary) -> void:
	assert_signal_emit_count(_manager, "volume_changed", BUS_KEYS.size())
	assert_signal_emit_count(_manager, "mute_toggled", BUS_KEYS.size())
	var volumes: Array = []
	var mutes: Array = []
	for index: int in range(BUS_KEYS.size()):
		volumes.append(get_signal_parameters(_manager, "volume_changed", index))
		mutes.append(get_signal_parameters(_manager, "mute_toggled", index))
	for bus: String in BUS_KEYS:
		assert_has(volumes, [bus, expected[bus]["volume"]])
		assert_has(mutes, [bus, expected[bus]["muted"]])


func test_null_config_preserves_state_without_signals() -> void:
	var before := _snapshot()
	watch_signals(_manager)
	_manager.apply_volumes_from_config(null)
	assert_eq(_snapshot(), before)
	assert_signal_not_emitted(_manager, "volume_changed")
	assert_signal_not_emitted(_manager, "mute_toggled")


func test_empty_config_preserves_state_and_emits_each_bus() -> void:
	var before := _snapshot()
	watch_signals(_manager)
	_manager.apply_volumes_from_config(_config)
	assert_eq(_snapshot(), before)
	_assert_bus_signals(before)


func test_applies_all_persisted_keys_with_matching_signals() -> void:
	var expected: Dictionary = {}
	var index: int = 0
	for bus: String in BUS_KEYS:
		var volume: float = 0.9 - index * 0.1
		var muted: bool = not _manager.get_muted(bus)
		_config.set_value("audio", BUS_KEYS[bus][0], volume)
		_config.set_value("audio", BUS_KEYS[bus][1], muted)
		expected[bus] = {"volume": volume, "muted": muted}
		index += 1
	watch_signals(_manager)
	_manager.apply_volumes_from_config(_config)
	assert_eq(_snapshot(), expected)
	_assert_bus_signals(expected)


func test_numeric_volumes_include_zero_and_one(
	value: Variant = use_parameters([0, 1, 0.0, 0.375, 1.0])
) -> void:
	var expected := _snapshot()
	for bus: String in BUS_KEYS:
		_config.set_value("audio", BUS_KEYS[bus][0], value)
		expected[bus]["volume"] = float(value)
	_manager.apply_volumes_from_config(_config)
	assert_eq(_snapshot(), expected, "Numeric volumes must preserve absent mute flags")


func test_both_boolean_mute_values_are_accepted(
	muted: bool = use_parameters([false, true])
) -> void:
	for bus: String in BUS_KEYS:
		_manager.set_muted(bus, not muted)
	var expected := _snapshot()
	for bus: String in BUS_KEYS:
		_config.set_value("audio", BUS_KEYS[bus][1], muted)
		expected[bus]["muted"] = muted
	_manager.apply_volumes_from_config(_config)
	assert_eq(_snapshot(), expected, "Mute-only settings must preserve current volumes")


func test_invalid_volume_keeps_current_value_but_applies_valid_mute(
	value: Variant = use_parameters(["0.5", "", true, false, [], {"volume": 0.5}])
) -> void:
	var expected := _snapshot()
	for bus: String in BUS_KEYS:
		_config.set_value("audio", BUS_KEYS[bus][0], value)
		_config.set_value("audio", BUS_KEYS[bus][1], not expected[bus]["muted"])
		expected[bus]["muted"] = not expected[bus]["muted"]
	_manager.apply_volumes_from_config(_config)
	assert_eq(_snapshot(), expected, "Invalid volumes must not discard valid mute flags")


func test_invalid_mute_keeps_current_value_but_applies_valid_volume(
	value: Variant = use_parameters([0, 1, 0.0, 1.0, "true", "false", [], {"muted": true}])
) -> void:
	var expected := _snapshot()
	for bus: String in BUS_KEYS:
		_config.set_value("audio", BUS_KEYS[bus][0], 0.875)
		_config.set_value("audio", BUS_KEYS[bus][1], value)
		expected[bus]["volume"] = 0.875
	_manager.apply_volumes_from_config(_config)
	assert_eq(_snapshot(), expected, "Invalid mute flags must not discard valid volumes")


func test_wrong_sections_and_unknown_keys_preserve_state() -> void:
	var before := _snapshot()
	for bus: String in BUS_KEYS:
		_config.set_value("Audio", BUS_KEYS[bus][0], 0.0)
		_config.set_value("settings", BUS_KEYS[bus][1], not before[bus]["muted"])
	_config.set_value("audio", "unknown_volume", 0.0)
	_config.set_value("audio", "unknown_muted", true)
	_manager.apply_volumes_from_config(_config)
	assert_eq(_snapshot(), before)


func test_partial_config_updates_only_the_requested_bus(
	bus: String = use_parameters(["Master", "Music", "SFX", "SFX_Weapon", "SFX_Rotors", "SFX_Menu"])
) -> void:
	var expected := _snapshot()
	_config.set_value("audio", BUS_KEYS[bus][0], 0.125)
	_config.set_value("audio", BUS_KEYS[bus][1], not expected[bus]["muted"])
	expected[bus] = {"volume": 0.125, "muted": not expected[bus]["muted"]}
	_manager.apply_volumes_from_config(_config)
	assert_eq(_snapshot(), expected, "Parsing one bus must not reset another")


func test_repeated_partial_configs_preserve_previously_applied_values() -> void:
	_config.set_value("audio", "master_volume", 0.875)
	_manager.apply_volumes_from_config(_config)
	var expected := _snapshot()
	var next_config := ConfigFile.new()
	next_config.set_value("audio", "master_volume", "invalid")
	next_config.set_value("audio", "music_muted", true)
	expected["Music"]["muted"] = true
	_manager.apply_volumes_from_config(next_config)
	assert_eq(_snapshot(), expected)


func test_parser_preserves_input_config_and_current_path() -> void:
	_config.set_value("audio", "master_volume", 0.875)
	_config.set_value("audio", "music_muted", "invalid")
	_config.set_value("unrelated", "keep", [1, 2, 3])
	var original_text: String = _config.encode_to_text()
	_manager.current_config_path = "user://audio_parser_unused.cfg"
	_manager.apply_volumes_from_config(_config)
	assert_eq(_config.encode_to_text(), original_text)
	assert_eq(_manager.current_config_path, "user://audio_parser_unused.cfg")


func test_parser_does_not_apply_state_to_audio_server() -> void:
	var runtime_states: Dictionary = {}
	for index: int in range(AudioServer.get_bus_count()):
		runtime_states[index] = [
			AudioServer.get_bus_volume_db(index), AudioServer.is_bus_mute(index)
		]
	for bus: String in BUS_KEYS:
		_config.set_value("audio", BUS_KEYS[bus][0], 0.125)
		_config.set_value("audio", BUS_KEYS[bus][1], true)
	_manager.apply_volumes_from_config(_config)
	for index: int in runtime_states:
		assert_eq(AudioServer.get_bus_volume_db(index), runtime_states[index][0])
		assert_eq(AudioServer.is_bus_mute(index), runtime_states[index][1])
