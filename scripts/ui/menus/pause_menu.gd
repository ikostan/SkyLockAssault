## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## Use for exiting game levels back to main menu without quitting.
## pause_menu.gd
##
## Pause menu overlay: Toggles with ESC, pauses the game tree, and handles resume/back to menu.
## Copyright (C) 2025 Egor Kostan

extends CanvasLayer

# Store JS callback objects to prevent garbage collection on Web export
# Variant (not JavaScriptObject) so tests can seed them: off web they'd always be null.
var _toggle_pause_cb: Variant
var _back_to_main_cb: Variant
var _resume_cb: Variant
var _options_cb: Variant
## JS `window` interface; only set on web. Variant so tests can inject a Dictionary.
var _js_window: Variant

@onready var resume_button: Button = $VBoxContainer/ResumeButton
@onready var back_to_main_button: Button = $VBoxContainer/BackToMainButton
@onready var options_button: Button = $VBoxContainer/OptionsButton


func _ready() -> void:
	## Initializes pause menu.
	##
	## Guards signal connects, hides menu, logs ready.
	##
	## :rtype: void
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not resume_button.pressed.is_connected(_on_resume_button_pressed):
		resume_button.pressed.connect(_on_resume_button_pressed)
	if not back_to_main_button.pressed.is_connected(_on_back_to_main_button_pressed):
		back_to_main_button.pressed.connect(_on_back_to_main_button_pressed)
	if not options_button.pressed.is_connected(_on_options_button_pressed):
		options_button.pressed.connect(_on_options_button_pressed)
	visible = false
	Globals.log_message("Pause menu is ready.", Globals.LogLevel.DEBUG)

	# Expose JS Web callbacks for automated testing & browser interaction
	if OS.get_name() == "Web":
		_js_window = JavaScriptBridge.get_interface("window")
		if _js_window:
			_toggle_pause_cb = JavaScriptBridge.create_callback(
				Callable(self, "_on_js_toggle_pause")
			)
			_js_window.togglePause = _toggle_pause_cb
			_back_to_main_cb = JavaScriptBridge.create_callback(
				Callable(self, "_on_back_to_main_button_pressed")
			)
			_js_window.mainMenuPressed = _back_to_main_cb
			_resume_cb = JavaScriptBridge.create_callback(
				Callable(self, "_on_resume_button_pressed")
			)
			_js_window.resumePressed = _resume_cb
			_options_cb = JavaScriptBridge.create_callback(
				Callable(self, "_on_options_button_pressed")
			)
			_js_window.pauseOptionsPressed = _options_cb
			Globals.log_message(
				"Exposed pause menu callbacks to JS for web overlays.", Globals.LogLevel.DEBUG
			)


## Clears the pause menu's JS entry points whenever the menu leaves the tree (#1166).
func _exit_tree() -> void:
	_unset_pause_menu_window_callbacks()


## Detaches the pause menu JS entry points from `window` and drops the callback refs.
## _js_window is only set on web, so this does nothing off web. Idempotent.
func _unset_pause_menu_window_callbacks() -> void:
	# This can run inside one of these callbacks (a JS press that frees the menu), so drop the
	# refs after the call returns: a callback must not be freed during its own call.
	_drop_pause_menu_callback_refs.call_deferred()
	if not _js_window:
		return
	_js_window.togglePause = null
	_js_window.mainMenuPressed = null
	_js_window.resumePressed = null
	_js_window.pauseOptionsPressed = null


func _drop_pause_menu_callback_refs() -> void:
	_toggle_pause_cb = null
	_back_to_main_cb = null
	_resume_cb = null
	_options_cb = null


func _unhandled_input(event: InputEvent) -> void:
	## Processes unhandled input for pause toggle.
	##
	## Ignores if hidden and options open.
	##
	## :param event: Input event.
	## :type event: InputEvent
	## :rtype: void
	if not visible and Globals.options_open:
		return
	if event.is_action_pressed("pause"):
		toggle_pause()


## Toggles pause menu visibility and pause state.
##
## Grabs focus on resume button when shown for keyboard and D-pad navigation.
func toggle_pause() -> void:
	## Toggles pause menu visibility and pause state.
	##
	## Grabs focus on resume button when shown for keyboard/D-pad navigation.
	##
	## :rtype: void
	visible = not visible
	get_tree().paused = visible
	if visible:
		Globals.ensure_initial_focus(
			resume_button, [back_to_main_button, options_button, resume_button], "Pause Menu"
		)


func _on_js_toggle_pause(_args: Array = []) -> void:
	## Handles toggle pause callback from JS bridge.
	##
	## :param _args: Optional arguments from web overlays (unused).
	## :type _args: Array
	## :rtype: void
	toggle_pause()


func _on_resume_button_pressed(_args: Array = []) -> void:
	## Handles resume button press.
	##
	## Logs and toggles pause.
	##
	## :param _args: Optional arguments from web overlays (unused).
	## :type _args: Array
	## :rtype: void
	Globals.log_message("Resume button pressed.", Globals.LogLevel.DEBUG)
	toggle_pause()


func _on_back_to_main_button_pressed(_args: Array = []) -> void:
	## Handles back to main button press.
	##
	## Unpauses, hides, loads main menu.
	##
	## :param _args: Optional arguments from web overlays (unused).
	## :type _args: Array
	## :rtype: void
	Globals.log_message("Back To Main Menu button pressed.", Globals.LogLevel.DEBUG)
	# The first press changes the scene, which takes this menu out of the tree at once. A second
	# press before it is freed (a double press or a JS burst) has no tree to unpause and must
	# not request another transition.
	if not is_inside_tree():
		Globals.log_message(
			"Back To Main Menu ignored: pause menu already left the tree.", Globals.LogLevel.DEBUG
		)
		return
	get_tree().paused = false
	visible = false
	Globals.load_scene_with_loading("res://scenes/main_menu.tscn")


func _on_options_button_pressed(_args: Array = []) -> void:
	## Handles options button press.
	##
	## Logs and loads options, hides self.
	##
	## :param _args: Optional arguments from web overlays (unused).
	## :type _args: Array
	## :rtype: void
	Globals.log_message("Options button pressed.", Globals.LogLevel.DEBUG)
	Globals.load_options(self)
