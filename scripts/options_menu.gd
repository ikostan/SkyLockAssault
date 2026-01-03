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

# Explicit mapping from display names to enum values
var log_level_display_to_enum: Dictionary = {
	"DEBUG": Globals.LogLevel.DEBUG,
	"INFO": Globals.LogLevel.INFO,
	"WARNING": Globals.LogLevel.WARNING,
	"ERROR": Globals.LogLevel.ERROR,
	"NONE": Globals.LogLevel.NONE
}
var audio_scene: PackedScene = preload("res://scenes/audio_settings.tscn")
var _change_log_level_cb: JavaScriptObject
var _change_difficulty_cb: JavaScriptObject
var _options_back_button_pressed_cb: JavaScriptObject

@onready var log_lvl_option: OptionButton = get_node(
	"Panel/OptionsVBoxContainer/LogLevelContainer/LogLevelOptionButton"
)
@onready var options_back_button: Button = $Panel/OptionsVBoxContainer/OptionsBackButton
@onready var difficulty_slider: HSlider = get_node(
	"Panel/OptionsVBoxContainer/DifficultyLevelContainer/DifficultyHSlider"
)
@onready var difficulty_label: Label = get_node(
	"Panel/OptionsVBoxContainer/DifficultyLevelContainer/DifficultyValueLabel"
)
@onready var audio_settings_button: Button = $Panel/OptionsVBoxContainer/AudioSettingsButton
@onready var version_label: Label = $Panel/OptionsVBoxContainer/VersionLabel


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
	# Populate OptionButton with all LogLevel enum values
	for level: String in Globals.LogLevel.keys():
		if level != "NONE":  # Skip auto-add NONE; add manually as "None"
			log_lvl_option.add_item(level)  # "Debug", "Info", etc.
	log_lvl_option.add_item("NONE")  # Manual for title case

	# Game version
	version_label.text = "Version: " + Globals.game_version
	Globals.log_message("Updated label to: " + version_label.text, Globals.LogLevel.DEBUG)

	# Set to current log level (find index by enum value)
	var current_value: int = Globals.current_log_level
	var index: int = Globals.LogLevel.values().find(current_value)
	if index != -1:
		log_lvl_option.selected = index
	else:
		log_lvl_option.selected = 1  # Fallback to INFO (index 1)
		Globals.log_message("Invalid saved log level—reset to INFO.", Globals.LogLevel.WARNING)

	# Connect signals to type-specific handlers (change: separate from JS callbacks)
	log_lvl_option.item_selected.connect(_on_log_level_item_selected)
	difficulty_slider.value_changed.connect(_on_difficulty_value_changed)

	if not options_back_button.pressed.is_connected(_on_options_back_button_pressed):
		options_back_button.pressed.connect(_on_options_back_button_pressed)

	if not audio_settings_button.pressed.is_connected(_on_audio_settings_button_pressed):
		audio_settings_button.pressed.connect(_on_audio_settings_button_pressed)

	# Set initial difficulty label (sync with global)
	difficulty_slider.value = Globals.difficulty
	difficulty_label.text = "{" + str(Globals.difficulty) + "}"

	# Configure for web overlays (invisible but positioned)
	process_mode = Node.PROCESS_MODE_ALWAYS  # Ignore pause
	Globals.log_message("Options menu loaded.", Globals.LogLevel.DEBUG)

	if os_wrapper.has_feature("web"):
		# Toggle overlays...
		(
			js_bridge_wrapper
			. eval(
				"""
				document.getElementById('log-level-select').style.display = 'block';
				document.getElementById('difficulty-slider').style.display = 'block';
				document.getElementById('options-back-button').style.display = 'block';
				""",
				true
			)
		)

		# Expose callbacks to JS (store refs to prevent GC)
		var js_window: JavaScriptObject = js_bridge_wrapper.get_interface("window")
		_change_log_level_cb = js_bridge_wrapper.create_callback(
			Callable(self, "_on_change_log_level_js")
		)
		js_window.changeLogLevel = _change_log_level_cb

		_change_difficulty_cb = js_bridge_wrapper.create_callback(
			Callable(self, "_on_change_difficulty_js")
		)
		js_window.changeDifficulty = _change_difficulty_cb

		_options_back_button_pressed_cb = js_bridge_wrapper.create_callback(
			Callable(self, "_on_options_back_button_pressed_js")
		)
		js_window.backPressed = _options_back_button_pressed_cb
		Globals.log_message(
			"Exposed options menu callbacks to JS for web overlays.", Globals.LogLevel.DEBUG
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
	## Shows previous menu from stack, resets globals.
	##
	## :rtype: void
	if not Globals.hidden_menus.is_empty():
		var prev_menu: Node = Globals.hidden_menus.pop_back()
		if is_instance_valid(prev_menu):
			prev_menu.visible = true
			Globals.log_message("Showing menu: " + prev_menu.name, Globals.LogLevel.DEBUG)
	Globals.options_open = false
	Globals.options_instance = null
	Globals.log_message("Options menu exited.", Globals.LogLevel.DEBUG)


func _exit_tree() -> void:
	## Handles node exit from scene tree.
	##
	## Restores hidden menu, clears flags/refs, logs exit.
	##
	## :rtype: void
	_teardown()  # Centralized cleanup
	Globals.log_message("Options menu exited.", Globals.LogLevel.DEBUG)


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
	log_lvl_option.selected = Globals.current_log_level
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
	Globals.log_message(
		"JS change_log_level callback called with args: " + str(args[0][0]), Globals.LogLevel.DEBUG
	)
	if args.size() > 0:
		# var js_array: Variant = args[0]  # The JS array passed from evaluate
		# var arg_value: Variant = js_array[0]  # Access first element with []
		var index: int = int(args[0][0])
		_on_log_level_item_selected(index)


# Change: Separate handler for signal (float value)
func _on_difficulty_value_changed(value: float) -> void:
	## Handles changes to the difficulty slider from the signal.
	##
	## Updates global difficulty, label text, logs the change, and saves settings.
	##
	## :param value: The new slider value.
	## :type value: float
	## :rtype: void
	Globals.difficulty = value
	difficulty_slider.value = Globals.difficulty
	difficulty_label.text = "{" + str(value) + "}"
	Globals.log_message("Difficulty changed to: " + str(value), Globals.LogLevel.DEBUG)
	Globals._save_settings()


# New: JS-specific callback (exactly one Array arg, no default)
func _on_change_difficulty_js(args: Array) -> void:
	## JS callback for changing difficulty.
	##
	## Routes to the signal handler.
	##
	## :param args: Array containing the value (from JS).
	## :type args: Array
	## :rtype: void
	if args.size() > 0:
		Globals.log_message(
			"JS difficulty callback called with args: " + str(args[0][0]), Globals.LogLevel.DEBUG
		)
		var value: float = float(args[0][0])
		_on_difficulty_value_changed(value)


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
		(
			js_bridge_wrapper
			. eval(
				"""
				document.getElementById('log-level-select').style.display = 'none';
				document.getElementById('difficulty-slider').style.display = 'none';
				document.getElementById('options-back-button').style.display = 'none';
				"""
			)
		)

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


## Handles Audio button press.
## Hides options menu, loads audio settings.
## :rtype: void
func _on_audio_settings_button_pressed() -> void:
	Globals.log_message("Audio button pressed.", Globals.LogLevel.DEBUG)
	var audio_instance: Control = audio_scene.instantiate()  # Use the preloaded var
	get_tree().root.add_child(audio_instance)
	Globals.hidden_menus.push_back(self)
	self.visible = false
