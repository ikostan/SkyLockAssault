extends Control

## The wrappers (like JavaScriptBridgeWrapper and presumably OSWrapper)
## are designed to abstract away direct singleton calls, making the code
## easier to unit test by allowing mocks/stubs without relying on the
## actual engine singletons.
var js_bridge_wrapper: JavaScriptBridgeWrapper = JavaScriptBridgeWrapper.new()
var os_wrapper: OSWrapper = OSWrapper.new()
var js_window: JavaScriptObject
var _change_difficulty_cb: JavaScriptObject
var _gameplay_back_button_pressed_cb: JavaScriptObject
var _gameplay_reset_cb: JavaScriptObject
var _intentional_exit: bool = false
var _default_difficulty: float = 1.0

@onready var difficulty_slider: HSlider = get_node(
	"Panel/Controls/DifficultyLevelContainer/DifficultyHSlider"
)
@onready var difficulty_label: Label = get_node(
	"Panel/Controls/DifficultyLevelContainer/DifficultyValueLabel"
)
@onready var gameplay_back_button: Button = get_node("Panel/Controls/BtnContainer/BackButton")
@onready var gameplay_reset_button: Button = get_node("Panel/Controls/BtnContainer/ResetButton")


func _ready() -> void:
	# Configure for web overlays (invisible but positioned)
	process_mode = Node.PROCESS_MODE_ALWAYS  # Ignore pause

	difficulty_slider.value_changed.connect(_on_difficulty_value_changed)
	# Set initial difficulty label (sync with global)
	difficulty_slider.value = Globals.difficulty
	difficulty_label.text = "{" + str(Globals.difficulty) + "}"
	# Back button
	if not gameplay_back_button.pressed.is_connected(_on_gameplay_back_button_pressed):
		gameplay_back_button.pressed.connect(_on_gameplay_back_button_pressed)
	# Reset button listener
	if not gameplay_reset_button.pressed.is_connected(_on_gameplay_reset_button_pressed):
		gameplay_reset_button.pressed.connect(_on_gameplay_reset_button_pressed)

	if os_wrapper.has_feature("web"):
		# Toggle overlays...
		(
			js_bridge_wrapper
			. eval(
				"""
				document.getElementById('difficulty-slider').style.display = 'block';
				document.getElementById('gameplay-back-button').style.display = 'block';
				document.getElementById('gameplay-reset-button').style.display = 'block';
				""",
				true
			)
		)
		# Expose callbacks to JS (store refs to prevent GC)
		js_window = js_bridge_wrapper.get_interface("window")
		if js_window:
			_change_difficulty_cb = js_bridge_wrapper.create_callback(
				Callable(self, "_on_change_difficulty_js")
			)
			js_window.changeDifficulty = _change_difficulty_cb

			_gameplay_back_button_pressed_cb = js_bridge_wrapper.create_callback(
				Callable(self, "_on_gameplay_back_button_pressed_js")
			)
			js_window.gameplayBackPressed = _gameplay_back_button_pressed_cb

			_gameplay_reset_cb = js_bridge_wrapper.create_callback(
				Callable(self, "_on_gameplay_reset_js")
			)
			js_window.gameplayResetPressed = _gameplay_reset_cb

			Globals.log_message(
				"Exposed gameplay settings callbacks to JS for web overlays.",
				Globals.LogLevel.DEBUG
			)
	# Menu is loaded
	Globals.log_message("Gameplay Settings menu loaded.", Globals.LogLevel.DEBUG)


## A cleanup function
func _unset_gameplay_settings_window_callbacks() -> void:
	if not os_wrapper.has_feature("web") or not js_window:
		return
	js_window.changeDifficulty = null
	js_window.gameplayBackPressed = null
	js_window.gameplayResetPressed = null


## RESET BUTTON
## Handles Gameplay Settings reset button press.
func _on_gameplay_reset_button_pressed() -> void:
	Globals.log_message("Gameplay Settings reset pressed.", Globals.LogLevel.DEBUG)
	# Set initial default label
	difficulty_slider.value = _default_difficulty
	difficulty_label.text = "{" + str(_default_difficulty) + "}"
	Globals._save_settings()


func _on_gameplay_reset_js(_args: Array) -> void:
	_on_gameplay_reset_button_pressed()


func _on_gameplay_back_button_pressed() -> void:
	## Handles Back button press.
	##
	## Shows previous menu from stack, removes gameplay menu.
	##
	## Hides web overlays if on web.
	##
	## :rtype: void
	Globals.log_message("Gameplay Settings Back button pressed.", Globals.LogLevel.DEBUG)

	var hidden_menu_found: bool = false
	if not Globals.hidden_menus.is_empty():
		var prev_menu: Node = Globals.hidden_menus.pop_back()
		if is_instance_valid(prev_menu):
			prev_menu.visible = true
			Globals.log_message("Showing menu: " + prev_menu.name, Globals.LogLevel.DEBUG)
			hidden_menu_found = true

	# Decoupled cleanup: Run if web and js_window available, but gate eval on js_bridge_wrapper
	if os_wrapper.has_feature("web") and js_window:
		_unset_gameplay_settings_window_callbacks()
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
					document.getElementById('gameplay-button').style.display = 'block';
					document.getElementById('options-back-button').style.display = 'block';
					// Hide Gameplay Settings overlays
					document.getElementById('difficulty-slider').style.display = 'none';
					document.getElementById('gameplay-back-button').style.display = 'none';
					document.getElementById('gameplay-reset-button').style.display = 'none';
					""",
					true
				)
			)
	if not hidden_menu_found:
		Globals.log_message("No hidden menu to show.", Globals.LogLevel.INFO)
	_intentional_exit = true
	queue_free()


# New: JS-specific callback (exactly one Array arg, no default)
func _on_gameplay_back_button_pressed_js(args: Array) -> void:
	## JS callback for back press.
	##
	## Routes to signal handler.
	##
	## :param args: Unused array from JS.
	## :type args: Array
	## :rtype: void
	Globals.log_message(
		"JS _gameplay_back_button_pressed_cb callback called with args: " + str(args),
		Globals.LogLevel.DEBUG
	)
	_on_gameplay_back_button_pressed()


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
	Globals.log_message("Gameplay Settings menu exited.", Globals.LogLevel.DEBUG)


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
