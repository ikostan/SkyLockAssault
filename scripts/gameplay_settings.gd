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
	# NEW: Attach tree_exited for unexpected removal cleanup (like other settings scripts)
	tree_exited.connect(_on_tree_exited)

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
	_grab_initial_focus()
	Globals.log_message("Gameplay Settings menu loaded.", Globals.LogLevel.DEBUG)


func _on_tree_exited() -> void:
	## Cleanup on unexpected tree exit (e.g. parent removed without calling back button).
	## Disconnects signals, restores previous menu if not intentional, clears JS/DOM state.
	## :rtype: void
	Globals.log_message("Gameplay Settings _on_tree_exited called.", Globals.LogLevel.DEBUG)

	# Disconnect Godot signals if still connected
	if difficulty_slider.value_changed.is_connected(_on_difficulty_value_changed):
		difficulty_slider.value_changed.disconnect(_on_difficulty_value_changed)
	if gameplay_back_button.pressed.is_connected(_on_gameplay_back_button_pressed):
		gameplay_back_button.pressed.disconnect(_on_gameplay_back_button_pressed)
	if gameplay_reset_button.pressed.is_connected(_on_gameplay_reset_button_pressed):
		gameplay_reset_button.pressed.disconnect(_on_gameplay_reset_button_pressed)

	# Clean up JS callbacks on window object
	_unset_gameplay_settings_window_callbacks()

	# Null out stored callback references
	_change_difficulty_cb = null
	_gameplay_back_button_pressed_cb = null
	_gameplay_reset_cb = null

	# Web overlay cleanup + optional menu restore
	if os_wrapper.has_feature("web") and js_window and js_bridge_wrapper:
		# Hide gameplay overlays (same DOM elements shown in _ready)
		var hide_gameplay: String = """
			document.getElementById('difficulty-slider').style.display = 'none';
			document.getElementById('gameplay-back-button').style.display = 'none';
			document.getElementById('gameplay-reset-button').style.display = 'none';
			"""

		if not _intentional_exit and not Globals.hidden_menus.is_empty():
			# Unexpected exit → restore previous menu and options overlays
			var prev_menu: Node = Globals.hidden_menus.pop_back()
			if is_instance_valid(prev_menu):
				prev_menu.visible = true
				Globals.log_message(
					"tree_exited: Restored menu: " + prev_menu.name, Globals.LogLevel.DEBUG
				)

			(
				js_bridge_wrapper
				. eval(
					(
						"""
						// Show Options menu overlays
						document.getElementById('controls-button').style.display = 'block';
						document.getElementById('audio-button').style.display = 'block';
						document.getElementById('advanced-button').style.display = 'block';
						document.getElementById('gameplay-button').style.display = 'block';
						document.getElementById('options-back-button').style.display = 'block';
						"""
						+ hide_gameplay
					),
					true
				)
			)
		else:
			# Intentional exit or no previous menu → just hide gameplay overlays
			js_bridge_wrapper.eval(hide_gameplay, true)


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
	_on_difficulty_value_changed(_default_difficulty)


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
			# NEW: When returning from Gameplay Settings menu →
			# → focus the Gameplay Settings button in Options
			if prev_menu is OptionsMenu:
				(prev_menu as OptionsMenu).grab_focus_on_gameplay_settings_button()

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
	if args.is_empty():
		Globals.log_message(
			"JS difficulty callback received empty args—skipping.", Globals.LogLevel.WARNING
		)
		return

	var first_arg: Variant = args[0]
	if (
		first_arg is not JavaScriptObject
		and typeof(first_arg) != TYPE_ARRAY
		and first_arg.size() == 0
		and first_arg.is_empty()
	):
		Globals.log_message(
			(
				"JS difficulty callback received invalid first arg (not a non-empty array): "
				+ str(args)
			),
			Globals.LogLevel.WARNING
		)
		return

	var potential_value: Variant = first_arg[0]
	if (
		typeof(potential_value) != TYPE_INT
		and typeof(potential_value) != TYPE_FLOAT
		and typeof(potential_value) != TYPE_STRING
	):
		Globals.log_message(
			"JS difficulty callback received non-convertible value: " + str(args),
			Globals.LogLevel.WARNING
		)
		return

	var value: float = float(potential_value)
	if value < difficulty_slider.min_value or value > difficulty_slider.max_value:
		Globals.log_message(
			(
				"JS difficulty callback received out-of-bounds value: "
				+ str(value)
				+ " (args: "
				+ str(args)
				+ ")"
			),
			Globals.LogLevel.WARNING
		)
		return

	Globals.log_message(
		"JS difficulty callback called with valid value: " + str(value), Globals.LogLevel.DEBUG
	)
	_on_difficulty_value_changed(value)


## Grabs initial focus on the difficulty slider using the global helper.
## Ensures the slider is focused when the menu opens.
## Falls back to other controls if needed.
##
## :rtype: void
func _grab_initial_focus() -> void:
	Globals.ensure_initial_focus(
		difficulty_slider,
		[difficulty_slider, gameplay_back_button, gameplay_reset_button],
		"Gameplay Settings Menu"
	)
