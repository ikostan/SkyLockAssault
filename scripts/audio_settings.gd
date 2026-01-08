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

# Volume controls
var _change_master_volume_cb: Variant
var _change_music_volume_cb: Variant
var _change_sfx_volume_cb: Variant
var _change_weapon_volume_cb: Variant
var _change_rotors_volume_cb: Variant
# Mute toggle
var _toggle_mute_master_cb: Variant
var _toggle_mute_music_cb: Variant
var _toggle_mute_sfx_cb: Variant
var _toggle_mute_weapon_cb: Variant
var _toggle_mute_rotors_cb: Variant
# Reset button
var _audio_reset_cb: Variant

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

	# Reset button listener
	if not audio_reset_button.pressed.is_connected(_on_audio_reset_button_pressed):
		audio_reset_button.pressed.connect(_on_audio_reset_button_pressed)

	tree_exited.connect(_on_tree_exited)
	process_mode = Node.PROCESS_MODE_ALWAYS
	Globals.log_message("Audio menu loaded.", Globals.LogLevel.DEBUG)

	_sync_ui_from_manager()
	# Apply initial UI state for others based on master (New)
	# _update_other_controls_ui()

	if os_wrapper.has_feature("web"):
		_toggle_audio_dom_visibility("block")
		js_window = js_bridge_wrapper.get_interface("window")
		if js_window:  # New: Null check
			_audio_back_button_pressed_cb = js_bridge_wrapper.create_callback(
				Callable(self, "_on_audio_back_button_pressed_js")
			)
			_previous_back_pressed_cb = js_window.backPressed  # Save previous before overwrite
			js_window.backPressed = _audio_back_button_pressed_cb  # Set audio callback
			##
			# Expose callbacks for changing volume
			# Master Volume
			_change_master_volume_cb = js_bridge_wrapper.create_callback(
				Callable(self, "_on_change_master_volume_js")
			)
			js_window.changeMasterVolume = _change_master_volume_cb
			# Music Volume
			_change_music_volume_cb = js_bridge_wrapper.create_callback(
				Callable(self, "_on_change_music_volume_js")
			)
			js_window.changeMusicVolume = _change_music_volume_cb
			# SFX Volume
			_change_sfx_volume_cb = js_bridge_wrapper.create_callback(
				Callable(self, "_on_change_sfx_volume_js")
			)
			js_window.changeSfxVolume = _change_sfx_volume_cb
			# Weapon Volume
			_change_weapon_volume_cb = js_bridge_wrapper.create_callback(
				Callable(self, "_on_change_weapon_volume_js")
			)
			js_window.changeWeaponVolume = _change_weapon_volume_cb
			# Rotors Volume
			_change_rotors_volume_cb = js_bridge_wrapper.create_callback(
				Callable(self, "_on_change_rotors_volume_js")
			)
			js_window.changeRotorsVolume = _change_rotors_volume_cb
			##
			# Expose callbacks for mute
			# Mute Master
			_toggle_mute_master_cb = js_bridge_wrapper.create_callback(
				Callable(self, "_on_toggle_mute_master_js")
			)
			js_window.toggleMuteMaster = _toggle_mute_master_cb
			# Mute Music
			_toggle_mute_music_cb = js_bridge_wrapper.create_callback(
				Callable(self, "_on_toggle_mute_music_js")
			)
			js_window.toggleMuteMusic = _toggle_mute_music_cb
			# Mute SFX
			_toggle_mute_sfx_cb = js_bridge_wrapper.create_callback(
				Callable(self, "_on_toggle_mute_sfx_js")
			)
			js_window.toggleMuteSfx = _toggle_mute_sfx_cb
			# Mute Weapon
			_toggle_mute_weapon_cb = js_bridge_wrapper.create_callback(
				Callable(self, "_on_toggle_mute_weapon_js")
			)
			js_window.toggleMuteWeapon = _toggle_mute_weapon_cb
			# Mute Rototors
			_toggle_mute_rotors_cb = js_bridge_wrapper.create_callback(
				Callable(self, "_on_toggle_mute_rotors_js")
			)
			js_window.toggleMuteRotors = _toggle_mute_rotors_cb
			# Expose callbacks for Reset button
			_audio_reset_cb = js_bridge_wrapper.create_callback(
				Callable(self, "_on_audio_reset_js")
			)
			js_window.audioReset = _audio_reset_cb
		_sync_dom_ui()


## Sync DOM overlays from Godot UI.
## :rtype: void
func _sync_dom_ui() -> void:
	if not os_wrapper.has_feature("web"):
		return
	js_bridge_wrapper.eval(
		"document.getElementById('master-slider').value = " + str(master_slider.value)
	)
	js_bridge_wrapper.eval(
		"document.getElementById('music-slider').value = " + str(music_slider.value)
	)
	js_bridge_wrapper.eval("document.getElementById('sfx-slider').value = " + str(sfx_slider.value))
	js_bridge_wrapper.eval(
		"document.getElementById('weapon-slider').value = " + str(weapon_slider.value)
	)
	js_bridge_wrapper.eval(
		"document.getElementById('rotors-slider').value = " + str(rotor_slider.value)
	)
	js_bridge_wrapper.eval(
		"document.getElementById('mute-master').checked = " + str(mute_master.button_pressed)
	)
	js_bridge_wrapper.eval(
		"document.getElementById('mute-music').checked = " + str(mute_music.button_pressed)
	)
	js_bridge_wrapper.eval(
		"document.getElementById('mute-sfx').checked = " + str(mute_sfx.button_pressed)
	)
	js_bridge_wrapper.eval(
		"document.getElementById('mute-weapon').checked = " + str(mute_weapon.button_pressed)
	)
	js_bridge_wrapper.eval(
		"document.getElementById('mute-rotors').checked = " + str(mute_rotor.button_pressed)
	)


## MASTER VOLUME
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


func _on_master_mute_toggled(toggled_on: bool) -> void:
	AudioManager.master_muted = not toggled_on  # Set directly to button state (instead of toggle)
	master_slider.editable = not AudioManager.master_muted
	_update_other_controls_ui()

	AudioManager.apply_volume_to_bus(
		AudioConstants.BUS_MASTER, AudioManager.master_volume, AudioManager.master_muted
	)
	AudioManager.save_volumes()
	Globals.log_message("Master mute button toggled to: " + str(toggled_on), Globals.LogLevel.DEBUG)
	_sync_dom_ui()


# New: JS callback for master volume
## :param args: Array with volume value.
## :type args: Array
## :rtype: void
func _on_change_master_volume_js(args: Array) -> void:
	if args.is_empty() or args[0].is_empty() or typeof(args[0][0]) != TYPE_FLOAT:
		Globals.log_message("Invalid args in _on_change_master_volume_js: " + str(args), Globals.LogLevel.ERROR)
		return

	# if args.size() > 0:
	var value: float = float(args[0][0])
	# AudioManager.set_volume(AudioConstants.BUS_MASTER, value)
	AudioManager.master_volume = value
	master_slider.set_value_no_signal(value)
	AudioManager.apply_volume_to_bus(
		AudioConstants.BUS_MASTER, value, AudioManager.master_muted
	)
	Globals.log_message("Master volume changed to: " + str(value), Globals.LogLevel.DEBUG)
	AudioManager.save_volumes()  # Call save directly (no debounce in this scope)
	_sync_dom_ui()


func _on_toggle_mute_master_js(args: Array) -> void:
	if args.is_empty() or args[0].is_empty() or typeof(args[0][0]) != TYPE_FLOAT:
		Globals.log_message("Invalid args in _on_toggle_mute_master_js: " + str(args), Globals.LogLevel.ERROR)
		return

	# if args.size() > 0:
	var checked: bool = bool(args[0][0])
	# print("checked: " + str(checked))
	mute_master.button_pressed = checked
	# _on_master_mute_toggled(checked)  # Adjust to your toggled func
	# _sync_dom_ui()


## MUSIC VOLUME
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


# New: Music toggle
func _on_music_mute_toggled(toggled_on: bool) -> void:
	AudioManager.music_muted = not toggled_on
	music_slider.editable = not AudioManager.music_muted

	AudioManager.apply_volume_to_bus(
		AudioConstants.BUS_MUSIC, AudioManager.music_volume, AudioManager.music_muted
	)
	AudioManager.save_volumes()
	Globals.log_message("Music mute button toggled to: " + str(toggled_on), Globals.LogLevel.DEBUG)
	_sync_dom_ui()


# New: Music mute button gui input (show warning if master muted)
# Music mute button gui input (no SFX)
func _on_music_mute_gui_input(event: InputEvent) -> void:
	_handle_mute_gui_input(
		event, AudioManager.master_muted, false, master_warning_dialog, sfx_warning_dialog
	)


# New: JS callback for music volume
## :param args: Array with volume value (e.g., [[0.5]]).
## :type args: Array
## :rtype: void
func _on_change_music_volume_js(args: Array) -> void:
	if args.is_empty() or args[0].is_empty() or typeof(args[0][0]) != TYPE_FLOAT:
		Globals.log_message("Invalid args in _on_change_music_volume_js: " + str(args), Globals.LogLevel.ERROR)
		return
	
	# if args.size() > 0:
	var value: float = float(args[0][0])  # Parse the float from JS array
	# Clamp value to valid range (0.0-1.0) for safety
	value = clamp(value, 0.0, 1.0)

	# Update AudioManager (sets music_volume)
	AudioManager.set_volume(AudioConstants.BUS_MUSIC, value)

	# Apply to AudioServer bus (handles db conversion and mute check)
	AudioManager.apply_volume_to_bus(AudioConstants.BUS_MUSIC, value, AudioManager.music_muted)

	# Log for debugging (visible in Godot console or browser logs)
	Globals.log_message("Music volume changed to: " + str(value), Globals.LogLevel.DEBUG)
	Globals.log_message(
		"Music Volume Level in AudioManager: " + str(AudioManager.music_volume),
		Globals.LogLevel.DEBUG
	)

	# Save changes to config (persistent across sessions)
	AudioManager.save_volumes()

	# Sync UI (update slider value without emitting signals, keep editable state)
	music_slider.set_value_no_signal(value)
	_sync_dom_ui()


func _on_toggle_mute_music_js(args: Array) -> void:
	if args.is_empty() or args[0].is_empty() or (typeof(args[0][0]) != TYPE_BOOL and typeof(args[0][0]) != TYPE_INT):
		Globals.log_message("Invalid args in _on_toggle_mute_music_js: " + str(args), Globals.LogLevel.ERROR)
		return

	# if args.size() > 0:
	var checked: bool = bool(args[0][0])  # true if button is checked (unmuted)
	# _on_music_mute_toggled(checked)
	mute_music.button_pressed = checked


## SFX VOLUME
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
	_sync_dom_ui()


# New: SFX mute button gui input
# SFX mute button gui input (no SFX check for self)
func _on_sfx_mute_gui_input(event: InputEvent) -> void:
	_handle_mute_gui_input(
		event, AudioManager.master_muted, false, master_warning_dialog, sfx_warning_dialog
	)


# New: JS callback for SFX volume
## Directly updates AudioManager and UI, mimicking volume_slider.gd logic.
## :param args: Array with volume value (e.g., [[0.5]]).
## :type args: Array
## :rtype: void
func _on_change_sfx_volume_js(args: Array) -> void:
	if args.is_empty() or args[0].is_empty() or typeof(args[0][0]) != TYPE_FLOAT:
		Globals.log_message("Invalid args in _on_change_sfx_volume_js: " + str(args), Globals.LogLevel.ERROR)
		return

	# if args.size() > 0:
	var value: float = float(args[0][0])  # Parse from JS array
	value = clamp(value, 0.0, 1.0)  # Safety: Prevent invalid values (e.g., from test scripts)

	# Update AudioManager (sets sfx_volume)
	AudioManager.set_volume(AudioConstants.BUS_SFX, value)

	# Apply to AudioServer bus (handles db conversion and mute check)
	AudioManager.apply_volume_to_bus(AudioConstants.BUS_SFX, value, AudioManager.sfx_muted)

	# Log the change (matches your DEBUG logs in audio_manager.gd)
	Globals.log_message("SFX volume level changed: " + str(value), Globals.LogLevel.DEBUG)
	Globals.log_message(
		"SFX Volume Level in AudioManager: " + str(AudioManager.sfx_volume),
		Globals.LogLevel.DEBUG
	)

	# Save settings (direct call, persistent across runs)
	AudioManager.save_volumes()

	# Sync UI without emitting signals (updates slider visually)
	sfx_slider.set_value_no_signal(value)

	# Update dependent controls (e.g., enables/disables weapon/rotor if SFX mute affects them)
	_update_other_controls_ui()
	_sync_dom_ui()


func _on_toggle_mute_sfx_js(args: Array) -> void:
	if args.is_empty() or args[0].is_empty() or (typeof(args[0][0]) != TYPE_BOOL and typeof(args[0][0]) != TYPE_INT):
		Globals.log_message("Invalid args in _on_toggle_mute_sfx_js: " + str(args), Globals.LogLevel.ERROR)
		return
	
	# if args.size() > 0:
	var checked: bool = bool(args[0][0])  # true if button is checked (unmuted)
	# _on_sfx_mute_toggled(checked)
	mute_sfx.button_pressed = checked


## WEAPON VOLUME
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
	_sync_dom_ui()


# New: Weapon mute button gui input
func _on_weapon_mute_gui_input(event: InputEvent) -> void:
	_handle_mute_gui_input(
		event,
		AudioManager.master_muted,
		AudioManager.sfx_muted,
		master_warning_dialog,
		sfx_warning_dialog
	)


# New: JS callback for Weapon volume
## Directly updates AudioManager and UI, mimicking volume_slider.gd logic.
## :param args: Array with volume value (e.g., [[0.5]]).
## :type args: Array
## :rtype: void
func _on_change_weapon_volume_js(args: Array) -> void:
	if args.is_empty() or args[0].is_empty() or typeof(args[0][0]) != TYPE_FLOAT:
		Globals.log_message("Invalid args in _on_change_weapon_volume_js: " + str(args), Globals.LogLevel.ERROR)
		return

	# if args.size() > 0:
	var value: float = float(args[0][0])  # Parse from JS array
	value = clamp(value, 0.0, 1.0)  # Safety: Prevent invalid values (e.g., from test scripts)

	# Update AudioManager (sets sfx_volume)
	AudioManager.set_volume(AudioConstants.BUS_SFX_WEAPON, value)

	# Apply to AudioServer bus (handles db conversion and mute check)
	AudioManager.apply_volume_to_bus(
		AudioConstants.BUS_SFX_WEAPON, value, AudioManager.weapon_muted
	)

	# Log the change (matches your DEBUG logs in audio_manager.gd)
	Globals.log_message("Weapon volume level changed: " + str(value), Globals.LogLevel.DEBUG)
	Globals.log_message(
		"Weapon Volume Level in AudioManager: " + str(AudioManager.weapon_volume),
		Globals.LogLevel.DEBUG
	)

	# Save settings (direct call, persistent across runs)
	AudioManager.save_volumes()

	# Sync UI without emitting signals (updates slider visually)
	weapon_slider.set_value_no_signal(value)

	# Update dependent controls (e.g., enables/disables weapon/rotor if SFX mute affects them)
	_update_other_controls_ui()
	_sync_dom_ui()


func _on_toggle_mute_weapon_js(args: Array) -> void:
	if args.is_empty() or args[0].is_empty() or (typeof(args[0][0]) != TYPE_BOOL and typeof(args[0][0]) != TYPE_INT):
		Globals.log_message("Invalid args in _on_toggle_mute_weapon_js: " + str(args), Globals.LogLevel.ERROR)
		return

	# if args.size() > 0:
	var checked: bool = bool(args[0][0])  # true if button is checked (unmuted)
	# _on_weapon_mute_toggled(checked)
	mute_weapon.button_pressed = checked


## ROTORS VOLUME
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
	_sync_dom_ui()


# New: Rotor mute button gui input
func _on_rotor_mute_gui_input(event: InputEvent) -> void:
	_handle_mute_gui_input(
		event,
		AudioManager.master_muted,
		AudioManager.sfx_muted,
		master_warning_dialog,
		sfx_warning_dialog
	)


# New: JS callback for Rotors volume
## Directly updates AudioManager and UI, mimicking volume_slider.gd logic.
## :param args: Array with volume value (e.g., [[0.5]]).
## :type args: Array
## :rtype: void
func _on_change_rotors_volume_js(args: Array) -> void:
	if args.is_empty() or args[0].is_empty() or typeof(args[0][0]) != TYPE_FLOAT:
		Globals.log_message("Invalid args in _on_change_rotors_volume_js: " + str(args), Globals.LogLevel.ERROR)
		return

	# if args.size() > 0:
	var value: float = float(args[0][0])  # Parse from JS array
	value = clamp(value, 0.0, 1.0)  # Safety: Prevent invalid values (e.g., from test scripts)

	# Update AudioManager (sets sfx_volume)
	AudioManager.set_volume(AudioConstants.BUS_SFX_ROTORS, value)

	# Apply to AudioServer bus (handles db conversion and mute check)
	AudioManager.apply_volume_to_bus(
		AudioConstants.BUS_SFX_ROTORS, value, AudioManager.rotors_muted
	)

	# Log the change (matches your DEBUG logs in audio_manager.gd)
	Globals.log_message("Rotors volume level changed: " + str(value), Globals.LogLevel.DEBUG)
	Globals.log_message(
		"Rotors Volume Level in AudioManager: " + str(AudioManager.rotors_volume),
		Globals.LogLevel.DEBUG
	)

	# Save settings (direct call, persistent across runs)
	AudioManager.save_volumes()

	# Sync UI without emitting signals (updates slider visually)
	rotor_slider.set_value_no_signal(value)

	# Update dependent controls (e.g., enables/disables weapon/rotor if SFX mute affects them)
	_update_other_controls_ui()


func _on_toggle_mute_rotors_js(args: Array) -> void:
	if args.is_empty() or args[0].is_empty() or (typeof(args[0][0]) != TYPE_BOOL and typeof(args[0][0]) != TYPE_INT):
		Globals.log_message("Invalid args in _on_toggle_mute_rotors_js: " + str(args), Globals.LogLevel.ERROR)
		return

	# if args.size() > 0:
	var checked: bool = bool(args[0][0])  # true if button is checked (unmuted)
	# _on_rotor_mute_toggled(checked)
	mute_rotor.button_pressed = checked


## RESET BUTTON
## Update _on_audio_reset_button_pressed:
func _on_audio_reset_button_pressed() -> void:
	AudioManager.reset_volumes()
	_sync_ui_from_manager()
	_sync_dom_ui()


func _on_audio_reset_js(_args: Array) -> void:
	_on_audio_reset_button_pressed()


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
		_toggle_audio_dom_visibility("none")
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
		_toggle_audio_dom_visibility("none")

	if not Globals.hidden_menus.is_empty():
		var prev_menu: Node = Globals.hidden_menus.pop_back()
		if is_instance_valid(prev_menu):
			prev_menu.visible = true
			Globals.log_message(
				"Audio menu exited unexpectedly, restored previous menu.", Globals.LogLevel.WARNING
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


## Reset button functionality
## Sync all UI controls from AudioManager states without emitting signals
## :rtype: void
func _sync_ui_from_manager() -> void:
	mute_master.set_pressed_no_signal(not AudioManager.master_muted)
	master_slider.set_value_no_signal(AudioManager.master_volume)
	master_slider.editable = not AudioManager.master_muted

	mute_music.set_pressed_no_signal(not AudioManager.music_muted)
	music_slider.set_value_no_signal(AudioManager.music_volume)
	music_slider.editable = not AudioManager.music_muted

	mute_sfx.set_pressed_no_signal(not AudioManager.sfx_muted)
	sfx_slider.set_value_no_signal(AudioManager.sfx_volume)
	sfx_slider.editable = not AudioManager.sfx_muted

	mute_weapon.set_pressed_no_signal(not AudioManager.weapon_muted)
	weapon_slider.set_value_no_signal(AudioManager.weapon_volume)
	weapon_slider.editable = not AudioManager.weapon_muted

	mute_rotor.set_pressed_no_signal(not AudioManager.rotors_muted)
	rotor_slider.set_value_no_signal(AudioManager.rotors_volume)
	rotor_slider.editable = not AudioManager.rotors_muted

	_update_other_controls_ui()


func _toggle_audio_dom_visibility(visibility: String) -> void:
	## Toggles visibility of all audio DOM overlays.
	## :param visibility: "block" or "none".
	## :type visibility: String
	## :rtype: void
	(
		js_bridge_wrapper
		. eval(
			(
				"""
		document.getElementById('audio-back-button').style.display = '%s';
		document.getElementById('audio-reset-button').style.display = '%s';
		document.getElementById('master-slider').style.display = '%s';
		document.getElementById('music-slider').style.display = '%s';
		document.getElementById('sfx-slider').style.display = '%s';
		document.getElementById('weapon-slider').style.display = '%s';
		document.getElementById('rotors-slider').style.display = '%s';
		document.getElementById('mute-master').style.display = '%s';
		document.getElementById('mute-music').style.display = '%s';
		document.getElementById('mute-sfx').style.display = '%s';
		document.getElementById('mute-weapon').style.display = '%s';
		document.getElementById('mute-rotors').style.display = '%s';
	"""
				% [
					visibility,
					visibility,
					visibility,
					visibility,
					visibility,
					visibility,
					visibility,
					visibility,
					visibility,
					visibility,
					visibility,
					visibility
				]
			)
		)
	)
