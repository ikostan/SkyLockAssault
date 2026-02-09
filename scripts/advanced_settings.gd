extends Control

var js_bridge_wrapper: JavaScriptBridgeWrapper = JavaScriptBridgeWrapper.new()
var os_wrapper: OSWrapper = OSWrapper.new()  # Assuming OSWrapper is defined similarly
var js_window: JavaScriptObject
# Explicit mapping from display names to enum values
var log_level_display_to_enum: Dictionary = {
	"DEBUG": Globals.LogLevel.DEBUG,
	"INFO": Globals.LogLevel.INFO,
	"WARNING": Globals.LogLevel.WARNING,
	"ERROR": Globals.LogLevel.ERROR,
	"NONE": Globals.LogLevel.NONE
}
var _change_log_level_cb: JavaScriptObject
# Reset button
var _advanced_reset_cb: Variant
# Back button
var _advanced_back_button_pressed_cb: Variant
var _intentional_exit: bool = false

@onready var advanced_back_button: Button = $Panel/Controls/BtnContainer/BackButton
@onready var advanced_reset_button: Button = $Panel/Controls/BtnContainer/ResetButton
@onready
var log_lvl_option: OptionButton = get_node("Panel/Controls/LogLevelContainer/LogLevelOptionButton")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Populate Log level with all LogLevel enum values
	for level: String in Globals.LogLevel.keys():
		if level != "NONE":  # Skip auto-add NONE; add manually as "None"
			log_lvl_option.add_item(level)  # "Debug", "Info", etc.
	log_lvl_option.add_item("NONE")  # Manual for title case
	# Set to current log level (find index by enum value)
	var current_value: int = Globals.current_log_level
	var index: int = Globals.LogLevel.values().find(current_value)
	if index != -1:
		log_lvl_option.selected = index
	else:
		log_lvl_option.selected = 1  # Fallback to INFO (index 1)
		Globals.log_message("Invalid saved log level—reset to INFO.", Globals.LogLevel.WARNING)

	# Connect signals to type-specific handlers (change: separate from JS callbacks)
	tree_exited.connect(_on_tree_exited)
	log_lvl_option.item_selected.connect(_on_log_level_item_selected)

	if js_bridge_wrapper and os_wrapper.has_feature("web"):
		# Toggle overlays...
		(
			js_bridge_wrapper
			. eval(
				"""
				document.getElementById('log-level-select').style.display = 'block';
				document.getElementById('advanced-back-button').style.display = 'block';
				document.getElementById('advanced-reset-button').style.display = 'block';
				""",
				true
			)
		)

	# Expose callbacks to JS (store refs to prevent GC)
	js_window = js_bridge_wrapper.get_interface("window") as JavaScriptObject
	if js_window:
		_change_log_level_cb = js_bridge_wrapper.create_callback(
			Callable(self, "_on_change_log_level_js")
		)
		js_window.changeLogLevel = _change_log_level_cb

	# Back button
	if not advanced_back_button.pressed.is_connected(_on_advanced_back_button_pressed):
		advanced_back_button.pressed.connect(_on_advanced_back_button_pressed)

	# Reset button listener
	if not advanced_reset_button.pressed.is_connected(_on_advanced_reset_button_pressed):
		advanced_reset_button.pressed.connect(_on_advanced_reset_button_pressed)

	if os_wrapper.has_feature("web"):
		if js_window:  # New: Null check
			# JS Callbacks
			# Expose callbacks for back button
			_advanced_back_button_pressed_cb = _register_js_callback(
				"_on_advanced_back_button_pressed_js", "advancedBackPressed"
			)
			# Expose callbacks for Reset button
			_advanced_reset_cb = _register_js_callback(
				"_on_advanced_reset_js", "advancedResetPressed"
			)

	Globals.log_message("Advanced Settings menu loaded.", Globals.LogLevel.DEBUG)


## Registers a JS callback by creating and assigning it to window property.
## :param callback_method: Name of the GDScript method to call.
## :type callback_method: String
## :param window_property: Name of the JS window property to assign.
## :type window_property: String
## :rtype: Variant
func _register_js_callback(callback_method: String, window_property: String) -> Variant:
	var callback: Variant = js_bridge_wrapper.create_callback(Callable(self, callback_method))
	js_window[window_property] = callback
	return callback


func _on_tree_exited() -> void:
	if _intentional_exit:
		return
	if os_wrapper.has_feature("web") and js_window:
		_unset_advanced_window_callbacks()
	if not Globals.hidden_menus.is_empty():
		var prev_menu: Node = Globals.hidden_menus.pop_back()
		if is_instance_valid(prev_menu):
			prev_menu.visible = true
			Globals.log_message(
				"Advanced menu exited unexpectedly, restored previous menu.",
				Globals.LogLevel.WARNING
			)


## A cleanup function
func _unset_advanced_window_callbacks() -> void:
	if not os_wrapper.has_feature("web") or not js_window:
		return
	js_window.changeLogLevel = null
	js_window.advancedBackPressed = null
	js_window.advancedResetPressed = null


## RESET BUTTON
## Handles Advanced Settings reset button press.
func _on_advanced_reset_button_pressed() -> void:
	Globals.log_message("Advanced Settings reset pressed.", Globals.LogLevel.DEBUG)
	# Log level should be reset to INFO
	Globals.current_log_level = Globals.LogLevel.INFO
	log_lvl_option.selected = Globals.LogLevel.values().find(Globals.LogLevel.INFO)
	Globals._save_settings()


func _on_advanced_reset_js(_args: Array) -> void:
	_on_advanced_reset_button_pressed()


func _on_advanced_back_button_pressed() -> void:
	## Handles Back button press.
	##
	## Shows previous menu from stack, removes advanced menu.
	##
	## Hides web overlays if on web.
	##
	## :rtype: void
	Globals.log_message("Back button pressed in advanced settings.", Globals.LogLevel.DEBUG)
	var hidden_menu_found: bool = false
	if not Globals.hidden_menus.is_empty():
		var prev_menu: Node = Globals.hidden_menus.pop_back()
		if is_instance_valid(prev_menu):
			prev_menu.visible = true
			Globals.log_message("Showing menu: " + prev_menu.name, Globals.LogLevel.DEBUG)
			hidden_menu_found = true
	# Decoupled cleanup: Run if web and js_window available, but gate eval on js_bridge_wrapper
	if os_wrapper.has_feature("web") and js_window:
		_unset_advanced_window_callbacks()
		# Set Options menu buttons visible in DOM (if bridge available for eval)
		if hidden_menu_found and js_bridge_wrapper:
			(
				js_bridge_wrapper
				. eval(
					"""
					// Show Options menu overlays
					document.getElementById('controls-button').style.display = 'block';
					document.getElementById('audio-button').style.display = 'block';
					document.getElementById('advanced-button').style.display = 'block';
					document.getElementById('difficulty-slider').style.display = 'block';
					document.getElementById('options-back-button').style.display = 'block';
					// Hide Advanced Settings overlays
					document.getElementById('log-level-select').style.display = 'none';
					document.getElementById('advanced-back-button').style.display = 'none';
					document.getElementById('advanced-reset-button').style.display = 'none';
					""",
					true
				)
			)
	if not hidden_menu_found:
		Globals.log_message("No hidden menu to show.", Globals.LogLevel.INFO)
	_intentional_exit = true
	queue_free()


func _on_advanced_back_button_pressed_js(args: Array) -> void:
	## JS callback for back press.
	##
	## Routes to signal handler.
	##
	## :param args: Unused array from JS.
	## :type args: Array
	## :rtype: void
	Globals.log_message(
		"JS _advanced_back_button_pressed_cb callback called with args: " + str(args),
		Globals.LogLevel.DEBUG
	)
	_on_advanced_back_button_pressed()


func get_log_level_index() -> int:
	## Retrieves the index of the current log level in the enum values.
	##
	## :returns: The index of the current log level.
	## :rtype: int
	return Globals.LogLevel.values().find(Globals.current_log_level)


# Change: Separate handler for signal (int index)
func _on_log_level_item_selected(index: int) -> void:
	## Handles log level selection from the OptionButton signal.
	##
	## Updates global log level, logs the change, and saves settings.
	##
	## :param index: The selected item index.
	## :type index: int
	## :rtype: void
	var selected_name: String = log_lvl_option.get_item_text(index)
	var selected_enum: Globals.LogLevel = log_level_display_to_enum.get(
		selected_name, Globals.LogLevel.INFO
	)
	Globals.current_log_level = selected_enum
	log_lvl_option.selected = Globals.LogLevel.values().find(selected_enum)
	# Temporary raw print to bypass log_message
	Globals.log_message("Log level changed to: " + selected_name, Globals.LogLevel.DEBUG)
	Globals._save_settings()


# New: JS-specific callback (exactly one Array arg, no default)
func _on_change_log_level_js(args: Array) -> void:
	## JS callback for changing log level.
	##
	## Routes to the signal handler.
	##
	## :param args: Array containing the index (from JS).
	## :type args: Array
	## :rtype: void
	if args.size() == 0:
		Globals.log_message(
			"JS change_log_level callback received empty args—skipping.", Globals.LogLevel.WARNING
		)
		return

	var first_arg: Variant = args[0]
	if typeof(first_arg) != TYPE_ARRAY or first_arg.size() == 0:
		Globals.log_message(
			(
				"JS change_log_level callback received invalid first arg (not a non-empty array): "
				+ str(args)
			),
			Globals.LogLevel.WARNING
		)
		return

	var potential_index: Variant = first_arg[0]
	if (
		typeof(potential_index) != TYPE_INT
		and typeof(potential_index) != TYPE_FLOAT
		and typeof(potential_index) != TYPE_STRING
	):
		Globals.log_message(
			"JS change_log_level callback received non-convertible index value: " + str(args),
			Globals.LogLevel.WARNING
		)
		return

	var index: int = int(potential_index)
	if index < 0 or index >= log_lvl_option.item_count:  # Optional: Bounds check against actual options
		Globals.log_message(
			(
				"JS change_log_level callback received out-of-bounds index: "
				+ str(index)
				+ " (args: "
				+ str(args)
				+ ")"
			),
			Globals.LogLevel.WARNING
		)
		return

	Globals.log_message(
		"JS change_log_level callback called with valid index: " + str(index),
		Globals.LogLevel.DEBUG
	)
	_on_log_level_item_selected(index)
