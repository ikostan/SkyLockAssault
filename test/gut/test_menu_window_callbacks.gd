## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_menu_window_callbacks.gd
##
## WCB: menus clear their `window.*` callbacks when freed (#1166).
##
## Options and Key Mapping use wrapper doubles, so they run their real web paths here. Main and
## Pause still call JavaScriptBridge directly (wrappers are deferred to the JS separation work),
## so their tests inject the `window` Dictionary that _ready() would store on web.

extends "res://addons/gut/test.gd"

const MAIN_MENU_SCENE: String = "res://scenes/main_menu.tscn"
const OPTIONS_CALLBACKS: Array[String] = [
	"optionsBackPressed", "controlsPressed", "audioPressed", "advancedPressed", "gameplayPressed"
]
const MAIN_CALLBACKS: Array[String] = ["startPressed", "optionsPressed", "quitPressed"]
const PAUSE_CALLBACKS: Array[String] = [
	"togglePause", "mainMenuPressed", "resumePressed", "pauseOptionsPressed"
]

## Shared fake JS `window`. Non-empty, so `if js_window:` is true.
var _window: Dictionary


func before_each() -> void:
	Globals.hidden_menus.clear()
	Globals.settings.current_log_level = Globals.LogLevel.NONE
	_window = {"is_valid_mock": true}


func after_each() -> void:
	Globals.hidden_menus.clear()
	Globals.options_open = false
	Globals.options_instance = null
	get_tree().paused = false
	Globals.settings.current_log_level = Globals.LogLevel.DEBUG


# ==============================================================================
# HELPERS
# ==============================================================================


## Injects OS/JS wrapper doubles into a menu that supports them, before _ready() runs.
func _inject_wrappers(menu: Node, on_web: bool) -> void:
	var mock_os: Variant = double(OSWrapper).new()
	stub(mock_os, "has_feature").to_return(on_web)
	var mock_js: Variant = double(JavaScriptBridgeWrapper).new()
	stub(mock_js, "get_interface").to_return(_window)
	stub(mock_js, "create_callback").to_return("mock_callback")
	menu.os_wrapper = mock_os
	menu.js_bridge_wrapper = mock_js


func _add_options(on_web: bool = true) -> CanvasLayer:
	var menu: CanvasLayer = load(GamePaths.OPTIONS_MENU_SCENE).instantiate()
	_inject_wrappers(menu, on_web)
	add_child_autofree(menu)
	return menu


func _add_key_mapping(on_web: bool = true) -> CanvasLayer:
	var menu: CanvasLayer = load(GamePaths.KEY_MAPPING_SCENE).instantiate()
	_inject_wrappers(menu, on_web)
	add_child_autofree(menu)
	return menu


## Removes a menu from the tree, which runs its _exit_tree() like a scene change does.
## Waits a frame first, so the focus calls the menu deferred in _ready() run while it's
## still in the tree.
func _exit(menu: Node) -> void:
	await get_tree().process_frame
	menu.get_parent().remove_child(menu)


func _assert_window_values(names: Array[String], expected: Variant, context: String) -> void:
	for callback_name: String in names:
		assert_eq(_window.get(callback_name, "missing"), expected, context + ": " + callback_name)


## Puts registered-looking callbacks on the fake window, as Main/Pause _ready() would on web.
func _fill_window(names: Array[String]) -> void:
	for callback_name: String in names:
		_window[callback_name] = "registered"


# ==============================================================================
# OPTIONS MENU
# ==============================================================================


## WCB-01 | Freeing Options clears its five callbacks and drops the stored refs
func test_wcb_01_options_exit_clears_callbacks() -> void:
	var menu: CanvasLayer = _add_options()
	_assert_window_values(OPTIONS_CALLBACKS, "mock_callback", "Registered on web")

	await _exit(menu)

	_assert_window_values(OPTIONS_CALLBACKS, null, "Cleared on exit")
	# The exit can run inside one of these callbacks, so the refs outlive the current call.
	assert_eq(menu._options_back_button_pressed_cb, "mock_callback", "Ref kept this frame")
	await get_tree().process_frame
	assert_null(menu._options_back_button_pressed_cb)
	assert_null(menu._controls_pressed_cb)
	assert_null(menu._audio_pressed_cb)
	assert_null(menu._advanced_pressed_cb)
	assert_null(menu._gameplay_settings_pressed_cb)


## WCB-02 | Options Back clears the callbacks straight away, before the deferred free
func test_wcb_02_options_back_clears_callbacks_immediately() -> void:
	var menu: CanvasLayer = _add_options()

	menu._on_options_back_button_pressed()

	assert_true(menu.is_queued_for_deletion())
	_assert_window_values(OPTIONS_CALLBACKS, null, "Cleared on Back")


## WCB-03 | Reopening Options straight after Back keeps the new instance's callbacks
func test_wcb_03_options_reopened_after_back_keeps_new_callbacks() -> void:
	var old_menu: CanvasLayer = _add_options()
	old_menu._on_options_back_button_pressed()  # queue_free(): still in the tree this frame
	_add_options()  # the new instance registers before the old one is freed

	await get_tree().process_frame  # the old instance's _exit_tree() runs now

	assert_false(is_instance_valid(old_menu), "Old Options instance was freed")
	_assert_window_values(OPTIONS_CALLBACKS, "mock_callback", "New instance keeps its callbacks")


## WCB-04 | Off web: freeing Options touches no window and drops the refs
func test_wcb_04_options_off_web_no_window_changes() -> void:
	var menu: CanvasLayer = _add_options(false)
	menu.js_window = _window  # even if a window were set, the web check comes first
	_window["optionsBackPressed"] = "untouched"

	await _exit(menu)

	assert_eq(_window["optionsBackPressed"], "untouched")
	assert_false(_window.has("audioPressed"), "No window keys are written off web")
	await get_tree().process_frame
	assert_null(menu._options_back_button_pressed_cb)


## WCB-05 | Options cleanup is safe to call twice
func test_wcb_05_options_cleanup_twice_is_safe() -> void:
	var menu: CanvasLayer = _add_options()

	menu._unset_options_menu_window_callbacks()
	menu._unset_options_menu_window_callbacks()
	await get_tree().process_frame

	_assert_window_values(OPTIONS_CALLBACKS, null, "Still cleared")
	assert_null(menu._audio_pressed_cb)


# ==============================================================================
# KEY MAPPING
# ==============================================================================


## WCB-06 | Key Mapping Back clears controlsBackPressed
func test_wcb_06_key_mapping_back_clears_callback() -> void:
	var menu: CanvasLayer = _add_key_mapping()
	assert_eq(_window.get("controlsBackPressed"), "mock_callback", "Registered on web")

	menu._on_controls_back_button_pressed()

	assert_null(_window["controlsBackPressed"])
	# Back runs inside this callback when pressed from JS: the ref must outlive the call.
	assert_eq(menu._controls_back_button_pressed_cb, "mock_callback", "Ref kept this frame")


## WCB-07 | Unexpected Key Mapping exit (no Back) clears controlsBackPressed
func test_wcb_07_key_mapping_unexpected_exit_clears_callback() -> void:
	var menu: CanvasLayer = _add_key_mapping()

	await _exit(menu)

	assert_false(menu._intentional_exit, "Exit did not go through Back")
	assert_null(_window["controlsBackPressed"])
	await get_tree().process_frame
	assert_null(menu._controls_back_button_pressed_cb)


## WCB-08 | Key Mapping reopened in the same frame as Back keeps the new instance's callback
func test_wcb_08_key_mapping_reopened_after_back_keeps_new_callback() -> void:
	var old_menu: CanvasLayer = _add_key_mapping()
	old_menu._on_controls_back_button_pressed()  # clears now, frees at end of frame
	var new_menu: CanvasLayer = _add_key_mapping()
	assert_eq(_window["controlsBackPressed"], "mock_callback", "New instance registered")

	await get_tree().process_frame  # the old instance's _exit_tree() runs now

	assert_false(is_instance_valid(old_menu), "Old Key Mapping instance was freed")
	assert_eq(_window["controlsBackPressed"], "mock_callback", "Old exit kept the new callback")
	assert_eq(new_menu._controls_back_button_pressed_cb, "mock_callback")


## WCB-09 | Off web: freeing Key Mapping touches no window
func test_wcb_09_key_mapping_off_web_no_window_changes() -> void:
	var menu: CanvasLayer = _add_key_mapping(false)
	menu.js_window = _window
	_window["controlsBackPressed"] = "untouched"

	await _exit(menu)

	assert_eq(_window["controlsBackPressed"], "untouched")
	await get_tree().process_frame
	assert_null(menu._controls_back_button_pressed_cb)


## WCB-10 | Key Mapping cleanup is safe to call twice
func test_wcb_10_key_mapping_cleanup_twice_is_safe() -> void:
	var menu: CanvasLayer = _add_key_mapping()

	menu._unset_key_mapping_window_callbacks()
	menu._unset_key_mapping_window_callbacks()
	await get_tree().process_frame

	assert_null(_window["controlsBackPressed"])
	assert_null(menu._controls_back_button_pressed_cb)


# ==============================================================================
# MAIN MENU
# ==============================================================================


## WCB-11 | Freeing the main menu clears its three callbacks and drops the stored refs
func test_wcb_11_main_menu_exit_clears_callbacks() -> void:
	var menu: Control = load(MAIN_MENU_SCENE).instantiate()
	add_child_autofree(menu)
	menu._js_window = _window  # what _ready() stores on web
	_fill_window(MAIN_CALLBACKS)

	await _exit(menu)

	_assert_window_values(MAIN_CALLBACKS, null, "Cleared on exit")
	await get_tree().process_frame
	assert_null(menu._start_pressed_cb)
	assert_null(menu._options_pressed_cb)
	assert_null(menu._quit_pressed_cb)


## WCB-12 | Off web the main menu stores no window, so freeing it changes nothing
func test_wcb_12_main_menu_off_web_no_window_changes() -> void:
	var menu: Control = load(MAIN_MENU_SCENE).instantiate()
	add_child_autofree(menu)
	assert_null(menu._js_window, "No window is stored off web")

	await _exit(menu)
	menu._unset_main_menu_window_callbacks()  # twice is safe
	await get_tree().process_frame

	assert_null(menu._start_pressed_cb)


## WCB-13 | A new main menu keeps its callbacks when the old one is freed first
func test_wcb_13_main_menu_reloaded_keeps_new_callbacks() -> void:
	var old_menu: Control = load(MAIN_MENU_SCENE).instantiate()
	add_child_autofree(old_menu)
	old_menu._js_window = _window
	_fill_window(MAIN_CALLBACKS)
	await _exit(old_menu)  # Start Game: the scene change frees the old menu

	_fill_window(MAIN_CALLBACKS)  # the reloaded main menu registers

	_assert_window_values(MAIN_CALLBACKS, "registered", "Reloaded main menu keeps its callbacks")


# ==============================================================================
# PAUSE MENU
# ==============================================================================


## WCB-14 | Freeing the pause menu clears its four callbacks and drops the stored refs
func test_wcb_14_pause_menu_exit_clears_callbacks() -> void:
	var menu: CanvasLayer = load(GamePaths.PAUSE_MENU_SCENE).instantiate()
	add_child_autofree(menu)
	menu._js_window = _window
	_fill_window(PAUSE_CALLBACKS)

	await _exit(menu)

	_assert_window_values(PAUSE_CALLBACKS, null, "Cleared on exit")
	await get_tree().process_frame
	assert_null(menu._toggle_pause_cb)
	assert_null(menu._back_to_main_cb)
	assert_null(menu._resume_cb)
	assert_null(menu._options_cb)


## WCB-15 | Off web the pause menu stores no window; its cleanup is safe to call twice
func test_wcb_15_pause_menu_off_web_and_twice_is_safe() -> void:
	var menu: CanvasLayer = load(GamePaths.PAUSE_MENU_SCENE).instantiate()
	add_child_autofree(menu)
	assert_null(menu._js_window, "No window is stored off web")

	await _exit(menu)
	menu._unset_pause_menu_window_callbacks()
	await get_tree().process_frame

	assert_null(menu._toggle_pause_cb)
