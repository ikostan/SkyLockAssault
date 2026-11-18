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
	Globals.settings.current_log_level = Globals.LogLevel.NONE


func after_each() -> void:
	Globals.hidden_menus.clear()
	Globals.settings.current_log_level = Globals.LogLevel.DEBUG


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
