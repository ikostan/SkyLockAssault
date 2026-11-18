## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## res://scripts/ui/menus/key_mapping.gd

extends CanvasLayer

## Instance ID of the Key Mapping whose callback is in `window.controlsBackPressed`, or 0
## (#1166). Reading the slot back returns a new JavaScriptObject wrapper, so ownership is tracked
## here instead of by comparing callbacks.
static var _window_callback_owner_id: int = 0

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


## Initializes the controls menu.
##
## Connects signals, configures process mode, and sets the initial device
## selection using `set_pressed_no_signal` to prevent triggering audio
## playback during initialization.
func _ready() -> void:
	# Back button connection
	if not controls_back_button.pressed.is_connected(_on_controls_back_button_pressed):
		controls_back_button.pressed.connect(_on_controls_back_button_pressed)

	# Reset button connection
	if not controls_reset_button.pressed.is_connected(_on_reset_pressed):
		controls_reset_button.pressed.connect(_on_reset_pressed)

	# Assign ButtonGroup for mutual exclusivity
	keyboard.button_group = device_group
	gamepad.button_group = device_group

	# FIX: Use set_pressed_no_signal() to set the default state without
	# triggering the _on_keyboard_toggled / _on_gamepad_toggled audio callbacks
	keyboard.set_pressed_no_signal(Globals.current_input_device == "keyboard")
	gamepad.set_pressed_no_signal(Globals.current_input_device == "gamepad")

	process_mode = Node.PROCESS_MODE_ALWAYS
	_grab_initial_focus()

	# Conflicting key remap functionality/setup
	add_to_group("key_mapping_menu")

	# Create the conflict dialog
	conflict_dialog = ConfirmationDialog.new()
	conflict_dialog.title = "Input Already Used"
	conflict_dialog.exclusive = true
	conflict_dialog.get_ok_button().text = "Reassign (unbind other)"
	conflict_dialog.get_cancel_button().text = "Cancel"
	add_child(conflict_dialog)

	conflict_dialog.confirmed.connect(_on_conflict_confirmed)
	conflict_dialog.canceled.connect(_on_conflict_canceled)

	Globals.log_message("Controls menu loaded.", Globals.LogLevel.DEBUG)

	if os_wrapper.has_feature("web"):
		js_window = js_bridge_wrapper.get_interface("window")
		if js_window:
			js_bridge_wrapper.eval(
				"document.getElementById('controls-back-button').style.display = 'block';", true
			)
			_controls_back_button_pressed_cb = js_bridge_wrapper.create_callback(
				Callable(self, "_on_controls_back_button_pressed_js")
			)
			js_window.controlsBackPressed = _controls_back_button_pressed_cb
			_window_callback_owner_id = get_instance_id()

	update_all_remap_buttons()


## Display a confirmation dialog when a duplicate input binding is detected.
##
## Called from InputRemapButton when a keyboard key, gamepad button or gamepad axis is already
## bound to another action. Populates and centers the conflict dialog.
##
## [param btn]: The InputRemapButton that triggered the duplicate binding.
## [param new_event]: The InputEvent (key, joypad button or joypad motion) that caused the
## conflict.
## [param conflicts]: An array of conflicting action names.
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

	# 1. Unbind ONLY the conflicting event of the SAME DEVICE (keyboard or gamepad)
	for act in current_conflicts:
		for ev: InputEvent in InputMap.action_get_events(act):
			if Settings.events_match(ev, current_pending_event):  # exact same binding
				InputMap.action_erase_event(act, ev)
				Globals.log_message(
					"Unbound specific device event for " + act, Globals.LogLevel.DEBUG
				)
				break  # only one match per device

	# 2. Apply the new binding
	current_remap_button.erase_old_event()
	InputMap.action_add_event(current_remap_button.action, current_pending_event)

	Globals.log_message(
		"Remapped %s (device-specific unbind)" % current_remap_button.action, Globals.LogLevel.DEBUG
	)

	# 3. Save (now only the right device is affected)
	Settings.save_input_mappings()

	# 4. Finish UI
	current_remap_button.finish_remap()
	update_all_remap_buttons()

	# Cleanup
	_clear_conflict_state()

	# NEW: Clear critical warning flag when player fixes unbound (once-per-session)
	var main := get_tree().current_scene
	if main and main is MainScene:
		main.clear_unbound_warning()


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
	# You must update the UI buttons so they show the new defaults!
	update_all_remap_buttons()
	Globals.log_message("Resetting " + device_type + " controls.", Globals.LogLevel.DEBUG)
	# NEW: Clear critical warning flag when player fixes unbound (once-per-session)
	var main := get_tree().current_scene
	if main and main is MainScene:
		main.clear_unbound_warning()


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
	# queue_free() frees the menu only at the end of the frame. A second Back before then (a
	# double press or a JS burst) must not pop the menu stack or change the overlays again.
	if _intentional_exit:
		Globals.log_message(
			"Back ignored: controls menu is already closing.", Globals.LogLevel.DEBUG
		)
		return
	_intentional_exit = true
	var hidden_menu_found: bool = false
	# Only the Options menu owns the Options DOM buttons. When the main menu's "Unbound
	# Controls" dialog opened Key Mapping, Back returns to the main menu instead (#1165).
	var returned_to_options: bool = false
	var prev_menu: Node = null
	# Pop into a Variant first: assigning a freed instance straight to a typed Node var raises
	# "Trying to assign invalid previously freed instance" and stops Back. Freed entries are
	# skipped and the next valid menu is shown, as SettingsMenuBase does (#1211).
	while prev_menu == null and not Globals.hidden_menus.is_empty():
		var popped: Variant = Globals.hidden_menus.pop_back()
		if is_instance_valid(popped):
			prev_menu = popped
		else:
			Globals.log_message("Discarding freed entry from hidden_menus.", Globals.LogLevel.DEBUG)
	if prev_menu != null:
		prev_menu.visible = true
		Globals.log_message("Showing menu: " + prev_menu.name, Globals.LogLevel.DEBUG)
		hidden_menu_found = true
		# NEW: When returning from Key Mapping menu → focus the Key Mapping button in Options
		if prev_menu is OptionsMenu:
			returned_to_options = true
			(prev_menu as OptionsMenu).grab_focus_on_key_mapping_button()
		# NEW: When returning to Main Menu → focus Start Game button
		elif prev_menu.name == "Panel" or prev_menu is Panel:  # ← this is the fix
			var start_button: Button = prev_menu.get_node_or_null("VBoxContainer/StartButton")
			if is_instance_valid(start_button):
				# Triple-deferred to be 100% sure after visibility change
				start_button.call_deferred("call_deferred", "call_deferred", "grab_focus")
				Globals.log_message(
					"Focus restored to Start Game button (triple deferred)", Globals.LogLevel.DEBUG
				)

	# Decoupled cleanup: Run if web and js_window available, but gate eval on js_bridge_wrapper
	if os_wrapper.has_feature("web") and js_window:
		# controls-back-button is shared by every Key Mapping: hide it only if this instance owns
		# it, or no instance does. A newer Key Mapping that took over still needs it (#1166).
		var owns_back_button: bool = (
			_window_callback_owner_id == get_instance_id() or _window_callback_owner_id == 0
		)
		_unset_key_mapping_window_callbacks()
		# Hide controls-back-button even when no hidden menu is found. Show the Options buttons
		# only when Back returns to the Options menu.
		if js_bridge_wrapper:
			var visible_ids: Array[String] = []
			# Not while a newer Key Mapping still owns the Back button: it is open over Options.
			if returned_to_options and owns_back_button:
				visible_ids = SettingsMenuBase.OPTIONS_MENU_OVERLAY_IDS
			var hidden_ids: Array[String] = []
			if owns_back_button:
				hidden_ids = ["controls-back-button"]
			if not visible_ids.is_empty() or not hidden_ids.is_empty():
				js_bridge_wrapper.eval(
					SettingsMenuBase._build_overlay_js(visible_ids, hidden_ids), true
				)
	if not hidden_menu_found:
		Globals.log_message("No hidden menu to show.", Globals.LogLevel.INFO)
	queue_free()


## Unexpected exits (scene change, parent freed) skip the Back path, so clear the JS entry
## point here too, and hide its overlay button so no shown control is left without a
## callback (#1166).
func _exit_tree() -> void:
	# Only while this instance owns the slot: after Back (which already hid the button and reset
	# the owner) or once a newer Key Mapping took over, the button belongs to someone else.
	var owned_slot: bool = _window_callback_owner_id == get_instance_id()
	_unset_key_mapping_window_callbacks()
	if owned_slot and js_bridge_wrapper:
		js_bridge_wrapper.eval(
			SettingsMenuBase._build_overlay_js([], ["controls-back-button"]), true
		)
	Globals.log_message("Key Mapping menu exited (left the tree).", Globals.LogLevel.DEBUG)


## Detaches the Key Mapping JS entry point from `window` (web only) and drops the callback ref.
##
## Clears the slot only while this instance owns it. Another Key Mapping can take it over before
## this one exits: one reopened in the same frame as Back (this instance's _exit_tree() runs at
## the end of the frame), or a second one opened while this one is still open. That instance's
## callback must stay (#1166). Idempotent.
func _unset_key_mapping_window_callbacks() -> void:
	# This can run inside one of these callbacks (a JS press that frees the menu), so drop the
	# refs after the call returns: a callback must not be freed during its own call.
	_drop_key_mapping_callback_refs.call_deferred()
	if not os_wrapper.has_feature("web") or not js_window:
		return
	if _window_callback_owner_id != get_instance_id():
		return
	js_window.controlsBackPressed = null
	_window_callback_owner_id = 0


func _drop_key_mapping_callback_refs() -> void:
	_controls_back_button_pressed_cb = null


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


## Callback triggered when the keyboard device toggle is interacted with.
## Saves the input preference to persistent settings, updates the UI button mappings,
## and plays confirmation audio feedback using the centralized SFX map.
## [param toggled_on]: The current boolean state of the toggle button.
func _on_keyboard_toggled(toggled_on: bool) -> void:
	if toggled_on:
		Globals.current_input_device = "keyboard"
		Settings.save_last_input_device("keyboard")
		update_all_remap_buttons()
		# FIX: Pass BUS_SFX_MENU explicitly as requested by reviewer
		SfxManager.play_sfx(AudioConstants.SFX_CHECK, AudioConstants.BUS_SFX_MENU)
		Globals.log_message("Current input device set to: keyboard", Globals.LogLevel.DEBUG)


## Callback triggered when the gamepad device toggle is interacted with.
## Saves the input preference to persistent settings, updates the UI button mappings,
## and plays confirmation audio feedback using the centralized SFX map.
## [param toggled_on]: The current boolean state of the toggle button.
func _on_gamepad_toggled(toggled_on: bool) -> void:
	if toggled_on:
		Globals.current_input_device = "gamepad"
		Settings.save_last_input_device("gamepad")
		update_all_remap_buttons()
		# FIX: Pass BUS_SFX_MENU explicitly as requested by reviewer
		SfxManager.play_sfx(AudioConstants.SFX_CHECK, AudioConstants.BUS_SFX_MENU)
		Globals.log_message("Current input device set to: gamepad", Globals.LogLevel.DEBUG)
