## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_audio_settings_lifecycle.gd
##
## ASL: Audio Settings on SettingsMenuBase (#1180).
##
## ASL-01 to ASL-05: label colors (a label is yellow while its slider or mute button has
##   focus, white otherwise). Written against the old per-frame _process() polling and kept
##   unchanged for the focus-signal version, so both behave the same.
## ASL-06: after Audio leaves the tree, it has no connections left on AudioManager or
##   AudioWebBridge.
## ASL-07 to ASL-09: Back restores exactly one live menu (double press, freed entries).
## ASL-10: no per-frame work while the menu is open.
## ASL-11 to ASL-13: web overlays on Back and on unexpected exit, with an AudioWebBridge
##   double at /root/AudioWebBridge and a JS bridge double shared by the bridge and the menu.

extends "res://addons/gut/test.gd"

# ==========================================
# MOCKS
# ==========================================


## Reports the web feature, so the menu and the bridge take their web paths off web.
class MockOSWrapper:
	extends OSWrapper

	func has_feature(feature: String) -> bool:
		return feature == "web"


## Records every eval() instead of running JavaScript.
class SpyJSBridgeWrapper:
	extends JavaScriptBridgeWrapper
	var eval_calls: Array[String] = []

	func eval(code: String, _global_exec: bool = false) -> Variant:
		eval_calls.append(code)
		return null


## AudioWebBridge double: skips the real _ready() (it frees itself off web and registers JS
## callbacks) and records toggle_dom_visibility() instead of sending 14 evals.
class SpyBridge:
	extends "res://scripts/system/audio_web_bridge.gd"
	var visibility_calls: Array[bool] = []

	func _ready() -> void:
		pass

	func toggle_dom_visibility(show: bool) -> void:
		visibility_calls.append(show)


# ==========================================
# FIXTURE
# ==========================================

const YELLOW: Color = Color("f5f50d")
const WHITE: Color = Color("ffffff")
## Two frames: the deferred initial focus grab, then one full frame of processing.
const SETTLE_FRAMES: int = 2
## [label, slider, mute button] property names on the Audio menu.
const LABEL_GROUPS: Array = [
	["master_label", "master_slider", "mute_master"],
	["music_label", "music_slider", "mute_music"],
	["sfx_label", "sfx_slider", "mute_sfx"],
	["weapon_label", "weapon_slider", "mute_weapon"],
	["rotor_label", "rotor_slider", "mute_rotor"],
	["menu_label", "menu_slider", "mute_menu"],
]

var _audio: Control
var _bridge: SpyBridge
var _js: SpyJSBridgeWrapper


func before_each() -> void:
	Globals.hidden_menus.clear()
	_audio = null
	_bridge = null
	_js = null


func after_each() -> void:
	if is_instance_valid(_audio):
		_audio.free()
	if is_instance_valid(_bridge):
		_bridge.free()
	Globals.hidden_menus.clear()
	await wait_process_frames(1)


## Opens the Audio menu. With on_web, an AudioWebBridge double is put at /root first and the
## menu gets web wrappers that share its JS double. set() is used so this also runs against
## an Audio script that has no os_wrapper / js_bridge_wrapper properties.
func _open_audio(on_web: bool = false) -> Control:
	if on_web:
		_js = SpyJSBridgeWrapper.new()
		_bridge = SpyBridge.new()
		_bridge.name = "AudioWebBridge"
		_bridge.os_wrapper = MockOSWrapper.new()
		_bridge.js_bridge_wrapper = _js
		_bridge.js_window = {"is_mock": true}  # Non-empty, so `if js_window:` is true.
		assert_null(get_tree().root.get_node_or_null("AudioWebBridge"), "No real bridge left")
		get_tree().root.add_child(_bridge)
	_audio = load(GamePaths.AUDIO_SETTINGS_SCENE).instantiate()
	if on_web:
		_audio.set("os_wrapper", MockOSWrapper.new())
		_audio.set("js_bridge_wrapper", _js)
	add_child(_audio)
	await wait_process_frames(SETTLE_FRAMES)
	return _audio


## Adds a hidden Options menu to the stack, as Options does when it opens Audio.
func _push_hidden_options() -> Node:
	var options: Node = load(GamePaths.OPTIONS_MENU_SCENE).instantiate()
	add_child_autofree(options)
	options.visible = false
	Globals.hidden_menus.push_back(options)
	return options


## Adds a hidden live Panel to the stack.
func _push_live_menu(menu_name: String) -> Panel:
	var menu := Panel.new()
	menu.name = menu_name
	add_child_autofree(menu)
	menu.visible = false
	Globals.hidden_menus.push_back(menu)
	return menu


## Pushes an entry that is freed while still on the stack.
func _push_freed_menu() -> void:
	var dead := Panel.new()
	Globals.hidden_menus.push_back(dead)
	dead.free()


## Asserts that only the labels at highlighted indexes are yellow.
func _assert_label_colors(highlighted: Array, context: String) -> void:
	for i: int in LABEL_GROUPS.size():
		var label: Label = _audio.get(LABEL_GROUPS[i][0])
		var expected: Color = YELLOW if highlighted.has(i) else WHITE
		assert_eq(
			label.modulate,
			expected,
			"%s: %s is %s" % [context, label.name, "yellow" if highlighted.has(i) else "white"]
		)


## True if signal_obj has a connection whose target is the Audio menu.
func _has_audio_connection(signal_obj: Signal) -> bool:
	for connection: Dictionary in signal_obj.get_connections():
		var target: Callable = connection["callable"]
		if target.get_object() == _audio:
			return true
	return false


## The JS that shows the five Options buttons in one eval.
func _options_restore_js() -> String:
	return SettingsMenuBase._build_overlay_js(SettingsMenuBase.OPTIONS_MENU_OVERLAY_IDS, [])


# ==========================================
# LABEL COLORS
# ==========================================


## ASL-01 | Each slider's focus highlights its own label only
func test_asl_01_slider_focus_highlights_its_label() -> void:
	await _open_audio()
	for i: int in LABEL_GROUPS.size():
		var slider: HSlider = _audio.get(LABEL_GROUPS[i][1])
		slider.grab_focus()
		await wait_process_frames(SETTLE_FRAMES)
		_assert_label_colors([i], slider.name + " focused")


## ASL-02 | Each mute button's focus highlights its own label only
func test_asl_02_mute_focus_highlights_its_label() -> void:
	await _open_audio()
	for i: int in LABEL_GROUPS.size():
		var mute: CheckButton = _audio.get(LABEL_GROUPS[i][2])
		mute.grab_focus()
		await wait_process_frames(SETTLE_FRAMES)
		_assert_label_colors([i], LABEL_GROUPS[i][2] + " focused")


## ASL-03 | Back or Reset focused: every label is white
func test_asl_03_button_focus_leaves_all_labels_white() -> void:
	await _open_audio()
	_audio.master_slider.grab_focus()
	await wait_process_frames(SETTLE_FRAMES)
	_audio.audio_back_button.grab_focus()
	await wait_process_frames(SETTLE_FRAMES)
	_assert_label_colors([], "Back focused")
	_audio.audio_reset_button.grab_focus()
	await wait_process_frames(SETTLE_FRAMES)
	_assert_label_colors([], "Reset focused")


## ASL-04 | On open, initial focus is on the Master slider and only its label is yellow
func test_asl_04_open_highlights_master_label() -> void:
	await _open_audio()
	assert_true(_audio.master_slider.has_focus(), "Initial focus on the Master slider")
	_assert_label_colors([0], "On open")


## ASL-05 | Focus leaves the menu: the last highlighted label turns white
func test_asl_05_focus_released_turns_label_white() -> void:
	await _open_audio()
	_audio.sfx_slider.grab_focus()
	await wait_process_frames(SETTLE_FRAMES)
	_audio.sfx_slider.release_focus()
	await wait_process_frames(SETTLE_FRAMES)
	_assert_label_colors([], "Focus released")


# ==========================================
# SIGNAL CLEANUP
# ==========================================


## ASL-06 | After Audio leaves the tree, nothing on AudioManager or AudioWebBridge targets it
func test_asl_06_no_connections_left_after_tree_exit() -> void:
	await _open_audio(true)
	assert_true(_has_audio_connection(AudioManager.volume_changed), "Connected while open")
	assert_true(_has_audio_connection(_bridge.web_back_requested), "Connected while open")

	remove_child(_audio)  # Leaves the tree but stays alive, so connections can be checked.

	assert_false(_has_audio_connection(AudioManager.volume_changed), "volume_changed")
	assert_false(_has_audio_connection(AudioManager.mute_toggled), "mute_toggled")
	assert_false(_has_audio_connection(_bridge.web_back_requested), "web_back_requested")
	assert_false(_has_audio_connection(_bridge.web_reset_requested), "web_reset_requested")


# ==========================================
# BACK NAVIGATION
# ==========================================


## ASL-07 | Two Back presses in one frame restore only one menu
func test_asl_07_second_back_press_restores_only_one_menu() -> void:
	await _open_audio()
	var lower: Panel = _push_live_menu("Lower")
	var nearest: Panel = _push_live_menu("Nearest")

	_audio._on_back_button_pressed()
	_audio._on_back_button_pressed()
	await wait_process_frames(1)

	assert_true(nearest.visible, "The nearest menu is shown")
	assert_false(lower.visible, "The second press does not show a second menu")
	assert_eq(Globals.hidden_menus, [lower], "Only one entry was popped")


## ASL-08 | Godot Back and browser Back in the same frame restore only one menu
func test_asl_08_godot_and_web_back_restore_only_one_menu() -> void:
	await _open_audio(true)
	var lower: Panel = _push_live_menu("Lower")
	var nearest: Panel = _push_live_menu("Nearest")

	_audio._on_back_button_pressed()
	_bridge.web_back_requested.emit()
	await wait_process_frames(1)

	assert_true(nearest.visible, "The nearest menu is shown")
	assert_false(lower.visible, "The browser Back does not show a second menu")
	assert_eq(Globals.hidden_menus, [lower], "Only one entry was popped")


## ASL-09 | A freed entry above Options is skipped and Options is shown
func test_asl_09_back_skips_freed_entry_and_shows_options() -> void:
	await _open_audio()
	var options: Node = _push_hidden_options()
	_push_freed_menu()

	_audio._on_back_button_pressed()
	await wait_process_frames(1)

	assert_false(is_instance_valid(_audio), "Audio is freed")
	assert_true(options.visible, "Options is shown")
	assert_true(Globals.hidden_menus.is_empty(), "Freed entry and Options were popped")


# ==========================================
# PER-FRAME WORK
# ==========================================


## ASL-10 | No _process() while open (label colors follow focus signals)
func test_asl_10_no_per_frame_work_while_open() -> void:
	await _open_audio()
	assert_false(_audio.has_method("_process"), "Audio defines no _process()")
	assert_false(_audio.is_processing(), "Audio is not processing every frame")


# ==========================================
# WEB OVERLAYS
# ==========================================


## ASL-11 | Back: the Audio overlay is hidden and the five Options buttons are shown
func test_asl_11_back_hides_audio_overlay_and_shows_options_buttons() -> void:
	await _open_audio(true)
	assert_eq(_bridge.visibility_calls, [true], "Audio overlay shown on open")
	var options: Node = _push_hidden_options()
	_js.eval_calls.clear()

	_audio._on_back_button_pressed()
	await wait_process_frames(1)

	assert_false(is_instance_valid(_audio), "Audio is freed")
	assert_true(options.visible, "Options is shown")
	assert_eq(_bridge.visibility_calls, [true, false], "Audio overlay hidden once")
	assert_eq(_js.eval_calls.count(_options_restore_js()), 1, "Five Options buttons shown once")


## ASL-12 | Unexpected exit: the Audio overlay is hidden and the five Options buttons are
## shown
func test_asl_12_unexpected_exit_hides_audio_overlay_and_shows_options_buttons() -> void:
	await _open_audio(true)
	var options: Node = _push_hidden_options()
	_js.eval_calls.clear()

	_audio.queue_free()
	await wait_process_frames(1)

	assert_false(is_instance_valid(_audio), "Audio is freed")
	assert_true(options.visible, "Options is shown")
	assert_eq(_bridge.visibility_calls, [true, false], "Audio overlay hidden once")
	assert_eq(_js.eval_calls.count(_options_restore_js()), 1, "Five Options buttons shown once")


## ASL-13 | Back with no menu left: Audio closes, its overlay is hidden, and the Options
## buttons are not shown (no "previous_scene" fallback, so nothing replaces the scene)
func test_asl_13_back_with_empty_stack_closes_without_options_buttons() -> void:
	var original_previous_scene: String = Globals.previous_scene
	Globals.previous_scene = ""  # The old fallback would replace the test runner's scene.
	await _open_audio(true)
	_js.eval_calls.clear()

	_audio._on_back_button_pressed()
	await wait_process_frames(1)
	Globals.previous_scene = original_previous_scene

	assert_false(is_instance_valid(_audio), "Audio is freed")
	assert_eq(_bridge.visibility_calls, [true, false], "Audio overlay hidden once")
	assert_eq(_js.eval_calls.count(_options_restore_js()), 0, "Options buttons not shown")
