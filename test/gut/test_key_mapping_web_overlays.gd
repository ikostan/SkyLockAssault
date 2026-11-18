## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_key_mapping_web_overlays.gd
##
## KM-WEB: DOM overlays Key Mapping's Back path shows and hides on web (#1165).
## Uses wrapper doubles, so these run off web.

extends "res://addons/gut/test.gd"

var _menu: CanvasLayer
var _js_bridge: Variant
var _window: Dictionary


func before_each() -> void:
	Globals.hidden_menus.clear()


func after_each() -> void:
	Globals.hidden_menus.clear()


## Adds a Key Mapping menu that believes it runs on web (or not, with on_web = false).
func _add_menu(on_web: bool = true) -> CanvasLayer:
	_menu = load(GamePaths.KEY_MAPPING_SCENE).instantiate()
	var mock_os: Variant = double(OSWrapper).new()
	stub(mock_os, "has_feature").to_return(on_web)
	_js_bridge = double(JavaScriptBridgeWrapper).new()
	# A non-empty Dictionary, so `if js_window:` is true.
	_window = {"is_valid_mock": true}
	stub(_js_bridge, "get_interface").to_return(_window)
	stub(_js_bridge, "create_callback").to_return("mock_callback")
	_menu.os_wrapper = mock_os
	_menu.js_bridge_wrapper = _js_bridge
	add_child_autofree(_menu)
	return _menu


## Adds a hidden Options menu to the menu stack, as Options does before opening Key Mapping.
func _push_hidden_options_menu() -> Node:
	var options: Node = load(GamePaths.OPTIONS_MENU_SCENE).instantiate()
	add_child_autofree(options)
	options.visible = false
	Globals.hidden_menus.push_back(options)
	return options


## The code of the last eval() call on the JS bridge double.
func _last_eval_code() -> String:
	var params: Variant = get_call_parameters(_js_bridge, "eval")
	return params[0] if params else ""


## KM-WEB-01 | Back to Options shows exactly the five Options buttons
func test_km_web_01_back_to_options_shows_five_options_buttons() -> void:
	_push_hidden_options_menu()
	_add_menu()

	_menu._on_controls_back_button_pressed()

	var code: String = _last_eval_code()
	assert_eq(
		code,
		SettingsMenuBase._build_overlay_js(
			SettingsMenuBase.OPTIONS_MENU_OVERLAY_IDS, ["controls-back-button"]
		),
		"One eval shows the five Options buttons and hides controls-back-button"
	)
	for id: String in SettingsMenuBase.OPTIONS_MENU_OVERLAY_IDS:
		assert_true(
			code.contains("getElementById('%s').style.display = 'block'" % id), id + " shown"
		)
	assert_eq(code.count("'block'"), 5, "Exactly five elements are shown")
	assert_true(code.contains("getElementById('controls-back-button').style.display = 'none'"))
	assert_false(code.contains("difficulty-slider"), "No Gameplay control is touched")


## KM-WEB-02 | Off web: Back makes no eval() call
func test_km_web_02_off_web_back_makes_no_eval_call() -> void:
	_push_hidden_options_menu()
	_add_menu(false)

	_menu._on_controls_back_button_pressed()

	assert_not_called(_js_bridge, "eval")
	assert_false(_window.has("controlsBackPressed"), "window is not touched off web")


## KM-WEB-03 | No hidden menu: Back shows none of the five, still hides controls-back-button
func test_km_web_03_no_hidden_menu_shows_no_options_buttons() -> void:
	_add_menu()

	_menu._on_controls_back_button_pressed()

	var code: String = _last_eval_code()
	assert_eq(code, SettingsMenuBase._build_overlay_js([], ["controls-back-button"]))
	assert_false(code.contains("'block'"), "No Options button is shown")


## KM-WEB-04 | Opened from the main menu's "Unbound Controls" dialog: Back shows none of the five
func test_km_web_04_back_to_main_menu_shows_no_options_buttons() -> void:
	# Globals.load_key_mapping(ui_panel) pushes the main menu's Panel, not an OptionsMenu.
	var main_panel: Panel = Panel.new()
	main_panel.name = "Panel"
	add_child_autofree(main_panel)
	main_panel.visible = false
	Globals.hidden_menus.push_back(main_panel)
	_add_menu()

	_menu._on_controls_back_button_pressed()

	assert_true(main_panel.visible, "Back returns to the main menu")
	var code: String = _last_eval_code()
	assert_eq(code, SettingsMenuBase._build_overlay_js([], ["controls-back-button"]))
	for id: String in SettingsMenuBase.OPTIONS_MENU_OVERLAY_IDS:
		assert_false(code.contains(id), id + " is not shown")


## KM-WEB-05 | A second Back before the menu is freed changes nothing: Main → Options → Key
## Mapping, Back twice in one frame, leaves Main hidden on the stack and Options shown
func test_km_web_05_second_back_before_free_is_ignored() -> void:
	var main_panel: Panel = Panel.new()
	main_panel.name = "Panel"
	add_child_autofree(main_panel)
	main_panel.visible = false
	Globals.hidden_menus.push_back(main_panel)
	var options: Node = _push_hidden_options_menu()
	_add_menu()

	_menu._on_controls_back_button_pressed()
	_menu._on_controls_back_button_pressed()  # same frame: queue_free() hasn't run yet

	assert_true(options.visible, "First Back shows Options")
	assert_false(main_panel.visible, "Second Back must not show the main menu")
	assert_eq(Globals.hidden_menus, [main_panel], "Second Back must not pop the stack")
	assert_called_count(_js_bridge.eval, 2)  # _ready() shows Back; first Back swaps overlays
	assert_eq(
		_last_eval_code(),
		SettingsMenuBase._build_overlay_js(
			SettingsMenuBase.OPTIONS_MENU_OVERLAY_IDS, ["controls-back-button"]
		),
		"The overlays stay as the first Back left them"
	)


## KM-WEB-06 | Unexpected exit (no Back) hides controls-back-button and nothing else
func test_km_web_06_unexpected_exit_hides_controls_back_button() -> void:
	_add_menu()
	await get_tree().process_frame  # let _ready()'s deferred focus calls run in the tree

	remove_child(_menu)  # leaves the tree without Back

	assert_called_count(_js_bridge.eval, 2)  # _ready() shows Back; the exit hides it
	assert_eq(_last_eval_code(), SettingsMenuBase._build_overlay_js([], ["controls-back-button"]))


## KM-WEB-07 | Exit after Back doesn't touch the overlays again: Back already hid the button,
## and a Key Mapping reopened in the same frame may have shown it again
func test_km_web_07_exit_after_back_leaves_overlays_alone() -> void:
	_push_hidden_options_menu()
	_add_menu()
	_menu._on_controls_back_button_pressed()
	var back_code: String = _last_eval_code()

	await get_tree().process_frame  # queue_free(): _exit_tree() runs now

	assert_called_count(_js_bridge.eval, 2)  # _ready() and Back only
	assert_eq(_last_eval_code(), back_code)


## KM-WEB-08 | An older Key Mapping's exit leaves the newer one's Back button shown
func test_km_web_08_older_exit_leaves_newer_back_button_shown() -> void:
	var older: CanvasLayer = _add_menu()
	var older_js: Variant = _js_bridge
	_add_menu()  # the newer instance owns window.controlsBackPressed now
	await get_tree().process_frame

	remove_child(older)

	assert_called_count(older_js.eval, 1)  # only _ready()'s show; no hide on exit
	older.free()


## KM-WEB-09 | Two Key Mappings opened from Options (Options is on the stack twice): the older
## one's Back shows no Options buttons while the newer one is still open; the newer one's Back
## then shows them and hides the Back button
func test_km_web_09_older_back_shows_no_options_buttons_over_newer() -> void:
	var options: Node = _push_hidden_options_menu()
	Globals.hidden_menus.push_back(options)  # Options pushes itself once per Key Mapping
	var older: CanvasLayer = _add_menu()
	var older_js: Variant = _js_bridge
	var newer: CanvasLayer = _add_menu()

	older._on_controls_back_button_pressed()

	for i: int in get_call_count(older_js, "eval"):
		var code: String = get_call_parameters(older_js, "eval", i)[0]
		for id: String in SettingsMenuBase.OPTIONS_MENU_OVERLAY_IDS:
			assert_false(
				code.contains("getElementById('%s').style.display = 'block'" % id),
				id + " must stay hidden while the newer Key Mapping is open"
			)

	newer._on_controls_back_button_pressed()

	assert_eq(
		_last_eval_code(),
		SettingsMenuBase._build_overlay_js(
			SettingsMenuBase.OPTIONS_MENU_OVERLAY_IDS, ["controls-back-button"]
		),
		"The owner's Back shows the Options buttons and hides the Back button"
	)


## KM-WEB-10 | A freed entry on top of the stack is skipped: Back shows the next valid menu, shows
## no Options buttons (it isn't Options) and hides controls-back-button (#1211)
func test_km_web_10_back_skips_freed_hidden_parent() -> void:
	var outer: Panel = Panel.new()
	add_child_autofree(outer)
	outer.hide()
	Globals.hidden_menus.push_back(outer)
	var stale: Panel = Panel.new()
	Globals.hidden_menus.push_back(stale)
	stale.free()
	_add_menu()

	_menu._on_controls_back_button_pressed()

	assert_true(Globals.hidden_menus.is_empty(), "The freed entry and the outer menu are popped")
	assert_true(outer.visible, "The next valid menu is shown")
	assert_eq(_last_eval_code(), SettingsMenuBase._build_overlay_js([], ["controls-back-button"]))
	assert_null(_window["controlsBackPressed"])
	assert_true(_menu.is_queued_for_deletion())


## KM-WEB-11 | Two Back calls through the JS entry point with no menu on the stack: one overlay
## update, the callback cleared, and the menu freed
func test_km_web_11_js_back_burst_without_parent_has_one_overlay_update() -> void:
	_add_menu()

	_menu._on_controls_back_button_pressed_js([])
	_menu._on_controls_back_button_pressed_js([])

	assert_called_count(_js_bridge.eval, 2)  # ready + first Back
	assert_eq(_last_eval_code(), SettingsMenuBase._build_overlay_js([], ["controls-back-button"]))
	assert_true(Globals.hidden_menus.is_empty())
	assert_null(_window["controlsBackPressed"])
	assert_true(_menu.is_queued_for_deletion())
