## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_toggle_mute_pipeline.gd
##
## TEST SUITE: AudioManager.toggle_mute() is the single mute pipeline (Issue #1048).
## The menu and the web bridge share one code path. Real UI presses are manual
## interactions (click + deferred hardware cutoff); the web bridge is programmatic
## (silent, immediate). Background sync never runs the pipeline, so it stays silent
## without any focus checks.

extends "res://addons/gut/test.gd"

# ==========================================
# MOCKS
# ==========================================


## WHY: Bypasses the self-destruction check in AudioWebBridge._ready() outside web builds.
class MockOSWrapper:
	extends OSWrapper

	func has_feature(feature: String) -> bool:
		return feature == "web"


## WHY: Swallows the JavaScript the bridge sends to the DOM.
class MockJSBridgeWrapper:
	extends JavaScriptBridgeWrapper
	var eval_calls: Array[String] = []
	# Non-empty: an empty Dictionary is falsy and the bridge would return early.
	var mock_window := {"is_mock": true}

	func eval(code: String, _global_exec: bool = false) -> Variant:
		eval_calls.append(code)
		return null

	func get_interface(interface: String) -> Variant:
		if interface == "window":
			return mock_window
		return null

	func create_callback(_callable: Callable) -> Variant:
		return {}


## WHY: Real JS callbacks receive a JavaScriptObject; tests pass a plain [checked] array.
class TestBridge:
	extends "res://scripts/system/audio_web_bridge.gd"

	func _validate_mute_args(args: Array) -> Variant:
		return bool(args[0])


# ==========================================
# FIXTURE
# ==========================================

const TEST_CONFIG_PATH: String = "user://test_toggle_mute_pipeline.cfg"
const BUS: String = AudioConstants.BUS_MUSIC
const START_VOLUME: float = 0.66
## Hardware cutoff delay plus a safety buffer for timer granularity.
const CUTOFF_WAIT: float = AudioConstants.MUTE_HARDWARE_DELAY + 0.1

var audio_scene: PackedScene = load(GamePaths.AUDIO_SETTINGS_SCENE)
var audio_instance: Control
var _original_config_path: String
var _original_states: Dictionary = {}


## Isolates config I/O and starts every bus unmuted at START_VOLUME.
## :rtype: void
func before_each() -> void:
	_original_config_path = AudioManager.current_config_path
	for bus: String in AudioConstants.BUS_CONFIG.keys():
		_original_states[bus] = AudioManager.get_bus_state(bus)

	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)
	Globals.set_test_encryption_key()

	for bus: String in AudioConstants.BUS_CONFIG.keys():
		AudioManager.set_bus_state(bus, START_VOLUME, false)
	AudioManager.load_volumes(TEST_CONFIG_PATH)  # no file: applies the state above
	AudioManager.stop_all_sfx()


## Lets pending cutoff timers finish, then restores the original audio state.
## :rtype: void
func after_each() -> void:
	if is_instance_valid(audio_instance):
		audio_instance.queue_free()
	audio_instance = null
	await get_tree().create_timer(CUTOFF_WAIT).timeout

	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)

	AudioManager.stop_all_sfx()
	AudioManager.current_config_path = _original_config_path
	for bus: String in _original_states.keys():
		var state: Dictionary = _original_states[bus]
		AudioManager.set_bus_state(bus, state["volume"], state["muted"])
	AudioManager.apply_all_volumes()


## Instantiates the Audio Settings menu.
## :rtype: void
func _open_menu() -> void:
	audio_instance = audio_scene.instantiate() as Control
	add_child(audio_instance)
	await get_tree().process_frame


## Instantiates the web bridge with mocked JS and OS wrappers.
## :rtype: TestBridge
func _create_bridge() -> TestBridge:
	var bridge := TestBridge.new()
	bridge.js_bridge_wrapper = MockJSBridgeWrapper.new()
	bridge.os_wrapper = MockOSWrapper.new()
	add_child_autoqfree(bridge)
	return bridge


## Returns whether AudioServer currently mutes the bus.
## :rtype: bool
func _hw_muted(bus_name: String) -> bool:
	var idx: int = AudioServer.get_bus_index(bus_name)
	assert_ne(idx, -1, bus_name + " bus must exist")
	return idx != -1 and AudioServer.is_bus_mute(idx)


## Reads the persisted mute flag for a bus from the test config.
## :rtype: Variant
func _saved_muted(bus_name: String) -> Variant:
	var data: Dictionary = Globals.safe_load_config(TEST_CONFIG_PATH)
	if data["err"] != OK:
		return null
	var key: String = AudioConstants.BUS_CONFIG[bus_name]["muted_var"]
	return (data["config"] as ConfigFile).get_value("audio", key, null)


# ==========================================
# AudioManager.toggle_mute()
# ==========================================


## Manual mute: click plays, logical state flips at once, hardware cutoff is deferred.
## :rtype: void
func test_manual_mute_clicks_and_defers_hardware_cutoff() -> void:
	AudioManager.toggle_mute(BUS, true, true)

	assert_true(AudioManager.get_muted(BUS), "Logical state flips immediately")
	assert_false(_hw_muted(BUS), "Hardware cutoff waits for the click to stream out")
	assert_true(AudioManager.is_any_sfx_playing(), "Confirmation click plays")

	await get_tree().create_timer(CUTOFF_WAIT).timeout
	assert_true(_hw_muted(BUS), "Hardware is muted after the delay")


## Programmatic mute: silent and immediate.
## :rtype: void
func test_programmatic_mute_is_silent_and_immediate() -> void:
	AudioManager.toggle_mute(BUS, true, false)

	assert_true(AudioManager.get_muted(BUS))
	assert_true(_hw_muted(BUS), "No deferral without a click")
	assert_false(AudioManager.is_any_sfx_playing(), "Programmatic toggles are silent")


## Manual unmute: click plays and the bus is audible immediately.
## :rtype: void
func test_manual_unmute_clicks_and_applies_immediately() -> void:
	AudioManager.toggle_mute(BUS, true, false)
	AudioManager.stop_all_sfx()

	AudioManager.toggle_mute(BUS, false, true)

	assert_false(AudioManager.get_muted(BUS))
	assert_false(_hw_muted(BUS), "Unmute is never deferred")
	assert_true(AudioManager.is_any_sfx_playing(), "Confirmation click plays")


## A newer toggle issued during the cutoff delay wins over the pending mute.
## :rtype: void
func test_unmute_during_cutoff_delay_is_not_overwritten() -> void:
	AudioManager.toggle_mute(BUS, true, true)
	AudioManager.toggle_mute(BUS, false, true)

	await get_tree().create_timer(CUTOFF_WAIT).timeout

	assert_false(AudioManager.get_muted(BUS))
	assert_false(_hw_muted(BUS), "Pending mute must re-read the newest (unmuted) state")


## Unmuting at zero through the pipeline restores an audible volume (Issue #1046).
## :rtype: void
func test_toggle_mute_unmute_at_zero_restores_volume() -> void:
	AudioManager.set_volume(BUS, 0.0)
	AudioManager.toggle_mute(BUS, true, false)

	AudioManager.toggle_mute(BUS, false, false)

	assert_almost_eq(AudioManager.get_volume(BUS), START_VOLUME, 0.0001)


## Unknown buses are rejected without side effects.
## :rtype: void
func test_unknown_bus_is_ignored() -> void:
	var emitted: Array = []
	var on_toggled := func(bus_name: String, is_muted: bool) -> void:
		emitted.append([bus_name, is_muted])
	AudioManager.mute_toggled.connect(on_toggled)

	AudioManager.toggle_mute("NoSuchBus", true, true)

	AudioManager.mute_toggled.disconnect(on_toggled)
	assert_eq(emitted.size(), 0, "No state change for an unknown bus")
	assert_false(AudioManager.is_any_sfx_playing(), "No click for an unknown bus")


# ==========================================
# MENU (manual interactions)
# ==========================================


## A real press clicks even when focus is elsewhere: the focus gate is gone.
## :rtype: void
func test_ui_press_clicks_regardless_of_focus() -> void:
	await _open_menu()
	audio_instance.audio_back_button.grab_focus()

	audio_instance.mute_music.button_pressed = false  # press = mute

	assert_true(AudioManager.get_muted(BUS))
	assert_true(AudioManager.is_any_sfx_playing(), "Real presses are manual interactions")
	await get_tree().create_timer(CUTOFF_WAIT).timeout
	assert_true(_hw_muted(BUS))
	assert_eq(_saved_muted(BUS), true, "Menu toggles are persisted")


## Clicking a locked slider is a manual unmute (click + immediate apply).
## :rtype: void
func test_locked_slider_click_is_manual_unmute() -> void:
	await _open_menu()
	AudioManager.toggle_mute(BUS, true, false)
	AudioManager.stop_all_sfx()

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	audio_instance.music_slider.gui_input.emit(click)
	await get_tree().process_frame

	assert_false(AudioManager.get_muted(BUS))
	assert_false(_hw_muted(BUS))
	assert_true(AudioManager.is_any_sfx_playing(), "Slider-click proxy counts as a user action")


## Background sync (e.g. reset, web bridge) never runs the pipeline: no click.
## :rtype: void
func test_background_sync_does_not_click() -> void:
	await _open_menu()

	AudioManager.set_muted(BUS, true)
	await get_tree().process_frame

	assert_false(audio_instance.mute_music.button_pressed, "Button mirrors the new state")
	assert_false(AudioManager.is_any_sfx_playing(), "Sync is silent")


# ==========================================
# WEB BRIDGE (programmatic)
# ==========================================


## Web toggles go through the shared pipeline: silent, immediate, persisted.
## :rtype: void
func test_web_mute_is_silent_immediate_and_saved() -> void:
	var bridge := _create_bridge()

	bridge._on_toggle_mute_music_js([false])  # unchecked = muted

	assert_true(AudioManager.get_muted(BUS))
	assert_true(_hw_muted(BUS), "Programmatic cutoff is immediate")
	assert_false(AudioManager.is_any_sfx_playing(), "Web toggles are silent")
	assert_eq(_saved_muted(BUS), true, "Web toggles are persisted")


## Web unmute: immediate and persisted.
## :rtype: void
func test_web_unmute_is_immediate_and_saved() -> void:
	var bridge := _create_bridge()
	AudioManager.toggle_mute(BUS, true, false)

	bridge._on_toggle_mute_music_js([true])

	assert_false(AudioManager.get_muted(BUS))
	assert_false(_hw_muted(BUS))
	assert_eq(_saved_muted(BUS), false)


## The parent-mute guard still blocks sub-bus toggles while Master is muted.
## :rtype: void
func test_web_parent_mute_guard_still_blocks() -> void:
	var bridge := _create_bridge()
	AudioManager.toggle_mute(AudioConstants.BUS_MASTER, true, false)

	bridge._on_toggle_mute_music_js([false])

	assert_false(AudioManager.get_muted(BUS), "Sub-bus must stay unchanged under a muted Master")
