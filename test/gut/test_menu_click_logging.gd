## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_menu_click_logging.gd
##
## GUT tests for #1169: the pause menu and Options no longer log every left click, and the
## main and pause menus open and close Options without their own Options scene preload.

extends GutTest


## Collects every logged line while it is added with OS.add_logger().
class LogCapture:
	extends Logger
	var lines: Array[String] = []
	var _mutex: Mutex = Mutex.new()

	func _log_message(message: String, _error: bool) -> void:
		_mutex.lock()
		lines.append(message)
		_mutex.unlock()

	func has_line_containing(text: String) -> bool:
		_mutex.lock()
		var found: bool = false
		for line: String in lines:
			if line.contains(text):
				found = true
				break
		_mutex.unlock()
		return found


var _log: LogCapture
var _original_settings: GameSettingsResource
var _original_options_open: bool
var _original_options_instance: CanvasLayer
var _original_hidden_menus: Array[Node]


func before_each() -> void:
	_original_settings = Globals.settings
	_original_options_open = Globals.options_open
	_original_options_instance = Globals.options_instance
	_original_hidden_menus = Globals.hidden_menus.duplicate()
	Globals.settings = GameSettingsResource.new()
	# DEBUG, so the old click log would have printed
	Globals.settings.current_log_level = Globals.LogLevel.DEBUG
	_log = LogCapture.new()
	OS.add_logger(_log)


func after_each() -> void:
	if _log != null:
		OS.remove_logger(_log)
		_log = null
	Globals.settings = _original_settings
	Globals.options_open = _original_options_open
	Globals.options_instance = _original_options_instance
	Globals.hidden_menus = _original_hidden_menus


## Builds a left (or right) mouse press at a corner where no button sits.
func _make_click(button_index: MouseButton = MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = true
	event.position = Vector2(1, 1)
	event.global_position = Vector2(1, 1)
	return event


## True if [param node]'s own script defines [param method].
func _script_defines(node: Node, method: String) -> bool:
	for entry: Dictionary in node.get_script().get_script_method_list():
		if entry["name"] == method:
			return true
	return false


## A left click with the pause menu open logs nothing.
func test_pause_menu_left_click_logs_nothing() -> void:
	var menu: CanvasLayer = load(GamePaths.PAUSE_MENU_SCENE).instantiate()
	add_child_autofree(menu)
	menu.visible = true
	await wait_process_frames(1)

	get_viewport().push_input(_make_click())
	get_viewport().push_input(_make_click(MOUSE_BUTTON_RIGHT))
	await wait_process_frames(1)

	assert_false(_log.has_line_containing("Clicked at"), "Pause menu must not log clicks.")
	assert_false(_script_defines(menu, "_input"), "pause_menu.gd must not define _input().")


## A left click with Options open logs nothing.
func test_options_menu_left_click_logs_nothing() -> void:
	var menu: Node = load(GamePaths.OPTIONS_MENU_SCENE).instantiate()
	add_child_autofree(menu)
	await wait_process_frames(1)

	get_viewport().push_input(_make_click())
	await wait_process_frames(1)

	assert_false(_log.has_line_containing("Clicked at"), "Options must not log clicks.")
	assert_false(_script_defines(menu, "_input"), "options_menu.gd must not define _input().")


## The main and pause menus no longer keep their own Options scene; both open Options
## through Globals.load_options().
func test_menus_do_not_preload_options_scene() -> void:
	for path: String in [GamePaths.PAUSE_MENU_SCENE, "res://scenes/main_menu.tscn"]:
		var menu: Node = load(path).instantiate()
		assert_false("options_menu" in menu, "%s must not keep an options_menu scene." % path)
		menu.free()


## Both callers still open the configured Options scene and are restored by its Back button.
func test_options_button_round_trip_without_a_menu_local_scene(
	caller: String = use_parameters(["main", "pause"])
) -> void:
	Globals.options_open = false
	Globals.options_instance = null
	Globals.hidden_menus = []
	Globals.settings.options_scene = load(GamePaths.OPTIONS_MENU_SCENE)

	var scene_path := GamePaths.PAUSE_MENU_SCENE if caller == "pause" else "res://scenes/main_menu.tscn"
	var menu: Node = load(scene_path).instantiate()
	add_child_autofree(menu)
	menu.show()
	var menu_to_hide: Node = menu if caller == "pause" else menu.ui_panel

	menu.options_button.pressed.emit()
	var options: CanvasLayer = Globals.options_instance
	assert_not_null(options, "The Options button opens the configured scene.")
	if options == null:
		return
	autoqfree(options)
	await wait_process_frames(1)
	assert_true(Globals.options_open)
	assert_false(menu_to_hide.visible, "Opening Options hides the caller.")

	options.options_back_button.pressed.emit()
	await wait_process_frames(2)
	assert_false(is_instance_valid(options), "Back closes the Options scene.")
	assert_false(Globals.options_open)
	assert_null(Globals.options_instance)
	assert_true(menu_to_hide.visible, "Back restores the caller.")
