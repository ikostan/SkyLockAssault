## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_unmute_from_zero.gd
##
## TEST SUITE: Unmuting a bus at zero volume restores an audible level (Issue #1046).
## A bus must never end up unmuted at (near) zero volume. Unmuting from zero restores
## the last committed audible volume, or AudioConstants.UNMUTE_FROM_ZERO_FALLBACK_VOLUME
## when none is known. Covers the menu mute button, clicking a locked slider, and the
## web bridge toggleMute* callbacks.

extends "res://addons/gut/test.gd"

# ==========================================
# MOCKS
# ==========================================


## WHY: Bypasses the self-destruction check in AudioWebBridge._ready() outside web builds.
class MockOSWrapper:
	extends OSWrapper

	func has_feature(feature: String) -> bool:
		return feature == "web"


## WHY: Records the JavaScript the bridge sends to the DOM.
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

const TEST_CONFIG_PATH: String = "user://test_unmute_from_zero.cfg"
const START_VOLUME: float = 0.66

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
	SfxManager.stop_all_sfx()

	for bus: String in AudioConstants.BUS_CONFIG.keys():
		AudioManager.set_bus_state(bus, START_VOLUME, false)
	# No file yet: load resets last-audible volumes from the in-memory state above.
	AudioManager.load_volumes(TEST_CONFIG_PATH)


## Frees the menu, removes the test config and restores the original audio state.
## :rtype: void
func after_each() -> void:
	if is_instance_valid(audio_instance):
		audio_instance.queue_free()
	audio_instance = null
	await get_tree().process_frame

	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)

	SfxManager.stop_all_sfx()
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


## Puts a bus in the auto-muted-at-zero state without committing (no save).
## :rtype: void
func _force_muted_at_zero(bus_name: String) -> void:
	AudioManager.set_volume(bus_name, 0.0)
	AudioManager.set_muted(bus_name, true)
	AudioManager.apply_volume_to_bus(bus_name, 0.0, true)


## Asserts AudioServer carries the expected unmuted level for a bus.
## :rtype: void
func _assert_bus_audible_at(bus_name: String, expected: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	assert_ne(idx, -1, bus_name + " bus must exist")
	if idx == -1:
		return
	assert_false(AudioServer.is_bus_mute(idx), bus_name + " must be unmuted in AudioServer")
	assert_almost_eq(
		AudioServer.get_bus_volume_db(idx),
		linear_to_db(expected),
		0.01,
		bus_name + " AudioServer volume must match the restored level"
	)


# ==========================================
# ACCEPTANCE CRITERIA
# ==========================================


## AC1: auto-mute at 0 from 0.66, then unmute (mute button) restores 0.66.
## :rtype: void
func test_ac1_unmute_button_restores_last_audible_volume() -> void:
	await _open_menu()
	_force_muted_at_zero(AudioConstants.BUS_MUSIC)

	audio_instance.mute_music.button_pressed = true  # pressed = unmuted
	await get_tree().process_frame

	assert_false(AudioManager.music_muted, "Music must be unmuted")
	assert_almost_eq(AudioManager.music_volume, START_VOLUME, 0.0001)
	assert_almost_eq(audio_instance.music_slider.value, START_VOLUME, 0.0001)
	_assert_bus_audible_at(AudioConstants.BUS_MUSIC, START_VOLUME)


## AC1 (real-world path): dragging 0.66 -> 0 passes through near-silent steps;
## the mute button must still restore 0.66, not the last step (0.033).
## :rtype: void
func test_ac1_drag_to_zero_then_unmute_button_restores_pre_drag_volume() -> void:
	await _open_menu()
	var slider: HSlider = audio_instance.music_slider

	var step_value: float = START_VOLUME
	while step_value > 0.0:
		step_value = maxf(step_value - slider.step, 0.0)
		slider.value = step_value  # emits value_changed, like a drag

	assert_true(AudioManager.music_muted, "Precondition: drag to 0 auto-mutes")

	audio_instance.mute_music.button_pressed = true  # pressed = unmuted
	await get_tree().process_frame

	assert_false(AudioManager.music_muted, "Mute button must unmute")
	assert_almost_eq(AudioManager.music_volume, START_VOLUME, 0.0001)
	_assert_bus_audible_at(AudioConstants.BUS_MUSIC, START_VOLUME)


## Clicking a muted slider unmutes it. Only the unmute is asserted: in a real click Godot's
## own Slider input then moves the value to the click position, which headless GUT cannot
## reproduce (the gui_input signal fires before the native handler).
## :rtype: void
func test_click_on_muted_slider_unmutes() -> void:
	await _open_menu()
	audio_instance.music_slider.value = 0.0
	assert_true(AudioManager.music_muted, "Precondition: auto-muted at 0")

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	audio_instance.music_slider.gui_input.emit(click)
	await get_tree().process_frame

	assert_false(AudioManager.music_muted, "Clicking the locked slider must unmute")
	assert_true(audio_instance.music_slider.editable, "Slider must be unlocked")


## The slider's debounced save is a commit point: a level the user settles on is what an
## unmute-from-zero restores, not the level from load.
## :rtype: void
func test_debounced_slider_save_commits_last_audible_volume() -> void:
	await _open_menu()
	var slider: VolumeSlider = audio_instance.music_slider as VolumeSlider
	assert_not_null(slider, "Music slider must be a VolumeSlider")
	const SETTLED: float = 0.396  # 12 slider steps

	slider.value = SETTLED
	await get_tree().create_timer(slider.save_debounce_timer.wait_time + 0.1).timeout

	var step_value: float = SETTLED
	while step_value > 0.0:
		step_value = maxf(step_value - slider.step, 0.0)
		slider.value = step_value
	assert_true(AudioManager.music_muted, "Precondition: drag to 0 auto-mutes")

	audio_instance.mute_music.button_pressed = true
	await get_tree().process_frame

	assert_almost_eq(AudioManager.music_volume, SETTLED, 0.0001)
	_assert_bus_audible_at(AudioConstants.BUS_MUSIC, SETTLED)


## AC2: after a restart (bus saved at 0 + muted, nothing audible known) -> 0.495.
## :rtype: void
func test_ac2_unmute_at_zero_after_restart_uses_fallback() -> void:
	_force_muted_at_zero(AudioConstants.BUS_MUSIC)
	AudioManager.save_volumes(TEST_CONFIG_PATH)
	AudioManager.cleanup_for_test()  # simulate a fresh process: in-memory state lost
	AudioManager.set_bus_state(AudioConstants.BUS_MUSIC, START_VOLUME, false)
	AudioManager.load_volumes(TEST_CONFIG_PATH)
	assert_almost_eq(AudioManager.music_volume, 0.0, 0.0001, "Precondition: loaded at 0")
	await _open_menu()

	audio_instance.mute_music.button_pressed = true
	await get_tree().process_frame

	assert_false(AudioManager.music_muted)
	assert_almost_eq(
		AudioManager.music_volume, AudioConstants.UNMUTE_FROM_ZERO_FALLBACK_VOLUME, 0.0001
	)
	_assert_bus_audible_at(
		AudioConstants.BUS_MUSIC, AudioConstants.UNMUTE_FROM_ZERO_FALLBACK_VOLUME
	)


## AC3: unmuting a bus above the threshold leaves its volume unchanged.
## :rtype: void
func test_ac3_unmute_above_threshold_keeps_volume() -> void:
	await _open_menu()
	AudioManager.set_volume(AudioConstants.BUS_MUSIC, 0.264)
	audio_instance.mute_music.button_pressed = false  # mute manually
	await get_tree().process_frame
	assert_true(AudioManager.music_muted, "Precondition: muted")

	audio_instance.mute_music.button_pressed = true
	await get_tree().process_frame

	assert_false(AudioManager.music_muted)
	assert_almost_eq(AudioManager.music_volume, 0.264, 0.0001)


## AC4: web bridge unmute at zero restores the volume and the DOM slider follows.
## :rtype: void
func test_ac4_web_unmute_restores_volume_and_syncs_dom_slider() -> void:
	var bridge := _create_bridge()
	var mock_js: MockJSBridgeWrapper = bridge.js_bridge_wrapper
	_force_muted_at_zero(AudioConstants.BUS_MUSIC)
	mock_js.eval_calls.clear()

	bridge._on_toggle_mute_music_js([true])  # checked = unmuted

	assert_false(AudioManager.music_muted)
	assert_almost_eq(AudioManager.music_volume, START_VOLUME, 0.0001)
	assert_has(
		mock_js.eval_calls,
		"document.getElementById('music-slider').value = %s" % str(START_VOLUME),
		"DOM slider must follow the restored volume"
	)
	_assert_bus_audible_at(AudioConstants.BUS_MUSIC, START_VOLUME)


# ==========================================
# EDGE CASES
# ==========================================


## Web unmute at zero with nothing audible known falls back to 0.495.
## :rtype: void
func test_web_unmute_without_history_uses_fallback() -> void:
	var bridge := _create_bridge()
	AudioManager.cleanup_for_test()
	_force_muted_at_zero(AudioConstants.BUS_SFX_ROTORS)

	bridge._on_toggle_mute_rotors_js([true])

	assert_false(AudioManager.rotors_muted)
	assert_almost_eq(
		AudioManager.rotors_volume, AudioConstants.UNMUTE_FROM_ZERO_FALLBACK_VOLUME, 0.0001
	)


## Muting must not touch the volume; a later unmute above zero keeps it.
## :rtype: void
func test_web_mute_then_unmute_above_threshold_keeps_volume() -> void:
	var bridge := _create_bridge()

	bridge._on_toggle_mute_music_js([false])
	assert_true(AudioManager.music_muted)
	bridge._on_toggle_mute_music_js([true])

	assert_false(AudioManager.music_muted)
	assert_almost_eq(AudioManager.music_volume, START_VOLUME, 0.0001)


## Master: unmuting inside the 0.15 s auto-mute zeroing window must not be undone
## by the pending timer.
## :rtype: void
func test_master_unmute_during_auto_mute_window_is_not_zeroed() -> void:
	await _open_menu()
	var slider: HSlider = audio_instance.master_slider
	slider.grab_focus()  # focus path schedules the deferred zeroing

	slider.value = 0.0
	await get_tree().process_frame
	assert_true(AudioManager.master_muted, "Precondition: auto-muted")

	audio_instance.mute_master.button_pressed = true
	await get_tree().create_timer(AudioConstants.MUTE_HARDWARE_DELAY + 0.1).timeout

	assert_false(AudioManager.master_muted)
	assert_almost_eq(AudioManager.master_volume, START_VOLUME, 0.0001)
	_assert_bus_audible_at(AudioConstants.BUS_MASTER, START_VOLUME)


## Same race through the web bridge: a toggleMuteMaster unmute inside the 0.15 s window
## must also cancel the menu's pending zeroing timer (review finding on #1046/#1048).
## :rtype: void
func test_master_web_unmute_during_auto_mute_window_is_not_zeroed() -> void:
	await _open_menu()
	var bridge := _create_bridge()
	var slider: HSlider = audio_instance.master_slider
	slider.grab_focus()  # focus path schedules the deferred zeroing

	slider.value = 0.0
	await get_tree().process_frame
	assert_true(AudioManager.master_muted, "Precondition: auto-muted")

	bridge._on_toggle_mute_master_js([true])  # checked = unmuted
	await get_tree().create_timer(AudioConstants.MUTE_HARDWARE_DELAY + 0.1).timeout

	assert_false(AudioManager.master_muted)
	assert_almost_eq(AudioManager.master_volume, START_VOLUME, 0.0001)
	_assert_bus_audible_at(AudioConstants.BUS_MASTER, START_VOLUME)


## After a restore, moving the slider straight back to 0 must auto-mute again
## (the slider's delta tracker must not still think it sits at 0).
## :rtype: void
func test_slider_back_to_zero_after_restore_auto_mutes_again() -> void:
	await _open_menu()
	var slider: HSlider = audio_instance.music_slider
	slider.value = 0.0
	assert_true(AudioManager.music_muted, "Precondition: auto-muted")
	audio_instance.mute_music.button_pressed = true
	await get_tree().process_frame
	assert_almost_eq(slider.value, START_VOLUME, 0.0001, "Precondition: restored")

	slider.value = 0.0

	assert_almost_eq(AudioManager.music_volume, 0.0, 0.0001, "Manager must follow the slider")
	assert_true(AudioManager.music_muted, "Bus must auto-mute again at 0")


## Only committed volumes count: an uncommitted near-silent step does not
## replace the last audible volume.
## :rtype: void
func test_last_audible_volume_ignores_uncommitted_changes() -> void:
	AudioManager.set_volume(AudioConstants.BUS_MUSIC, 0.033)
	assert_almost_eq(
		AudioManager._get_last_audible_volume(AudioConstants.BUS_MUSIC), START_VOLUME, 0.0001
	)

	AudioManager.save_volumes(TEST_CONFIG_PATH)
	assert_almost_eq(AudioManager._get_last_audible_volume(AudioConstants.BUS_MUSIC), 0.033, 0.0001)


## The fallback sits exactly on the sliders' 0.033 step grid.
## :rtype: void
func test_fallback_volume_is_on_slider_step_grid() -> void:
	var steps: float = AudioConstants.UNMUTE_FROM_ZERO_FALLBACK_VOLUME / 0.033
	assert_almost_eq(steps, roundf(steps), 0.0001)
	assert_gt(
		AudioConstants.UNMUTE_FROM_ZERO_FALLBACK_VOLUME, AudioConstants.AUTO_MUTE_VOLUME_THRESHOLD
	)


# ==========================================
# REVIEW FINDINGS (load normalization, paused drags, range)
# ==========================================


## Writes an encrypted audio config with Music at the given state.
## :rtype: void
func _write_music_config(volume: Variant, muted: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music_volume", volume)
	cfg.set_value("audio", "music_muted", muted)
	assert_eq(cfg.save_encrypted_pass(TEST_CONFIG_PATH, Globals.ensure_encryption_key()), OK)


## Sends a left-button press or release to a slider's gui_input.
## :rtype: void
func _mouse_button(slider: HSlider, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	slider.gui_input.emit(event)


## A config saved at zero volume while unmuted loads muted (auto-mute rule), so the bus
## never starts silent-but-unmuted; unmuting then restores the fallback.
## :rtype: void
func test_load_zero_volume_unmuted_loads_muted() -> void:
	_write_music_config(0.0, false)

	AudioManager.load_volumes(TEST_CONFIG_PATH)

	assert_true(AudioManager.music_muted, "Zero volume must load muted")
	assert_almost_eq(AudioManager.music_volume, 0.0, 0.0001, "Saved volume is kept")

	AudioManager.toggle_mute(AudioConstants.BUS_MUSIC, false, false)
	assert_almost_eq(
		AudioManager.music_volume, AudioConstants.UNMUTE_FROM_ZERO_FALLBACK_VOLUME, 0.0001
	)


## Out-of-range config volumes are clamped to 0.0-1.0 on load.
## :rtype: void
func test_load_clamps_out_of_range_volume() -> void:
	_write_music_config(1.5, false)
	AudioManager.load_volumes(TEST_CONFIG_PATH)
	assert_almost_eq(AudioManager.music_volume, 1.0, 0.0001, "Above 1.0 clamps to 1.0")
	assert_false(AudioManager.music_muted)

	_write_music_config(-0.25, false)
	AudioManager.load_volumes(TEST_CONFIG_PATH)
	assert_almost_eq(AudioManager.music_volume, 0.0, 0.0001, "Below 0.0 clamps to 0.0")
	assert_true(AudioManager.music_muted, "Clamped to zero, so loaded muted")


## A volume above 1.0 set directly is never recorded as a restore value.
## :rtype: void
func test_last_audible_volume_is_clamped() -> void:
	AudioManager.set_volume(AudioConstants.BUS_MUSIC, 1.7)
	AudioManager.save_volumes(TEST_CONFIG_PATH)

	assert_almost_eq(AudioManager._get_last_audible_volume(AudioConstants.BUS_MUSIC), 1.0, 0.0001)


## A drag that pauses longer than the debounce on a near-silent step, then continues to 0,
## must still restore the pre-drag volume: no save while the pointer is held.
## :rtype: void
func test_paused_drag_does_not_commit_near_silent_step() -> void:
	await _open_menu()
	var slider: VolumeSlider = audio_instance.music_slider as VolumeSlider
	assert_not_null(slider, "Music slider must be a VolumeSlider")

	_mouse_button(slider, true)
	slider.value = 0.066
	await get_tree().create_timer(slider.save_debounce_timer.wait_time + 0.2).timeout
	assert_almost_eq(
		AudioManager._get_last_audible_volume(AudioConstants.BUS_MUSIC),
		START_VOLUME,
		0.0001,
		"No commit while the pointer is held"
	)

	slider.value = 0.033
	slider.value = 0.0
	_mouse_button(slider, false)
	assert_true(AudioManager.music_muted, "Precondition: drag to 0 auto-mutes")

	audio_instance.mute_music.button_pressed = true
	await get_tree().process_frame

	assert_almost_eq(AudioManager.music_volume, START_VOLUME, 0.0001)


## The postponed save still lands after release, committing the level the user let go at.
## :rtype: void
func test_drag_release_commits_after_debounce() -> void:
	await _open_menu()
	var slider: VolumeSlider = audio_instance.music_slider as VolumeSlider

	_mouse_button(slider, true)
	slider.value = 0.396
	await get_tree().create_timer(slider.save_debounce_timer.wait_time + 0.2).timeout
	_mouse_button(slider, false)
	await get_tree().create_timer(slider.save_debounce_timer.wait_time + 0.2).timeout

	assert_almost_eq(AudioManager._get_last_audible_volume(AudioConstants.BUS_MUSIC), 0.396, 0.0001)
