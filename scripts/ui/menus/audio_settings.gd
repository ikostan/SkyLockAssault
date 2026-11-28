## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## audio_settings.gd
##
## Audio Settings Script
## Handles UI logic, slider inputs, warning dialogs, and menu navigation.
## Web integration is now decoupled and managed by the AudioWebBridge Autoload.
## Signal cleanup, Back / unexpected-exit handling, menu-stack navigation and focus are
## inherited from SettingsMenuBase (settings_menu_base.gd) (#1180).

extends SettingsMenuBase

## Label color while its slider or mute button has focus.
const LABEL_FOCUS_COLOR: Color = Color("f5f50d")
## Label color otherwise.
const LABEL_IDLE_COLOR: Color = Color("ffffff")

# Test flags for warning popups
var master_warning_shown: bool = false
var sfx_warning_shown: bool = false
## The AudioWebBridge autoload, or null off web (it frees itself there). Cached in _ready()
## so _cleanup() can hide the overlay after this menu has left the tree.
var _audio_web_bridge: Node = null

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
	super()  # process_mode = ALWAYS (usable while paused) + tree_exited -> teardown

	# Warning popup messages
	master_warning_dialog.title = "Warning"
	master_warning_dialog.dialog_text = "To adjust this volume, please unmute the Master volume first."
	sfx_warning_dialog.title = "Warning"
	sfx_warning_dialog.dialog_text = "To adjust this volume, please unmute the SFX volume first."

	# Connect dialog close signals for flag reset
	safe_connect(master_warning_dialog.confirmed, _reset_master_warning_shown)
	safe_connect(master_warning_dialog.canceled, _reset_master_warning_shown)
	safe_connect(sfx_warning_dialog.confirmed, _reset_sfx_warning_shown)
	safe_connect(sfx_warning_dialog.canceled, _reset_sfx_warning_shown)

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
	safe_connect(mute_music.gui_input, _on_music_mute_gui_input)
	safe_connect(mute_sfx.gui_input, _on_sfx_mute_gui_input)
	safe_connect(mute_weapon.gui_input, _on_weapon_mute_gui_input)
	safe_connect(mute_rotor.gui_input, _on_rotor_mute_gui_input)
	safe_connect(mute_menu.gui_input, _on_menu_mute_gui_input)

	# Buttons
	safe_connect(audio_back_button.pressed, _on_back_button_pressed)
	safe_connect(audio_reset_button.pressed, _on_audio_reset_button_pressed)

	# Label highlight follows focus (no per-frame polling)
	_connect_label_focus(master_label, master_slider, mute_master)
	_connect_label_focus(music_label, music_slider, mute_music)
	_connect_label_focus(sfx_label, sfx_slider, mute_sfx)
	_connect_label_focus(weapon_label, weapon_slider, mute_weapon)
	_connect_label_focus(rotor_label, rotor_slider, mute_rotor)
	_connect_label_focus(menu_label, menu_slider, mute_menu)

	_sync_ui_from_manager()

	# Initial Focus (deferred grab; the label highlight follows through focus_entered)
	_grab_initial_focus()

	# 1. Listen for changes coming from Playwright/Web
	safe_connect(AudioManager.volume_changed, _on_global_volume_changed)
	safe_connect(AudioManager.mute_toggled, _on_global_mute_toggled)

	# Apply the hierarchy locks immediately when the menu opens
	_update_ui_interactivity()

	# --- WEB BRIDGE CONNECTIONS ---
	_audio_web_bridge = get_node_or_null("/root/AudioWebBridge")
	if _audio_web_bridge:
		# Show the HTML overlays when the menu opens
		_audio_web_bridge.toggle_dom_visibility(true)

		# Listen for the browser's Back button!
		safe_connect(_audio_web_bridge.web_back_requested, _on_back_button_pressed)

		# Listen for the browser's Reset button!
		safe_connect(_audio_web_bridge.web_reset_requested, _on_audio_reset_button_pressed)


## Back button (Godot and browser).
##
## Delegates to SettingsMenuBase._go_back(): restores exactly one previous menu, shows the
## Options overlay and frees this menu. A second press before the free is ignored. The Audio
## overlay is hidden by _cleanup() when the menu leaves the tree.
## :rtype: void
func _on_back_button_pressed() -> void:
	_go_back()


# ==========================================================================
# SettingsMenuBase HOOKS
# ==========================================================================


func _get_menu_name() -> String:
	return "Audio Settings"


## AudioWebBridge owns the Audio overlay (toggle_dom_visibility()), so the base hides
## nothing itself; _cleanup() hides the overlay. The base still shows the Options overlay
## (OPTIONS_MENU_OVERLAY_IDS) on both exit paths.
func _get_overlay_ids() -> Array[String]:
	return []


func _get_initial_focus_control() -> Control:
	return master_slider


func _get_focus_controls() -> Array[Control]:
	return [
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


## Back path only: return focus to the Audio button in Options, or to Start in the main menu.
## The name / type checks are replaced by the menu stack in #1100.
## :param prev_menu: The menu that was just restored.
## :type prev_menu: Node
## :rtype: void
func _on_previous_menu_restored(prev_menu: Node) -> void:
	if prev_menu.has_method("grab_focus_on_audio_settings_button"):
		prev_menu.call("grab_focus_on_audio_settings_button")
	elif prev_menu.name == "Panel" or prev_menu is Panel:
		var start_button: Button = prev_menu.get_node_or_null("VBoxContainer/StartButton")
		if is_instance_valid(start_button):
			start_button.call_deferred("grab_focus")


## Teardown hook (runs once, on Back and on unexpected exit, before the base disconnects the
## tracked signals): hides the Audio overlay through AudioWebBridge.
## :rtype: void
func _cleanup() -> void:
	if is_instance_valid(_audio_web_bridge):
		_audio_web_bridge.toggle_dom_visibility(false)
	_audio_web_bridge = null


## Syncs the disabled/editable state of every mute button and slider from AudioManager's
## hierarchy rules (Issue #1154): a mute button is disabled while a muted ancestor locks its
## bus, and a slider is editable only while its bus is not effectively muted.
func _update_ui_interactivity() -> void:
	for bus: String in AudioConstants.BUS_CONFIG.keys():
		var mute_button: CheckButton = _get_mute_button_for_bus(bus)
		var slider: HSlider = _get_slider_for_bus(bus)
		if mute_button == null or slider == null:
			continue
		mute_button.disabled = not AudioManager.get_muted_ancestor(bus).is_empty()
		slider.editable = not AudioManager.is_effectively_muted(bus)


# ==========================================================================
# SYMMETRIC VISUAL AND AUDIO VOLUME COUPLING
# ==========================================================================


## Visual-only observer of AudioManager.volume_changed (Issue #1043, epic #725): moves the
## bus's slider to the volume the manager already holds, and nothing else.
## For volume changes, the near-zero auto-mute rule, the confirmation click, the Master
## feedback hold and the AudioServer write live in AudioManager.change_volume(), which every
## volume source calls with its own intent (Issue #1042). Mute presses go through
## AudioManager.toggle_mute() instead (Issue #1048). This menu writes neither the mixer nor
## the rule, so behavior is the same whether the menu is open or not, and this handler never
## awaits: no hold coroutine lives on this node to be dropped when the menu is freed.
## :param bus_name: The constant identifier name of the audio channel.
## :type bus_name: String
## :param volume: The current linear volume scale level (0.0 to 1.0).
## :type volume: float
## :rtype: void
func _on_global_volume_changed(bus_name: String, volume: float) -> void:
	_sync_slider_visual(_get_slider_for_bus(bus_name), volume)


## Moves a slider to a volume AudioManager already holds, without emitting value_changed.
## VolumeSlider also resyncs its delta tracker so the next manual move is never swallowed
## (Issue #1046); a plain HSlider only gets its visual value updated.
## :param slider: The slider mirroring the bus.
## :type slider: HSlider
## :param volume: The current linear volume (0.0 to 1.0).
## :type volume: float
## :rtype: void
func _sync_slider_visual(slider: HSlider, volume: float) -> void:
	if slider is VolumeSlider:
		(slider as VolumeSlider).sync_from_manager(volume)
	elif slider != null:
		slider.set_value_no_signal(volume)


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
	safe_connect(mute_btn.toggled, mute_callback)
	# FIX: Use set_pressed_no_signal so it doesn't trigger the callback during setup
	mute_btn.set_pressed_no_signal(not is_muted)
	safe_connect(slider.gui_input, gui_callback)


# ==========================================
# LABEL HIGHLIGHT (focus-driven, #1180)
# ==========================================


## Keeps a bus label's color in step with its slider's and mute button's focus, and sets it
## once now. Focus moving between the two fires focus_exited first (nothing focused yet),
## then focus_entered, so the label ends up highlighted.
## :param label: The bus label.
## :type label: Label
## :param slider: The bus's volume slider.
## :type slider: HSlider
## :param mute_btn: The bus's mute button.
## :type mute_btn: CheckButton
## :rtype: void
func _connect_label_focus(label: Label, slider: HSlider, mute_btn: CheckButton) -> void:
	var update: Callable = _update_label_color.bind(label, slider, mute_btn)
	for control: Control in [slider, mute_btn]:
		safe_connect(control.focus_entered, update)
		safe_connect(control.focus_exited, update)
	_update_label_color(label, slider, mute_btn)


## Colors a bus label: LABEL_FOCUS_COLOR while its slider or mute button has focus,
## LABEL_IDLE_COLOR otherwise.
## :param label: The bus label.
## :type label: Label
## :param slider: The bus's volume slider.
## :type slider: HSlider
## :param mute_btn: The bus's mute button.
## :type mute_btn: CheckButton
## :rtype: void
func _update_label_color(label: Label, slider: HSlider, mute_btn: CheckButton) -> void:
	var focused: bool = slider.has_focus() or mute_btn.has_focus()
	label.modulate = LABEL_FOCUS_COLOR if focused else LABEL_IDLE_COLOR


# ==========================================
# SLIDER AND MUTE BUTTON INPUT (warning dialogs)
# ==========================================
# Each wrapper names its bus; _handle_slider_gui_input() and _handle_mute_gui_input() ask
# AudioManager which muted ancestor, if any, locks it (Issue #1154).


func _on_master_volume_control_gui_input(event: InputEvent) -> void:
	_handle_slider_gui_input(event, AudioConstants.BUS_MASTER, mute_master)


func _on_music_volume_control_gui_input(event: InputEvent) -> void:
	_handle_slider_gui_input(event, AudioConstants.BUS_MUSIC, mute_music)


func _on_music_mute_gui_input(event: InputEvent) -> void:
	_handle_mute_gui_input(event, AudioConstants.BUS_MUSIC)


func _on_sfx_volume_control_gui_input(event: InputEvent) -> void:
	_handle_slider_gui_input(event, AudioConstants.BUS_SFX, mute_sfx)


func _on_sfx_mute_gui_input(event: InputEvent) -> void:
	_handle_mute_gui_input(event, AudioConstants.BUS_SFX)


func _on_weapon_volume_control_gui_input(event: InputEvent) -> void:
	_handle_slider_gui_input(event, AudioConstants.BUS_SFX_WEAPON, mute_weapon)


func _on_weapon_mute_gui_input(event: InputEvent) -> void:
	_handle_mute_gui_input(event, AudioConstants.BUS_SFX_WEAPON)


func _on_rotor_volume_control_gui_input(event: InputEvent) -> void:
	_handle_slider_gui_input(event, AudioConstants.BUS_SFX_ROTORS, mute_rotor)


func _on_rotor_mute_gui_input(event: InputEvent) -> void:
	_handle_mute_gui_input(event, AudioConstants.BUS_SFX_ROTORS)


func _on_menu_volume_control_gui_input(event: InputEvent) -> void:
	_handle_slider_gui_input(event, AudioConstants.BUS_SFX_MENU, mute_menu)


func _on_menu_mute_gui_input(event: InputEvent) -> void:
	_handle_mute_gui_input(event, AudioConstants.BUS_SFX_MENU)


# ==========================================
# UI UPDATES & NAVIGATION
# ==========================================


func _on_audio_reset_button_pressed() -> void:
	Globals.log_message("Audio reset pressed.", Globals.LogLevel.DEBUG)
	AudioManager.reset_volumes()

	# Force the UI to visually sync with the newly reset AudioManager
	_sync_ui_from_manager()

	# 2. Sync The Ghost (HTML DOM overlays for Playwright)
	var web_bridge: Node = get_node_or_null("/root/AudioWebBridge")
	if web_bridge and web_bridge.has_method("sync_all_to_dom"):
		web_bridge.sync_all_to_dom()


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


# ==========================================
# WARNING DIALOG HELPERS
# ==========================================


## A click or ui_accept on a slider: if a muted ancestor locks the bus, shows its warning
## dialog; otherwise, if the bus itself is muted, presses its mute button to unmute it.
## :param event: The slider's input event.
## :type event: InputEvent
## :param bus_name: The slider's bus.
## :type bus_name: String
## :param mute_button: The bus's mute button.
## :type mute_button: CheckButton
## :rtype: void
func _handle_slider_gui_input(
	event: InputEvent, bus_name: String, mute_button: CheckButton
) -> void:
	if not _is_activation(event):
		return
	if _show_parent_mute_warning(AudioManager.get_muted_ancestor(bus_name)):
		return
	if AudioManager.get_muted(bus_name):
		mute_button.button_pressed = true


## A click or ui_accept on a mute button: if a muted ancestor locks the bus, shows its
## warning dialog and consumes the input.
## :param event: The mute button's input event.
## :type event: InputEvent
## :param bus_name: The mute button's bus.
## :type bus_name: String
## :rtype: void
func _handle_mute_gui_input(event: InputEvent, bus_name: String) -> void:
	if _is_activation(event):
		_show_parent_mute_warning(AudioManager.get_muted_ancestor(bus_name))


## True for a left mouse press or a ui_accept press.
## :param event: The input event.
## :type event: InputEvent
## :rtype: bool
func _is_activation(event: InputEvent) -> bool:
	var is_mouse_click: bool = (
		event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	)
	return is_mouse_click or event.is_action_pressed("ui_accept")


## Shows the warning dialog for the muted ancestor that locks a control ("unmute Master" or
## "unmute SFX") and consumes the input. Returns false, showing nothing, when [param locked_by]
## is "" or has no dialog.
## :param locked_by: The locking ancestor from AudioManager.get_muted_ancestor().
## :type locked_by: String
## :rtype: bool
func _show_parent_mute_warning(locked_by: String) -> bool:
	match locked_by:
		AudioConstants.BUS_MASTER:
			master_warning_dialog.popup_centered()
			master_warning_shown = true
		AudioConstants.BUS_SFX:
			sfx_warning_dialog.popup_centered()
			sfx_warning_shown = true
		_:
			return false
	get_viewport().set_input_as_handled()
	return true


func _reset_master_warning_shown() -> void:
	master_warning_shown = false


func _reset_sfx_warning_shown() -> void:
	sfx_warning_shown = false


# ==========================================================================
# BUS LOOKUP HELPERS
# ==========================================================================


## Auxiliary lookup tool to map string-based audio buses to their respective scene tree sliders.
## Refactored with an explicit default fallback branch to capture configuration mismatches early.
## :param bus_name: The constant identifier name of the audio channel.
## :type bus_name: String
## :rtype: HSlider
func _get_slider_for_bus(bus_name: String) -> HSlider:
	var target_slider: HSlider = null

	match bus_name:
		AudioConstants.BUS_MASTER:
			target_slider = master_slider
		AudioConstants.BUS_MUSIC:
			target_slider = music_slider
		AudioConstants.BUS_SFX:
			target_slider = sfx_slider
		AudioConstants.BUS_SFX_WEAPON:
			target_slider = weapon_slider
		AudioConstants.BUS_SFX_ROTORS:
			target_slider = rotor_slider
		AudioConstants.BUS_SFX_MENU:
			target_slider = menu_slider
		_:
			Globals.log_message(
				"Critical: Unknown bus_name passed to slider lookup: " + bus_name,
				Globals.LogLevel.ERROR
			)

	return target_slider


## Maps an audio bus to its mute button. Returns null (and logs an error) for an unknown bus.
## :param bus_name: The constant identifier name of the audio channel.
## :type bus_name: String
## :rtype: CheckButton
func _get_mute_button_for_bus(bus_name: String) -> CheckButton:
	var target_button: CheckButton = null

	match bus_name:
		AudioConstants.BUS_MASTER:
			target_button = mute_master
		AudioConstants.BUS_MUSIC:
			target_button = mute_music
		AudioConstants.BUS_SFX:
			target_button = mute_sfx
		AudioConstants.BUS_SFX_WEAPON:
			target_button = mute_weapon
		AudioConstants.BUS_SFX_ROTORS:
			target_button = mute_rotor
		AudioConstants.BUS_SFX_MENU:
			target_button = mute_menu
		_:
			Globals.log_message(
				"Critical: Unknown bus_name passed to mute button lookup: " + bus_name,
				Globals.LogLevel.ERROR
			)

	return target_button


# ==========================================================================
# FIXED MUTE TOGGLE CALLBACKS (WITH BACKGROUND BUFFER DEFERRAL)
# ==========================================================================


## Centralized handler for all UI bus mute toggles (visual-only since Issue #1048).
## Only real presses reach this: background sync (_on_global_mute_toggled) uses
## set_pressed_no_signal, so 'toggled' never fires for it. Every call is therefore a manual
## interaction, including the locked-slider click proxy in _handle_slider_gui_input.
## The click, the deferred hardware cutoff, the unmute-from-zero restore and the AudioServer
## update all live in AudioManager.toggle_mute(); UI locks follow via mute_toggled.
## toggle_mute() is deliberately not awaited: the logical mute state (and any unmute-from-zero
## restore) is set synchronously before its MUTE_HARDWARE_DELAY wait, so it is saved at once.
## The deferred cutoff finishes inside the AudioManager autoload, so closing the menu during
## the delay can no longer drop the save along with this node's coroutine.
## :param bus_name: The bus being toggled.
## :type bus_name: String
## :param toggled_on: True if the bus is unmuted (button pressed), false if muted.
## :type toggled_on: bool
## :rtype: void
func _execute_bus_mute_toggle(bus_name: String, toggled_on: bool) -> void:
	AudioManager.toggle_mute(bus_name, not toggled_on, true)
	AudioManager.save_volumes()


## Handles Master Mute toggle mutations via the centralized pipeline.
## :param toggled_on: True if the bus is unmuted (button pressed), false if muted.
## :type toggled_on: bool
## :rtype: void
func _on_master_mute_toggled(toggled_on: bool) -> void:
	_execute_bus_mute_toggle(AudioConstants.BUS_MASTER, toggled_on)


## Handles Music Mute toggle mutations via the centralized pipeline.
## :param toggled_on: True if the bus is unmuted (button pressed), false if muted.
## :type toggled_on: bool
## :rtype: void
func _on_music_mute_toggled(toggled_on: bool) -> void:
	_execute_bus_mute_toggle(AudioConstants.BUS_MUSIC, toggled_on)


## Handles Parent SFX Mute toggle mutations via the centralized pipeline.
## :param toggled_on: True if the bus is unmuted (button pressed), false if muted.
## :type toggled_on: bool
## :rtype: void
func _on_sfx_mute_toggled(toggled_on: bool) -> void:
	_execute_bus_mute_toggle(AudioConstants.BUS_SFX, toggled_on)


## Handles Weapon SFX Mute toggle mutations via the centralized pipeline.
## :param toggled_on: True if the bus is unmuted (button pressed), false if muted.
## :type toggled_on: bool
## :rtype: void
func _on_weapon_mute_toggled(toggled_on: bool) -> void:
	_execute_bus_mute_toggle(AudioConstants.BUS_SFX_WEAPON, toggled_on)


## Handles Rotor SFX Mute toggle mutations via the centralized pipeline.
## :param toggled_on: True if the bus is unmuted (button pressed), false if muted.
## :type toggled_on: bool
## :rtype: void
func _on_rotor_mute_toggled(toggled_on: bool) -> void:
	_execute_bus_mute_toggle(AudioConstants.BUS_SFX_ROTORS, toggled_on)


## Handles Menu UI SFX Mute toggle mutations via the centralized pipeline.
## :param toggled_on: True if the bus is unmuted (button pressed), false if muted.
## :type toggled_on: bool
## :rtype: void
func _on_menu_mute_toggled(toggled_on: bool) -> void:
	_execute_bus_mute_toggle(AudioConstants.BUS_SFX_MENU, toggled_on)
