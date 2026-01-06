## audio_settings.gd (updated with flags for testing warning popups)
##
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
## :vartype _intentional_exit: bool

extends Control

# global
var js_window: Variant
var os_wrapper: OSWrapper = OSWrapper.new()
var js_bridge_wrapper: JavaScriptBridgeWrapper = JavaScriptBridgeWrapper.new()

# Test flags for warning popups (to reliably test in CI/headless)
var master_warning_shown: bool = false
var sfx_warning_shown: bool = false

# local
var _audio_back_button_pressed_cb: Variant
var _previous_back_pressed_cb: Variant
var _intentional_exit: bool = false

# Master Volume Controls
@onready
var master_slider: HSlider = $Panel/OptionsContainer/VolumeControls/Master/MasterControl/HSlider
@onready var mute_master: CheckButton = $Panel/OptionsContainer/VolumeControls/Master/Mute
# Music Volume Controls
@onready
var music_slider: HSlider = $Panel/OptionsContainer/VolumeControls/Music/MusicControl/HSlider
@onready var mute_music: CheckButton = $Panel/OptionsContainer/VolumeControls/Music/Mute
# SFX Volume Controls
@onready var sfx_slider: HSlider = $Panel/OptionsContainer/VolumeControls/SFX/SFXControl/HSlider
@onready var mute_sfx: CheckButton = $Panel/OptionsContainer/VolumeControls/SFX/Mute
# SFX Weapon Volume Controls
@onready
var weapon_slider: HSlider = $Panel/OptionsContainer/VolumeControls/SFXWeapon/WeaponControl/HSlider
@onready var mute_weapon: CheckButton = $Panel/OptionsContainer/VolumeControls/SFXWeapon/Mute
# SFX Rotor Volume Controls
@onready
var rotor_slider: HSlider = $Panel/OptionsContainer/VolumeControls/SFXRotors/RotorsControl/HSlider
@onready var mute_rotor: CheckButton = $Panel/OptionsContainer/VolumeControls/SFXRotors/Mute
#Other UI elements
@onready var master_warning_dialog: AcceptDialog = $MasterWarningDialog
@onready var sfx_warning_dialog: AcceptDialog = $SFXWarningDialog
@onready var audio_back_button: Button = $Panel/OptionsContainer/BtnContainer/AudioBackButton
@onready var audio_reset_button: Button = $Panel/OptionsContainer/BtnContainer/AudioResetButton


func _ready() -> void:
	## Initializes audio menu.
	##
	## Connects signals, configures process mode.
	##
	## Toggles web overlays if on web.
	##
	## :rtype: void
	##

	# Warning popup message
	master_warning_dialog.title = "Warning"
	master_warning_dialog.dialog_text = "To adjust this volume, please unmute the Master volume first."
	sfx_warning_dialog.title = "Warning"
	sfx_warning_dialog.dialog_text = "To adjust this volume, please unmute the SFX volume first."

	# Connect dialog close signals for flag reset
	if not master_warning_dialog.confirmed.is_connected(_reset_master_warning_shown):
		master_warning_dialog.confirmed.connect(_reset_master_warning_shown)
	if not master_warning_dialog.canceled.is_connected(_reset_master_warning_shown):
		master_warning_dialog.canceled.connect(_reset_master_warning_shown)
	if not sfx_warning_dialog.confirmed.is_connected(_reset_sfx_warning_shown):
		sfx_warning_dialog.confirmed.connect(_reset_sfx_warning_shown)
	if not sfx_warning_dialog.canceled.is_connected(_reset_sfx_warning_shown):
		sfx_warning_dialog.canceled.connect(_reset_sfx_warning_shown)

	# Master Mute toggle master_slider
	if not mute_master.toggled.is_connected(_on_master_mute_toggled):
		mute_master.toggled.connect(_on_master_mute_toggled)  # Use toggled for CheckButton state
	mute_master.button_pressed = not AudioManager.master_muted  # Direct sync (checked = unmuted)

	# Master slider input for unmute on click
	if not master_slider.gui_input.is_connected(_on_master_volume_control_gui_input):
		master_slider.gui_input.connect(_on_master_volume_control_gui_input)
	master_slider.editable = not AudioManager.master_muted  # Initial state

	# Music (New)
	if not mute_music.toggled.is_connected(_on_music_mute_toggled):
		mute_music.toggled.connect(_on_music_mute_toggled)
	mute_music.button_pressed = not AudioManager.music_muted
	if not music_slider.gui_input.is_connected(_on_music_volume_control_gui_input):
		music_slider.gui_input.connect(_on_music_volume_control_gui_input)
	if not mute_music.gui_input.is_connected(_on_music_mute_gui_input):
		mute_music.gui_input.connect(_on_music_mute_gui_input)

	# SFX (New)
	if not mute_sfx.toggled.is_connected(_on_sfx_mute_toggled):
		mute_sfx.toggled.connect(_on_sfx_mute_toggled)
	mute_sfx.button_pressed = not AudioManager.sfx_muted
	if not sfx_slider.gui_input.is_connected(_on_sfx_volume_control_gui_input):
		sfx_slider.gui_input.connect(_on_sfx_volume_control_gui_input)
	if not mute_sfx.gui_input.is_connected(_on_sfx_mute_gui_input):
		mute_sfx.gui_input.connect(_on_sfx_mute_gui_input)

	# Weapon (New)
	if not mute_weapon.toggled.is_connected(_on_weapon_mute_toggled):
		mute_weapon.toggled.connect(_on_weapon_mute_toggled)
	mute_weapon.button_pressed = not AudioManager.weapon_muted
	if not weapon_slider.gui_input.is_connected(_on_weapon_volume_control_gui_input):
		weapon_slider.gui_input.connect(_on_weapon_volume_control_gui_input)
	if not mute_weapon.gui_input.is_connected(_on_weapon_mute_gui_input):
		mute_weapon.gui_input.connect(_on_weapon_mute_gui_input)

	# Rotors (New)
	if not mute_rotor.toggled.is_connected(_on_rotor_mute_toggled):
		mute_rotor.toggled.connect(_on_rotor_mute_toggled)
	mute_rotor.button_pressed = not AudioManager.rotors_muted
	if not rotor_slider.gui_input.is_connected(_on_rotor_volume_control_gui_input):
		rotor_slider.gui_input.connect(_on_rotor_volume_control_gui_input)
	if not mute_rotor.gui_input.is_connected(_on_rotor_mute_gui_input):
		mute_rotor.gui_input.connect(_on_rotor_mute_gui_input)

	# Back buttom
	if not audio_back_button.pressed.is_connected(_on_audio_back_button_pressed):
		audio_back_button.pressed.connect(_on_audio_back_button_pressed)

	tree_exited.connect(_on_tree_exited)
	process_mode = Node.PROCESS_MODE_ALWAYS
	Globals.log_message("Audio menu loaded.", Globals.LogLevel.DEBUG)
	# Apply initial UI state for others based on master (New)
	_update_other_controls_ui()

	# Reset button listener
	if not audio_reset_button.pressed.is_connected(_on_audio_reset_button_pressed):
		audio_reset_button.pressed.connect(_on_audio_reset_button_pressed)

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
		if js_window:  # New: Null check
			_audio_back_button_pressed_cb = js_bridge_wrapper.create_callback(
				Callable(self, "_on_audio_back_button_pressed_js")
			)
			_previous_back_pressed_cb = js_window.backPressed  # Save previous before overwrite
			js_window.backPressed = _audio_back_button_pressed_cb  # Set audio callback


func _on_master_mute_toggled(toggled_on: bool) -> void:
	AudioManager.master_muted = not toggled_on  # Set directly to button state (instead of toggle)
	master_slider.editable = not AudioManager.master_muted
	_update_other_controls_ui()

	AudioManager.apply_volume_to_bus(
		AudioConstants.BUS_MASTER, AudioManager.master_volume, AudioManager.master_muted
	)
	AudioManager.save_volumes()
	Globals.log_message("Master mute button toggled to: " + str(toggled_on), Globals.LogLevel.DEBUG)


# New: Music toggle
func _on_music_mute_toggled(toggled_on: bool) -> void:
	AudioManager.music_muted = not toggled_on
	music_slider.editable = not AudioManager.music_muted

	AudioManager.apply_volume_to_bus(
		AudioConstants.BUS_MUSIC, AudioManager.music_volume, AudioManager.music_muted
	)
	AudioManager.save_volumes()
	Globals.log_message("Music mute button toggled to: " + str(toggled_on), Globals.LogLevel.DEBUG)


# New: SFX toggle
func _on_sfx_mute_toggled(toggled_on: bool) -> void:
	AudioManager.sfx_muted = not toggled_on
	sfx_slider.editable = not AudioManager.sfx_muted
	_update_sfx_controls_ui()

	AudioManager.apply_volume_to_bus(
		AudioConstants.BUS_SFX, AudioManager.sfx_volume, AudioManager.sfx_muted
	)
	AudioManager.save_volumes()
	Globals.log_message("SFX mute button toggled to: " + str(toggled_on), Globals.LogLevel.DEBUG)


# New: Weapon toggle
func _on_weapon_mute_toggled(toggled_on: bool) -> void:
	AudioManager.weapon_muted = not toggled_on
	weapon_slider.editable = not AudioManager.weapon_muted
	_update_sfx_controls_ui()

	AudioManager.apply_volume_to_bus(
		AudioConstants.BUS_SFX_WEAPON, AudioManager.weapon_volume, AudioManager.weapon_muted
	)
	AudioManager.save_volumes()
	Globals.log_message("Weapon mute button toggled to: " + str(toggled_on), Globals.LogLevel.DEBUG)


# New: Rotor toggle
func _on_rotor_mute_toggled(toggled_on: bool) -> void:
	AudioManager.rotors_muted = not toggled_on
	rotor_slider.editable = not AudioManager.rotors_muted
	_update_sfx_controls_ui()

	AudioManager.apply_volume_to_bus(
		AudioConstants.BUS_SFX_ROTORS, AudioManager.rotors_volume, AudioManager.rotors_muted
	)
	AudioManager.save_volumes()
	Globals.log_message("Rotors mute button toggled to: " + str(toggled_on), Globals.LogLevel.DEBUG)


# New: Update UI for other controls based on master muted
func _update_other_controls_ui() -> void:
	var is_master_muted: bool = AudioManager.master_muted
	# Music
	mute_music.disabled = is_master_muted
	music_slider.editable = not is_master_muted and not AudioManager.music_muted
	# SFX
	mute_sfx.disabled = is_master_muted
	sfx_slider.editable = not is_master_muted and not AudioManager.sfx_muted
	_update_sfx_controls_ui()


# New: Update UI for SFX sub-controls based on SFX/master mute state
func _update_sfx_controls_ui() -> void:
	var sfx_controls_locked: bool = AudioManager.sfx_muted or AudioManager.master_muted
	# Weapon
	mute_weapon.disabled = sfx_controls_locked
	weapon_slider.editable = not sfx_controls_locked and not AudioManager.weapon_muted
	# Rotors
	mute_rotor.disabled = sfx_controls_locked
	rotor_slider.editable = not sfx_controls_locked and not AudioManager.rotors_muted


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
		if js_window:  # New: Null check
			js_window.backPressed = _previous_back_pressed_cb  # Restore previous callback
		(
			js_bridge_wrapper
			. eval(
				"""
				document.getElementById('audio-back-button').style.display = 'none';
				"""
			)
		)
	_intentional_exit = true
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
	if _intentional_exit:
		return
	if os_wrapper.has_feature("web"):
		if js_window:  # New: Null check
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


func _on_master_volume_control_gui_input(event: InputEvent) -> void:
	## Handles GUI input on master volume control.
	##
	## Unmutes and enables slider if muted and clicked.
	##
	## :param event: The input event.
	## :type event: InputEvent
	## :rtype: void
	# Check if the event is a mouse button click
	if event is InputEventMouseButton and event.pressed and AudioManager.master_muted:
		if event.button_index == MOUSE_BUTTON_LEFT:
			mute_master.button_pressed = true  # Set button to pressed (unmuted) state visually
			get_viewport().set_input_as_handled()  # Consume the event to prevent further propagation
			Globals.log_message("Master Volume Slider is enabled now.", Globals.LogLevel.DEBUG)


# New: Music slider gui input (show warning if master muted)
# Music slider gui input (no SFX dependency)
func _on_music_volume_control_gui_input(event: InputEvent) -> void:
	# sfx_muted=false as placeholder
	_handle_slider_gui_input(
		event,
		AudioManager.master_muted,
		false,
		AudioManager.music_muted,
		mute_music,
		master_warning_dialog,
		sfx_warning_dialog
	)


# New: Music mute button gui input (show warning if master muted)
# Music mute button gui input (no SFX)
func _on_music_mute_gui_input(event: InputEvent) -> void:
	_handle_mute_gui_input(
		event, AudioManager.master_muted, false, master_warning_dialog, sfx_warning_dialog
	)


# New: SFX slider gui input
# SFX slider gui input (self as SFX)
func _on_sfx_volume_control_gui_input(event: InputEvent) -> void:
	# sfx_muted=false for self-check
	_handle_slider_gui_input(
		event,
		AudioManager.master_muted,
		false,
		AudioManager.sfx_muted,
		mute_sfx,
		master_warning_dialog,
		sfx_warning_dialog
	)


# New: SFX mute button gui input
# SFX mute button gui input (no SFX check for self)
func _on_sfx_mute_gui_input(event: InputEvent) -> void:
	_handle_mute_gui_input(
		event, AudioManager.master_muted, false, master_warning_dialog, sfx_warning_dialog
	)


# New: Rotor mute button gui input
func _on_rotor_mute_gui_input(event: InputEvent) -> void:
	_handle_mute_gui_input(
		event,
		AudioManager.master_muted,
		AudioManager.sfx_muted,
		master_warning_dialog,
		sfx_warning_dialog
	)


# New: Rotor slider gui input
func _on_rotor_volume_control_gui_input(event: InputEvent) -> void:
	_handle_slider_gui_input(
		event,
		AudioManager.master_muted,
		AudioManager.sfx_muted,
		AudioManager.rotors_muted,
		mute_rotor,
		master_warning_dialog,
		sfx_warning_dialog
	)


# New: Weapon slider gui input
func _on_weapon_volume_control_gui_input(event: InputEvent) -> void:
	_handle_slider_gui_input(
		event,
		AudioManager.master_muted,
		AudioManager.sfx_muted,
		AudioManager.weapon_muted,
		mute_weapon,
		master_warning_dialog,
		sfx_warning_dialog
	)


# New: Weapon mute button gui input
func _on_weapon_mute_gui_input(event: InputEvent) -> void:
	_handle_mute_gui_input(
		event,
		AudioManager.master_muted,
		AudioManager.sfx_muted,
		master_warning_dialog,
		sfx_warning_dialog
	)


## Handles common slider GUI input logic for warnings and unmute.
## :param event: The input event.
## :type event: InputEvent
## :param master_muted: Master's muted state.
## :type master_muted: bool
## :param sfx_muted: SFX's muted state (for SFX children).
## :type sfx_muted: bool
## :param bus_muted: Specific bus muted state.
## :type bus_muted: bool
## :param mute_button: The mute CheckButton.
## :type mute_button: CheckButton
## :param master_dialog: Master warning dialog.
## :type master_dialog: AcceptDialog
## :param sfx_dialog: SFX warning dialog.
## :type sfx_dialog: AcceptDialog
## :rtype: void
func _handle_slider_gui_input(
	event: InputEvent,
	master_muted: bool,
	sfx_muted: bool,
	bus_muted: bool,
	mute_button: CheckButton,
	master_dialog: AcceptDialog,
	sfx_dialog: AcceptDialog
) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if master_muted:
			master_dialog.popup_centered()
			master_warning_shown = true
			get_viewport().set_input_as_handled()
		elif sfx_muted:
			sfx_dialog.popup_centered()
			sfx_warning_shown = true
			get_viewport().set_input_as_handled()
		elif bus_muted:
			mute_button.button_pressed = true
			# No consume - allow slide


## Handles common mute button GUI input logic for warnings.
## :param event: The input event.
## :type event: InputEvent
## :param master_muted: Master's muted state.
## :type master_muted: bool
## :param sfx_muted: SFX's muted state (for SFX children).
## :type sfx_muted: bool
## :param master_dialog: Master warning dialog.
## :type master_dialog: AcceptDialog
## :param sfx_dialog: SFX warning dialog.
## :type sfx_dialog: AcceptDialog
## :rtype: void
func _handle_mute_gui_input(
	event: InputEvent,
	master_muted: bool,
	sfx_muted: bool,
	master_dialog: AcceptDialog,
	sfx_dialog: AcceptDialog
) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if master_muted:
			master_dialog.popup_centered()
			master_warning_shown = true
			get_viewport().set_input_as_handled()
		elif sfx_muted:
			sfx_dialog.popup_centered()
			sfx_warning_shown = true
			get_viewport().set_input_as_handled()


## Resets master_warning_shown flag.
## :rtype: void
func _reset_master_warning_shown() -> void:
	master_warning_shown = false


## Resets sfx_warning_shown flag.
## :rtype: void
func _reset_sfx_warning_shown() -> void:
	sfx_warning_shown = false


# Reset button functionality
func _on_audio_reset_button_pressed() -> void:
	# Reset all mute flags to false (unmuted)
	AudioManager.master_muted = false
	AudioManager.music_muted = false
	AudioManager.sfx_muted = false
	AudioManager.weapon_muted = false
	AudioManager.rotors_muted = false

	# Reset all volumes to maximum (1.0)
	AudioManager.master_volume = 1.0
	AudioManager.music_volume = 1.0
	AudioManager.sfx_volume = 1.0
	AudioManager.weapon_volume = 1.0
	AudioManager.rotors_volume = 1.0

	# Apply the changes to AudioServer
	AudioManager.apply_all_volumes()

	# Save the reset settings
	AudioManager.save_volumes()

	# Update UI elements to reflect resets
	mute_master.button_pressed = true  # Unmuted
	master_slider.value = 1.0
	master_slider.editable = true

	mute_music.button_pressed = true
	music_slider.value = 1.0
	music_slider.editable = true

	mute_sfx.button_pressed = true
	sfx_slider.value = 1.0
	sfx_slider.editable = true

	mute_weapon.button_pressed = true
	weapon_slider.value = 1.0
	weapon_slider.editable = true

	mute_rotor.button_pressed = true
	rotor_slider.value = 1.0
	rotor_slider.editable = true

	# Update dependent UI states
	_update_other_controls_ui()

	Globals.log_message("Audio settings reset to defaults.", Globals.LogLevel.DEBUG)
