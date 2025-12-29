## audio_settings.gd (add null checks)
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
# local
var _audio_back_button_pressed_cb: Variant
var _previous_back_pressed_cb: Variant
var _intentional_exit: bool = false
# Master Volume Controls
@onready var master_slider: HSlider = $Panel/OptionsVBoxContainer/VolumeControls/MasterVolume/MasterVolumeControl/HSlider
@onready var mute_master: CheckButton = $Panel/OptionsVBoxContainer/VolumeControls/MasterVolume/Mute
# Music Volume Controls
@onready var music_slider: HSlider = $Panel/OptionsVBoxContainer/VolumeControls/MusicVolume/MusicVolumeControl/HSlider
@onready var mute_music: CheckButton = $Panel/OptionsVBoxContainer/VolumeControls/MusicVolume/Mute
# SFX Volume Controls
@onready var sfx_slider: HSlider = $Panel/OptionsVBoxContainer/VolumeControls/SFXVolume/SFXVolumeControl/HSlider
@onready var mute_sfx: CheckButton = $Panel/OptionsVBoxContainer/VolumeControls/SFXVolume/Mute
# SFX Weapon Volume Controls
@onready var weapon_slider: HSlider = $Panel/OptionsVBoxContainer/VolumeControls/SFXWeapon/SFXWeaponVolumeControl/HSlider
@onready var mute_weapon: CheckButton = $Panel/OptionsVBoxContainer/VolumeControls/SFXWeapon/Mute
# SFX Rotor Volume Controls
@onready var rotor_slider: HSlider = $Panel/OptionsVBoxContainer/VolumeControls/SFXRotors/SFXRotorsVolumeControl/HSlider
@onready var mute_rotor: CheckButton = $Panel/OptionsVBoxContainer/VolumeControls/SFXRotors/Mute
#Other UI elements
@onready var warning_dialog: AcceptDialog = $WarningDialog
@onready var audio_back_button: Button = $Panel/OptionsVBoxContainer/AudioBackButton

var all_sliders_and_mutes: Array


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
	warning_dialog.title = "Warning"
	warning_dialog.dialog_text = "To adjust this volume, please unmute the Master volume first."

	# Master Mute toggle master_slider
	if not mute_master.toggled.is_connected(_on_master_mute_toggled):
		mute_master.toggled.connect(_on_master_mute_toggled)  # Use toggled for CheckButton state
	mute_master.button_pressed = not AudioManager.master_muted  # Direct sync (checked = muted)

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
	
	# Back buttom
	if not audio_back_button.pressed.is_connected(_on_audio_back_button_pressed):
		audio_back_button.pressed.connect(_on_audio_back_button_pressed)
	
	tree_exited.connect(_on_tree_exited)
	process_mode = Node.PROCESS_MODE_ALWAYS
	Globals.log_message("Audio menu loaded.", Globals.LogLevel.DEBUG)

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
			
	all_sliders_and_mutes = [
		[music_slider, mute_music, AudioManager.music_muted], 
		[sfx_slider, mute_sfx, AudioManager.sfx_muted], 
		[weapon_slider, mute_weapon, AudioManager.weapon_muted], 
		[rotor_slider, mute_rotor, AudioManager.rotors_muted]
	]
	
	if AudioManager.master_muted:
		for pair: Array in all_sliders_and_mutes:
			var slider: HSlider = pair[0]
			var mute: CheckButton = pair[1]
			
			if slider:
				slider.editable = not AudioManager.master_muted
			
			if mute:
				mute.disabled = AudioManager.master_muted
		

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


# New: Update UI for other controls based on master muted
func _update_other_controls_ui() -> void:
	var is_master_muted: bool = AudioManager.master_muted
	# Music
	mute_music.disabled = is_master_muted
	music_slider.editable = not is_master_muted and not AudioManager.music_muted
	# SFX
	mute_sfx.disabled = is_master_muted
	sfx_slider.editable = not is_master_muted and not AudioManager.sfx_muted
	# Weapon
	mute_weapon.disabled = is_master_muted
	weapon_slider.editable = not is_master_muted and not AudioManager.weapon_muted
	# Rotors
	mute_rotor.disabled = is_master_muted
	rotor_slider.editable = not is_master_muted and not AudioManager.rotors_muted
	

# New: Update UI for SFX sub-controls based on master muted
func _update_sfx_controls_ui() -> void:
	var is_master_muted: bool = AudioManager.sfx_muted
	# Weapon
	mute_weapon.disabled = is_master_muted
	weapon_slider.editable = not is_master_muted and not AudioManager.weapon_muted
	# Rotors
	mute_rotor.disabled = is_master_muted
	rotor_slider.editable = not is_master_muted and not AudioManager.rotors_muted


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
			_on_master_mute_toggled(true)
			mute_master.button_pressed = true  # Set button to pressed (unmuted) state visually
			get_viewport().set_input_as_handled()  # Consume the event to prevent further propagation
			Globals.log_message(
				"Master Volume Slider is enabled now.", Globals.LogLevel.DEBUG
			)


# New: Music slider gui input (show warning if master muted)
func _on_music_volume_control_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Display warning message when pressed and master volume disabled/muted
		if AudioManager.master_muted:
			warning_dialog.popup_centered()
			get_viewport().set_input_as_handled()
		# Unmute when pressed and music is muted and master is unmuted
		elif not AudioManager.master_muted and AudioManager.music_muted:
			_on_music_mute_toggled(true)
			mute_music.button_pressed = true
			get_viewport().set_input_as_handled()


# New: Music mute button gui input (show warning if master muted)
func _on_music_mute_gui_input(event: InputEvent) -> void:
	if AudioManager.master_muted and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		warning_dialog.popup_centered()
		get_viewport().set_input_as_handled()
