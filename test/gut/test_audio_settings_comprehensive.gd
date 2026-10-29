## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_audio_settings_comprehensive.gd
##
## Comprehensive integration suite for the near-zero auto-mute rule through the Audio Settings
## menu (Feature Task #724, reworked for Issue #1044, epic #725).
## Every case drives a real input path instead of calling AudioManager.set_volume() or
## emitting volume_changed directly:
##   - manual: a focused VolumeSlider moved through slider.value;
##   - programmatic: the web bridge volume handler (what Playwright and JS automation use).
## Assertions cover what the player gets: manager state, the mute button, the AudioServer mute
## flag and a click that is actually audible (its bus chain unmuted), not just playing.
## Per-bus cases are parameterized over all six buses. TC-AM numbering is kept for
## traceability. The manager-level contract lives in test_audio_manager_auto_mute.gd.

extends "res://addons/gut/test.gd"


## WHY: Real JS callbacks receive a JavaScriptObject; tests pass a plain [volume] array.
## The bridge is never added to the tree, so its web-only _ready() never runs.
class TestBridge:
	extends "res://scripts/system/audio_web_bridge.gd"

	func _validate_volume_args(args: Array) -> float:
		return clampf(float(args[0]), 0.0, 1.0)


const TEST_CONFIG_PATH: String = "user://test_audio_settings_comprehensive.cfg"
const START_VOLUME: float = 0.66
const RAISED_VOLUME: float = 0.5
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
## Menu control names per bus: [slider property, mute button property].
const BUS_CONTROLS: Dictionary = {
	AudioConstants.BUS_MASTER: ["master_slider", "mute_master"],
	AudioConstants.BUS_MUSIC: ["music_slider", "mute_music"],
	AudioConstants.BUS_SFX: ["sfx_slider", "mute_sfx"],
	AudioConstants.BUS_SFX_WEAPON: ["weapon_slider", "mute_weapon"],
	AudioConstants.BUS_SFX_ROTORS: ["rotor_slider", "mute_rotor"],
	AudioConstants.BUS_SFX_MENU: ["menu_slider", "mute_menu"],
}

var audio_scene: PackedScene = load(GamePaths.AUDIO_SETTINGS_SCENE)
var audio_instance: Control
var bridge: Node
var _original_states: Dictionary = {}
var _original_config_path: String
var _original_encryption_key: String


## Isolates config I/O, starts every bus unmuted at START_VOLUME, and opens the menu.
## :rtype: void
func before_each() -> void:
	_original_config_path = AudioManager.current_config_path
	_original_encryption_key = Globals.save_encryption_pass
	for bus: String in AudioConstants.BUS_CONFIG.keys():
		_original_states[bus] = AudioManager.get_bus_state(bus)

	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)
	Globals.set_test_encryption_key()
	AudioManager.current_config_path = TEST_CONFIG_PATH
	for bus: String in AudioConstants.BUS_CONFIG.keys():
		AudioManager.set_bus_state(bus, START_VOLUME, false)
	AudioManager.apply_all_volumes()
	SfxManager.stop_all_sfx()

	bridge = autofree(TestBridge.new())
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	await get_tree().process_frame


## Closes the menu, lets pending holds settle, and restores audio state.
## :rtype: void
func after_each() -> void:
	if is_instance_valid(audio_instance):
		audio_instance.queue_free()
	audio_instance = null
	await wait_seconds(HOLD_WAIT)
	SfxManager.stop_all_sfx()

	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)
	AudioManager.current_config_path = _original_config_path
	for bus: String in _original_states.keys():
		var state: Dictionary = _original_states[bus]
		AudioManager.set_bus_state(bus, state["volume"], state["muted"])
	AudioManager.apply_all_volumes()
	Globals.save_encryption_pass = _original_encryption_key


# ==========================================================================
# HELPERS
# ==========================================================================


## Returns the menu slider for a bus.
## :rtype: HSlider
func _slider(bus_name: String) -> HSlider:
	return audio_instance.get(BUS_CONTROLS[bus_name][0])


## Returns the menu mute button for a bus.
## :rtype: CheckButton
func _button(bus_name: String) -> CheckButton:
	return audio_instance.get(BUS_CONTROLS[bus_name][1])


## Returns the AudioServer index of a bus, failing the test if it is missing.
## :rtype: int
func _bus_idx(bus_name: String) -> int:
	var idx: int = AudioServer.get_bus_index(bus_name)
	assert_ne(idx, -1, bus_name + " bus must exist")
	return idx


## Returns the AudioServer mute flag for a bus.
## :rtype: bool
func _hw_muted(bus_name: String) -> bool:
	return AudioServer.is_bus_mute(_bus_idx(bus_name))


## Returns the volume AudioServer holds for a bus, in dB.
## :rtype: float
func _hw_db(bus_name: String) -> float:
	return AudioServer.get_bus_volume_db(_bus_idx(bus_name))


## Returns the SFX_CHECK player that is currently playing, or null.
## :rtype: AudioStreamPlayer
func _playing_click() -> AudioStreamPlayer:
	var check_path: String = AudioConstants.SFX_DIR_PATH + "check.wav"
	for player: AudioStreamPlayer in SfxManager.get_sfx_pool_players():
		if is_instance_valid(player) and player.playing and player.stream:
			if player.stream.resource_path == check_path:
				return player
	return null


## Number of pool players currently playing the SFX_CHECK click. A click played twice for one
## transition occupies two players, so this tells "once" apart from "twice".
## :rtype: int
func _count_playing_clicks() -> int:
	var check_path: String = AudioConstants.SFX_DIR_PATH + "check.wav"
	var count: int = 0
	for player: AudioStreamPlayer in SfxManager.get_sfx_pool_players():
		if is_instance_valid(player) and player.playing and player.stream:
			if player.stream.resource_path == check_path:
				count += 1
	return count


## True when the SFX_CHECK click is playing at all (audible or not).
## :rtype: bool
func _is_click_playing() -> bool:
	return _playing_click() != null


## True when the SFX_CHECK click is playing on a bus chain the player can hear: every bus from
## the player's own bus up its AudioServer sends to Master is unmuted and above
## AUTO_MUTE_VOLUME_THRESHOLD. A bare player.playing check passes even for a click routed
## through a muted or near-zero bus, which is what the old TC-AM-003/006 asserted (#1047).
## :rtype: bool
func _is_click_audible() -> bool:
	var player: AudioStreamPlayer = _playing_click()
	if player == null:
		return false
	var bus: String = player.bus
	for _step in range(AudioServer.bus_count):
		if _hw_muted(bus):
			return false
		if db_to_linear(_hw_db(bus)) <= AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD:
			return false
		bus = String(AudioServer.get_bus_send(_bus_idx(bus)))
		if bus.is_empty():
			return true
	return false


## Moves a slider the way keyboard input does: focused, through slider.value, so the change
## goes through VolumeSlider._on_value_changed like a real interaction.
## :rtype: void
func _move_focused_slider(bus_name: String, value: float) -> void:
	var slider: HSlider = _slider(bus_name)
	slider.grab_focus()
	slider.value = value


## Sends a volume change through the web bridge handler, unfocused, like JS automation does.
## :rtype: void
func _bridge_volume(bus_name: String, value: float) -> void:
	var slider: HSlider = _slider(bus_name)
	if slider.has_focus():
		slider.release_focus()
	bridge._on_change_volume_js([value], bus_name)


## Returns the number of mute_toggled emissions for a bus since watch_signals().
## :rtype: int
func _mute_emits_for(bus_name: String) -> int:
	var count: int = 0
	for i in range(get_signal_emit_count(AudioManager, "mute_toggled")):
		var params: Array = get_signal_parameters(AudioManager, "mute_toggled", i)
		if params[0] == bus_name:
			count += 1
	return count


# ==========================================================================
# 1. MANUAL SLIDER AUTO-MUTE (TC-AM-001 to TC-AM-006)
# ==========================================================================


## A focused slider dragged to zero auto-mutes its bus: manager, mute button and mixer all
## report muted, and the confirmation click plays and is audible.
## :rtype: void
func test_tc_am_001_006_manual_slider_auto_mutes(bus: String = use_parameters(ALL_BUSES)) -> void:
	_move_focused_slider(bus, 0.0)
	var click_played: bool = _is_click_playing()
	var click_audible: bool = _is_click_audible()
	await wait_seconds(HOLD_WAIT)

	assert_true(AudioManager.get_muted(bus), bus + " is auto-muted at zero")
	assert_false(_button(bus).button_pressed, bus + " mute button shows muted")
	assert_true(_hw_muted(bus), bus + " is muted in AudioServer")
	assert_true(click_played, bus + ": the confirmation click plays")
	# Enforced on all six buses: SFX and SFX_Menu are held audible like Master (Issue #1047).
	assert_true(click_audible, bus + ": the confirmation click is audible")


## The exact AUTO_MUTE_VOLUME_THRESHOLD counts as zero through the slider path too.
## :rtype: void
func test_tc_am_001_threshold_is_inclusive_through_slider() -> void:
	var bus: String = AudioConstants.BUS_MUSIC
	var slider: HSlider = _slider(bus)
	slider.grab_focus()
	# Bypass the slider step so the exact threshold reaches AudioManager.
	slider.set_value_no_signal(AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD)
	slider.value_changed.emit(AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD)
	await get_tree().process_frame

	assert_true(AudioManager.get_muted(bus), "The threshold itself auto-mutes")
	assert_false(_button(bus).button_pressed)


# ==========================================================================
# 2. AUTOMATION SILENCE (TC-AM-007 to TC-AM-012)
# ==========================================================================


## A programmatic change to zero (web bridge, slider unfocused) auto-mutes silently: the
## state, button and mixer follow, and no SFX plays, not even after the hold window.
## :rtype: void
func test_tc_am_007_012_automation_auto_mutes_silently(
	bus: String = use_parameters(ALL_BUSES)
) -> void:
	_bridge_volume(bus, 0.0)
	var sfx_after_change: bool = SfxManager.is_any_sfx_playing()
	await wait_seconds(HOLD_WAIT)

	assert_true(AudioManager.get_muted(bus), bus + " is auto-muted at zero")
	assert_false(_button(bus).button_pressed, bus + " mute button shows muted")
	assert_true(_hw_muted(bus), bus + " is muted in AudioServer")
	assert_almost_eq(_slider(bus).value, 0.0, 0.0001, bus + " slider follows the bridge")
	assert_false(sfx_after_change, bus + ": automation never plays SFX")
	assert_false(SfxManager.is_any_sfx_playing(), bus + ": still silent after the hold window")


## An unfocused slider moved programmatically (no keyboard or drag) is automation too.
## :rtype: void
func test_tc_am_007_012_unfocused_slider_is_silent(bus: String = use_parameters(ALL_BUSES)) -> void:
	var slider: HSlider = _slider(bus)
	if slider.has_focus():
		slider.release_focus()

	slider.value = 0.0
	await wait_seconds(HOLD_WAIT)

	assert_true(AudioManager.get_muted(bus), bus + " is auto-muted at zero")
	assert_true(_hw_muted(bus), bus + " is muted in AudioServer")
	assert_false(SfxManager.is_any_sfx_playing(), bus + ": no click without focus")


# ==========================================================================
# T5: CALLERS STATE THEIR OWN INTENT (Issue #1042)
# ==========================================================================


## The web bridge is never a manual interaction, even while Master holds the menu's initial
## focus from Globals.ensure_initial_focus(). changeMasterVolume([0]) right after the menu
## opens must mute Master at once, with no confirmation click and no feedback hold.
## Unlike _bridge_volume(), focus is deliberately left where the menu put it.
## :rtype: void
func test_t5_bridge_master_zero_with_initial_focus_is_silent() -> void:
	await get_tree().process_frame  # ensure_initial_focus() grabs focus deferred
	var master: String = AudioConstants.BUS_MASTER
	assert_true(_slider(master).has_focus(), "Precondition: Master holds the initial focus")

	bridge._on_change_volume_js([0.0], master)
	var click_after_change: bool = _is_click_playing()
	var muted_in_mixer_at_once: bool = _hw_muted(master)
	await wait_seconds(HOLD_WAIT)

	assert_true(AudioManager.get_muted(master), "Master is auto-muted at zero")
	assert_true(muted_in_mixer_at_once, "No feedback hold: Master is muted in AudioServer at once")
	assert_true(_hw_muted(master), "Master stays muted in AudioServer")
	assert_false(click_after_change, "The bridge never plays the confirmation click")
	assert_false(_is_click_playing(), "Still no click after the hold window")


## A focused slider moved to zero auto-mutes its bus and plays the confirmation click exactly
## once: the slider routes through AudioManager.change_volume() and the rule is applied once.
## :rtype: void
func test_t5_focused_slider_to_zero_clicks_once(bus: String = use_parameters(ALL_BUSES)) -> void:
	_move_focused_slider(bus, 0.0)
	var clicks: int = _count_playing_clicks()
	await wait_seconds(HOLD_WAIT)

	assert_true(AudioManager.get_muted(bus), bus + " is auto-muted at zero")
	assert_true(_hw_muted(bus), bus + " is muted in AudioServer")
	assert_eq(clicks, 1, bus + ": the confirmation click plays exactly once")


# ==========================================================================
# 3. BOUNDARY CONTROL & IDEMPOTENCY (TC-AM-013)
# ==========================================================================


## Once a bus is auto-muted, further near-zero updates from any path are no-ops:
## no mute transition, no click, and the bus stays muted in the mixer.
## :rtype: void
func test_tc_am_013_repeated_near_zero_is_noop(bus: String = use_parameters(ALL_BUSES)) -> void:
	_move_focused_slider(bus, 0.0)
	await wait_seconds(HOLD_WAIT)
	SfxManager.stop_all_sfx()
	watch_signals(AudioManager)

	_bridge_volume(bus, 0.0)
	_bridge_volume(bus, AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD)
	_move_focused_slider(bus, 0.0)
	await wait_seconds(HOLD_WAIT)

	assert_eq(_mute_emits_for(bus), 0, bus + ": no mute_toggled on repeated near-zero updates")
	assert_false(_is_click_playing(), bus + ": repeated near-zero updates stay silent")
	assert_true(AudioManager.get_muted(bus))
	assert_true(_hw_muted(bus), bus + " stays muted in AudioServer")


# ==========================================================================
# 4. UPWARD CYCLE TRANSITIONS (TC-AM-014)
# ==========================================================================


## Raising a focused slider from an auto-muted zero unmutes the bus everywhere, with an
## audible click, and the manager holds the slider's value.
## :rtype: void
func test_tc_am_014_manual_upward_unmute(bus: String = use_parameters(ALL_BUSES)) -> void:
	_move_focused_slider(bus, 0.0)
	await wait_seconds(HOLD_WAIT)
	assert_true(AudioManager.get_muted(bus), "Precondition: auto-muted at zero")
	SfxManager.stop_all_sfx()

	_move_focused_slider(bus, RAISED_VOLUME)
	var click_audible: bool = _is_click_audible()
	await get_tree().process_frame

	assert_false(AudioManager.get_muted(bus), bus + " is auto-unmuted")
	assert_true(_button(bus).button_pressed, bus + " mute button shows unmuted")
	assert_false(_hw_muted(bus), bus + " is audible in AudioServer")
	# The slider snaps to its step, so compare against what the slider actually holds.
	assert_almost_eq(AudioManager.get_volume(bus), _slider(bus).value, 0.0001)
	assert_true(click_audible, bus + ": the confirmation click is audible")


## A programmatic raise from an auto-muted zero clears the AudioServer mute on every bus,
## not only Master, and stays silent.
## :rtype: void
func test_tc_am_014_automation_upward_unmute(bus: String = use_parameters(ALL_BUSES)) -> void:
	_bridge_volume(bus, 0.0)
	await wait_seconds(HOLD_WAIT)
	assert_true(_hw_muted(bus), "Precondition: muted in AudioServer")

	_bridge_volume(bus, RAISED_VOLUME)
	await get_tree().process_frame

	assert_false(AudioManager.get_muted(bus), bus + " is auto-unmuted")
	assert_true(_button(bus).button_pressed, bus + " mute button shows unmuted")
	assert_false(_hw_muted(bus), bus + " must be audible in AudioServer")
	assert_almost_eq(_hw_db(bus), linear_to_db(RAISED_VOLUME), 0.0001)
	assert_false(SfxManager.is_any_sfx_playing(), bus + ": automation never plays SFX")


# ==========================================================================
# 5. MASTER FEEDBACK HOLD (TC-AM-015 to TC-AM-016)
# ==========================================================================


## Dragging Master to zero holds it audible for the click, then silences it: muted in
## AudioServer at the stored volume (re-synced from AudioManager, Issue #1041).
## :rtype: void
func test_tc_am_015_master_feedback_hold_then_silence() -> void:
	var bus: String = AudioConstants.BUS_MASTER

	_move_focused_slider(bus, 0.0)

	assert_almost_eq(
		_hw_db(bus),
		linear_to_db(AudioConstants.FEEDBACK_HOLD_VOLUME_LINEAR),
		0.0001,
		"Master is held audible while the click plays"
	)
	assert_false(_hw_muted(bus), "Master is not muted in AudioServer during the hold")
	assert_true(_is_click_audible(), "The click is audible during the hold")

	await wait_seconds(HOLD_WAIT)

	assert_true(_hw_muted(bus), "Master is muted in AudioServer after the hold")
	assert_almost_eq(_hw_db(bus), linear_to_db(AudioManager.get_volume(bus)), 0.0001)


## Dragging Master back up before the hold expires wins: the stale timer re-applies the
## newer unmuted state instead of silencing the bus.
## :rtype: void
func test_tc_am_016_master_hold_aborted_by_newer_drag() -> void:
	var bus: String = AudioConstants.BUS_MASTER

	_move_focused_slider(bus, 0.0)
	_move_focused_slider(bus, RAISED_VOLUME)
	await wait_seconds(HOLD_WAIT)

	assert_false(AudioManager.get_muted(bus), "Master ends unmuted")
	assert_true(_button(bus).button_pressed)
	assert_false(_hw_muted(bus), "The late re-sync applies the newer drag")
	assert_almost_eq(_hw_db(bus), linear_to_db(_slider(bus).value), 0.0001)


## Pressing the Master mute button to unmute during the hold also wins over the stale timer,
## and the unmute-from-zero restore leaves Master audible (Issue #1046).
## :rtype: void
func test_tc_am_016_master_button_unmute_during_hold_wins() -> void:
	var bus: String = AudioConstants.BUS_MASTER

	_move_focused_slider(bus, 0.0)
	_button(bus).button_pressed = true  # Emits toggled -> the menu's real mute pipeline
	await wait_seconds(HOLD_WAIT)

	assert_false(AudioManager.get_muted(bus), "Master ends unmuted")
	assert_false(_hw_muted(bus), "Stale hold re-applied the unmuted state")
	assert_gt(AudioManager.get_volume(bus), AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD)
	assert_almost_eq(_hw_db(bus), linear_to_db(AudioManager.get_volume(bus)), 0.0001)


## A hold on Master never touches the other buses.
## :rtype: void
func test_tc_am_016_master_hold_leaves_other_buses_alone() -> void:
	_move_focused_slider(AudioConstants.BUS_MASTER, 0.0)
	await wait_seconds(HOLD_WAIT)

	for bus: String in ALL_BUSES:
		if bus == AudioConstants.BUS_MASTER:
			continue
		assert_false(AudioManager.get_muted(bus), bus + " stays unmuted")
		assert_false(_hw_muted(bus), bus + " stays unmuted in AudioServer")
		assert_almost_eq(_hw_db(bus), linear_to_db(START_VOLUME), 0.0001)


# ==========================================================================
# 6. MENU LIFETIME
# ==========================================================================


## Freeing the menu during the Master feedback hold raises no errors.
## :rtype: void
func test_menu_freed_during_master_hold_raises_no_errors() -> void:
	var bus: String = AudioConstants.BUS_MASTER
	_move_focused_slider(bus, 0.0)
	assert_true(AudioManager.get_muted(bus), "Precondition: Master auto-muted")

	audio_instance.free()
	audio_instance = null
	await wait_seconds(HOLD_WAIT)

	assert_engine_error_count(0, "No errors after the menu is freed mid-hold")
	assert_true(AudioManager.get_muted(bus), "Master stays muted in the manager")


## Freeing the menu during the Master feedback hold still ends with Master muted in the mixer
## (Issue #1041). Since #1043 the hold runs in AudioManager.change_volume() and survives the
## menu: closing the menu mid-hold no longer cuts the confirmation click short, and the hold's
## own re-sync mutes Master once MUTE_HARDWARE_DELAY ends.
## :rtype: void
func test_menu_freed_during_master_hold_ends_muted_in_mixer() -> void:
	var bus: String = AudioConstants.BUS_MASTER
	_move_focused_slider(bus, 0.0)
	assert_false(_hw_muted(bus), "Precondition: the hold is still pending")

	audio_instance.free()
	audio_instance = null

	# The hold is not tied to the menu: Master stays audible for the click after the close.
	assert_false(_hw_muted(bus), "The hold survives the menu being freed")
	assert_almost_eq(
		_hw_db(bus),
		linear_to_db(AudioConstants.FEEDBACK_HOLD_VOLUME_LINEAR),
		0.0001,
		"Master is still held audible right after the menu is freed"
	)
	assert_true(_is_click_audible(), "The click keeps playing after the menu is freed")

	await wait_seconds(HOLD_WAIT)
	assert_true(_hw_muted(bus), "Master is muted in the mixer once the hold ends")
	assert_almost_eq(_hw_db(bus), linear_to_db(AudioManager.get_volume(bus)), 0.0001)


## Closing the menu during the hold re-syncs to the newest state, not to a fixed mute: a
## Master raised back up before the close ends audible.
## :rtype: void
func test_menu_freed_after_newer_drag_keeps_master_audible() -> void:
	var bus: String = AudioConstants.BUS_MASTER
	_move_focused_slider(bus, 0.0)
	_move_focused_slider(bus, RAISED_VOLUME)

	audio_instance.free()
	audio_instance = null
	await wait_seconds(HOLD_WAIT)

	assert_false(AudioManager.get_muted(bus))
	assert_false(_hw_muted(bus), "Master stays audible after the menu closes")
	assert_almost_eq(_hw_db(bus), linear_to_db(AudioManager.get_volume(bus)), 0.0001)


# ==========================================================================
# 7. PLAYER-CHOSEN MUTES SURVIVE WITH THE MENU OPEN (Issue #1040)
# ==========================================================================


## Mutes a bus at an audible volume the way the player does, silently and immediately.
## :rtype: void
func _player_mute(bus_name: String) -> void:
	await AudioManager.toggle_mute(bus_name, true, false)
	assert_true(AudioManager.get_muted(bus_name), "Precondition: " + bus_name + " muted")
	assert_true(_hw_muted(bus_name), "Precondition: " + bus_name + " muted in AudioServer")


## A web-bridge change to another audible volume does not unmute a bus the player muted
## (the old level-triggered menu observer did).
## :rtype: void
func test_player_mute_survives_bridge_audible_change(
	bus: String = use_parameters(ALL_BUSES)
) -> void:
	await _player_mute(bus)
	watch_signals(AudioManager)

	_bridge_volume(bus, RAISED_VOLUME)
	await get_tree().process_frame

	assert_true(AudioManager.get_muted(bus), bus + " stays muted")
	assert_false(_button(bus).button_pressed, bus + " mute button still shows muted")
	assert_true(_hw_muted(bus), bus + " stays muted in AudioServer")
	assert_eq(_mute_emits_for(bus), 0, bus + ": no mute transition without a crossing")
	assert_almost_eq(AudioManager.get_volume(bus), RAISED_VOLUME, 0.0001, "Volume still stored")
	# The slider snaps to its step, so allow up to one step of difference.
	assert_almost_eq(_slider(bus).value, RAISED_VOLUME, _slider(bus).step, "Slider follows")
	assert_false(SfxManager.is_any_sfx_playing(), bus + ": no click without a transition")


## AudioManager.change_volume() on a player-muted bus keeps it muted with the menu open too:
## the menu observer no longer overrides the manager's crossing rule.
## :rtype: void
func test_player_mute_survives_change_volume_with_menu_open(
	bus: String = use_parameters(ALL_BUSES)
) -> void:
	await _player_mute(bus)
	watch_signals(AudioManager)

	await AudioManager.change_volume(bus, RAISED_VOLUME)

	assert_true(AudioManager.get_muted(bus), bus + " muted at 0.66 stays muted at 0.5")
	assert_false(_button(bus).button_pressed)
	assert_true(_hw_muted(bus))
	assert_eq(_mute_emits_for(bus), 0, bus + ": no mute transition without a crossing")


## Documented corner case, through the menu: a player mute taken through zero and back up is
## unmuted, because at zero an explicit mute and an auto-mute look the same.
## :rtype: void
func test_player_mute_through_zero_unmutes_via_bridge(
	bus: String = use_parameters(ALL_BUSES)
) -> void:
	await _player_mute(bus)

	_bridge_volume(bus, 0.0)
	_bridge_volume(bus, RAISED_VOLUME)
	await get_tree().process_frame

	assert_false(AudioManager.get_muted(bus), "Accepted: crossing up from zero unmutes")
	assert_true(_button(bus).button_pressed)
	assert_false(_hw_muted(bus))


# ==========================================================================
# 8. OBSERVER BASELINES AND INTERLEAVED CHANGES (Issue #1040)
# ==========================================================================


## Reopens the menu after changing a bus while no menu is observing the manager.
## :rtype: void
func _reopen_with_bus_state(bus: String, volume: float, muted: bool) -> void:
	audio_instance.free()
	AudioManager.set_bus_state(bus, volume, muted)
	AudioManager.apply_all_volumes()
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	await get_tree().process_frame


## The first update after opening must compare against the manager's existing threshold value.
## :rtype: void
func test_regression_open_at_threshold_first_raise_unmutes(
	bus: String = use_parameters(ALL_BUSES)
) -> void:
	await _reopen_with_bus_state(bus, AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD, true)
	var raised: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD + 0.000001
	watch_signals(AudioManager)

	_bridge_volume(bus, raised)

	assert_eq(
		AudioManager.get_volume(bus), raised, "Preserve the bridge value before slider snapping"
	)
	assert_false(
		AudioManager.get_muted(bus), "The first update crosses up from the seeded baseline"
	)
	assert_true(_button(bus).button_pressed)
	assert_false(_hw_muted(bus))
	assert_almost_eq(_hw_db(bus), linear_to_db(raised), 0.0001)
	assert_eq(_mute_emits_for(bus), 1)
	assert_signal_emitted_with_parameters(AudioManager, "mute_toggled", [bus, false])
	assert_false(SfxManager.is_any_sfx_playing(), "An unfocused bridge update stays silent")


## Opening at an unmuted near-zero state must not invent a crossing from a default volume.
## :rtype: void
func test_regression_open_at_threshold_near_zero_updates_stay_unmuted(
	bus: String = use_parameters(ALL_BUSES)
) -> void:
	var threshold: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD
	await _reopen_with_bus_state(bus, threshold, false)
	watch_signals(AudioManager)

	for volume: float in [0.0, threshold / 2.0, threshold]:
		_bridge_volume(bus, volume)
		assert_false(
			AudioManager.get_muted(bus), "No crossing when already at or below the threshold"
		)
		assert_true(_button(bus).button_pressed)
		assert_false(_hw_muted(bus))
		assert_eq(_mute_emits_for(bus), 0)
		assert_false(SfxManager.is_any_sfx_playing())

	_bridge_volume(bus, RAISED_VOLUME)
	assert_false(AudioManager.get_muted(bus), "Crossing up on an unmuted bus is a no-op")
	assert_eq(_mute_emits_for(bus), 0)
	_bridge_volume(bus, threshold)
	assert_true(AudioManager.get_muted(bus), "A later genuine downward crossing must auto-mute")
	assert_false(_button(bus).button_pressed)
	assert_true(_hw_muted(bus))
	assert_eq(_mute_emits_for(bus), 1)


## A reopened menu seeds a new baseline after a player mute made while it was closed.
## :rtype: void
func test_regression_reopened_menu_preserves_new_audible_mute(
	bus: String = use_parameters(ALL_BUSES)
) -> void:
	_bridge_volume(bus, 0.0)
	await _reopen_with_bus_state(bus, START_VOLUME, true)
	watch_signals(AudioManager)

	_bridge_volume(bus, RAISED_VOLUME)

	assert_true(AudioManager.get_muted(bus), "The old menu's near-zero baseline must be discarded")
	assert_false(_button(bus).button_pressed)
	assert_true(_hw_muted(bus))
	assert_almost_eq(_hw_db(bus), linear_to_db(RAISED_VOLUME), 0.0001)
	assert_eq(_mute_emits_for(bus), 0)
	assert_false(SfxManager.is_any_sfx_playing())


## Changes on other buses must not overwrite the previous volume the crossing rule uses for this bus.
## :rtype: void
func test_regression_interleaved_bus_crossings_are_independent(
	bus: String = use_parameters(ALL_BUSES)
) -> void:
	var other: String = ALL_BUSES[(ALL_BUSES.find(bus) + 1) % ALL_BUSES.size()]
	_slider(AudioConstants.BUS_MASTER).release_focus()
	watch_signals(AudioManager)

	# The manager supports changes while parent buses are muted; the web bridge blocks them.
	await AudioManager.change_volume(bus, 0.0)
	await AudioManager.change_volume(other, RAISED_VOLUME)
	await AudioManager.change_volume(bus, RAISED_VOLUME)

	assert_false(
		AudioManager.get_muted(bus), "Another bus's audible update must not hide this crossing up"
	)
	assert_true(_button(bus).button_pressed)
	assert_false(_hw_muted(bus))
	assert_eq(_mute_emits_for(bus), 2)
	assert_eq(_mute_emits_for(other), 0)

	await AudioManager.change_volume(other, 0.0)
	await AudioManager.change_volume(bus, START_VOLUME)
	await AudioManager.change_volume(other, RAISED_VOLUME)

	assert_false(AudioManager.get_muted(other), "Crossings must remain independent in either order")
	assert_true(_button(other).button_pressed)
	assert_false(_hw_muted(other))
	assert_eq(_mute_emits_for(other), 2)
	assert_eq(_mute_emits_for(bus), 2, "An audible update must not add a mute transition")
	assert_eq(
		get_signal_emit_count(AudioManager, "volume_changed"), 6, "Visual sync must not feed back"
	)
	assert_almost_eq(_hw_db(bus), linear_to_db(START_VOLUME), 0.0001)
	assert_almost_eq(_hw_db(other), linear_to_db(RAISED_VOLUME), 0.0001)
	assert_false(SfxManager.is_any_sfx_playing())
