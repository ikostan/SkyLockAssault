## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_audio_manager_auto_mute.gd
##
## TEST SUITE: the near-zero auto-mute contract, pinned at manager level (epic #725).
## Renamed from test_audio_manager_change_volume.gd (Issue #1044): this is the suite T7 asks
## for, so it is extended here rather than duplicated in a second file.
## AudioManager.change_volume() owns the rule (Issue #1039). It runs from the autoload with no
## Audio Settings menu in the tree, and callers state their intent through
## is_manual_interaction instead of slider focus. The rule fires only on
## AUTO_MUTE_VOLUME_THRESHOLD crossings (Issue #1040), so mutes the player chose at an audible
## volume stay put. The raw setters (set_volume, set_bus_state, config load, reset) must never
## apply the rule. Once an auto-mute settles, AudioServer is re-synced from the manager's
## current state, so the mixer mute flag always matches and stale hold timers need no token
## (Issue #1041). A pending Master hold also owns the mixer against at-or-below-threshold
## follow-ups and earlier overlapping timers (Issue #1075).
## Every behavior is parameterized over the six buses.

extends "res://addons/gut/test.gd"

const TEST_CONFIG_PATH: String = "user://test_audio_manager_auto_mute.cfg"
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
## Buses off the click's path (SFX_Menu -> SFX -> Master): muting them never silences it.
const OFF_PATH_BUSES: Array = [
	AudioConstants.BUS_MUSIC,
	AudioConstants.BUS_SFX_WEAPON,
	AudioConstants.BUS_SFX_ROTORS,
]
## Path buses other than Master; Master's hold is covered in MASTER FEEDBACK HOLD.
const HELD_SFX_BUSES: Array = [AudioConstants.BUS_SFX, AudioConstants.BUS_SFX_MENU]

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
# TRANSITION MATRIX: BUS x CALLER x DIRECTION (Issue #1044)
# ==========================================


## Builds [bus, is_manual, crossing_down] for every bus, caller and direction.
## :rtype: Array
static func _transition_matrix() -> Array:
	var rows: Array = []
	for bus: String in ALL_BUSES:
		for is_manual: bool in [false, true]:
			for crossing_down: bool in [true, false]:
				rows.append([bus, is_manual, crossing_down])
	return rows


## Each crossing flips the mute exactly once, syncs the mixer, and clicks only when manual.
## :rtype: void
func test_transition_matrix(params: Array = use_parameters(_transition_matrix())) -> void:
	var bus: String = params[0]
	var is_manual: bool = params[1]
	var crossing_down: bool = params[2]
	if not crossing_down:
		_force_muted_at_zero(bus)
	var target: float = 0.0 if crossing_down else RAISED_VOLUME
	watch_signals(AudioManager)

	# Not awaited: read the click right away, before a Master hold can outlast it.
	AudioManager.change_volume(bus, target, is_manual)
	var click_playing: bool = SfxManager.is_any_sfx_playing()
	await wait_seconds(HOLD_WAIT)  # Let any Master hold settle before checking the mixer

	assert_eq(AudioManager.get_muted(bus), crossing_down, bus + ": mute follows the crossing")
	assert_eq(_mute_emits_for(bus), 1, bus + ": exactly one mute transition")
	assert_signal_emitted_with_parameters(AudioManager, "mute_toggled", [bus, crossing_down])
	assert_eq(_hw_muted(bus), AudioManager.get_muted(bus), bus + ": mixer matches the manager")
	assert_almost_eq(_hw_linear(bus), target, 0.0001, bus + ": mixer holds the new volume")
	assert_eq(click_playing, is_manual, bus + ": click only for manual changes")


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


## An already muted bus at zero is a no-op for every caller: no mute signal, no click.
## :rtype: void
func test_repeated_zero_is_noop(params: Array = use_parameters(_bus_caller_pairs())) -> void:
	var bus: String = params[0]
	var is_manual: bool = params[1]
	await AudioManager.change_volume(bus, 0.0, is_manual)
	await wait_seconds(HOLD_WAIT)
	SfxManager.stop_all_sfx()
	watch_signals(AudioManager)

	await AudioManager.change_volume(bus, 0.0, is_manual)

	assert_eq(_mute_emits_for(bus), 0, "No mute_toggled on a repeated near-zero update")
	assert_false(SfxManager.is_any_sfx_playing(), "No click on a repeated near-zero update")
	assert_true(_hw_muted(bus), "The mixer stays muted")


## Builds [bus, is_manual] for every bus and caller.
## :rtype: Array
static func _bus_caller_pairs() -> Array:
	var rows: Array = []
	for bus: String in ALL_BUSES:
		for is_manual: bool in [false, true]:
			rows.append([bus, is_manual])
	return rows


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
	assert_true(_hw_muted(bus), "The re-sync sets the AudioServer mute flag after the hold")


## Programmatic Master auto-mute never holds.
## :rtype: void
func test_programmatic_master_has_no_hold() -> void:
	var bus: String = AudioConstants.BUS_MASTER
	AudioManager.change_volume(bus, 0.0)
	assert_almost_eq(_hw_linear(bus), 0.0, 0.0001, "No hold for programmatic changes")


## Music is off the click's feedback path, so it is never held (path buses: Issue #1047).
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


## load_volumes() from an encrypted file applies saved states verbatim: an audible muted bus
## stays muted in the manager and the mixer, with no SFX (the near-zero load guard aside).
## :rtype: void
func test_load_volumes_from_disk_bypasses_rule() -> void:
	var cfg := ConfigFile.new()
	for bus: String in AudioConstants.BUS_CONFIG.keys():
		var data: Dictionary = AudioConstants.BUS_CONFIG[bus]
		cfg.set_value("audio", data["volume_var"], 0.5)
		cfg.set_value("audio", data["muted_var"], true)
	assert_eq(cfg.save_encrypted_pass(TEST_CONFIG_PATH, Globals.ensure_encryption_key()), OK)

	AudioManager.load_volumes(TEST_CONFIG_PATH)

	for bus: String in ALL_BUSES:
		assert_true(AudioManager.get_muted(bus), bus + " stays muted after load")
		assert_eq(AudioManager.get_volume(bus), 0.5)
		assert_true(_hw_muted(bus), bus + " is muted in the mixer after load")
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


## A stale hold timer re-applies whatever state the manager holds when it fires, even when
## that state changed through the raw setters with no AudioServer write (Issue #1041).
## :rtype: void
func test_stale_master_hold_reapplies_current_state() -> void:
	var bus: String = AudioConstants.BUS_MASTER
	AudioManager.change_volume(bus, 0.0, true)
	AudioManager.set_bus_state(bus, RAISED_VOLUME, false)

	await wait_seconds(HOLD_WAIT)

	assert_false(_hw_muted(bus), "The late re-sync applies the current unmuted state")
	assert_almost_eq(_hw_linear(bus), RAISED_VOLUME, 0.0001, "...at the current volume")


## Cleanup still silences SFX after the token was removed.
## :rtype: void
func test_cleanup_stops_sfx() -> void:
	AudioManager.change_volume(AudioConstants.BUS_MUSIC, 0.0, true)
	assert_true(SfxManager.is_any_sfx_playing(), "Precondition: the click is playing")

	AudioManager.cleanup_for_test()

	assert_false(SfxManager.is_any_sfx_playing(), "Audio cleanup delegates to SfxManager")


# ==========================================
# AUDIOSERVER RE-SYNC (Issue #1041)
# ==========================================


## After any auto-mute settles, the AudioServer mute flag matches AudioManager.
## :rtype: void
func test_auto_mute_syncs_hardware_mute(
	params: Array = use_parameters(
		[
			[AudioConstants.BUS_MASTER, false],
			[AudioConstants.BUS_MASTER, true],
			[AudioConstants.BUS_MUSIC, false],
			[AudioConstants.BUS_MUSIC, true],
			[AudioConstants.BUS_SFX, false],
			[AudioConstants.BUS_SFX, true],
			[AudioConstants.BUS_SFX_WEAPON, false],
			[AudioConstants.BUS_SFX_WEAPON, true],
			[AudioConstants.BUS_SFX_ROTORS, false],
			[AudioConstants.BUS_SFX_ROTORS, true],
			[AudioConstants.BUS_SFX_MENU, false],
			[AudioConstants.BUS_SFX_MENU, true],
		]
	)
) -> void:
	var bus: String = params[0]
	var is_manual: bool = params[1]

	await AudioManager.change_volume(bus, 0.0, is_manual)

	assert_true(AudioManager.get_muted(bus))
	assert_eq(_hw_muted(bus), AudioManager.get_muted(bus), bus + ": mixer matches the manager")
	assert_almost_eq(_hw_linear(bus), 0.0, 0.0001)


## A positive near-zero auto-mute is silenced by the mute flag, not by a forced 0.0 write.
## :rtype: void
func test_near_zero_auto_mute_keeps_stored_volume_in_mixer(
	is_manual: bool = use_parameters([false, true])
) -> void:
	var bus: String = AudioConstants.BUS_MASTER
	var volume: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD / 2.0

	await AudioManager.change_volume(bus, volume, is_manual)

	assert_true(_hw_muted(bus), "Silenced by the AudioServer mute flag")
	assert_almost_eq(_hw_linear(bus), volume, 0.000001, "Mixer level mirrors the stored volume")


## Down-crossing then up-crossing within MUTE_HARDWARE_DELAY ends unmuted at the up volume.
## :rtype: void
func test_down_up_within_delay_ends_unmuted(bus: String = use_parameters(ALL_BUSES)) -> void:
	AudioManager.change_volume(bus, 0.0, true)
	await AudioManager.change_volume(bus, RAISED_VOLUME, true)

	await wait_seconds(HOLD_WAIT)

	assert_false(AudioManager.get_muted(bus))
	assert_false(_hw_muted(bus), bus + " is audible in AudioServer after any hold settles")
	assert_almost_eq(_hw_linear(bus), RAISED_VOLUME, 0.0001)


## The generation token is gone from the manager and the menu. The click-window counter
## (Issues #1075, #1047) is not a token (it only decides when the mixer is written), and an
## idle manager has no window open: every click from earlier tests has finished.
## :rtype: void
func test_no_hold_token_remains() -> void:
	assert_false("_master_hold_token" in AudioManager, "No token in AudioManager")
	var menu_props: Array[String] = []
	var menu_script: Script = load("res://scripts/ui/menus/audio_settings.gd")
	for prop: Dictionary in menu_script.get_script_property_list():
		menu_props.append(prop["name"])
	assert_false(menu_props.has("_master_zero_token"), "No token in the Audio Settings menu")
	assert_eq(AudioManager._clicks_in_flight, 0, "No click window left open at rest")


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


## Starting exactly at the threshold must count as the near-zero side of an upward crossing.
## :rtype: void
func test_regression_exact_threshold_raise_unmutes(
	params: Array = use_parameters(_bus_caller_pairs())
) -> void:
	var bus: String = params[0]
	var is_manual: bool = params[1]
	var raised: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD + 0.000001
	_force_muted_at(bus, AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD)
	watch_signals(AudioManager)

	await AudioManager.change_volume(bus, raised, is_manual)

	assert_false(AudioManager.get_muted(bus), "An upward crossing includes old volume == threshold")
	assert_false(_hw_muted(bus), "The mixer must unmute immediately")
	assert_almost_eq(_hw_linear(bus), raised, 0.0000001)
	assert_eq(get_signal_emit_count(AudioManager, "volume_changed"), 1)
	assert_signal_emitted_with_parameters(AudioManager, "volume_changed", [bus, raised])
	assert_eq(_mute_emits_for(bus), 1)
	assert_signal_emitted_with_parameters(AudioManager, "mute_toggled", [bus, false])
	assert_eq(SfxManager.is_any_sfx_playing(), is_manual)


## An unmuted threshold baseline stays unmuted until it goes above and crosses down again.
## :rtype: void
func test_regression_exact_threshold_requires_fresh_down_crossing(
	bus: String = use_parameters(ALL_BUSES)
) -> void:
	var threshold: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD
	AudioManager.set_bus_state(bus, threshold, false)
	AudioManager.apply_volume_to_bus(bus, threshold, false)
	watch_signals(AudioManager)

	for volume: float in [threshold, 0.0, threshold / 2.0, threshold + 0.000001]:
		await AudioManager.change_volume(bus, volume, true)
		assert_false(AudioManager.get_muted(bus), "No downward crossing to " + str(volume))
		assert_false(_hw_muted(bus))
		assert_eq(_mute_emits_for(bus), 0)
		assert_false(SfxManager.is_any_sfx_playing(), "No click without a mute transition")

	await AudioManager.change_volume(bus, threshold)

	assert_true(AudioManager.get_muted(bus), "The fresh downward crossing must auto-mute")
	assert_true(_hw_muted(bus))
	assert_almost_eq(_hw_linear(bus), threshold, 0.0000001)
	assert_eq(_mute_emits_for(bus), 1)
	assert_signal_emitted_with_parameters(AudioManager, "mute_toggled", [bus, true])


## A hold must preserve a newer audible volume even if the latest state is still muted.
## :rtype: void
func test_regression_master_hold_reapplies_latest_muted_volume() -> void:
	var bus: String = AudioConstants.BUS_MASTER
	AudioManager.change_volume(bus, 0.0, true)
	AudioManager.set_bus_state(bus, RAISED_VOLUME, true)
	SfxManager.stop_all_sfx()
	watch_signals(AudioManager)

	await wait_seconds(HOLD_WAIT)

	assert_eq(AudioManager.get_volume(bus), RAISED_VOLUME)
	assert_true(AudioManager.get_muted(bus))
	assert_true(_hw_muted(bus), "The hold applies the latest mute flag")
	assert_almost_eq(
		_hw_linear(bus), RAISED_VOLUME, 0.0001, "Do not replace muted volume with zero"
	)
	assert_signal_not_emitted(AudioManager, "volume_changed")
	assert_signal_not_emitted(AudioManager, "mute_toggled")
	assert_false(SfxManager.is_any_sfx_playing(), "A delayed re-sync must not replay feedback")


## Several pending holds must all re-read the final state rather than restore their own.
## :rtype: void
func test_regression_overlapping_master_holds_preserve_final_state(
	final_muted: bool = use_parameters([false, true])
) -> void:
	var bus: String = AudioConstants.BUS_MASTER
	AudioManager.change_volume(bus, 0.0, true)
	await AudioManager.change_volume(bus, RAISED_VOLUME)
	AudioManager.change_volume(bus, 0.0, true)
	AudioManager.set_bus_state(bus, START_VOLUME, final_muted)
	watch_signals(AudioManager)

	await wait_seconds(HOLD_WAIT)

	assert_eq(AudioManager.get_bus_state(bus), {"volume": START_VOLUME, "muted": final_muted})
	assert_eq(_hw_muted(bus), final_muted, "Both pending timers must apply the final mute flag")
	assert_almost_eq(_hw_linear(bus), START_VOLUME, 0.0001)
	assert_signal_not_emitted(AudioManager, "volume_changed")
	assert_signal_not_emitted(AudioManager, "mute_toggled")


# ==========================================
# NEAR-ZERO FOLLOW-UPS DURING THE MASTER HOLD (Issue #1075)
# ==========================================


## Builds [value, is_manual] for at-or-below-threshold follow-ups from both callers.
## :rtype: Array
static func _near_zero_follow_ups() -> Array:
	var rows: Array = []
	var threshold: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD
	for value: float in [0.0, threshold / 2.0, threshold]:
		for is_manual: bool in [false, true]:
			rows.append([value, is_manual])
	return rows


## An at-or-below follow-up during the hold is not a new crossing, but it must not hard-mute
## Master under the click either: Master stays at the hold level, then is muted at the
## follow-up's volume once MUTE_HARDWARE_DELAY ends.
## :rtype: void
func test_regression_near_zero_follow_up_keeps_master_hold(
	params: Array = use_parameters(_near_zero_follow_ups())
) -> void:
	var bus: String = AudioConstants.BUS_MASTER
	var value: float = params[0]
	var is_manual: bool = params[1]
	AudioManager.change_volume(bus, 0.0, true)
	watch_signals(AudioManager)

	await AudioManager.change_volume(bus, value, is_manual)

	assert_false(_hw_muted(bus), "The follow-up must not hard-mute Master during the hold")
	assert_almost_eq(
		_hw_linear(bus),
		AudioConstants.FEEDBACK_HOLD_VOLUME_LINEAR,
		0.0001,
		"Master stays at the hold level"
	)
	assert_true(SfxManager.is_any_sfx_playing(), "The confirmation click is still playing")
	assert_eq(_mute_emits_for(bus), 0, "Already muted: the follow-up is not a transition")

	await wait_seconds(HOLD_WAIT)

	assert_eq(AudioManager.get_volume(bus), value)
	assert_true(AudioManager.get_muted(bus))
	assert_true(_hw_muted(bus), "Master is muted once the hold ends")
	assert_almost_eq(_hw_linear(bus), value, 0.000001, "The hold re-syncs to the newest volume")


## A programmatic crossing down during a pending hold (after an audible raise) starts no hold
## of its own and must not settle early: Master goes back to the hold level, and the pending
## hold mutes it when it ends.
## :rtype: void
func test_regression_crossing_down_during_hold_waits_for_master_hold(
	is_manual_raise: bool = use_parameters([false, true])
) -> void:
	var bus: String = AudioConstants.BUS_MASTER
	AudioManager.change_volume(bus, 0.0, true)
	await AudioManager.change_volume(bus, RAISED_VOLUME, is_manual_raise)
	assert_false(_hw_muted(bus), "Precondition: the raise applied immediately")

	await AudioManager.change_volume(bus, 0.0)

	assert_true(AudioManager.get_muted(bus), "The crossing still auto-mutes the manager state")
	assert_false(_hw_muted(bus), "The pending hold owns the mixer until it ends")
	assert_almost_eq(
		_hw_linear(bus),
		AudioConstants.FEEDBACK_HOLD_VOLUME_LINEAR,
		0.0001,
		"Master goes back to the hold level, not to the raised volume"
	)

	await wait_seconds(HOLD_WAIT)

	assert_true(_hw_muted(bus), "The pending hold mutes Master when it ends")
	assert_almost_eq(_hw_linear(bus), 0.0, 0.0001)


## Above-threshold updates during the hold still apply immediately (TC-AM-016 unchanged),
## whether they cross up or stay audible.
## :rtype: void
func test_audible_updates_during_master_hold_apply_immediately(
	is_manual: bool = use_parameters([false, true])
) -> void:
	var bus: String = AudioConstants.BUS_MASTER
	AudioManager.change_volume(bus, 0.0, true)

	await AudioManager.change_volume(bus, RAISED_VOLUME, is_manual)

	assert_false(_hw_muted(bus), "Crossing up unmutes the mixer right away")
	assert_almost_eq(_hw_linear(bus), RAISED_VOLUME, 0.0001, "...at the raised volume")

	await AudioManager.change_volume(bus, START_VOLUME, is_manual)

	assert_false(_hw_muted(bus))
	assert_almost_eq(_hw_linear(bus), START_VOLUME, 0.0001, "Audible updates apply right away")

	await wait_seconds(HOLD_WAIT)

	assert_false(AudioManager.get_muted(bus))
	assert_false(_hw_muted(bus), "The stale hold re-applies the newest unmuted state")
	assert_almost_eq(_hw_linear(bus), START_VOLUME, 0.0001)


## While a newer click is still streaming, the first hold's timer must neither mute nor unmute
## Master: only the last click window re-syncs the mixer. Deterministic on purpose: two real
## 0.15 s timers started apart can fire in the same frame after a frame hitch, so the newer
## click's window is held open by hand and closed with _end_click_window().
## :rtype: void
func test_regression_first_of_overlapping_holds_leaves_second_alone() -> void:
	var bus: String = AudioConstants.BUS_MASTER
	AudioManager.change_volume(bus, 0.0, true)
	assert_eq(AudioManager._clicks_in_flight, 1, "Click 1's window is open")
	# Click 2 is still streaming when click 1's window closes.
	AudioManager._clicks_in_flight += 1

	await wait_seconds(HOLD_WAIT)

	assert_eq(AudioManager._clicks_in_flight, 1, "Only click 1's window has closed")
	assert_true(AudioManager.get_muted(bus), "The manager state is muted throughout")
	assert_false(_hw_muted(bus), "Hold 1 must not mute Master under the second click")
	assert_almost_eq(
		_hw_linear(bus),
		AudioConstants.FEEDBACK_HOLD_VOLUME_LINEAR,
		0.0001,
		"Master is still at the hold level"
	)

	AudioManager._end_click_window()

	assert_eq(AudioManager._clicks_in_flight, 0, "Closing click 2's window drains it")
	assert_true(_hw_muted(bus), "The last window re-syncs Master to muted")
	assert_almost_eq(_hw_linear(bus), 0.0, 0.0001)


## Two real overlapping manual holds (down, up, down within the delay) both settle: Master
## ends muted in the mixer and no click window is left open. Each of the three manual
## transitions plays its own click, so three windows are open at once.
## :rtype: void
func test_overlapping_real_master_holds_settle_muted_and_drain() -> void:
	var bus: String = AudioConstants.BUS_MASTER
	AudioManager.change_volume(bus, 0.0, true)
	await AudioManager.change_volume(bus, RAISED_VOLUME, true)
	AudioManager.change_volume(bus, 0.0, true)
	assert_eq(AudioManager._clicks_in_flight, 3, "Three click windows are open")
	assert_false(_hw_muted(bus), "Master is held audible for the second click")

	await wait_seconds(HOLD_WAIT)

	assert_true(AudioManager.get_muted(bus))
	assert_true(_hw_muted(bus), "The last hold mutes Master when it ends")
	assert_almost_eq(_hw_linear(bus), 0.0, 0.0001)
	assert_eq(AudioManager._clicks_in_flight, 0, "No click window left open")


# ==========================================
# FEEDBACK PATH HOLD: SFX AND SFX_MENU (Issue #1047)
# ==========================================


## True when every bus from SFX_Menu up to Master is unmuted and above the threshold in
## AudioServer, so a click on SFX_Menu can actually be heard (a bus check, not player.playing).
## :rtype: bool
func _click_chain_audible() -> bool:
	for bus: String in [
		AudioConstants.BUS_SFX_MENU, AudioConstants.BUS_SFX, AudioConstants.BUS_MASTER
	]:
		if _hw_muted(bus) or _hw_linear(bus) <= AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD:
			return false
	return true


## The path is walked from SFX_Menu through AudioServer sends: today SFX_Menu, SFX and Master.
## :rtype: void
func test_feedback_path_membership(
	params: Array = use_parameters(
		[
			[AudioConstants.BUS_MASTER, true],
			[AudioConstants.BUS_SFX, true],
			[AudioConstants.BUS_SFX_MENU, true],
			[AudioConstants.BUS_MUSIC, false],
			[AudioConstants.BUS_SFX_WEAPON, false],
			[AudioConstants.BUS_SFX_ROTORS, false],
			["NotABus", false],
		]
	)
) -> void:
	assert_eq(AudioManager._is_in_feedback_path(params[0]), params[1], str(params[0]))


## The path follows the live bus layout: re-routing SFX_Menu straight to Master drops SFX.
## :rtype: void
func test_feedback_path_follows_bus_layout() -> void:
	var menu_idx: int = _bus_idx(AudioConstants.BUS_SFX_MENU)
	var original_send: StringName = AudioServer.get_bus_send(menu_idx)
	AudioServer.set_bus_send(menu_idx, AudioConstants.BUS_MASTER)

	var sfx_on_path: bool = AudioManager._is_in_feedback_path(AudioConstants.BUS_SFX)
	var master_on_path: bool = AudioManager._is_in_feedback_path(AudioConstants.BUS_MASTER)
	AudioServer.set_bus_send(menu_idx, original_send)

	assert_false(sfx_on_path, "SFX is off the path once SFX_Menu bypasses it")
	assert_true(master_on_path, "Master is still on the path")


## A misconfigured send cycle cannot hang the walk.
## :rtype: void
func test_feedback_path_walk_survives_send_cycle() -> void:
	var sfx_idx: int = _bus_idx(AudioConstants.BUS_SFX)
	var original_send: StringName = AudioServer.get_bus_send(sfx_idx)
	AudioServer.set_bus_send(sfx_idx, AudioConstants.BUS_SFX_MENU)  # SFX_Menu <-> SFX

	var music_on_path: bool = AudioManager._is_in_feedback_path(AudioConstants.BUS_MUSIC)
	AudioServer.set_bus_send(sfx_idx, original_send)

	assert_false(music_on_path, "The capped walk returns instead of looping")


## A manual auto-mute of SFX or SFX_Menu holds the bus audible for the click, then mutes it.
## :rtype: void
func test_manual_feedback_path_hold_then_flatten(
	bus: String = use_parameters(HELD_SFX_BUSES)
) -> void:
	AudioManager.change_volume(bus, 0.0, true)

	assert_true(AudioManager.get_muted(bus), "State flips immediately")
	assert_false(_hw_muted(bus), bus + " is not muted in the mixer during the hold")
	assert_almost_eq(
		_hw_linear(bus),
		AudioConstants.FEEDBACK_HOLD_VOLUME_LINEAR,
		0.0001,
		bus + " is held at the feedback level"
	)
	assert_true(SfxManager.is_any_sfx_playing(), "The click is playing")
	assert_true(_click_chain_audible(), "The click's bus chain is audible during the hold")

	await wait_seconds(HOLD_WAIT)

	assert_true(_hw_muted(bus), bus + " is muted in the mixer once the hold ends")
	assert_almost_eq(_hw_linear(bus), 0.0, 0.0001)
	assert_eq(AudioManager._clicks_in_flight, 0, "No click window left open")


## Buses off the path are muted right away even for manual changes: no hold, no hold state.
## :rtype: void
func test_off_path_manual_auto_mute_has_no_hold(
	bus: String = use_parameters(OFF_PATH_BUSES)
) -> void:
	AudioManager.change_volume(bus, 0.0, true)

	assert_true(_hw_muted(bus), bus + " is muted in the mixer immediately")
	assert_almost_eq(_hw_linear(bus), 0.0, 0.0001)
	assert_false(AudioManager._is_path_write_deferred(bus), "Off-path writes are never deferred")
	assert_true(_click_chain_audible(), "Muting an off-path bus never silences the click")


## Programmatic auto-mutes of path buses stay silent and immediate: the hold is manual-only.
## :rtype: void
func test_programmatic_feedback_path_auto_mute_has_no_hold(
	bus: String = use_parameters(HELD_SFX_BUSES)
) -> void:
	AudioManager.change_volume(bus, 0.0)

	assert_true(_hw_muted(bus), bus + " is muted in the mixer immediately")
	assert_almost_eq(_hw_linear(bus), 0.0, 0.0001)
	assert_false(SfxManager.is_any_sfx_playing(), "Programmatic changes never play SFX")
	assert_eq(AudioManager._clicks_in_flight, 0, "Programmatic changes open no click window")


## The Issue #1075 guard covers the new path buses too: a near-zero follow-up during an SFX or
## SFX_Menu hold keeps the hold, and the bus is muted at the newest volume afterwards.
## :rtype: void
func test_near_zero_follow_up_keeps_feedback_path_hold(
	bus: String = use_parameters(HELD_SFX_BUSES)
) -> void:
	var near_zero: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD / 2.0
	AudioManager.change_volume(bus, 0.0, true)

	await AudioManager.change_volume(bus, near_zero)

	assert_false(_hw_muted(bus), "The follow-up must not hard-mute the held bus")
	assert_almost_eq(_hw_linear(bus), AudioConstants.FEEDBACK_HOLD_VOLUME_LINEAR, 0.0001)

	await wait_seconds(HOLD_WAIT)

	assert_true(_hw_muted(bus))
	assert_almost_eq(_hw_linear(bus), near_zero, 0.000001, "Re-synced to the newest volume")


# ==========================================
# FEEDBACK HOLD ROUTING AND LIFECYCLE REGRESSIONS
# ==========================================


## With no click bus, no configured bus can belong to its feedback path.
## :rtype: void
func test_feedback_hold_path_without_menu_bus() -> void:
	var menu_idx: int = _bus_idx(AudioConstants.BUS_SFX_MENU)
	AudioServer.set_bus_name(menu_idx, "TestMissingMenuBus")
	var membership: Array = []
	for bus: String in ALL_BUSES:
		membership.append(AudioManager._is_in_feedback_path(bus))
	AudioServer.set_bus_name(menu_idx, AudioConstants.BUS_SFX_MENU)

	for i: int in range(ALL_BUSES.size()):
		assert_false(membership[i], ALL_BUSES[i] + " has no path without SFX_Menu")


## Moving the click through Music must change which bus gets a real manual hold.
## :rtype: void
func test_feedback_hold_rerouting_changes_manual_cutoff(
	params: Array = use_parameters(
		[[AudioConstants.BUS_MUSIC, true], [AudioConstants.BUS_SFX, false]]
	)
) -> void:
	var bus: String = params[0]
	var should_hold: bool = params[1]
	var menu_idx: int = _bus_idx(AudioConstants.BUS_SFX_MENU)
	var original_send: StringName = AudioServer.get_bus_send(menu_idx)
	AudioServer.set_bus_send(menu_idx, AudioConstants.BUS_MUSIC)

	AudioManager.change_volume(bus, 0.0, true)
	var held: bool = AudioManager._is_path_write_deferred(bus)
	var mixer_muted: bool = _hw_muted(bus)
	var mixer_volume: float = _hw_linear(bus)
	var menu_audible: bool = not _hw_muted(AudioConstants.BUS_SFX_MENU)
	var music_audible: bool = not _hw_muted(AudioConstants.BUS_MUSIC)
	var master_audible: bool = not _hw_muted(AudioConstants.BUS_MASTER)
	AudioServer.set_bus_send(menu_idx, original_send)

	assert_eq(held, should_hold, "The live send controls the hold, not the bus name")
	assert_eq(mixer_muted, not should_hold)
	var expected_volume: float = AudioConstants.FEEDBACK_HOLD_VOLUME_LINEAR if should_hold else 0.0
	assert_almost_eq(mixer_volume, expected_volume, 0.0001)
	assert_true(
		menu_audible and music_audible and master_audible, "The rerouted path stays unmuted"
	)
	assert_true(SfxManager.is_any_sfx_playing(), "Manual transitions still play a click")
	assert_true(AudioManager.get_muted(bus), "The logical mute is immediate")

	await wait_seconds(HOLD_WAIT)

	assert_true(_hw_muted(bus), "The final mute applies even after the route changes back")
	assert_almost_eq(_hw_linear(bus), 0.0, 0.0001)
	assert_eq(AudioManager._clicks_in_flight, 0, "No click window left open")


## Repeated boundary updates on the newly held buses neither cut off nor replay the click.
## :rtype: void
func test_feedback_hold_sfx_boundary_follow_ups(
	params: Array = use_parameters(
		[
			[AudioConstants.BUS_SFX, false],
			[AudioConstants.BUS_SFX, true],
			[AudioConstants.BUS_SFX_MENU, false],
			[AudioConstants.BUS_SFX_MENU, true],
		]
	)
) -> void:
	var bus: String = params[0]
	var is_manual: bool = params[1]
	var threshold: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD
	AudioManager.change_volume(bus, 0.0, true)
	SfxManager.stop_all_sfx()
	watch_signals(AudioManager)

	for value: float in [threshold, 0.0, threshold / 2.0]:
		await AudioManager.change_volume(bus, value, is_manual)

		assert_eq(AudioManager.get_volume(bus), value)
		assert_true(AudioManager.get_muted(bus))
		assert_false(_hw_muted(bus), "At-or-below-threshold updates preserve the hold")
		assert_almost_eq(_hw_linear(bus), AudioConstants.FEEDBACK_HOLD_VOLUME_LINEAR, 0.0001)
		assert_eq(AudioManager._clicks_in_flight, 1, "No extra click window")
		assert_false(SfxManager.is_any_sfx_playing(), "No new click without a crossing")

	assert_signal_emit_count(AudioManager, "volume_changed", 3)
	assert_signal_not_emitted(AudioManager, "mute_toggled")
	await wait_seconds(HOLD_WAIT)

	assert_true(_hw_muted(bus))
	assert_almost_eq(_hw_linear(bus), threshold / 2.0, 0.000001)
	assert_eq(AudioManager._clicks_in_flight, 0, "No click window left open")
	assert_signal_emit_count(AudioManager, "volume_changed", 3, "Settling only writes the mixer")
	assert_signal_not_emitted(AudioManager, "mute_toggled")


## The first value above the threshold takes effect immediately on the new path buses.
## :rtype: void
func test_feedback_hold_sfx_raise_at_boundary(bus: String = use_parameters(HELD_SFX_BUSES)) -> void:
	var raised: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD + 0.000001
	AudioManager.change_volume(bus, 0.0, true)
	watch_signals(AudioManager)

	await AudioManager.change_volume(bus, raised)

	assert_false(AudioManager.get_muted(bus))
	assert_false(_hw_muted(bus), "An upward crossing applies before the hold timer ends")
	assert_almost_eq(_hw_linear(bus), raised, 0.0000001)
	assert_eq(AudioManager._clicks_in_flight, 1, "The old click window is still open")
	assert_signal_emitted_with_parameters(AudioManager, "mute_toggled", [bus, false])
	SfxManager.stop_all_sfx()

	await wait_seconds(HOLD_WAIT)

	assert_false(_hw_muted(bus), "The old timer must preserve the newer unmute")
	assert_almost_eq(_hw_linear(bus), raised, 0.0000001)
	assert_eq(AudioManager._clicks_in_flight, 0, "No click window left open")
	assert_signal_emit_count(AudioManager, "mute_toggled", 1)
	assert_false(SfxManager.is_any_sfx_playing(), "Settling does not replay the click")


## Overlapping holds on SFX buses re-read both fields of the latest state and drain fully.
## :rtype: void
func test_feedback_hold_sfx_overlaps_preserve_latest_state(
	params: Array = use_parameters(
		[
			[AudioConstants.BUS_SFX, false],
			[AudioConstants.BUS_SFX, true],
			[AudioConstants.BUS_SFX_MENU, false],
			[AudioConstants.BUS_SFX_MENU, true],
		]
	)
) -> void:
	var bus: String = params[0]
	var final_muted: bool = params[1]
	AudioManager.change_volume(bus, 0.0, true)
	await AudioManager.change_volume(bus, RAISED_VOLUME)
	AudioManager.change_volume(bus, 0.0, true)
	assert_eq(AudioManager._clicks_in_flight, 2, "One window per manual click")
	assert_false(_hw_muted(bus))
	assert_almost_eq(_hw_linear(bus), AudioConstants.FEEDBACK_HOLD_VOLUME_LINEAR, 0.0001)
	AudioManager.set_bus_state(bus, START_VOLUME, final_muted)
	SfxManager.stop_all_sfx()
	watch_signals(AudioManager)

	await wait_seconds(HOLD_WAIT)

	assert_eq(AudioManager.get_bus_state(bus), {"volume": START_VOLUME, "muted": final_muted})
	assert_eq(_hw_muted(bus), final_muted)
	assert_almost_eq(_hw_linear(bus), START_VOLUME, 0.0001)
	assert_eq(AudioManager._clicks_in_flight, 0, "No click window left open")
	assert_signal_not_emitted(AudioManager, "volume_changed")
	assert_signal_not_emitted(AudioManager, "mute_toggled")
	assert_false(SfxManager.is_any_sfx_playing())


## Unmuting one of several held buses must leave the other buses' holds intact.
## :rtype: void
func test_feedback_hold_buses_settle_independently(
	raised_bus: String = use_parameters(
		[AudioConstants.BUS_MASTER, AudioConstants.BUS_SFX, AudioConstants.BUS_SFX_MENU]
	)
) -> void:
	var buses: Array = [
		AudioConstants.BUS_MASTER, AudioConstants.BUS_SFX, AudioConstants.BUS_SFX_MENU
	]
	for bus: String in buses:
		AudioManager.change_volume(bus, 0.0, true)
	await AudioManager.change_volume(raised_bus, RAISED_VOLUME)

	assert_eq(AudioManager._clicks_in_flight, 3, "One window per manual click")
	for bus: String in buses:
		assert_true(AudioManager._is_path_write_deferred(bus), bus + " is still held")
		assert_false(_hw_muted(bus))
		var expected: float = (
			RAISED_VOLUME if bus == raised_bus else AudioConstants.FEEDBACK_HOLD_VOLUME_LINEAR
		)
		assert_almost_eq(_hw_linear(bus), expected, 0.0001)

	await wait_seconds(HOLD_WAIT)

	for bus: String in buses:
		var should_mute: bool = bus != raised_bus
		assert_eq(AudioManager.get_muted(bus), should_mute)
		assert_eq(_hw_muted(bus), should_mute, bus + " settles from its own state")
		assert_almost_eq(_hw_linear(bus), 0.0 if should_mute else RAISED_VOLUME, 0.0001)
	assert_eq(AudioManager._clicks_in_flight, 0, "No click window left open")


## Cleanup must retain open click windows so an old timer cannot close a newer one early.
## :rtype: void
func test_feedback_hold_cleanup_preserves_pending_count(
	bus: String = use_parameters(HELD_SFX_BUSES)
) -> void:
	AudioManager.change_volume(bus, 0.0, true)
	AudioManager.cleanup_for_test()
	assert_eq(AudioManager._clicks_in_flight, 1, "Cleanup keeps the open click window")

	await AudioManager.change_volume(bus, RAISED_VOLUME)
	AudioManager.change_volume(bus, 0.0, true)
	assert_eq(AudioManager._clicks_in_flight, 2, "The new click has its own window")
	assert_false(_hw_muted(bus))
	assert_almost_eq(_hw_linear(bus), AudioConstants.FEEDBACK_HOLD_VOLUME_LINEAR, 0.0001)

	await wait_seconds(HOLD_WAIT)

	assert_true(AudioManager.get_muted(bus))
	assert_true(_hw_muted(bus))
	assert_almost_eq(_hw_linear(bus), 0.0, 0.0001)
	assert_eq(AudioManager._clicks_in_flight, 0, "No click window left open")


## New path buses also take the immediate branch when their manager has no SceneTree.
## :rtype: void
func test_feedback_hold_sfx_outside_tree_is_immediate(
	bus: String = use_parameters(HELD_SFX_BUSES)
) -> void:
	var manager: Node = autofree(load("res://scripts/managers/audio_manager.gd").new())
	manager.set_bus_state(bus, START_VOLUME, false)

	await manager.change_volume(bus, 0.0, true)

	assert_true(manager.get_muted(bus))
	assert_true(_hw_muted(bus), "An unattached manager cannot defer the hardware cutoff")
	assert_almost_eq(_hw_linear(bus), 0.0, 0.0001)
	assert_eq(manager._clicks_in_flight, 0, "An unattached manager opens no click window")
	assert_true(SfxManager.is_any_sfx_playing(), "The manual transition still requests feedback")


## Cross-bus overlap (review on #1047): SFX_Menu is auto-muted, then SFX, and a later click is
## still streaming when the first windows close. SFX_Menu's timer must not mute SFX_Menu (or
## SFX) under that click: both stay held until the last window closes, then both are muted.
## The later click's window is held open by hand, so the check does not race real timers.
## :rtype: void
func test_regression_cross_bus_holds_wait_for_last_click() -> void:
	var menu_bus: String = AudioConstants.BUS_SFX_MENU
	var sfx_bus: String = AudioConstants.BUS_SFX
	AudioManager.change_volume(menu_bus, 0.0, true)
	AudioManager.change_volume(sfx_bus, 0.0, true)
	AudioManager._clicks_in_flight += 1  # A later click still streaming through both buses

	await wait_seconds(HOLD_WAIT)

	assert_eq(AudioManager._clicks_in_flight, 1, "Only the later click's window is open")
	for bus: String in [menu_bus, sfx_bus]:
		assert_true(AudioManager.get_muted(bus), bus + " is muted in the manager")
		assert_false(_hw_muted(bus), bus + " must not be muted under the later click")
		assert_almost_eq(
			_hw_linear(bus), AudioConstants.FEEDBACK_HOLD_VOLUME_LINEAR, 0.0001, bus + " held"
		)
	assert_true(_click_chain_audible(), "The later click can still be heard")

	AudioManager._end_click_window()

	for bus: String in [menu_bus, sfx_bus]:
		assert_true(_hw_muted(bus), bus + " is muted once the last window closes")
		assert_almost_eq(_hw_linear(bus), 0.0, 0.0001)


## Same cross-bus sequence with real timers only: both holds settle and nothing stays open.
## :rtype: void
func test_cross_bus_real_holds_settle_muted() -> void:
	AudioManager.change_volume(AudioConstants.BUS_SFX_MENU, 0.0, true)
	AudioManager.change_volume(AudioConstants.BUS_SFX, 0.0, true)
	assert_eq(AudioManager._clicks_in_flight, 2, "One window per click")

	await wait_seconds(HOLD_WAIT)

	for bus: String in HELD_SFX_BUSES:
		assert_true(_hw_muted(bus), bus + " is muted after both holds")
		assert_almost_eq(_hw_linear(bus), 0.0, 0.0001)
	assert_eq(AudioManager._clicks_in_flight, 0, "No click window left open")


## A programmatic mute of a feedback-path bus while a click streams (review on #1047) is
## deferred: the manager state flips now, the mixer mutes when the last window closes.
## :rtype: void
func test_regression_programmatic_toggle_mute_waits_for_click(
	bus: String = use_parameters([AudioConstants.BUS_MASTER, AudioConstants.BUS_SFX])
) -> void:
	AudioManager.change_volume(AudioConstants.BUS_SFX_MENU, 0.0, true)
	watch_signals(AudioManager)

	await AudioManager.toggle_mute(bus, true)

	assert_true(AudioManager.get_muted(bus), "The manager state flips immediately")
	assert_signal_emitted_with_parameters(AudioManager, "mute_toggled", [bus, true])
	assert_false(_hw_muted(bus), bus + " is not muted under the streaming click")
	assert_true(_click_chain_audible(), "The click can still be heard")

	await wait_seconds(HOLD_WAIT)

	assert_true(_hw_muted(bus), bus + " is muted once the click has finished")
	assert_almost_eq(_hw_linear(bus), START_VOLUME, 0.0001, "Muted at its own volume")


## Off-path programmatic mutes and any unmute still apply at once while a click streams.
## :rtype: void
func test_toggle_mute_during_click_applies_immediately_when_safe() -> void:
	var master: String = AudioConstants.BUS_MASTER
	AudioManager.change_volume(master, 0.0, true)

	await AudioManager.toggle_mute(AudioConstants.BUS_MUSIC, true)
	assert_true(_hw_muted(AudioConstants.BUS_MUSIC), "An off-path mute is never deferred")

	await AudioManager.toggle_mute(master, false)
	assert_false(_hw_muted(master), "An unmute applies immediately during the hold")
	assert_gt(_hw_linear(master), AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD, "Volume restored")


## A manual mute toggle's own click keeps the path open (review on #1047): when its delay
## ends while another click is still streaming, the toggled bus is not muted yet; the last
## window mutes it. The other click's window is held open by hand to avoid a timer race.
## :rtype: void
func test_regression_manual_toggle_mute_waits_for_last_click() -> void:
	var bus: String = AudioConstants.BUS_SFX
	AudioManager.toggle_mute(bus, true, true)
	assert_eq(AudioManager._clicks_in_flight, 1, "The toggle's click opens a window")
	AudioManager._clicks_in_flight += 1  # Another click still streaming after the toggle's

	await wait_seconds(HOLD_WAIT)

	assert_true(AudioManager.get_muted(bus))
	assert_false(_hw_muted(bus), "The toggle's delay must not cut the other click short")

	AudioManager._end_click_window()

	assert_true(_hw_muted(bus), "The last window applies the toggled mute")
