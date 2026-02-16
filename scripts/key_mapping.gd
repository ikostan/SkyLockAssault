## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later

extends CanvasLayer

# global
var js_window: Variant
var os_wrapper: OSWrapper = OSWrapper.new()
var js_bridge_wrapper: JavaScriptBridgeWrapper = JavaScriptBridgeWrapper.new()
# ── Conflict dialog (created in code – no scene edit needed) ─────
var conflict_dialog: ConfirmationDialog
var current_remap_button: InputRemapButton = null
var current_pending_event: InputEvent = null
var current_conflicts: Array[String] = []
# local
var _controls_back_button_pressed_cb: Variant
var _intentional_exit: bool = false

@onready var controls_back_button: Button = $Panel/Options/BtnContainer/ControlsBackButton
@onready var controls_reset_button: Button = $Panel/Options/BtnContainer/ControlResetButton
# NEW: Onreadys for device switcher
@onready var keyboard: CheckButton = $Panel/Options/DeviceTypeContainer/Keyboard
@onready var gamepad: CheckButton = $Panel/Options/DeviceTypeContainer/Gamepad
@onready var device_group: ButtonGroup = ButtonGroup.new()  # Mutual exclusivity


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

	# NEW: Reset button connect (add if not there—resets to defaults)
	if not controls_reset_button.pressed.is_connected(_on_reset_pressed):
		controls_reset_button.pressed.connect(_on_reset_pressed)

	# NEW: Assign ButtonGroup for exclusivity
	keyboard.button_group = device_group
	gamepad.button_group = device_group
	keyboard.button_pressed = true  # Default: Keyboard
	update_all_remap_buttons()

	process_mode = Node.PROCESS_MODE_ALWAYS
	# NEW: Default focus on "Keyboard" when the menu opens
	_grab_initial_focus()

	# Conflicting key remap functionality/setup
	add_to_group("key_mapping_menu")  # so buttons can find us
	# Create the conflict dialog once
	conflict_dialog = ConfirmationDialog.new()
	conflict_dialog.title = "Input Already Used"
	conflict_dialog.exclusive = true  # blocks background input
	conflict_dialog.get_ok_button().text = "Reassign (unbind other)"
	conflict_dialog.get_cancel_button().text = "Cancel"
	add_child(conflict_dialog)

	conflict_dialog.confirmed.connect(_on_conflict_confirmed)
	conflict_dialog.canceled.connect(_on_conflict_canceled)

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


## Called from InputRemapButton when a duplicate binding is detected.
func show_conflict_dialog(
	btn: InputRemapButton, new_event: InputEvent, conflicts: Array[String]
) -> void:
	current_remap_button = btn
	current_pending_event = new_event
	current_conflicts = conflicts

	var txt: String = "The input you just pressed is already used by:\n\n"
	for c in conflicts:
		txt += "• " + c.to_upper().replace("_", " ") + "\n"
	txt += "\nReassign anyway? The conflicting mapping(s) will be set to Unbound."

	conflict_dialog.dialog_text = txt
	conflict_dialog.popup_centered()


func _on_conflict_confirmed() -> void:
	if not current_remap_button or not current_pending_event:
		return

	# 1. COMPLETELY unbind every conflicting action (this was the missing piece)
	for act in current_conflicts:
		InputMap.action_erase_events(act)  # Removes ALL events for that action
		Globals.log_message("Completely unbound action: " + act, Globals.LogLevel.DEBUG)

	# 2. Apply the new binding
	current_remap_button.erase_old_event()
	InputMap.action_add_event(current_remap_button.action, current_pending_event)

	Globals.log_message(
		(
			"Remapped %s (unbound %d conflicts)"
			% [current_remap_button.action, current_conflicts.size()]
		),
		Globals.LogLevel.DEBUG
	)

	# 3. Save ALL changes to disk (including the now-empty actions)
	Settings.save_input_mappings()

	# 4. Finish the remap for the button we changed
	current_remap_button.finish_remap()

	# 5. Refresh UI
	update_all_remap_buttons()

	# Cleanup
	_clear_conflict_state()


func _on_conflict_canceled() -> void:
	if not current_remap_button:
		return
	# Just stop listening – original binding stays
	current_remap_button.button_pressed = false
	current_remap_button.listening = false
	current_remap_button.update_button_text()
	_clear_conflict_state()


func _clear_conflict_state() -> void:
	current_remap_button = null
	current_pending_event = null
	current_conflicts.clear()


## Updates all remap buttons.
## :rtype: void
func update_all_remap_buttons() -> void:
	var current: InputRemapButton.DeviceType = (
		InputRemapButton.DeviceType.KEYBOARD
		if keyboard.button_pressed
		else InputRemapButton.DeviceType.GAMEPAD
	)
	var buttons: Array[Node] = get_tree().get_nodes_in_group("remap_buttons")
	for btn: InputRemapButton in buttons:
		btn.current_device = current
		btn.update_button_text()


# NEW: Reset button handler—resets InputMap to defaults and updates buttons
func _on_reset_pressed() -> void:
	# Function resets only the selected device type (keyboard or gamepad)
	var device_type: String = "keyboard" if keyboard.button_pressed else "gamepad"
	Settings.reset_to_defaults(device_type)
	update_all_remap_buttons()
	Globals.log_message("Resetting " + device_type + " controls.", Globals.LogLevel.DEBUG)


func _on_keyboard_toggled(toggled_on: bool) -> void:
	if toggled_on:
		Globals.log_message(
			"_on_keyboard_toggled control pressed: " + str(toggled_on), Globals.LogLevel.DEBUG
		)
		update_all_remap_buttons()


func _on_gamepad_toggled(toggled_on: bool) -> void:
	if toggled_on:
		Globals.log_message(
			"_on_gamepad_toggled control pressed: " + str(toggled_on), Globals.LogLevel.DEBUG
		)
		update_all_remap_buttons()


func _on_controls_back_button_pressed() -> void:
	## Handles Back button press.
	##
	## Shows previous menu from stack, removes controls menu.
	##
	## Restores focus to the "Key Mapping" button in OptionsMenu when returning.
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
			# NEW: When returning from Key Mapping menu → focus the Key Mapping button in Options
			if prev_menu is OptionsMenu:
				(prev_menu as OptionsMenu).grab_focus_on_key_mapping_button()
			# NEW: When returning to Main Menu → focus Start Game button
			elif prev_menu.name == "Panel" or prev_menu is Panel:  # ← this is the fix
				var start_button: Button = prev_menu.get_node_or_null("VBoxContainer/StartButton")
				if is_instance_valid(start_button):
					# Triple-deferred to be 100% sure after visibility change
					start_button.call_deferred("call_deferred", "call_deferred", "grab_focus")
					Globals.log_message(
						"Focus restored to Start Game button (triple deferred)",
						Globals.LogLevel.DEBUG
					)

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
			# Only showing all five when a previous menu exists.
			if hidden_menu_found:
				(
					js_bridge_wrapper
					. eval(
						"""
						document.getElementById('audio-button').style.display = 'block';
						document.getElementById('advanced-button').style.display = 'block';
						document.getElementById('controls-button').style.display = 'block';
						document.getElementById('difficulty-slider').style.display = 'block';
						document.getElementById('options-back-button').style.display = 'block';
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


## Ensures "Keyboard" gets focus by default when the menu opens.
## Uses the same safe logic as OptionsMenu so we don't fight controller navigation.
func _grab_initial_focus() -> void:
	var allowed_controls: Array[Control] = [
		keyboard, gamepad, controls_back_button, controls_reset_button
	]

	# Add every remap button so the helper knows what's "inside" the menu
	var remap_buttons: Array[Node] = get_tree().get_nodes_in_group("remap_buttons")
	for btn: Node in remap_buttons:
		if btn is Control:
			allowed_controls.append(btn)

	Globals.ensure_initial_focus(keyboard, allowed_controls, "Key Mapping Menu")  # candidate
