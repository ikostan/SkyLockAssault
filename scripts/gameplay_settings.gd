extends Control

## The wrappers (like JavaScriptBridgeWrapper and presumably OSWrapper)
## are designed to abstract away direct singleton calls, making the code
## easier to unit test by allowing mocks/stubs without relying on the
## actual engine singletons.
var js_bridge_wrapper: JavaScriptBridgeWrapper = JavaScriptBridgeWrapper.new()
var os_wrapper: OSWrapper = OSWrapper.new()
var js_window: Variant
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

	var settings_res := Globals.settings if is_instance_valid(Globals) else null

	# ADD GUARDS HERE:
	if not difficulty_slider.value_changed.is_connected(_on_difficulty_value_changed):
		difficulty_slider.value_changed.connect(_on_difficulty_value_changed)

	# Set initial difficulty label (sync with global if available)
	# FIX: Use the local reference for consistency
	if is_instance_valid(settings_res):
		difficulty_slider.value = settings_res.difficulty
		difficulty_label.text = "{" + str(settings_res.difficulty) + "}"
	else:
		difficulty_slider.value = _default_difficulty
		difficulty_label.text = "{" + str(_default_difficulty) + "}"

	# Back button
	if not gameplay_back_button.pressed.is_connected(_on_gameplay_back_button_pressed):
		gameplay_back_button.pressed.connect(_on_gameplay_back_button_pressed)
	# Reset button listener
	if not gameplay_reset_button.pressed.is_connected(_on_gameplay_reset_button_pressed):
		gameplay_reset_button.pressed.connect(_on_gameplay_reset_button_pressed)
	# NEW: Attach tree_exited for unexpected removal cleanup (like other settings scripts)
	if not tree_exited.is_connected(_on_tree_exited):
		tree_exited.connect(_on_tree_exited)

	# NEW: The UI now observes the resource for external changes
	# if not Globals.settings.setting_changed.is_connected(_on_external_setting_changed):
	#	Globals.settings.setting_changed.connect(_on_external_setting_changed)
	if (
		is_instance_valid(settings_res)
		and not settings_res.setting_changed.is_connected(_on_external_setting_changed)
	):
		settings_res.setting_changed.connect(_on_external_setting_changed)

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


func _on_external_setting_changed(setting_name: String, new_value: Variant) -> void:
	## SYNC UI ONLY:
	## This observer reacts to changes from the resource.
	## We must ensure the UI nodes are still valid before updating them.
	if setting_name == "difficulty":
		# FIX: Guard against 'previously freed' errors during teardown/unit tests
		if not is_instance_valid(difficulty_slider) or not is_instance_valid(difficulty_label):
			return

		# Use set_value_no_signal to prevent re-triggering local handlers
		difficulty_slider.set_value_no_signal(float(new_value))
		difficulty_label.text = "{" + str(new_value) + "}"


func _on_tree_exited() -> void:
	## Cleanup on unexpected tree exit (e.g. parent removed without calling back button).
	## Disconnects signals, restores previous menu if not intentional, clears JS/DOM state.
	## :rtype: void
	## Cleanup on unexpected tree exit.
	Globals.log_message("Gameplay Settings _on_tree_exited called.", Globals.LogLevel.DEBUG)

	# 1. Safe Global Resource Disconnection
	var settings_res := Globals.settings if is_instance_valid(Globals) else null
	if is_instance_valid(settings_res):
		if settings_res.setting_changed.is_connected(_on_external_setting_changed):
			settings_res.setting_changed.disconnect(_on_external_setting_changed)

	# 2. FIX: Guarded Local Disconnections
	# We must check if the nodes still exist before accessing 'value_changed' or 'pressed'
	if is_instance_valid(difficulty_slider):
		if difficulty_slider.value_changed.is_connected(_on_difficulty_value_changed):
			difficulty_slider.value_changed.disconnect(_on_difficulty_value_changed)

	if is_instance_valid(gameplay_back_button):
		if gameplay_back_button.pressed.is_connected(_on_gameplay_back_button_pressed):
			gameplay_back_button.pressed.disconnect(_on_gameplay_back_button_pressed)

	if is_instance_valid(gameplay_reset_button):
		if gameplay_reset_button.pressed.is_connected(_on_gameplay_reset_button_pressed):
			gameplay_reset_button.pressed.disconnect(_on_gameplay_reset_button_pressed)

	# 3. Clean up JS/Web state
	_unset_gameplay_settings_window_callbacks()
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
			# When returning from Gameplay Settings menu → restore focus to the
			# Gameplay Settings button in Options
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
	# Update the resource first (this triggers clamping in the setter)
	#Globals.settings.difficulty = value
	# Update the UI components using the ALREADY CLAMPED value from the resource
	#difficulty_slider.value = Globals.settings.difficulty
	#difficulty_label.text = "{" + str(Globals.settings.difficulty) + "}"
	var settings_res := Globals.settings if is_instance_valid(Globals) else null

	# FIX: Use the local reference exclusively
	if not is_instance_valid(settings_res):
		Globals.log_message(
			"Gameplay Settings: settings_res unavailable; skipping difficulty update.",
			Globals.LogLevel.WARNING
		)
		return

	settings_res.difficulty = value
	difficulty_slider.value = settings_res.difficulty
	difficulty_label.text = "{" + str(settings_res.difficulty) + "}"


# New: JS-specific callback (exactly one Array arg, no default)
func _on_change_difficulty_js(args: Array) -> void:
	## JS callback for changing difficulty.
	##
	## Routes to the signal handler after performing strict type and
	## bounds validation to prevent engine crashes on malformed JS input.
	##
	## :param args: Array containing the value (from JS).
	## :type args: Array
	## :rtype: void

	var potential_value: Variant = _extract_js_difficulty(args)

	if potential_value == null:
		return

	# GS-JS-12/15/22: Validate that the extracted value is a convertible type
	if (
		typeof(potential_value) != TYPE_INT
		and typeof(potential_value) != TYPE_FLOAT
		and typeof(potential_value) != TYPE_STRING
	):
		Globals.log_message(
			"JS difficulty callback received non-convertible value: " + str(potential_value),
			Globals.LogLevel.WARNING
		)
		return

	# GS-JS-03: Coerce to float (e.g., "1.5" becomes 1.5)
	# FIX: Ensure strings are numeric before conversion to prevent 0.0/clamping reset
	if typeof(potential_value) == TYPE_STRING and not potential_value.is_valid_float():
		Globals.log_message(
			"JS difficulty callback: Rejected non-numeric string: " + str(potential_value),
			Globals.LogLevel.WARNING
		)
		return

	var value: float = float(potential_value)

	# GS-JS-30: Guard against missing UI nodes during callback
	if not is_instance_valid(difficulty_slider):
		Globals.log_message(
			"JS difficulty callback: Slider node is invalid/freed.", Globals.LogLevel.WARNING
		)

		# FIX: Safely check for Globals and Settings before falling back
		var settings_res := Globals.settings if is_instance_valid(Globals) else null
		if is_instance_valid(settings_res):
			settings_res.difficulty = value  # Update resource even if UI is gone
		return

	# GS-JS-04/05: Validate bounds against the UI constraints
	if value < difficulty_slider.min_value or value > difficulty_slider.max_value:
		Globals.log_message(
			"JS difficulty callback received out-of-bounds value: " + str(value),
			Globals.LogLevel.WARNING
		)

	Globals.log_message(
		"JS difficulty callback called with valid value: " + str(value), Globals.LogLevel.DEBUG
	)

	# Pass the validated value to the standard handler
	_on_difficulty_value_changed(value)


## GS-JS: Helper to extract a potential value from diverse JS bridge payloads.
## Isolates branching logic for standard Arrays, JavaScriptObjects, and scalars.
func _extract_js_difficulty(args: Array) -> Variant:
	# GS-JS-10: Guard against entirely empty arguments from the bridge
	if args.is_empty():
		Globals.log_message(
			"JS difficulty callback received empty args—skipping.", Globals.LogLevel.WARNING
		)
		return null

	var first_arg: Variant = args[0]

	# GS-JS-20/21: Branch logic to handle TYPE_ARRAY and JavaScriptObject separately
	if typeof(first_arg) == TYPE_ARRAY:
		# Safe to use .size() and indexing on standard GDScript Arrays
		if first_arg.size() > 0:
			return first_arg[0]

		Globals.log_message("JS callback: Array is empty.", Globals.LogLevel.WARNING)
		return null

	if first_arg is JavaScriptObject:
		# BUG RISK FIX: Validate the 'length' property exists and is numeric
		# before treating the object as an array.
		# Note: Must use dot notation, as .get() attempts to call a JS method.
		var js_length: Variant = first_arg.length

		if js_length != null and typeof(js_length) in [TYPE_INT, TYPE_FLOAT] and js_length > 0:
			# JS-FIX: If we receive a JS Object (like from Playwright),
			# we must index it to get the raw value before the type check.
			return first_arg[0]

		# It is a generic JS object or a non-array; treat as a scalar reference
		return first_arg

	# Handle scalar values (e.g., [1.5]) directly
	return first_arg


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
