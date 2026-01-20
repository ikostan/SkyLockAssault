extends CanvasLayer

# global
var js_window: Variant
var os_wrapper: OSWrapper = OSWrapper.new()
var js_bridge_wrapper: JavaScriptBridgeWrapper = JavaScriptBridgeWrapper.new()

# local
var _controls_back_button_pressed_cb: Variant
var _intentional_exit: bool = false

@onready var controls_back_button: Button = $Panel/OptionsVBoxContainer/BtnContainer/ControlsBackButton
@onready var controls_reset_button: Button = $Panel/OptionsVBoxContainer/BtnContainer/ControlResetButton


func _ready() -> void:
	## Initializes controls menu.
	##
	## Connects signals, configures process mode.
	##
	## Toggles web overlays if on web.
	##
	## :rtype: void
	##
	# Back button
	if not controls_back_button.pressed.is_connected(_on_controls_back_button_pressed):
		controls_back_button.pressed.connect(_on_controls_back_button_pressed)

	process_mode = Node.PROCESS_MODE_ALWAYS
	Globals.log_message("Controls menu loaded.", Globals.LogLevel.DEBUG)

	if os_wrapper.has_feature("web"):
		js_window = js_bridge_wrapper.get_interface("window")
		if js_window:  # New: Null check
			(
				js_bridge_wrapper
				. eval(
					"""
					document.getElementById('controls-back-button').style.display = 'block';
					""",
					true
				)
			)
			# JS Callbacks
			_controls_back_button_pressed_cb = js_bridge_wrapper.create_callback(
				Callable(self, "_on_controls_back_button_pressed_js")
			)
			js_window.controlsBackPressed = _controls_back_button_pressed_cb


func _on_controls_back_button_pressed() -> void:
	## Handles Back button press.
	##
	## Shows previous menu from stack, removes controls menu.
	##
	## Hides web overlays if on web.
	##
	## :rtype: void
	Globals.log_message(
		"Back (controls_back_button) button pressed in controls.", Globals.LogLevel.DEBUG
	)
	var hidden_menu_found: bool = false
	if not Globals.hidden_menus.is_empty():
		var prev_menu: Node = Globals.hidden_menus.pop_back()
		if is_instance_valid(prev_menu):
			prev_menu.visible = true
			Globals.log_message("Showing menu: " + prev_menu.name, Globals.LogLevel.DEBUG)
			hidden_menu_found = true
	# Decoupled cleanup: Run if web and js_window available, but gate eval on js_bridge_wrapper
	if os_wrapper.has_feature("web") and js_window:
		js_window.controlsBackPressed = null
		# Set AUDIO & CONTROLS button visible in DOM (if bridge available for eval)
		# Hide controls-back-button even when no hidden menu is found.
		if js_bridge_wrapper:
			(
				js_bridge_wrapper
				. eval(
					"""
					document.getElementById('controls-back-button').style.display = 'none';
					""",
					true
				)
			)
			# Only showing audio/controls when a previous menu exists.
			if hidden_menu_found:
				(
					js_bridge_wrapper
					. eval(
						"""
						document.getElementById('audio-button').style.display = 'block';
						document.getElementById('controls-button').style.display = 'block';
						""",
						true
					)
				)
	if not hidden_menu_found:
		Globals.log_message("No hidden menu to show.", Globals.LogLevel.INFO)
	_intentional_exit = true
	queue_free()


func _on_controls_back_button_pressed_js(args: Array) -> void:
	## JS callback for back press.
	##
	## Routes to signal handler.
	##
	## :param args: Unused array from JS.
	## :type args: Array
	## :rtype: void
	Globals.log_message(
		"JS _controls_back_button_pressed_cb callback called with args: " + str(args),
		Globals.LogLevel.DEBUG
	)
	_on_controls_back_button_pressed()
