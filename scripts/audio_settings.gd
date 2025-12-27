## audio_settings.gd"
## Audio Settings Script
##
## Handles back navigation in audio menu.
##
## Supports web overlays, ignores pause mode.
##
## Saves/restores previous JS back callback on web.
##
## :vartype js_window: Variant
## :vartype _audio_back_button_pressed_cb: Variant
## :vartype _previous_back_pressed_cb: Variant
## :vartype audio_back_button: Button

extends Control

# global
var js_window: Variant
var os_wrapper: OSWrapper = OSWrapper.new()
var js_bridge_wrapper: JavaScriptBridgeWrapper = JavaScriptBridgeWrapper.new()
# local
var _audio_back_button_pressed_cb: Variant
var _previous_back_pressed_cb: Variant

@onready var audio_back_button: Button = $Panel/OptionsVBoxContainer/AudioBackButton


func _ready() -> void:
	## Initializes audio menu.
	##
	## Connects signals, configures process mode.
	##
	## Toggles web overlays if on web.
	##
	## :rtype: void
	audio_back_button.pressed.connect(_on_audio_back_button_pressed)
	tree_exited.connect(_on_tree_exited)
	process_mode = Node.PROCESS_MODE_ALWAYS
	Globals.log_message("Audio menu loaded.", Globals.LogLevel.DEBUG)

	if os_wrapper.has_feature("web"):
		(
			js_bridge_wrapper
			. eval(
				"""
				document.getElementById('audio-back-button').style.display = 'block';
				""",
				true
			)
		)
		js_window = js_bridge_wrapper.get_interface("window")
		_audio_back_button_pressed_cb = js_bridge_wrapper.create_callback(
			Callable(self, "_on_audio_back_button_pressed_js")
		)
		_previous_back_pressed_cb = js_window.backPressed  # Save previous before overwrite
		js_window.backPressed = _audio_back_button_pressed_cb  # Set audio callback


func _on_audio_back_button_pressed() -> void:
	## Handles Back button press.
	##
	## Shows previous menu from stack, removes audio menu.
	##
	## Hides web overlays if on web.
	##
	## :rtype: void
	Globals.log_message("Back (audio_back_button) button pressed in audio.", Globals.LogLevel.DEBUG)
	if not Globals.hidden_menus.is_empty():
		var prev_menu: Node = Globals.hidden_menus.pop_back()
		if is_instance_valid(prev_menu):
			prev_menu.visible = true
			Globals.log_message("Showing menu: " + prev_menu.name, Globals.LogLevel.DEBUG)
	if os_wrapper.has_feature("web"):
		js_window.backPressed = _previous_back_pressed_cb  # Restore previous callback
		(
			js_bridge_wrapper
			. eval(
				"""
				document.getElementById('audio-back-button').style.display = 'none';
				"""
			)
		)
	queue_free()


func _on_audio_back_button_pressed_js(args: Array) -> void:
	## JS callback for back press.
	##
	## Routes to signal handler.
	##
	## :param args: Unused array from JS.
	## :type args: Array
	## :rtype: void
	Globals.log_message(
		"JS _audio_back_button_pressed_cb callback called with args: " + str(args),
		Globals.LogLevel.DEBUG
	)
	_on_audio_back_button_pressed()


func _on_tree_exited() -> void:
	## Handles unexpected tree exit.
	##
	## Restores previous menu if not already handled.
	##
	## :rtype: void
	if os_wrapper.has_feature("web"):
		js_window.backPressed = _previous_back_pressed_cb  # Restore previous callback
		(
			js_bridge_wrapper
			. eval(
				"""
				document.getElementById('audio-back-button').style.display = 'none';
				"""
			)
		)

	if not Globals.hidden_menus.is_empty():
		var prev_menu: Node = Globals.hidden_menus.pop_back()
		if is_instance_valid(prev_menu):
			prev_menu.visible = true
			Globals.log_message(
				"Audio menu exited unexpectedly, restored previous menu.", Globals.LogLevel.WARNING
			)
