## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## audio_settings.gd
##
## Audio Settings Script
## Handles UI logic, slider inputs, warning dialogs, and menu navigation.
## Web integration is now decoupled and managed by the AudioWebBridge Autoload.

extends Control

# Test flags for warning popups
var master_warning_shown: bool = false
var sfx_warning_shown: bool = false
var _intentional_exit: bool = false

# Master Volume Controls
@onready var master_slider: HSlider = $Panel/VolumeControls/Master/HSlider
@onready var mute_master: CheckButton = $Panel/VolumeControls/Master/Mute
# Music Volume Controls
@onready var music_slider: HSlider = $Panel/VolumeControls/Music/HSlider
@onready var mute_music: CheckButton = $Panel/VolumeControls/Music/Mute
# SFX Volume Controls
@onready var sfx_slider: HSlider = $Panel/VolumeControls/SFX/HSlider
@onready var mute_sfx: CheckButton = $Panel/VolumeControls/SFX/Mute
# SFX Weapon Volume Controls
@onready var weapon_slider: HSlider = $Panel/VolumeControls/SFXWeapon/HSlider
@onready var mute_weapon: CheckButton = $Panel/VolumeControls/SFXWeapon/Mute
# SFX Rotor Volume Controls
@onready var rotor_slider: HSlider = $Panel/VolumeControls/SFXRotors/HSlider
@onready var mute_rotor: CheckButton = $Panel/VolumeControls/SFXRotors/Mute
# SFX Menu Volume Controls
@onready var menu_slider: HSlider = $Panel/VolumeControls/SFXMenu/HSlider
@onready var mute_menu: CheckButton = $Panel/VolumeControls/SFXMenu/Mute
# Other UI elements
@onready var master_warning_dialog: AcceptDialog = $MasterWarningDialog
@onready var sfx_warning_dialog: AcceptDialog = $SFXWarningDialog
@onready var audio_back_button: Button = $Panel/BtnContainer/AudioBackButton
@onready var audio_reset_button: Button = $Panel/BtnContainer/AudioResetButton
# Labels
@onready var master_label: Label = $Panel/VolumeControls/Master/MasterLabel
@onready var music_label: Label = $Panel/VolumeControls/Music/MusicLabel
@onready var sfx_label: Label = $Panel/VolumeControls/SFX/SFXLabel
@onready var weapon_label: Label = $Panel/VolumeControls/SFXWeapon/SFXWeaponLabel
@onready var rotor_label: Label = $Panel/VolumeControls/SFXRotors/SFXRotorsLabel
@onready var menu_label: Label = $Panel/VolumeControls/SFXMenu/SFXMenuLabel


func _ready() -> void:
	# Warning popup messages
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

	# --- Connect UI Signals ---
	_connect_bus_ui(
		mute_master,
		master_slider,
		_on_master_mute_toggled,
		_on_master_volume_control_gui_input,
		AudioManager.master_muted
	)
	_connect_bus_ui(
		mute_music,
		music_slider,
		_on_music_mute_toggled,
		_on_music_volume_control_gui_input,
		AudioManager.music_muted
	)
	_connect_bus_ui(
		mute_sfx,
		sfx_slider,
		_on_sfx_mute_toggled,
		_on_sfx_volume_control_gui_input,
		AudioManager.sfx_muted
	)
	_connect_bus_ui(
		mute_weapon,
		weapon_slider,
		_on_weapon_mute_toggled,
		_on_weapon_volume_control_gui_input,
		AudioManager.weapon_muted
	)
	_connect_bus_ui(
		mute_rotor,
		rotor_slider,
		_on_rotor_mute_toggled,
		_on_rotor_volume_control_gui_input,
		AudioManager.rotors_muted
	)
	_connect_bus_ui(
		mute_menu,
		menu_slider,
		_on_menu_mute_toggled,
		_on_menu_volume_control_gui_input,
		AudioManager.menu_muted
	)

	# Connect specific mute button warning interceptors
	if not mute_music.gui_input.is_connected(_on_music_mute_gui_input):
		mute_music.gui_input.connect(_on_music_mute_gui_input)
	if not mute_sfx.gui_input.is_connected(_on_sfx_mute_gui_input):
		mute_sfx.gui_input.connect(_on_sfx_mute_gui_input)
	if not mute_weapon.gui_input.is_connected(_on_weapon_mute_gui_input):
		mute_weapon.gui_input.connect(_on_weapon_mute_gui_input)
	if not mute_rotor.gui_input.is_connected(_on_rotor_mute_gui_input):
		mute_rotor.gui_input.connect(_on_rotor_mute_gui_input)
	if not mute_menu.gui_input.is_connected(_on_menu_mute_gui_input):
		mute_menu.gui_input.connect(_on_menu_mute_gui_input)

	# Buttons
	# To this:
	if not audio_back_button.pressed.is_connected(_on_back_button_pressed):
		audio_back_button.pressed.connect(_on_back_button_pressed)

	if not audio_reset_button.pressed.is_connected(_on_audio_reset_button_pressed):
		audio_reset_button.pressed.connect(_on_audio_reset_button_pressed)

	tree_exited.connect(_on_tree_exited)
	process_mode = Node.PROCESS_MODE_ALWAYS

	_sync_ui_from_manager()

	# Initial Focus
	var menu_controls: Array[Control] = [
		master_slider,
		mute_master,
		music_slider,
		mute_music,
		sfx_slider,
		mute_sfx,
		weapon_slider,
		mute_weapon,
		rotor_slider,
		mute_rotor,
		menu_slider,
		mute_menu,
		audio_back_button,
		audio_reset_button
	]
	Globals.ensure_initial_focus(master_slider, menu_controls, "Audio Settings")

	# 1. Listen for changes coming from Playwright/Web
	AudioManager.volume_changed.connect(_on_global_volume_changed)
	AudioManager.mute_toggled.connect(_on_global_mute_toggled)

	# Apply the hierarchy locks immediately when the menu opens
	_update_ui_interactivity()

	# --- WEB BRIDGE CONNECTIONS ---
	var web_bridge: Node = get_node_or_null("/root/AudioWebBridge")
	if web_bridge:
		# Show the HTML overlays when the menu opens
		web_bridge.toggle_dom_visibility(true)

		# Listen for the browser's Back button!
		if not web_bridge.web_back_requested.is_connected(_on_back_button_pressed):
			web_bridge.web_back_requested.connect(_on_back_button_pressed)

		# Listen for the browser's Reset button!
		if not web_bridge.web_reset_requested.is_connected(_on_audio_reset_button_pressed):
			web_bridge.web_reset_requested.connect(_on_audio_reset_button_pressed)


func _on_back_button_pressed() -> void:
	Globals.log_message("Audio Settings: Back button pressed.", Globals.LogLevel.DEBUG)
	_intentional_exit = true

	# 1. Safely hide the Audio HTML DOM
	var web_bridge: Node = get_node_or_null("/root/AudioWebBridge")
	if web_bridge:
		web_bridge.toggle_dom_visibility(false)

	# 2. Restore the previous menu AND its HTML DOM AND focus
	if Globals.hidden_menus.size() > 0:
		var prev_menu: Node = Globals.hidden_menus.pop_back()
		if is_instance_valid(prev_menu):
			prev_menu.show()

			# --- Focus Restoration (Moved here from the old function!) ---
			if prev_menu.has_method("grab_focus_on_audio_settings_button"):
				prev_menu.call("grab_focus_on_audio_settings_button")
			elif prev_menu.name == "Panel" or prev_menu is Panel:
				var start_button: Button = prev_menu.get_node_or_null("VBoxContainer/StartButton")
				if is_instance_valid(start_button):
					# FIX: Changed from triple-nested call_deferred to a single call
					start_button.call_deferred("grab_focus")

			# --- HTML DOM Restoration ---
			if prev_menu.has_method("toggle_dom_visibility"):
				prev_menu.toggle_dom_visibility(true)
			elif "_web_bridge" in prev_menu and prev_menu.get("_web_bridge") != null:
				var prev_bridge: Node = prev_menu.get("_web_bridge")
				if prev_bridge.has_method("toggle_dom_visibility"):
					prev_bridge.toggle_dom_visibility(true)
			elif web_bridge and web_bridge.has_method("restore_options_menu_dom"):
				# Clean fallback via the bridge! (Replaces the raw JS evals)
				web_bridge.restore_options_menu_dom()
	else:
		# --- Fallback to previous scene ---
		if Globals.previous_scene != "":
			get_tree().change_scene_to_file(Globals.previous_scene)

	queue_free()


## Syncs the disabled/editable state of all UI elements based on the hierarchy rules
func _update_ui_interactivity() -> void:
	var is_master_muted: bool = AudioManager.master_muted

	# 1. MASTER HIERARCHY
	master_slider.editable = not is_master_muted

	# 2. LEVEL 1 CHILDREN (Music & SFX)
	# Mute buttons are disabled if Master is muted.
	# Sliders are disabled if Master is muted OR their own bus is muted.
	mute_music.disabled = is_master_muted
	music_slider.editable = not (is_master_muted or AudioManager.music_muted)

	mute_sfx.disabled = is_master_muted
	sfx_slider.editable = not (is_master_muted or AudioManager.sfx_muted)

	# 3. LEVEL 2 CHILDREN (SFX Sub-buses: Weapon, Rotors, Menu)
	var is_sfx_hierarchy_muted: bool = is_master_muted or AudioManager.sfx_muted

	mute_weapon.disabled = is_sfx_hierarchy_muted
	weapon_slider.editable = not (is_sfx_hierarchy_muted or AudioManager.weapon_muted)

	# Note: Double check your @onready var name for the rotors mute button (mute_rotors vs mute_rotor)
	mute_rotor.disabled = is_sfx_hierarchy_muted
	rotor_slider.editable = not (is_sfx_hierarchy_muted or AudioManager.rotors_muted)

	mute_menu.disabled = is_sfx_hierarchy_muted
	menu_slider.editable = not (is_sfx_hierarchy_muted or AudioManager.menu_muted)


## Updates the visual Godot HSliders when Playwright changes the AudioManager
func _on_global_volume_changed(bus_name: String, volume: float) -> void:
	match bus_name:
		AudioConstants.BUS_MASTER:
			master_slider.set_value_no_signal(volume)
		AudioConstants.BUS_MUSIC:
			music_slider.set_value_no_signal(volume)
		AudioConstants.BUS_SFX:
			sfx_slider.set_value_no_signal(volume)
		AudioConstants.BUS_SFX_WEAPON:
			weapon_slider.set_value_no_signal(volume)
		AudioConstants.BUS_SFX_ROTORS:
			rotor_slider.set_value_no_signal(volume)
		AudioConstants.BUS_SFX_MENU:
			menu_slider.set_value_no_signal(volume)


## Updates the visual Godot CheckButtons when Playwright mutes the AudioManager
func _on_global_mute_toggled(bus_name: String, is_muted: bool) -> void:
	# In your Godot UI, if a button is "pressed", it means the audio is UNMUTED.
	var is_pressed: bool = not is_muted

	match bus_name:
		AudioConstants.BUS_MASTER:
			mute_master.set_pressed_no_signal(is_pressed)
		AudioConstants.BUS_MUSIC:
			mute_music.set_pressed_no_signal(is_pressed)
		AudioConstants.BUS_SFX:
			mute_sfx.set_pressed_no_signal(is_pressed)
		AudioConstants.BUS_SFX_WEAPON:
			mute_weapon.set_pressed_no_signal(is_pressed)
		AudioConstants.BUS_SFX_ROTORS:
			mute_rotor.set_pressed_no_signal(is_pressed)
		AudioConstants.BUS_SFX_MENU:
			mute_menu.set_pressed_no_signal(is_pressed)

	# Refresh the UI locks after applying the new mute state
	_update_ui_interactivity()


func _connect_bus_ui(
	mute_btn: CheckButton,
	slider: HSlider,
	mute_callback: Callable,
	gui_callback: Callable,
	is_muted: bool
) -> void:
	if not mute_btn.toggled.is_connected(mute_callback):
		mute_btn.toggled.connect(mute_callback)
	mute_btn.button_pressed = not is_muted
	if not slider.gui_input.is_connected(gui_callback):
		slider.gui_input.connect(gui_callback)


func _process(_delta: float) -> void:
	_update_label_colors()


func _update_label_colors() -> void:
	var yellow := Color("f5f50d")
	var white := Color("ffffff")

	master_label.modulate = (
		yellow if (master_slider.has_focus() or mute_master.has_focus()) else white
	)
	music_label.modulate = yellow if (music_slider.has_focus() or mute_music.has_focus()) else white
	sfx_label.modulate = yellow if (sfx_slider.has_focus() or mute_sfx.has_focus()) else white
	weapon_label.modulate = (
		yellow if (weapon_slider.has_focus() or mute_weapon.has_focus()) else white
	)
	rotor_label.modulate = yellow if (rotor_slider.has_focus() or mute_rotor.has_focus()) else white
	menu_label.modulate = yellow if (menu_slider.has_focus() or mute_menu.has_focus()) else white


# ==========================================
# MASTER VOLUME
# ==========================================
func _on_master_volume_control_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and AudioManager.master_muted:
		if event.button_index == MOUSE_BUTTON_LEFT:
			mute_master.button_pressed = true
			get_viewport().set_input_as_handled()


func _on_master_mute_toggled(toggled_on: bool) -> void:
	AudioManager.set_muted(AudioConstants.BUS_MASTER, not toggled_on)
	_update_ui_interactivity()  # Single source of truth updates everything
	AudioManager.apply_volume_to_bus(
		AudioConstants.BUS_MASTER, AudioManager.master_volume, AudioManager.master_muted
	)
	AudioManager.save_volumes()


# ==========================================
# MUSIC VOLUME
# ==========================================
func _on_music_volume_control_gui_input(event: InputEvent) -> void:
	_handle_slider_gui_input(
		event,
		AudioManager.master_muted,
		false,
		AudioManager.music_muted,
		mute_music,
		master_warning_dialog,
		sfx_warning_dialog
	)


func _on_music_mute_toggled(toggled_on: bool) -> void:
	AudioManager.set_muted(AudioConstants.BUS_MUSIC, not toggled_on)
	_update_ui_interactivity()
	AudioManager.apply_volume_to_bus(
		AudioConstants.BUS_MUSIC, AudioManager.music_volume, AudioManager.music_muted
	)
	AudioManager.save_volumes()


func _on_music_mute_gui_input(event: InputEvent) -> void:
	_handle_mute_gui_input(
		event, AudioManager.master_muted, false, master_warning_dialog, sfx_warning_dialog
	)


# ==========================================
# SFX VOLUME
# ==========================================
func _on_sfx_volume_control_gui_input(event: InputEvent) -> void:
	_handle_slider_gui_input(
		event,
		AudioManager.master_muted,
		false,
		AudioManager.sfx_muted,
		mute_sfx,
		master_warning_dialog,
		sfx_warning_dialog
	)


func _on_sfx_mute_toggled(toggled_on: bool) -> void:
	AudioManager.set_muted(AudioConstants.BUS_SFX, not toggled_on)
	_update_ui_interactivity()
	AudioManager.apply_volume_to_bus(
		AudioConstants.BUS_SFX, AudioManager.sfx_volume, AudioManager.sfx_muted
	)
	AudioManager.save_volumes()


func _on_sfx_mute_gui_input(event: InputEvent) -> void:
	_handle_mute_gui_input(
		event, AudioManager.master_muted, false, master_warning_dialog, sfx_warning_dialog
	)


# ==========================================
# WEAPON VOLUME
# ==========================================
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


func _on_weapon_mute_toggled(toggled_on: bool) -> void:
	AudioManager.set_muted(AudioConstants.BUS_SFX_WEAPON, not toggled_on)
	_update_ui_interactivity()
	AudioManager.apply_volume_to_bus(
		AudioConstants.BUS_SFX_WEAPON, AudioManager.weapon_volume, AudioManager.weapon_muted
	)
	AudioManager.save_volumes()


func _on_weapon_mute_gui_input(event: InputEvent) -> void:
	_handle_mute_gui_input(
		event,
		AudioManager.master_muted,
		AudioManager.sfx_muted,
		master_warning_dialog,
		sfx_warning_dialog
	)


# ==========================================
# ROTORS VOLUME
# ==========================================
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


func _on_rotor_mute_toggled(toggled_on: bool) -> void:
	AudioManager.set_muted(AudioConstants.BUS_SFX_ROTORS, not toggled_on)
	_update_ui_interactivity()
	AudioManager.apply_volume_to_bus(
		AudioConstants.BUS_SFX_ROTORS, AudioManager.rotors_volume, AudioManager.rotors_muted
	)
	AudioManager.save_volumes()


func _on_rotor_mute_gui_input(event: InputEvent) -> void:
	_handle_mute_gui_input(
		event,
		AudioManager.master_muted,
		AudioManager.sfx_muted,
		master_warning_dialog,
		sfx_warning_dialog
	)


# ==========================================
# MENU VOLUME
# ==========================================
func _on_menu_volume_control_gui_input(event: InputEvent) -> void:
	_handle_slider_gui_input(
		event,
		AudioManager.master_muted,
		AudioManager.sfx_muted,
		AudioManager.menu_muted,
		mute_menu,
		master_warning_dialog,
		sfx_warning_dialog
	)


func _on_menu_mute_toggled(toggled_on: bool) -> void:
	AudioManager.set_muted(AudioConstants.BUS_SFX_MENU, not toggled_on)
	_update_ui_interactivity()
	AudioManager.apply_volume_to_bus(
		AudioConstants.BUS_SFX_MENU, AudioManager.menu_volume, AudioManager.menu_muted
	)
	AudioManager.save_volumes()


func _on_menu_mute_gui_input(event: InputEvent) -> void:
	_handle_mute_gui_input(
		event,
		AudioManager.master_muted,
		AudioManager.sfx_muted,
		master_warning_dialog,
		sfx_warning_dialog
	)


# ==========================================
# UI UPDATES & NAVIGATION
# ==========================================


func _on_audio_reset_button_pressed() -> void:
	Globals.log_message("Audio reset pressed.", Globals.LogLevel.DEBUG)
	AudioManager.reset_volumes()

	# Force the UI to visually sync with the newly reset AudioManager
	_sync_ui_from_manager()
	# 1. Sync The Face (Godot UI)
	_sync_all_sliders_and_mutes()
	_update_ui_interactivity()

	# 2. Sync The Ghost (HTML DOM overlays for Playwright)
	var web_bridge: Node = get_node_or_null("/root/AudioWebBridge")
	if web_bridge and web_bridge.has_method("sync_all_to_dom"):
		web_bridge.sync_all_to_dom()


## Manually syncs all visual UI elements to match the current AudioManager state
func _sync_all_sliders_and_mutes() -> void:
	# Master
	_on_global_volume_changed(AudioConstants.BUS_MASTER, AudioManager.master_volume)
	_on_global_mute_toggled(AudioConstants.BUS_MASTER, AudioManager.master_muted)

	# Music
	_on_global_volume_changed(AudioConstants.BUS_MUSIC, AudioManager.music_volume)
	_on_global_mute_toggled(AudioConstants.BUS_MUSIC, AudioManager.music_muted)

	# SFX
	_on_global_volume_changed(AudioConstants.BUS_SFX, AudioManager.sfx_volume)
	_on_global_mute_toggled(AudioConstants.BUS_SFX, AudioManager.sfx_muted)

	# Weapon
	_on_global_volume_changed(AudioConstants.BUS_SFX_WEAPON, AudioManager.weapon_volume)
	_on_global_mute_toggled(AudioConstants.BUS_SFX_WEAPON, AudioManager.weapon_muted)

	# Rotors
	_on_global_volume_changed(AudioConstants.BUS_SFX_ROTORS, AudioManager.rotors_volume)
	_on_global_mute_toggled(AudioConstants.BUS_SFX_ROTORS, AudioManager.rotors_muted)

	# Menu
	_on_global_volume_changed(AudioConstants.BUS_SFX_MENU, AudioManager.menu_volume)
	_on_global_mute_toggled(AudioConstants.BUS_SFX_MENU, AudioManager.menu_muted)


func _sync_ui_from_manager() -> void:
	mute_master.set_pressed_no_signal(not AudioManager.master_muted)
	master_slider.set_value_no_signal(AudioManager.master_volume)

	mute_music.set_pressed_no_signal(not AudioManager.music_muted)
	music_slider.set_value_no_signal(AudioManager.music_volume)

	mute_sfx.set_pressed_no_signal(not AudioManager.sfx_muted)
	sfx_slider.set_value_no_signal(AudioManager.sfx_volume)

	mute_weapon.set_pressed_no_signal(not AudioManager.weapon_muted)
	weapon_slider.set_value_no_signal(AudioManager.weapon_volume)

	mute_rotor.set_pressed_no_signal(not AudioManager.rotors_muted)
	rotor_slider.set_value_no_signal(AudioManager.rotors_volume)

	mute_menu.set_pressed_no_signal(not AudioManager.menu_muted)
	menu_slider.set_value_no_signal(AudioManager.menu_volume)

	# Delegate all lock/unlock hierarchy logic to the single source of truth
	_update_ui_interactivity()


func _on_tree_exited() -> void:
	# --- CLEANUP: Disconnect from Autoloads to prevent memory leaks/errors ---
	if AudioManager.volume_changed.is_connected(_on_global_volume_changed):
		AudioManager.volume_changed.disconnect(_on_global_volume_changed)

	if AudioManager.mute_toggled.is_connected(_on_global_mute_toggled):
		AudioManager.mute_toggled.disconnect(_on_global_mute_toggled)

	var web_bridge: Node = get_node_or_null("/root/AudioWebBridge")
	if web_bridge:
		if web_bridge.web_back_requested.is_connected(_on_back_button_pressed):
			web_bridge.web_back_requested.disconnect(_on_back_button_pressed)
		if web_bridge.web_reset_requested.is_connected(_on_audio_reset_button_pressed):
			web_bridge.web_reset_requested.disconnect(_on_audio_reset_button_pressed)
	# -------------------------------------------------------------------------

	if _intentional_exit:
		return

	if not Globals.hidden_menus.is_empty():
		var prev_menu: Node = Globals.hidden_menus.pop_back()
		if is_instance_valid(prev_menu):
			prev_menu.visible = true


# ==========================================
# WARNING DIALOG HELPERS
# ==========================================


func _handle_slider_gui_input(
	event: InputEvent,
	master_muted: bool,
	sfx_muted: bool,
	bus_muted: bool,
	mute_button: CheckButton,
	master_dialog: AcceptDialog,
	sfx_dialog: AcceptDialog
) -> void:
	var is_mouse_click: bool = (
		event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	)
	var is_ui_accept: bool = event.is_action_pressed("ui_accept")

	if is_mouse_click or is_ui_accept:
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


func _handle_mute_gui_input(
	event: InputEvent,
	master_muted: bool,
	sfx_muted: bool,
	master_dialog: AcceptDialog,
	sfx_dialog: AcceptDialog
) -> void:
	var is_mouse_click: bool = (
		event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	)
	var is_ui_accept: bool = event.is_action_pressed("ui_accept")

	if is_mouse_click or is_ui_accept:
		if master_muted:
			master_dialog.popup_centered()
			master_warning_shown = true
			get_viewport().set_input_as_handled()
		elif sfx_muted:
			sfx_dialog.popup_centered()
			sfx_warning_shown = true
			get_viewport().set_input_as_handled()


func _reset_master_warning_shown() -> void:
	master_warning_shown = false


func _reset_sfx_warning_shown() -> void:
	sfx_warning_shown = false
