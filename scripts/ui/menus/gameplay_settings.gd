## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## res://scripts/ui/menus/gameplay_settings.gd
##
## Gameplay Settings menu (difficulty slider, Back, Reset).
## Signal cleanup, web overlay toggling, menu-stack navigation and focus handling are
## inherited from SettingsMenuBase (settings_menu_base.gd).
extends SettingsMenuBase

## DOM overlays owned by this menu (see custom_shell.html).
const GAMEPLAY_OVERLAY_IDS: Array[String] = [
	"difficulty-slider", "gameplay-back-button", "gameplay-reset-button"
]

var _change_difficulty_cb: JavaScriptObject
var _gameplay_back_button_pressed_cb: JavaScriptObject
var _gameplay_reset_cb: JavaScriptObject
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
	super()  # process_mode = ALWAYS (ignore pause) + tree_exited -> teardown

	var settings_res := Globals.settings if is_instance_valid(Globals) else null

	safe_connect(difficulty_slider.value_changed, _on_difficulty_value_changed)

	# Set initial difficulty label (sync with global if available)
	if is_instance_valid(settings_res):
		difficulty_slider.value = settings_res.difficulty
		difficulty_label.text = "{" + str(settings_res.difficulty) + "}"
	else:
		difficulty_slider.value = _default_difficulty
		difficulty_label.text = "{" + str(_default_difficulty) + "}"

	safe_connect(gameplay_back_button.pressed, _on_gameplay_back_button_pressed)
	safe_connect(gameplay_reset_button.pressed, _on_gameplay_reset_button_pressed)

	# The UI observes the resource for external changes (e.g. from JS / other menus)
	if is_instance_valid(settings_res):
		safe_connect(settings_res.setting_changed, _on_external_setting_changed)

	if os_wrapper.has_feature("web"):
		update_web_overlays(_get_overlay_ids(), [])
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


# ==============================================================================
# SettingsMenuBase HOOKS
# ==============================================================================


func _get_menu_name() -> String:
	return "Gameplay Settings"


func _get_overlay_ids() -> Array[String]:
	return GAMEPLAY_OVERLAY_IDS


func _get_initial_focus_control() -> Control:
	return difficulty_slider


func _get_focus_controls() -> Array[Control]:
	return [difficulty_slider, gameplay_back_button, gameplay_reset_button]


## Back path only: return focus to the Gameplay Settings button in the Options menu.
func _on_previous_menu_restored(prev_menu: Node) -> void:
	if prev_menu is OptionsMenu:
		(prev_menu as OptionsMenu).grab_focus_on_gameplay_settings_button()


## Teardown hook (runs once, before the base disconnects the tracked signals).
## Detaches the JS entry points and drops the callback refs. Safe to call repeatedly.
func _cleanup() -> void:
	_unset_gameplay_settings_window_callbacks()
	_change_difficulty_cb = null
	_gameplay_back_button_pressed_cb = null
	_gameplay_reset_cb = null


## Detaches the gameplay JS entry points from `window` (web only). Idempotent.
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
	# Route through standard handler with explicit interaction override set to true
	_on_difficulty_value_changed(_default_difficulty, true)


func _on_gameplay_reset_js(_args: Array) -> void:
	_on_gameplay_reset_button_pressed()


func _on_gameplay_back_button_pressed() -> void:
	## Handles Back button press (Godot button and JS overlay).
	##
	## Delegates to SettingsMenuBase._go_back(): restores the previous menu from the
	## stack, swaps the web overlays and frees this menu.
	##
	## :rtype: void
	_go_back()


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
func _on_difficulty_value_changed(value: float, is_interactive: bool = false) -> void:
	## Handles changes to the difficulty slider from the signal.
	##
	## Updates global difficulty, label text, logs the change, and saves settings.
	## Gates slider.wav playback behind UI focus verification or explicit external
	## interaction overrides.
	##
	## :param value: The new slider value.
	## :type value: float
	## :param is_interactive: True if the event was triggered by a verified external human
	## interaction vector.
	## :type is_interactive: bool
	## :rtype: void
	var settings_res := Globals.settings if is_instance_valid(Globals) else null

	# FIX: Use the local reference exclusively
	if not is_instance_valid(settings_res):
		Globals.log_message(
			"Gameplay Settings: settings_res unavailable; skipping difficulty update.",
			Globals.LogLevel.WARNING
		)
		return

	# Evaluate focus validation before updating UI structures
	var slider_has_focus: bool = false
	if is_instance_valid(difficulty_slider):
		slider_has_focus = difficulty_slider.has_focus()

	# Gate audio playback on explicit intent token or validated UI focus
	var should_play_audio: bool = is_interactive or slider_has_focus

	settings_res.difficulty = value
	if is_instance_valid(difficulty_slider):
		difficulty_slider.set_value_no_signal(settings_res.difficulty)
	if is_instance_valid(difficulty_label):
		difficulty_label.text = "{" + str(settings_res.difficulty) + "}"

	if should_play_audio:
		_play_slider_sfx()


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

	# Pass the validated value to the standard handler with the interactive flag explicitly overridden
	_on_difficulty_value_changed(value, true)


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


## Helper to cleanly trigger interactive feedback via the global AudioManager
## Prevents engine-level environment execution faults during headless unit testing pipelines.
##
## :rtype: void
func _play_slider_sfx() -> void:
	if is_instance_valid(AudioManager) and AudioManager.has_method("play_sfx"):
		AudioManager.play_sfx("slider")
	elif is_instance_valid(Globals):
		Globals.log_message(
			"Gameplay Settings: AudioManager unavailable or missing play_sfx method.",
			Globals.LogLevel.DEBUG
		)
