## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## Unit regressions for the volume callers and visual observer migrated in #1042/#1043.
## Uses standalone sliders and an unattached menu script, without loading the menu scene.

extends "res://addons/gut/test.gd"


## Native tests cannot construct JavaScriptObject arguments. Adapt only that boundary,
## leaving the bridge's volume handler, parent guards and persistence intact.
class NativeBridge:
	extends "res://scripts/system/audio_web_bridge.gd"

	func _validate_volume_args(args: Array) -> float:
		return clampf(float(args[0]), 0.0, 1.0)


const MENU_SCRIPT = preload("res://scripts/ui/menus/audio_settings.gd")
const TEST_CONFIG_PATH: String = "user://test_volume_change_callers.cfg"
const START_VOLUME: float = 0.66
const ALL_BUSES: Array = [
	AudioConstants.BUS_MASTER,
	AudioConstants.BUS_MUSIC,
	AudioConstants.BUS_SFX,
	AudioConstants.BUS_SFX_WEAPON,
	AudioConstants.BUS_SFX_ROTORS,
	AudioConstants.BUS_SFX_MENU,
]

## Buses the confirmation click plays through (SFX_Menu -> SFX -> Master). A manual auto-mute
## of any of them is held at FEEDBACK_HOLD_VOLUME_LINEAR for the click (Issue #1047).
const FEEDBACK_PATH_BUSES: Array = [
	AudioConstants.BUS_MASTER,
	AudioConstants.BUS_SFX,
	AudioConstants.BUS_SFX_MENU,
]

const SLIDER_PROPERTIES: Dictionary = {
	AudioConstants.BUS_MASTER: "master_slider",
	AudioConstants.BUS_MUSIC: "music_slider",
	AudioConstants.BUS_SFX: "sfx_slider",
	AudioConstants.BUS_SFX_WEAPON: "weapon_slider",
	AudioConstants.BUS_SFX_ROTORS: "rotor_slider",
	AudioConstants.BUS_SFX_MENU: "menu_slider",
}

var _sliders: Dictionary
var _bridge: Node
var _original_states: Dictionary
var _original_last_audible: Dictionary
var _original_config_path: String
var _original_encryption_key: String
var _needs_hold_wait: bool

## Test-local volume_changed listener. A lambda is not tied to a node, so Godot never
## disconnects it automatically; after_each() does, even if a test exits early.
var _capture: Callable


func before_each() -> void:
	_original_states = {}
	_original_config_path = AudioManager.current_config_path
	_original_last_audible = AudioManager._last_audible_volume.duplicate()
	_original_encryption_key = Globals.save_encryption_pass
	for bus: String in ALL_BUSES:
		_original_states[bus] = AudioManager.get_bus_state(bus)
		AudioManager.set_bus_state(bus, START_VOLUME, false)
	AudioManager.apply_all_volumes()
	AudioManager.current_config_path = TEST_CONFIG_PATH
	Globals.set_test_encryption_key()
	_remove_test_config()
	SfxManager.stop_all_sfx()
	_needs_hold_wait = false
	_capture = Callable()
	_bridge = autofree(NativeBridge.new())  # Avoid the web-only _ready().
	_sliders = {}
	for bus: String in ALL_BUSES:
		var slider: VolumeSlider = VolumeSlider.new()
		slider.bus_name = bus
		slider.max_value = 1.0
		slider.step = 0.0  # Exercise the exact threshold without scene step rounding.
		add_child_autofree(slider)
		_sliders[bus] = slider


func after_each() -> void:
	# Before any state restore: the restore emits volume_changed, and the capture reads a slider.
	if _capture.is_valid() and AudioManager.volume_changed.is_connected(_capture):
		AudioManager.volume_changed.disconnect(_capture)
	_capture = Callable()
	
	# Prevent an old debounce or hold from mutating the next test's restored state.
	for slider: VolumeSlider in _sliders.values():
		slider.save_debounce_timer.stop()
	if _needs_hold_wait:
		await wait_seconds(GutTestHelper.MUTE_CUTOFF_WAIT)
	SfxManager.stop_all_sfx()
	_remove_test_config()
	AudioManager.current_config_path = _original_config_path
	for bus: String in ALL_BUSES:
		var state: Dictionary = _original_states[bus]
		AudioManager.set_bus_state(bus, state["volume"], state["muted"])
	AudioManager.apply_all_volumes()
	AudioManager._last_audible_volume = _original_last_audible
	Globals.save_encryption_pass = _original_encryption_key


func _remove_test_config() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)


func _slider(bus: String) -> VolumeSlider:
	return _sliders[bus]


func _assert_bus_state(bus: String, volume: float, muted: bool) -> void:
	assert_almost_eq(AudioManager.get_volume(bus), volume, 0.00001, bus + ": manager volume")
	assert_eq(AudioManager.get_muted(bus), muted, bus + ": manager mute")
	var index: int = AudioServer.get_bus_index(bus)
	assert_ne(index, -1, bus + ": mixer bus exists")
	assert_eq(AudioServer.is_bus_mute(index), muted, bus + ": mixer mute")
	assert_almost_eq(
		db_to_linear(AudioServer.get_bus_volume_db(index)), volume, 0.00001, bus + ": mixer volume"
	)


func _assert_saved_state(bus: String, volume: float, muted: bool) -> void:
	var config: ConfigFile = ConfigFile.new()
	assert_eq(config.load_encrypted_pass(TEST_CONFIG_PATH, Globals.save_encryption_pass), OK)
	var keys: Dictionary = AudioConstants.BUS_CONFIG[bus]
	assert_eq(config.get_value("audio", keys["volume_var"]), volume, "Saved volume")
	assert_eq(config.get_value("audio", keys["muted_var"]), muted, "Save includes auto-mute result")


func _count_confirmation_clicks() -> int:
	var count: int = 0
	for player: AudioStreamPlayer in SfxManager._sfx_pool:
		if player.playing and player.stream:
			if player.stream.resource_path == AudioConstants.SFX_DIR_PATH + "check.wav":
				count += 1
	return count


## Bind the observer's dependencies directly; _ready(), focus setup and dialogs are irrelevant.
func _create_observer() -> Control:
	var menu: Control = autofree(MENU_SCRIPT.new())
	for bus: String in ALL_BUSES:
		menu.set(SLIDER_PROPERTIES[bus], _slider(bus))
	return menu


## Explicit programmatic updates stay silent even when both manual-intent flags are set.
## The exact threshold is inclusive; subsequent near-zero changes cannot toggle mute again.
func test_programmatic_threshold_cycle_ignores_focus_and_drag(
	bus: String = use_parameters(ALL_BUSES)
) -> void:
	var slider: VolumeSlider = _slider(bus)
	slider.grab_focus()
	slider._is_dragging = true
	watch_signals(slider)
	watch_signals(AudioManager)
	var threshold: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD

	slider.set_value_programmatically(threshold)
	_assert_bus_state(bus, threshold, true)
	slider.set_value_programmatically(threshold / 2.0)
	slider.set_value_programmatically(0.0)
	assert_signal_emit_count(AudioManager, "mute_toggled", 1)
	slider.set_value_programmatically(threshold * 2.0)
	_assert_bus_state(bus, threshold * 2.0, false)
	assert_signal_emit_count(AudioManager, "mute_toggled", 2)
	assert_eq(slider.value, threshold * 2.0)
	assert_eq(slider.get_previous_value(), threshold * 2.0)
	assert_signal_not_emitted(slider, "value_changed")
	assert_true(slider.save_debounce_timer.is_stopped())
	assert_false(FileAccess.file_exists(TEST_CONFIG_PATH), "Programmatic slider changes do not save")
	assert_false(SfxManager.is_any_sfx_playing(), "Programmatic changes never play feedback")


func test_programmatic_out_of_range_values_clamp_before_auto_mute(
	bus: String = use_parameters(ALL_BUSES)
) -> void:
	var slider: VolumeSlider = _slider(bus)
	slider.set_value_programmatically(-1.0)
	_assert_bus_state(bus, 0.0, true)
	assert_eq(slider.value, 0.0)
	assert_eq(slider.get_previous_value(), 0.0)
	slider.set_value_programmatically(2.0)
	_assert_bus_state(bus, 1.0, false)
	assert_eq(slider.value, 1.0)
	assert_eq(slider.get_previous_value(), 1.0)
	assert_true(slider.save_debounce_timer.is_stopped())
	assert_false(SfxManager.is_any_sfx_playing())


func test_programmatic_audible_change_preserves_explicit_mute(
	bus: String = use_parameters(ALL_BUSES)
) -> void:
	AudioManager.set_muted(bus, true)
	AudioManager.apply_all_volumes()
	watch_signals(AudioManager)
	_slider(bus).set_value_programmatically(0.33)
	_assert_bus_state(bus, 0.33, true)
	assert_signal_not_emitted(AudioManager, "mute_toggled")
	assert_false(SfxManager.is_any_sfx_playing())


func test_repeated_programmatic_value_does_not_repeat_backend_update(
	bus: String = use_parameters(ALL_BUSES)
) -> void:
	var slider: VolumeSlider = _slider(bus)
	slider.set_value_programmatically(0.33)
	watch_signals(AudioManager)
	slider.set_value_programmatically(0.33)
	_assert_bus_state(bus, 0.33, false)
	assert_signal_not_emitted(AudioManager, "volume_changed")
	assert_signal_not_emitted(AudioManager, "mute_toggled")
	assert_true(slider.save_debounce_timer.is_stopped())
	assert_false(FileAccess.file_exists(TEST_CONFIG_PATH))


## A mouse drag remains manual without keyboard focus, including the feedback hold on every
## bus the click plays through (SFX_Menu, SFX, Master; Issue #1047).
func test_unfocused_drag_to_zero_is_manual(bus: String = use_parameters(ALL_BUSES)) -> void:
	var slider: VolumeSlider = _slider(bus)
	assert_false(slider.has_focus(), "Precondition: drag has no keyboard focus")
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	slider._on_gui_input(press)
	_needs_hold_wait = bus in FEEDBACK_PATH_BUSES
	slider.value = 0.0

	assert_true(AudioManager.get_muted(bus))
	assert_eq(_count_confirmation_clicks(), 1, "Manual transition confirms exactly once")
	assert_false(slider.save_debounce_timer.is_stopped(), "Manual changes schedule persistence")
	if bus in FEEDBACK_PATH_BUSES:
		var index: int = AudioServer.get_bus_index(bus)
		assert_false(AudioServer.is_bus_mute(index), bus + " remains audible during feedback")
		assert_almost_eq(
			db_to_linear(AudioServer.get_bus_volume_db(index)),
			AudioConstants.FEEDBACK_HOLD_VOLUME_LINEAR,
			0.00001
		)
		await wait_seconds(GutTestHelper.MUTE_CUTOFF_WAIT)
		_needs_hold_wait = false
	_assert_bus_state(bus, 0.0, true)


func test_unfocused_value_signal_auto_mutes_without_feedback(
	bus: String = use_parameters(ALL_BUSES)
) -> void:
	_slider(bus).value = 0.0
	_assert_bus_state(bus, 0.0, true)
	assert_false(SfxManager.is_any_sfx_playing())
	assert_false(_slider(bus).save_debounce_timer.is_stopped())


## A synchronous observer must see the new delta baseline, and returning to the old value
## must still reach the manager instead of being discarded as a duplicate.
func test_programmatic_observer_sync_keeps_next_manual_change(
	bus: String = use_parameters(ALL_BUSES)
) -> void:
	var observed: Array[float] = []
	var slider: VolumeSlider = _slider(bus)
	_capture = func(changed_bus: String, _volume: float) -> void:
		if changed_bus == bus:
			observed.append(slider.get_previous_value())
	# Connected before the menu observer, so it sees the slider's own commit, not the
	# observer's sync_from_manager() write. Disconnected in after_each().
	AudioManager.volume_changed.connect(_capture)
	var menu: Control = _create_observer()
	AudioManager.volume_changed.connect(menu._on_global_volume_changed)
	watch_signals(AudioManager)

	slider.set_value_programmatically(0.33)
	slider.grab_focus()
	slider.value = START_VOLUME

	assert_eq(observed, [0.33, START_VOLUME], "Delta tracker is committed before observers run")
	assert_signal_emit_count(AudioManager, "volume_changed", 2)
	_assert_bus_state(bus, START_VOLUME, false)
	assert_false(slider.save_debounce_timer.is_stopped())
	AudioManager.volume_changed.disconnect(_capture)


## No menu is connected: the bridge itself must invoke the rule and save its final result.
func test_bridge_threshold_crossing_mutes_and_persists_without_menu(
	bus: String = use_parameters(ALL_BUSES)
) -> void:
	var threshold: float = AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD
	_bridge._on_change_volume_js([threshold], bus)
	_assert_bus_state(bus, threshold, true)
	_assert_saved_state(bus, threshold, true)
	assert_false(SfxManager.is_any_sfx_playing())


func test_bridge_upward_crossing_unmutes_and_persists_without_menu(
	bus: String = use_parameters(ALL_BUSES)
) -> void:
	AudioManager.set_bus_state(bus, 0.0, true)
	AudioManager.apply_all_volumes()
	_bridge._on_change_volume_js([0.33], bus)
	_assert_bus_state(bus, 0.33, false)
	_assert_saved_state(bus, 0.33, false)
	assert_false(SfxManager.is_any_sfx_playing())


func test_bridge_audible_change_preserves_explicit_mute(
	bus: String = use_parameters(ALL_BUSES)
) -> void:
	AudioManager.set_muted(bus, true)
	AudioManager.apply_all_volumes()
	watch_signals(AudioManager)
	_bridge._on_change_volume_js([0.33], bus)
	_assert_bus_state(bus, 0.33, true)
	_assert_saved_state(bus, 0.33, true)
	assert_signal_not_emitted(AudioManager, "mute_toggled")
	assert_false(SfxManager.is_any_sfx_playing())


## A bridge raise during a manual Master hold must survive its stale completion timer.
func test_bridge_raise_during_slider_hold_wins() -> void:
	var master: String = AudioConstants.BUS_MASTER
	_slider(master).grab_focus()
	_needs_hold_wait = true
	_slider(master).value = 0.0
	SfxManager.stop_all_sfx()
	_bridge._on_change_volume_js([0.33], master)
	_assert_bus_state(master, 0.33, false)
	assert_false(SfxManager.is_any_sfx_playing(), "Bridge remains silent with the slider focused")
	await wait_seconds(GutTestHelper.MUTE_CUTOFF_WAIT)
	_needs_hold_wait = false
	_assert_bus_state(master, 0.33, false)
	_assert_saved_state(master, 0.33, false)


## The observer receives raw state updates too. Crossing zero through a raw setter must
## only move the slider, even with focus; it cannot invent mute transitions or mixer writes.
func test_observer_raw_crossings_only_update_visuals(bus: String = use_parameters(ALL_BUSES)) -> void:
	var menu: Control = _create_observer()
	AudioManager.volume_changed.connect(menu._on_global_volume_changed)
	var slider: VolumeSlider = _slider(bus)
	slider.grab_focus()
	watch_signals(slider)
	watch_signals(AudioManager)

	AudioManager.set_volume(bus, 0.0)
	assert_eq(slider.value, 0.0)
	assert_eq(slider.get_previous_value(), 0.0)
	assert_false(AudioManager.get_muted(bus), "Raw setters do not apply the crossing rule")
	var index: int = AudioServer.get_bus_index(bus)
	assert_false(AudioServer.is_bus_mute(index))
	assert_almost_eq(
		db_to_linear(AudioServer.get_bus_volume_db(index)), START_VOLUME, 0.00001,
		"Observer leaves the mixer at its previous volume"
	)
	AudioManager.set_muted(bus, true)
	AudioManager.apply_volume_to_bus(bus, 0.0, true)
	AudioManager.set_volume(bus, 0.33)
	assert_eq(slider.value, 0.33)
	assert_eq(slider.get_previous_value(), 0.33)
	assert_true(AudioManager.get_muted(bus), "Observer cannot auto-unmute a raw update")
	assert_true(AudioServer.is_bus_mute(index))
	assert_eq(db_to_linear(AudioServer.get_bus_volume_db(index)), 0.0, "Observer leaves mixer alone")
	assert_signal_emit_count(AudioManager, "volume_changed", 2, "No observer feedback loop")
	assert_signal_emit_count(AudioManager, "mute_toggled", 1, "Only the explicit mute was emitted")
	assert_signal_not_emitted(slider, "value_changed")
	assert_true(slider.save_debounce_timer.is_stopped())
	assert_false(SfxManager.is_any_sfx_playing())
	assert_false(FileAccess.file_exists(TEST_CONFIG_PATH))
	for other: String in ALL_BUSES:
		if other != bus:
			assert_almost_eq(_slider(other).value, START_VOLUME, 0.00001, "Other sliders stay put")


## Plain HSliders are supported by the visual observer as well as VolumeSlider components.
func test_observer_plain_slider_does_not_emit_or_write_audio() -> void:
	var menu: Control = _create_observer()
	var plain: HSlider = autofree(HSlider.new())
	plain.max_value = 1.0
	plain.step = 0.0
	plain.value = START_VOLUME
	menu.master_slider = plain
	watch_signals(plain)
	watch_signals(AudioManager)
	menu._on_global_volume_changed(AudioConstants.BUS_MASTER, 0.0)
	assert_eq(plain.value, 0.0)
	assert_signal_not_emitted(plain, "value_changed")
	assert_signal_not_emitted(AudioManager, "volume_changed")
	assert_signal_not_emitted(AudioManager, "mute_toggled")
	_assert_bus_state(AudioConstants.BUS_MASTER, START_VOLUME, false)
	assert_false(SfxManager.is_any_sfx_playing())


func test_observer_missing_slider_is_a_noop() -> void:
	var menu: Control = _create_observer()
	menu.music_slider = null
	watch_signals(AudioManager)
	menu._on_global_volume_changed(AudioConstants.BUS_MUSIC, 0.0)
	_assert_bus_state(AudioConstants.BUS_MUSIC, START_VOLUME, false)
	assert_signal_not_emitted(AudioManager, "volume_changed")
	assert_signal_not_emitted(AudioManager, "mute_toggled")
	assert_false(SfxManager.is_any_sfx_playing())
