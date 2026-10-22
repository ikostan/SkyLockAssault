## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_audio_manager_change_volume.gd
##
## TEST SUITE: AudioManager.change_volume() owns the near-zero auto-mute rule (Issue #1039).
## change_volume() runs from the autoload with no Audio Settings menu in the tree, and callers
## state their intent through is_manual_interaction instead of slider focus. The rule fires
## only on AUTO_MUTE_VOLUME_THRESHOLD crossings (Issue #1040), so mutes the player chose at
## an audible volume stay put. The raw setters (set_volume, set_bus_state, config load, reset)
## must never apply the rule.
## Part of epic #725. T4 (#1041) changes the AudioServer re-sync; T7 (#1044) extends this suite.

extends "res://addons/gut/test.gd"

const TEST_CONFIG_PATH: String = "user://test_audio_manager_change_volume.cfg"
const START_VOLUME: float = 0.66
const RAISED_VOLUME: float = 0.33
## Hold delay plus a safety buffer for timer granularity.
const HOLD_WAIT: float = AudioConstants.MUTE_HARDWARE_DELAY + 0.1
const ALL_BUSES: Array = [
	AudioConstants.BUS_MASTER,
	AudioConstants.BUS_MUSIC,
	AudioConstants.BUS_SFX,
	AudioConstants.BUS_SFX_WEAPON,
	AudioConstants.BUS_SFX_ROTORS,
	AudioConstants.BUS_SFX_MENU,
]

var _original_config_path: String
var _original_states: Dictionary = {}
var _original_last_audible: Dictionary = {}
var _original_encryption_key: String


## Isolates config I/O and starts every bus unmuted at START_VOLUME, in AudioServer too.
## :rtype: void
func before_each() -> void:
	_original_config_path = AudioManager.current_config_path
	_original_last_audible = AudioManager._last_audible_volume.duplicate()
	_original_encryption_key = Globals.save_encryption_pass
	for bus: String in AudioConstants.BUS_CONFIG.keys():
		_original_states[bus] = AudioManager.get_bus_state(bus)

	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)
	Globals.set_test_encryption_key()
	AudioManager.current_config_path = TEST_CONFIG_PATH
	SfxManager.stop_all_sfx()

	for bus: String in AudioConstants.BUS_CONFIG.keys():
		AudioManager.set_bus_state(bus, START_VOLUME, false)
	AudioManager.apply_all_volumes()


## Lets any pending Master hold finish, then restores the original audio state.
## :rtype: void
func after_each() -> void:
	await wait_seconds(HOLD_WAIT)
	SfxManager.stop_all_sfx()

	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)

	AudioManager.current_config_path = _original_config_path
	for bus: String in _original_states.keys():
		var state: Dictionary = _original_states[bus]
		AudioManager.set_bus_state(bus, state["volume"], state["muted"])
	AudioManager.apply_all_volumes()
	AudioManager._last_audible_volume = _original_last_audible
	Globals.save_encryption_pass = _original_encryption_key


# ==========================================
# HELPERS
# ==========================================


## Returns the AudioServer index of a bus, failing the test if it is missing.
## :rtype: int
func _bus_idx(bus_name: String) -> int:
	var idx: int = AudioServer.get_bus_index(bus_name)
	assert_ne(idx, -1, bus_name + " bus must exist")
	return idx


## Returns the linear volume AudioServer currently holds for a bus.
## :rtype: float
func _hw_linear(bus_name: String) -> float:
	return db_to_linear(AudioServer.get_bus_volume_db(_bus_idx(bus_name)))


## Returns the AudioServer mute flag for a bus.
## :rtype: bool
func _hw_muted(bus_name: String) -> bool:
	return AudioServer.is_bus_mute(_bus_idx(bus_name))


## Puts a bus in the muted-at-zero state through the raw setters (no rule, no SFX).
## :rtype: void
func _force_muted_at_zero(bus_name: String) -> void:
	AudioManager.set_bus_state(bus_name, 0.0, true)
	AudioManager.apply_volume_to_bus(bus_name, 0.0, true)


## Returns the number of mute_toggled emissions for a bus since watch_signals().
## :rtype: int
func _mute_emits_for(bus_name: String) -> int:
	var count: int = 0
	for i in range(get_signal_emit_count(AudioManager, "mute_toggled")):
		var params: Array = get_signal_parameters(AudioManager, "mute_toggled", i)
		if params[0] == bus_name:
			count += 1
	return count


# ==========================================
# PRECONDITION: NO MENU
# ==========================================


## The rule must not depend on the Audio Settings menu (epic #725 DoD).
## :rtype: void
func test_no_audio_menu_in_tree() -> void:
	var menus: Array[Node] = get_tree().root.find_children("*", "Control", true, false).filter(
		func(n: Node) -> bool: return n.scene_file_path == GamePaths.AUDIO_SETTINGS_SCENE
	)
	assert_eq(menus.size(), 0, "This suite must run with no Audio Settings menu in the tree")


# ==========================================
# AUTO-MUTE (DOWN)
# ==========================================


## Programmatic change to zero auto-mutes silently and writes the volume to AudioServer.
## :rtype: void
func test_programmatic_zero_auto_mutes_silently(bus: String = use_parameters(ALL_BUSES)) -> void:
	await AudioManager.change_volume(bus, 0.0)

	assert_eq(AudioManager.get_volume(bus), 0.0, "Volume is stored")
	assert_true(AudioManager.get_muted(bus), bus + " is auto-muted at zero")
	assert_false(SfxManager.is_any_sfx_playing(), "Programmatic changes never play SFX")
	assert_almost_eq(_hw_linear(bus), 0.0, 0.0001, "AudioServer gets the zero volume")


## Manual change to zero auto-mutes and plays the confirmation click.
## :rtype: void
func test_manual_zero_auto_mutes_with_click(bus: String = use_parameters(ALL_BUSES)) -> void:
	AudioManager.change_volume(bus, 0.0, true)

	assert_true(AudioManager.get_muted(bus), bus + " is auto-muted at zero")
	assert_true(SfxManager.is_any_sfx_playing(), "Manual auto-mute plays the click")
	assert_eq(
		SfxManager.get_active_sfx_stream_path(),
		AudioConstants.SFX_DIR_PATH + "check.wav",
		"The click is SFX_CHECK"
	)


## Values below the threshold count as zero.
## :rtype: void
func test_value_at_threshold_auto_mutes(bus: String = use_parameters(ALL_BUSES)) -> void:
	await AudioManager.change_volume(bus, AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD)
	assert_true(AudioManager.get_muted(bus), "Threshold is inclusive")


## An already muted bus at zero is a no-op: no mute signal, no click.
## :rtype: void
func test_repeated_zero_is_noop(bus: String = use_parameters(ALL_BUSES)) -> void:
	await AudioManager.change_volume(bus, 0.0, true)
	await wait_seconds(HOLD_WAIT)
	SfxManager.stop_all_sfx()
	watch_signals(AudioManager)

	await AudioManager.change_volume(bus, 0.0, true)

	assert_eq(_mute_emits_for(bus), 0, "No mute_toggled on a repeated near-zero update")
	assert_false(SfxManager.is_any_sfx_playing(), "No click on a repeated near-zero update")


# ==========================================
# AUTO-UNMUTE (UP)
# ==========================================


## Programmatic change above the threshold unmutes an auto-muted bus silently.
## :rtype: void
func test_programmatic_raise_unmutes_silently(bus: String = use_parameters(ALL_BUSES)) -> void:
	_force_muted_at_zero(bus)

	await AudioManager.change_volume(bus, RAISED_VOLUME)

	assert_false(AudioManager.get_muted(bus), bus + " is auto-unmuted")
	assert_eq(AudioManager.get_volume(bus), RAISED_VOLUME)
	assert_false(SfxManager.is_any_sfx_playing(), "Programmatic changes never play SFX")
	assert_almost_eq(_hw_linear(bus), RAISED_VOLUME, 0.0001, "AudioServer gets the new volume")


## Manual change above the threshold unmutes and plays the click.
## :rtype: void
func test_manual_raise_unmutes_with_click(bus: String = use_parameters(ALL_BUSES)) -> void:
	_force_muted_at_zero(bus)

	await AudioManager.change_volume(bus, RAISED_VOLUME, true)

	assert_false(AudioManager.get_muted(bus), bus + " is auto-unmuted")
	assert_true(SfxManager.is_any_sfx_playing(), "Manual auto-unmute plays the click")


## Programmatic auto-unmute must clear the AudioServer mute flag on every bus, so the mixer
## never stays muted while AudioManager reports unmuted.
## :rtype: void
func test_programmatic_auto_unmute_clears_hardware_mute(
	bus: String = use_parameters(ALL_BUSES)
) -> void:
	_force_muted_at_zero(bus)

	await AudioManager.change_volume(bus, RAISED_VOLUME)

	assert_false(AudioManager.get_muted(bus))
	assert_false(_hw_muted(bus), bus + " must be audible in AudioServer")
	assert_almost_eq(_hw_linear(bus), RAISED_VOLUME, 0.0001)


## Manual auto-unmute must clear the AudioServer mute flag on every bus, not only Master.
## :rtype: void
func test_manual_auto_unmute_clears_hardware_mute(bus: String = use_parameters(ALL_BUSES)) -> void:
	_force_muted_at_zero(bus)

	await AudioManager.change_volume(bus, RAISED_VOLUME, true)

	assert_false(AudioManager.get_muted(bus))
	assert_false(_hw_muted(bus), bus + " must be audible in AudioServer")
	assert_almost_eq(_hw_linear(bus), RAISED_VOLUME, 0.0001)


## Down then up through change_volume() alone ends audible in the mixer too.
## :rtype: void
func test_programmatic_down_then_up_ends_audible(bus: String = use_parameters(ALL_BUSES)) -> void:
	await AudioManager.change_volume(bus, 0.0)
	await AudioManager.change_volume(bus, RAISED_VOLUME)

	assert_false(AudioManager.get_muted(bus))
	assert_false(_hw_muted(bus), bus + " must not stay muted in AudioServer")
	assert_almost_eq(_hw_linear(bus), RAISED_VOLUME, 0.0001)


## Manual Master unmute clears the AudioServer mute flag right away (ported as-is).
## :rtype: void
func test_manual_master_raise_clears_hardware_mute() -> void:
	var bus: String = AudioConstants.BUS_MASTER
	_force_muted_at_zero(bus)

	await AudioManager.change_volume(bus, RAISED_VOLUME, true)

	assert_false(_hw_muted(bus), "Master is audible in AudioServer")
	assert_almost_eq(_hw_linear(bus), RAISED_VOLUME, 0.0001)


## An ordinary change on an unmuted bus touches neither the mute state nor SFX.
## :rtype: void
func test_audible_change_on_unmuted_bus_is_plain(bus: String = use_parameters(ALL_BUSES)) -> void:
	watch_signals(AudioManager)

	await AudioManager.change_volume(bus, RAISED_VOLUME, true)

	assert_eq(_mute_emits_for(bus), 0, "No mute transition above the threshold")
	assert_false(AudioManager.get_muted(bus))
	assert_false(SfxManager.is_any_sfx_playing(), "No click without a transition")
	assert_signal_emitted_with_parameters(AudioManager, "volume_changed", [bus, RAISED_VOLUME])


# ==========================================
# THRESHOLD CROSSING RULE (Issue #1040)
# ==========================================


## Puts a bus in the "muted by the player at an audible volume" state, in AudioServer too.
## :rtype: void
func _force_muted_at(bus_name: String, volume: float) -> void:
	AudioManager.set_bus_state(bus_name, volume, true)
	AudioManager.apply_volume_to_bus(bus_name, volume, true)


## A player-chosen mute survives an audible volume change, manual or programmatic.
## :rtype: void
func test_player_mute_survives_audible_change(
	params: Array = use_parameters(
		[
			[AudioConstants.BUS_MASTER, false],
			[AudioConstants.BUS_MASTER, true],
			[AudioConstants.BUS_MUSIC, false],
			[AudioConstants.BUS_MUSIC, true],
			[AudioConstants.BUS_SFX, false],
			[AudioConstants.BUS_SFX_WEAPON, true],
			[AudioConstants.BUS_SFX_ROTORS, false],
			[AudioConstants.BUS_SFX_MENU, true],
		]
	)
) -> void:
	var bus: String = params[0]
	var is_manual: bool = params[1]
	_force_muted_at(bus, 0.8)
	watch_signals(AudioManager)

	await AudioManager.change_volume(bus, 0.5, is_manual)

	assert_true(AudioManager.get_muted(bus), bus + " muted at 0.8 stays muted at 0.5")
	assert_eq(AudioManager.get_volume(bus), 0.5, "The new volume is still stored")
	assert_signal_emitted_with_parameters(AudioManager, "volume_changed", [bus, 0.5])
	assert_eq(_mute_emits_for(bus), 0, "No mute transition without a crossing")
	assert_false(SfxManager.is_any_sfx_playing(), "No click without a transition")
	assert_true(_hw_muted(bus), "AudioServer stays muted")
	assert_almost_eq(_hw_linear(bus), 0.5, 0.0001, "The level is ready for a later unmute")


## Raising a player-muted bus to full volume still keeps it muted.
## :rtype: void
func test_player_mute_survives_raise_to_full(bus: String = use_parameters(ALL_BUSES)) -> void:
	_force_muted_at(bus, 0.5)

	await AudioManager.change_volume(bus, 1.0, true)

	assert_true(AudioManager.get_muted(bus))
	assert_true(_hw_muted(bus))


## A bus auto-muted at zero unmutes when raised back above the threshold.
## :rtype: void
func test_auto_muted_bus_unmutes_on_crossing_up(
	is_manual: bool = use_parameters([false, true])
) -> void:
	var bus: String = AudioConstants.BUS_MUSIC
	await AudioManager.change_volume(bus, 0.0, is_manual)
	assert_true(AudioManager.get_muted(bus), "Precondition: auto-muted at zero")
	SfxManager.stop_all_sfx()

	await AudioManager.change_volume(bus, 0.3, is_manual)

	assert_false(AudioManager.get_muted(bus), "Crossing up unmutes")
	assert_false(_hw_muted(bus))
	assert_almost_eq(_hw_linear(bus), 0.3, 0.0001)
	assert_eq(SfxManager.is_any_sfx_playing(), is_manual, "Click only for manual changes")


## Successive near-zero values (not just repeated 0.0) are no-ops once muted.
## :rtype: void
func test_repeated_near_zero_values_are_noop(bus: String = use_parameters(ALL_BUSES)) -> void:
	var near_zero: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD / 2.0
	await AudioManager.change_volume(bus, near_zero, true)
	await wait_seconds(HOLD_WAIT)
	SfxManager.stop_all_sfx()
	watch_signals(AudioManager)

	await AudioManager.change_volume(bus, 0.0, true)
	await AudioManager.change_volume(bus, AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD, true)
	await AudioManager.change_volume(bus, near_zero, true)

	assert_true(AudioManager.get_muted(bus))
	assert_eq(_mute_emits_for(bus), 0, "No mute_toggled while staying at or below the threshold")
	assert_false(SfxManager.is_any_sfx_playing(), "No click while staying at or below")


## Crossing down on a bus the player already muted changes nothing but the volume.
## :rtype: void
func test_crossing_down_on_player_muted_bus_is_silent(bus: String = use_parameters(ALL_BUSES)) -> void:
	_force_muted_at(bus, 0.8)
	watch_signals(AudioManager)

	await AudioManager.change_volume(bus, 0.0, true)

	assert_true(AudioManager.get_muted(bus))
	assert_eq(_mute_emits_for(bus), 0, "Already muted: no transition")
	assert_false(SfxManager.is_any_sfx_playing(), "Already muted: no click")
	assert_almost_eq(_hw_linear(bus), 0.0, 0.0001, "No Master hold without a transition")


## Documented corner case: a button mute at 0.8, then 0 and back up, is unmuted.
## At zero an explicit mute and an auto-mute look the same, and the rule keeps no extra state.
## :rtype: void
func test_corner_case_player_mute_through_zero_unmutes(
	bus: String = use_parameters(ALL_BUSES)
) -> void:
	_force_muted_at(bus, 0.8)

	await AudioManager.change_volume(bus, 0.0)
	await AudioManager.change_volume(bus, 0.3)

	assert_false(AudioManager.get_muted(bus), "Accepted: crossing up from zero unmutes")
	assert_false(_hw_muted(bus))


## A bus left unmuted at zero by the raw setters is not muted by a near-zero update:
## the rule needs a crossing down, and the bus never was above the threshold.
## :rtype: void
func test_unmuted_at_zero_stays_unmuted_below_threshold(
	bus: String = use_parameters(ALL_BUSES)
) -> void:
	AudioManager.set_bus_state(bus, 0.0, false)
	watch_signals(AudioManager)

	await AudioManager.change_volume(bus, AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD / 2.0, true)

	assert_false(AudioManager.get_muted(bus), "No crossing down, no auto-mute")
	assert_eq(_mute_emits_for(bus), 0)
	assert_false(SfxManager.is_any_sfx_playing())


# ==========================================
# MASTER FEEDBACK HOLD
# ==========================================


## Manual Master auto-mute holds an audible level, then flattens it after the delay.
## :rtype: void
func test_manual_master_hold_then_flatten() -> void:
	var bus: String = AudioConstants.BUS_MASTER

	AudioManager.change_volume(bus, 0.0, true)
	assert_almost_eq(
		_hw_linear(bus),
		AudioConstants.FEEDBACK_HOLD_VOLUME_LINEAR,
		0.0001,
		"Master is held audible while the click plays"
	)

	await wait_seconds(HOLD_WAIT)
	assert_almost_eq(_hw_linear(bus), 0.0, 0.0001, "Master is flattened after the hold")
	assert_true(AudioManager.get_muted(bus))


## Programmatic Master auto-mute never holds.
## :rtype: void
func test_programmatic_master_has_no_hold() -> void:
	var bus: String = AudioConstants.BUS_MASTER
	AudioManager.change_volume(bus, 0.0)
	assert_almost_eq(_hw_linear(bus), 0.0, 0.0001, "No hold for programmatic changes")


## Only Master is held; other buses are not (hold for SFX/SFX_Menu is #1047).
## :rtype: void
func test_non_master_manual_has_no_hold() -> void:
	var bus: String = AudioConstants.BUS_MUSIC
	AudioManager.change_volume(bus, 0.0, true)
	assert_almost_eq(_hw_linear(bus), 0.0, 0.0001, "Only Master gets the feedback hold")


## Raising Master during the hold wins: the stale timer must not flatten the bus.
## :rtype: void
func test_master_raise_during_hold_wins() -> void:
	var bus: String = AudioConstants.BUS_MASTER

	AudioManager.change_volume(bus, 0.0, true)
	await AudioManager.change_volume(bus, RAISED_VOLUME, true)
	await wait_seconds(HOLD_WAIT)

	assert_false(AudioManager.get_muted(bus), "Master ends unmuted")
	assert_false(_hw_muted(bus), "Master is audible in AudioServer")
	assert_almost_eq(_hw_linear(bus), RAISED_VOLUME, 0.0001, "Stale hold did not flatten Master")


## A mute-button unmute during the hold also wins over the stale timer.
## :rtype: void
func test_master_unmute_during_hold_wins() -> void:
	var bus: String = AudioConstants.BUS_MASTER

	AudioManager.change_volume(bus, 0.0, true)
	AudioManager.set_volume(bus, RAISED_VOLUME)
	AudioManager.set_muted(bus, false)
	AudioManager.apply_volume_to_bus(bus, RAISED_VOLUME, false)
	await wait_seconds(HOLD_WAIT)

	assert_almost_eq(_hw_linear(bus), RAISED_VOLUME, 0.0001, "Stale hold did not flatten Master")


# ==========================================
# RAW SETTERS BYPASS THE RULE
# ==========================================


## set_volume() stores zero without muting.
## :rtype: void
func test_set_volume_never_auto_mutes(bus: String = use_parameters(ALL_BUSES)) -> void:
	AudioManager.set_volume(bus, 0.0)
	assert_false(AudioManager.get_muted(bus), "Raw set_volume must not apply the rule")


## set_bus_state() keeps {audible, muted} exactly, with a single mute emission.
## :rtype: void
func test_set_bus_state_keeps_muted_audible_bus(bus: String = use_parameters(ALL_BUSES)) -> void:
	watch_signals(AudioManager)

	AudioManager.set_bus_state(bus, 0.5, true)

	assert_true(AudioManager.get_muted(bus), "Muted flag kept")
	assert_eq(AudioManager.get_volume(bus), 0.5)
	assert_eq(_mute_emits_for(bus), 1, "No spurious unmute/re-mute")
	assert_signal_emitted_with_parameters(AudioManager, "mute_toggled", [bus, true])


## set_bus_state() at zero does not force a mute.
## :rtype: void
func test_set_bus_state_zero_unmuted_not_forced(bus: String = use_parameters(ALL_BUSES)) -> void:
	AudioManager.set_bus_state(bus, 0.0, false)
	assert_false(AudioManager.get_muted(bus), "Raw set_bus_state must not apply the rule")


## Loading {0.5, muted} keeps the bus muted without an unmute emission.
## :rtype: void
func test_config_load_keeps_muted_audible_bus() -> void:
	var cfg := ConfigFile.new()
	for bus: String in AudioConstants.BUS_CONFIG.keys():
		var data: Dictionary = AudioConstants.BUS_CONFIG[bus]
		cfg.set_value("audio", data["volume_var"], 0.5)
		cfg.set_value("audio", data["muted_var"], true)
	watch_signals(AudioManager)

	AudioManager.apply_volumes_from_config(cfg)

	for bus: String in ALL_BUSES:
		assert_true(AudioManager.get_muted(bus), bus + " stays muted")
		assert_eq(AudioManager.get_volume(bus), 0.5)
		assert_eq(_mute_emits_for(bus), 1, bus + ": single mute emission, no unmute/re-mute")
	assert_false(SfxManager.is_any_sfx_playing(), "Loading never plays SFX")


## Reset restores defaults verbatim and never plays SFX.
## :rtype: void
func test_reset_volumes_bypasses_rule() -> void:
	for bus: String in ALL_BUSES:
		_force_muted_at_zero(bus)

	AudioManager.reset_volumes()

	for bus: String in ALL_BUSES:
		var data: Dictionary = AudioConstants.BUS_CONFIG[bus]
		assert_eq(AudioManager.get_volume(bus), data["default_volume"])
		assert_eq(AudioManager.get_muted(bus), data["default_muted"])
	assert_false(SfxManager.is_any_sfx_playing(), "Reset never plays SFX")


# ==========================================
# GUARDS
# ==========================================


## Unknown buses are rejected without touching state or playing SFX.
## :rtype: void
func test_unknown_bus_is_rejected() -> void:
	watch_signals(AudioManager)

	await AudioManager.change_volume("NotABus", 0.0, true)

	assert_signal_not_emitted(AudioManager, "volume_changed")
	assert_signal_not_emitted(AudioManager, "mute_toggled")
	assert_false(SfxManager.is_any_sfx_playing())


# ==========================================
# BOUNDARIES AND CALLER CONTRACTS
# ==========================================


## A positive value below the threshold mutes without replacing the requested volume.
## :rtype: void
func test_positive_near_zero_is_stored_and_muted(bus: String = use_parameters(ALL_BUSES)) -> void:
	var volume: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD / 2.0
	watch_signals(AudioManager)

	await AudioManager.change_volume(bus, volume)

	assert_eq(AudioManager.get_volume(bus), volume, "Keep the caller's near-zero value")
	assert_almost_eq(_hw_linear(bus), volume, 0.000001)
	assert_true(AudioManager.get_muted(bus))
	assert_eq(_mute_emits_for(bus), 1)
	assert_signal_emitted_with_parameters(AudioManager, "mute_toggled", [bus, true])
	assert_false(SfxManager.is_any_sfx_playing())


## The smallest tested step above the boundary must not mute an audible bus.
## :rtype: void
func test_just_above_threshold_stays_unmuted(bus: String = use_parameters(ALL_BUSES)) -> void:
	var volume: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD + 0.000001
	watch_signals(AudioManager)

	await AudioManager.change_volume(bus, volume, true)

	assert_false(AudioManager.get_muted(bus))
	assert_eq(AudioManager.get_volume(bus), volume)
	assert_almost_eq(_hw_linear(bus), volume, 0.000001)
	assert_eq(_mute_emits_for(bus), 0, "No transition just above the boundary")
	assert_false(SfxManager.is_any_sfx_playing())


## A bus muted at an audible volume stays muted just above the boundary: no crossing (#1040).
## :rtype: void
func test_just_above_threshold_keeps_audible_muted_bus_muted(
	bus: String = use_parameters(ALL_BUSES)
) -> void:
	AudioManager.set_bus_state(bus, START_VOLUME, true)
	AudioManager.apply_volume_to_bus(bus, START_VOLUME, true)
	var volume: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD + 0.000001
	watch_signals(AudioManager)

	await AudioManager.change_volume(bus, volume)

	assert_true(AudioManager.get_muted(bus), "The rule is edge-triggered: no crossing, no unmute")
	assert_eq(AudioManager.get_volume(bus), volume)
	assert_eq(_mute_emits_for(bus), 0)
	assert_false(SfxManager.is_any_sfx_playing())


## A down/up sequence emits exactly one transition each way and leaves other buses alone.
## :rtype: void
func test_volume_round_trip_is_isolated_to_target_bus(
	bus: String = use_parameters(ALL_BUSES)
) -> void:
	watch_signals(AudioManager)

	await AudioManager.change_volume(bus, 0.0)
	await AudioManager.change_volume(bus, 1.0)

	assert_eq(AudioManager.get_volume(bus), 1.0, "Full volume is accepted")
	assert_false(AudioManager.get_muted(bus))
	assert_eq(get_signal_emit_count(AudioManager, "volume_changed"), 2)
	assert_eq(get_signal_emit_count(AudioManager, "mute_toggled"), 2)
	assert_eq(get_signal_parameters(AudioManager, "mute_toggled", 0), [bus, true])
	assert_eq(get_signal_parameters(AudioManager, "mute_toggled", 1), [bus, false])
	for other: String in ALL_BUSES:
		if other == bus:
			continue
		assert_eq(AudioManager.get_bus_state(other), {"volume": START_VOLUME, "muted": false})
		assert_almost_eq(_hw_linear(other), START_VOLUME, 0.0001)
		assert_false(_hw_muted(other), other + " hardware mute must remain unchanged")


## Persistence belongs to callers: transitions neither create nor rewrite the config.
## :rtype: void
func test_change_volume_never_saves(is_manual: bool = use_parameters([false, true])) -> void:
	var bus: String = AudioConstants.BUS_MASTER
	await AudioManager.change_volume(bus, 0.0, is_manual)
	assert_false(FileAccess.file_exists(TEST_CONFIG_PATH), "No implicit first save")

	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", START_VOLUME)
	cfg.set_value("sentinel", "keep", "unchanged")
	assert_eq(cfg.save_encrypted_pass(TEST_CONFIG_PATH, Globals.ensure_encryption_key()), OK)
	var saved_bytes: PackedByteArray = FileAccess.get_file_as_bytes(TEST_CONFIG_PATH)
	var history: Dictionary = AudioManager._last_audible_volume.duplicate()

	await AudioManager.change_volume(bus, RAISED_VOLUME, is_manual)
	await AudioManager.change_volume(bus, 0.0, is_manual)

	assert_eq(FileAccess.get_file_as_bytes(TEST_CONFIG_PATH), saved_bytes, "No implicit rewrite")
	assert_eq(AudioManager._last_audible_volume, history, "No implicit audible-volume commit")


## The raw setter emits volume only and does not change the hardware or muted state.
## :rtype: void
func test_raw_set_volume_has_no_hardware_or_unmute_side_effects(
	bus: String = use_parameters(ALL_BUSES)
) -> void:
	_force_muted_at_zero(bus)
	watch_signals(AudioManager)

	AudioManager.set_volume(bus, RAISED_VOLUME)

	assert_true(AudioManager.get_muted(bus))
	assert_true(_hw_muted(bus))
	assert_almost_eq(_hw_linear(bus), 0.0, 0.0001)
	assert_signal_emitted_with_parameters(AudioManager, "volume_changed", [bus, RAISED_VOLUME])
	assert_signal_not_emitted(AudioManager, "mute_toggled")
	assert_false(SfxManager.is_any_sfx_playing())
	assert_false(FileAccess.file_exists(TEST_CONFIG_PATH))


## Updating a different bus must not cancel the pending Master cutoff.
## :rtype: void
func test_other_bus_change_does_not_cancel_master_hold() -> void:
	AudioManager.change_volume(AudioConstants.BUS_MASTER, 0.0, true)
	await AudioManager.change_volume(AudioConstants.BUS_MUSIC, RAISED_VOLUME, true)
	await wait_seconds(HOLD_WAIT)

	assert_true(AudioManager.get_muted(AudioConstants.BUS_MASTER))
	assert_almost_eq(_hw_linear(AudioConstants.BUS_MASTER), 0.0, 0.0001)
	assert_eq(AudioManager.get_volume(AudioConstants.BUS_MUSIC), RAISED_VOLUME)
	assert_false(AudioManager.get_muted(AudioConstants.BUS_MUSIC))


## Cleanup must invalidate an outstanding hold even when Master is still logically muted.
## :rtype: void
func test_cleanup_invalidates_pending_master_hold() -> void:
	var bus: String = AudioConstants.BUS_MASTER
	AudioManager.change_volume(bus, 0.0, true)
	AudioManager.cleanup_for_test()
	AudioServer.set_bus_volume_db(_bus_idx(bus), linear_to_db(RAISED_VOLUME))

	await wait_seconds(HOLD_WAIT)

	assert_true(AudioManager.get_muted(bus), "The mute guard alone cannot cancel this timer")
	assert_almost_eq(_hw_linear(bus), RAISED_VOLUME, 0.0001, "Cleanup orphaned the stale hold")
	assert_false(SfxManager.is_any_sfx_playing(), "Audio cleanup delegates to SfxManager")


## An unattached manager takes the immediate Master cutoff path without needing a timer.
## :rtype: void
func test_manual_master_mute_outside_tree_flattens_immediately() -> void:
	var manager: Node = autofree(load("res://scripts/managers/audio_manager.gd").new())
	manager.set_bus_state(AudioConstants.BUS_MASTER, START_VOLUME, false)
	assert_false(manager.is_inside_tree())

	await manager.change_volume(AudioConstants.BUS_MASTER, 0.0, true)

	assert_true(manager.get_muted(AudioConstants.BUS_MASTER))
	assert_eq(manager.get_volume(AudioConstants.BUS_MASTER), 0.0)
	assert_almost_eq(_hw_linear(AudioConstants.BUS_MASTER), 0.0, 0.0001)
	assert_true(SfxManager.is_any_sfx_playing(), "The confirmation still routes to SfxManager")
