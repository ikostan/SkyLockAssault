## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## Options Menu Script
##
## Handles log level selection, difficulty adjustment, and back navigation
## in the options menu.
##
## Supports web overlays for UI interactions and ignores pause mode.
##
## :vartype log_level_display_to_enum: Dictionary
## :vartype log_lvl_option: OptionButton
## :vartype back_button: Button
## :vartype difficulty_slider: HSlider
## :vartype difficulty_label: Label

extends CanvasLayer

## The wrappers (like JavaScriptBridgeWrapper and presumably OSWrapper)
## are designed to abstract away direct singleton calls, making the code
## easier to unit test by allowing mocks/stubs without relying on the
## actual engine singletons.
var js_bridge_wrapper: JavaScriptBridgeWrapper = JavaScriptBridgeWrapper.new()
var os_wrapper: OSWrapper = OSWrapper.new()  # Assuming OSWrapper is defined similarly
var audio_scene: PackedScene = preload("res://scenes/audio_settings.tscn")
var controls_scene: PackedScene = preload("res://scenes/key_mapping_menu.tscn")
var advanced_scene: PackedScene = preload("res://scenes/advanced_settings.tscn")
var gameplay_settings_scene: PackedScene = preload("res://scenes/gameplay_settings.tscn")
var _options_back_button_pressed_cb: JavaScriptObject
var _controls_pressed_cb: JavaScriptObject
var _audio_pressed_cb: JavaScriptObject
var _advanced_pressed_cb: JavaScriptObject
var _gameplay_settings_pressed_cb: JavaScriptObject
var _torn_down: bool = false  # Guard against multiple teardown calls

@onready var options_back_button: Button = $Panel/OptionsVBoxContainer/OptionsBackButton
@onready var audio_settings_button: Button = $Panel/OptionsVBoxContainer/AudioSettingsButton
@onready var key_mapping_button: Button = $Panel/OptionsVBoxContainer/KeyMappingButton
@onready var gameplay_settings_button: Button = $Panel/OptionsVBoxContainer/GameplaySettingsButton
@onready var advanced_settings_button: Button = $Panel/OptionsVBoxContainer/AdvancedSettingsButton
@onready var version_label: Label = $Panel/OptionsVBoxContainer/VersionLabel
@onready var options_vbox: VBoxContainer = $Panel/OptionsVBoxContainer


func _ready() -> void:
	## Initializes the options menu when the node enters the scene tree.
	##
	## Populates the log level options, sets initial values, connects signals,
	## and configures process mode.
	##
	## Toggles web overlays to visible layout (but still invisible visually) if on web.
	## Exposes functions to JS for web overlays if on web.
	##
	## :rtype: void

	# Game version
	version_label.text = "Version: " + Globals.get_game_version()
	Globals.log_message("Updated label to: " + version_label.text, Globals.LogLevel.DEBUG)

	if not options_back_button.pressed.is_connected(_on_options_back_button_pressed):
		options_back_button.pressed.connect(_on_options_back_button_pressed)

	if not key_mapping_button.pressed.is_connected(_on_key_mapping_button_pressed):
		key_mapping_button.pressed.connect(_on_key_mapping_button_pressed)

	if not audio_settings_button.pressed.is_connected(_on_audio_settings_button_pressed):
		audio_settings_button.pressed.connect(_on_audio_settings_button_pressed)

	if not gameplay_settings_button.pressed.is_connected(_on_gameplay_settings_button_pressed):
		gameplay_settings_button.pressed.connect(_on_gameplay_settings_button_pressed)

	if not advanced_settings_button.pressed.is_connected(_on_advanced_settings_button_pressed):
		advanced_settings_button.pressed.connect(_on_advanced_settings_button_pressed)

	# Configure for web overlays (invisible but positioned)
	process_mode = Node.PROCESS_MODE_ALWAYS  # Ignore pause
	Globals.log_message("Options menu loaded.", Globals.LogLevel.DEBUG)

	if os_wrapper.has_feature("web"):
		# Toggle overlays...
		(
			js_bridge_wrapper
			. eval(
				"""
				document.getElementById('controls-button').style.display = 'block';
				document.getElementById('audio-button').style.display = 'block';
				document.getElementById('advanced-button').style.display = 'block';
				document.getElementById('gameplay-button').style.display = 'block';
				document.getElementById('options-back-button').style.display = 'block';
				""",
				true
			)
		)

		# Expose callbacks to JS (store refs to prevent GC)
		var js_window: JavaScriptObject = js_bridge_wrapper.get_interface("window")
		if js_window:
			_options_back_button_pressed_cb = js_bridge_wrapper.create_callback(
				Callable(self, "_on_options_back_button_pressed_js")
			)
			js_window.optionsBackPressed = _options_back_button_pressed_cb

			_controls_pressed_cb = js_bridge_wrapper.create_callback(
				Callable(self, "_on_controls_pressed_js")
			)
			js_window.controlsPressed = _controls_pressed_cb

			_audio_pressed_cb = js_bridge_wrapper.create_callback(
				Callable(self, "_on_audio_pressed_js")
			)
			js_window.audioPressed = _audio_pressed_cb

			_advanced_pressed_cb = js_bridge_wrapper.create_callback(
				Callable(self, "_on_advanced_pressed_js")
			)
			js_window.advancedPressed = _advanced_pressed_cb

			_gameplay_settings_pressed_cb = js_bridge_wrapper.create_callback(
				Callable(self, "_on_gameplay_settings_pressed_js")
			)
			js_window.gameplayPressed = _gameplay_settings_pressed_cb

			Globals.log_message(
				"Exposed options menu callbacks to JS for web overlays.", Globals.LogLevel.DEBUG
			)
	_torn_down = false  # Reset guard on ready
	_grab_first_button_focus()  # Dynamically grab focus on the first button


func _grab_first_button_focus() -> void:
	## Dynamically grabs focus on the first Button child in the OptionsVBoxContainer.
	##
	## Skips non-Button nodes like Labels.
	##
	## :rtype: void
	for child in options_vbox.get_children():
		if child is Button:
			child.grab_focus()
			Globals.log_message("Grabbed initial focus on: " + child.name, Globals.LogLevel.DEBUG)
			return
	Globals.log_message(
		"No Button found in OptionsVBoxContainer for initial focus!", Globals.LogLevel.WARNING
	)


func _input(event: InputEvent) -> void:
	## Handles input events for the options menu.
	##
	## Logs mouse click positions for debugging.
	##
	## :param event: The input event to process.
	## :type event: InputEvent
	## :rtype: void
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos: Vector2 = event.position  # Explicitly type as Vector2
		Globals.log_message("Clicked at: (%s, %s)" % [pos.x, pos.y], Globals.LogLevel.DEBUG)


func _teardown() -> void:
	## Cleans up on options close.
	##
	## Shows previous menu from stack, resets globals,
	## and restores focus to the Options button if it's a menu with the group.
	##
	## :rtype: void
	if _torn_down:
		return
	_torn_down = true
	if not Globals.hidden_menus.is_empty():
		var prev_menu: Node = Globals.hidden_menus.pop_back()
		if is_instance_valid(prev_menu):
			prev_menu.visible = true
			Globals.log_message("Showing menu: " + prev_menu.name, Globals.LogLevel.DEBUG)

			# Unified check using the "MenuWithOptions" group you added in Editor
			if prev_menu.is_in_group("MenuWithOptions"):
				# Log context for debug (pause vs main, using node name)
				var log_context: String = (
					"from " + ("PAUSE menu" if prev_menu.name == "PauseMenu" else "MAIN menu")
				)
				_grab_options_focus(prev_menu, log_context)
			else:
				Globals.log_message(
					"No MenuWithOptions group on " + prev_menu.name + " - skipping focus grab",
					Globals.LogLevel.DEBUG
				)

	Globals.options_open = false
	Globals.options_instance = null
	Globals.log_message("Options menu exited.", Globals.LogLevel.DEBUG)


func _grab_options_focus(menu_node: Node, log_context: String) -> void:
	## Helper to grab focus on OptionsButton.
	##
	## Validates and logs for easy debugging.
	##
	## :param menu_node: Menu node with the button.
	## :type menu_node: Node
	## :param log_context: Debug context (e.g., "from MAIN menu").
	## :type log_context: String
	## :rtype: void
	var options_btn: Button = menu_node.get_node_or_null("VBoxContainer/OptionsButton")
	if is_instance_valid(options_btn):
		options_btn.call_deferred("grab_focus")  # Deferred to ensure after visibility change
		Globals.log_message(
			"Grabbed focus on OPTIONS button " + log_context + "...", Globals.LogLevel.DEBUG
		)
	else:
		Globals.log_message(
			"OptionsButton not found in " + menu_node.name + " - check path or scene structure!",
			Globals.LogLevel.ERROR
		)


func _exit_tree() -> void:
	## Handles node exit from scene tree.
	##
	## Restores hidden menu, clears flags/refs, logs exit.
	##
	## :rtype: void
	_teardown()  # Centralized cleanup
	Globals.log_message("Options menu exited.", Globals.LogLevel.DEBUG)


# New: JS callback for audio button
# warning-ignore:unused_argument
func _on_audio_pressed_js(_args: Array) -> void:
	## JS callback for audio button press.
	##
	## Routes to signal handler.
	##
	## :param _args: Unused array from JS.
	## :type _args: Array
	## :rtype: void
	_on_audio_settings_button_pressed()


# New: JS callback for advanced button
# warning-ignore:unused_argument
func _on_advanced_pressed_js(_args: Array) -> void:
	## JS callback for advanced button press.
	##
	## Routes to signal handler.
	##
	## :param _args: Unused array from JS.
	## :type _args: Array
	## :rtype: void
	_on_advanced_settings_button_pressed()


# New: JS callback for gameplay settings button
# warning-ignore:unused_argument
func _on_gameplay_settings_pressed_js(_args: Array) -> void:
	## JS callback for gameplay settings button press.
	##
	## Routes to signal handler.
	##
	## :param _args: Unused array from JS.
	## :type _args: Array
	## :rtype: void
	_on_gameplay_settings_button_pressed()


# New: JS callback for controls button
# warning-ignore:unused_argument
func _on_controls_pressed_js(_args: Array) -> void:
	## JS callback for controls button press.
	##
	## Routes to signal handler.
	##
	## :param _args: Unused array from JS.
	## :type _args: Array
	## :rtype: void
	_on_key_mapping_button_pressed()


# Change: Signal handler (no arg)
func _on_options_back_button_pressed() -> void:
	## Handles the Back button press from the signal.
	##
	## Shows hidden menu if valid, logs the action, removes the options menu,
	## and hides web overlays if on web.
	##
	## :rtype: void
	Globals.log_message("Options Back button pressed.", Globals.LogLevel.DEBUG)
	_teardown()  # Centralized cleanup

	if os_wrapper.has_feature("web"):
		# Hide options overlays after closing menu
		_hide_web_overlays()

	Globals.options_open = false  # Reset flag first
	Globals.options_instance = null  # Optional: Clear ref
	queue_free()


# New: JS-specific callback (exactly one Array arg, no default)
func _on_options_back_button_pressed_js(args: Array) -> void:
	## JS callback for back button press.
	##
	## Routes to the signal handler (ignores args).
	##
	## :param args: Array (unused, from JS).
	## :type args: Array
	## :rtype: void
	Globals.log_message(
		"JS back_pressed callback called with args: " + str(args), Globals.LogLevel.DEBUG
	)
	_on_options_back_button_pressed()


func _hide_web_overlays() -> void:
	## Hides web overlays for options menu buttons.
	##
	## Executes JS to set display none for specific elements.
	##
	## :rtype: void
	if os_wrapper.has_feature("web") and js_bridge_wrapper:
		(
			js_bridge_wrapper
			. eval(
				"""
				document.getElementById('audio-button').style.display = 'none';
				document.getElementById('advanced-button').style.display = 'none';
				document.getElementById('controls-button').style.display = 'none';
				document.getElementById('gameplay-button').style.display = 'none';
				document.getElementById('options-back-button').style.display = 'none';
				""",
				true
			)
		)


func _open_sub_menu(scene: PackedScene, log_msg: String) -> void:
	## Opens a sub-menu by instantiating and adding the scene.
	##
	## Logs the action, adds instance to root, hides current menu,
	## and hides web overlays if applicable.
	##
	## :param scene: The PackedScene to instantiate.
	## :type scene: PackedScene
	## :param log_msg: The message to log.
	## :type log_msg: String
	## :rtype: void
	Globals.log_message(log_msg, Globals.LogLevel.DEBUG)
	var instance: Node = scene.instantiate()
	get_tree().root.add_child(instance)
	Globals.hidden_menus.push_back(self)
	self.visible = false
	_hide_web_overlays()


## Handles Audio button press.
## Hides options menu, loads audio settings.
## :rtype: void
func _on_audio_settings_button_pressed() -> void:
	_open_sub_menu(audio_scene, "Audio button pressed.")


## Handles Controls button press.
## Hides options menu, loads Key Mappings settings.
## :rtype: void
func _on_key_mapping_button_pressed() -> void:
	_open_sub_menu(controls_scene, "Controls button pressed.")


func _on_advanced_settings_button_pressed() -> void:
	_open_sub_menu(advanced_scene, "Advanced Settings button pressed.")


func _on_gameplay_settings_button_pressed() -> void:
	_open_sub_menu(gameplay_settings_scene, "Gameplay Settings button pressed.")
