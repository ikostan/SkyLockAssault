## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_ui_sfx_menu_bus.gd
##
## Issue #1152: every UI sound (navigation, cancel, button accept) plays on the Menu bus
## (SFX_Menu), so the Menu slider and mute silence all of them, while SFX and Master still
## apply through the bus sends, and the Weapon and Rotors buses don't follow the Menu bus.
##
## Uses the real UiManager, SfxManager, AudioManager, and AudioServer bus layout.

extends GutTest

const MENU_BUS: String = AudioConstants.BUS_SFX_MENU
## Buses whose state these tests change; snapshotted and restored around every test.
const TOUCHED_BUSES: Array[String] = [
	AudioConstants.BUS_MASTER,
	AudioConstants.BUS_SFX,
	AudioConstants.BUS_SFX_MENU,
	AudioConstants.BUS_SFX_WEAPON,
	AudioConstants.BUS_SFX_ROTORS,
]

## bus name -> [volume, muted] in AudioManager before the test.
var _saved_state: Dictionary = {}


func before_all() -> void:
	for bus: String in TOUCHED_BUSES:
		assert_ne(
			AudioServer.get_bus_index(bus), -1, "Bus '%s' must exist in the bus layout." % bus
		)


func before_each() -> void:
	_saved_state.clear()
	for bus: String in TOUCHED_BUSES:
		_saved_state[bus] = [AudioManager.get_volume(bus), AudioManager.get_muted(bus)]
		_set_bus(bus, 1.0, false)
	SfxManager.stop_all_sfx()
	_release_focus()
	Globals.options_open = true  # Menu context without depending on a scene marker


func after_each() -> void:
	SfxManager.stop_all_sfx()
	Globals.options_open = false
	_release_focus()
	for bus: String in _saved_state.keys():
		var state: Array = _saved_state[bus]
		_set_bus(bus, state[0], state[1])
	_saved_state.clear()


## Sets the AudioManager state and the AudioServer bus without saving to disk.
func _set_bus(bus: String, volume: float, muted: bool) -> void:
	AudioManager.set_bus_state(bus, volume, muted)
	AudioManager.apply_volume_to_bus(bus, volume, muted)


func _release_focus() -> void:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus_owner):
		focus_owner.release_focus()


## True when [param bus] and every bus it sends to (up to Master) is unmuted with a
## volume above zero, i.e. a player on this bus can be heard.
func _is_bus_chain_audible(bus: String) -> bool:
	var current: String = bus
	var guard: int = 0
	while current != "" and guard < 16:
		var idx: int = AudioServer.get_bus_index(current)
		if idx == -1:
			return false
		if AudioServer.is_bus_mute(idx) or db_to_linear(AudioServer.get_bus_volume_db(idx)) <= 0.0:
			return false
		if current == AudioConstants.BUS_MASTER:
			return true
		current = String(AudioServer.get_bus_send(idx))
		guard += 1
	return false


func _send_action(action: String) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	UiManager._input(event)


## Plays [param kind] ("navigation", "cancel" or "accept") and returns the bus of the
## player that started. Fails the test if nothing started.
func _play_ui_sound(kind: String) -> String:
	SfxManager.stop_all_sfx()
	match kind:
		"navigation":
			_send_action("ui_down")
		"cancel":
			_send_action("ui_cancel")
		"accept":
			var btn: Button = Button.new()
			add_child_autofree(btn)
			await wait_process_frames(1)
			btn.pressed.emit()
			await wait_process_frames(1)  # The global accept handler is CONNECT_DEFERRED
	assert_true(SfxManager.is_any_sfx_playing(), "The %s sound must start a player." % kind)
	return SfxManager.get_active_sfx_bus_name()


## Navigation, cancel and accept sounds all start on the Menu bus.
func test_all_ui_sounds_play_on_menu_bus() -> void:
	for kind: String in ["navigation", "cancel", "accept"]:
		var bus: String = await _play_ui_sound(kind)
		assert_eq(bus, MENU_BUS, "The %s sound must play on '%s'." % [kind, MENU_BUS])


## The Menu bus sends to SFX, so SFX and Master still apply to UI sounds.
func test_menu_bus_sends_to_sfx() -> void:
	var idx: int = AudioServer.get_bus_index(MENU_BUS)
	assert_eq(String(AudioServer.get_bus_send(idx)), AudioConstants.BUS_SFX)


## With Menu muted, navigation, cancel and accept are all silent.
func test_menu_muted_silences_all_ui_sounds() -> void:
	_set_bus(MENU_BUS, 1.0, true)
	for kind: String in ["navigation", "cancel", "accept"]:
		var bus: String = await _play_ui_sound(kind)
		assert_eq(bus, MENU_BUS, "The %s sound must play on '%s'." % [kind, MENU_BUS])
		assert_false(_is_bus_chain_audible(bus), "The %s sound must be silent." % kind)


## With the Menu slider at 0, navigation, cancel and accept are all silent.
func test_menu_volume_zero_silences_all_ui_sounds() -> void:
	_set_bus(MENU_BUS, 0.0, false)
	for kind: String in ["navigation", "cancel", "accept"]:
		var bus: String = await _play_ui_sound(kind)
		assert_eq(bus, MENU_BUS, "The %s sound must play on '%s'." % [kind, MENU_BUS])
		assert_false(_is_bus_chain_audible(bus), "The %s sound must be silent." % kind)


## With everything at normal volume, UI sounds are audible on the Menu bus.
func test_ui_sounds_audible_at_normal_volume() -> void:
	for kind: String in ["navigation", "cancel", "accept"]:
		var bus: String = await _play_ui_sound(kind)
		assert_true(_is_bus_chain_audible(bus), "The %s sound must be audible." % kind)


## With the parent SFX bus muted, UI sounds are silent.
func test_sfx_muted_silences_ui_sounds() -> void:
	_set_bus(AudioConstants.BUS_SFX, 1.0, true)
	for kind: String in ["navigation", "cancel", "accept"]:
		var bus: String = await _play_ui_sound(kind)
		assert_false(_is_bus_chain_audible(bus), "SFX muted: the %s sound must be silent." % kind)


## With Master muted, UI sounds are silent.
func test_master_muted_silences_ui_sounds() -> void:
	_set_bus(AudioConstants.BUS_MASTER, 1.0, true)
	for kind: String in ["navigation", "cancel", "accept"]:
		var bus: String = await _play_ui_sound(kind)
		assert_false(
			_is_bus_chain_audible(bus), "Master muted: the %s sound must be silent." % kind
		)


## Muting the Menu bus or setting it to 0 leaves the Weapon and Rotors buses audible
## and unchanged.
func test_menu_slider_does_not_affect_weapon_or_rotors() -> void:
	var others: Array[String] = [AudioConstants.BUS_SFX_WEAPON, AudioConstants.BUS_SFX_ROTORS]
	var before_db: Dictionary = {}
	for bus: String in others:
		before_db[bus] = AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus))

	for menu_state: Array in [[0.0, false], [1.0, true], [0.0, true]]:
		_set_bus(MENU_BUS, menu_state[0], menu_state[1])
		for bus: String in others:
			var idx: int = AudioServer.get_bus_index(bus)
			assert_true(_is_bus_chain_audible(bus), "'%s' must stay audible." % bus)
			assert_false(AudioManager.get_muted(bus), "'%s' must not be muted." % bus)
			assert_almost_eq(AudioManager.get_volume(bus), 1.0, 0.0001)
			assert_almost_eq(AudioServer.get_bus_volume_db(idx), before_db[bus], 0.0001)
		
