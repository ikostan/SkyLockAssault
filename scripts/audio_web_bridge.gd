## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## audio_web_bridge.gd
## Autoload singleton for Web/JS integration.
## Bridges JavaScript DOM events to the AudioManager, and syncs Godot state to the DOM.

extends Node

# Custom signals for the UI to listen to
signal web_back_requested
signal web_reset_requested

var os_wrapper: OSWrapper = OSWrapper.new()
var js_bridge_wrapper: JavaScriptBridgeWrapper = JavaScriptBridgeWrapper.new()
var js_window: Variant

# JS Callback references (must be stored to prevent garbage collection)
var _audio_back_button_pressed_cb: Variant
var _audio_reset_cb: Variant
var _change_master_volume_cb: Variant
var _change_music_volume_cb: Variant
var _change_sfx_volume_cb: Variant
var _change_weapon_volume_cb: Variant
var _change_rotors_volume_cb: Variant
var _change_menu_volume_cb: Variant
var _toggle_mute_master_cb: Variant
var _toggle_mute_music_cb: Variant
var _toggle_mute_sfx_cb: Variant
var _toggle_mute_weapon_cb: Variant
var _toggle_mute_rotors_cb: Variant
var _toggle_mute_menu_cb: Variant

func _ready() -> void:
	# 1. Self-Destruct if not on web
	if not os_wrapper.has_feature("web"):
		queue_free()
		return
		
	js_window = js_bridge_wrapper.get_interface("window")
	if not js_window:
		Globals.log_message("AudioWebBridge: Failed to get JS window interface.", Globals.LogLevel.ERROR)
		return

	# 2. Register all JS -> Godot Callbacks
	_register_all_callbacks()

	# 3. Connect Godot -> JS Sync Signals
	AudioManager.volume_changed.connect(_on_godot_volume_changed)
	AudioManager.mute_toggled.connect(_on_godot_mute_toggled)
	
	Globals.log_message("AudioWebBridge initialized successfully.", Globals.LogLevel.DEBUG)


# ==========================================
# PUBLIC API (Called by audio_settings.gd)
# ==========================================

## Toggles visibility of all audio DOM overlays.
## :param show: true for "block", false for "none".
func toggle_dom_visibility(show: bool) -> void:
	if not js_window:
		return
		
	var visibility: String = "block" if show else "none"
	var ids: Array[String] = [
		"audio-back-button", "audio-reset-button",
		"master-slider", "music-slider", "sfx-slider",
		"weapon-slider", "rotors-slider", "menu-slider",
		"mute-master", "mute-music", "mute-sfx",
		"mute-weapon", "mute-rotors", "mute-menu"
	]

	for id: String in ids:
		js_bridge_wrapper.eval("document.getElementById('%s').style.display = '%s';" % [id, visibility])
		
	# If showing the menu, immediately sync the DOM to current Godot values
	if show:
		_sync_all_dom_values()


# ==========================================
# GODOT -> JS (Updating the DOM)
# ==========================================

func _on_godot_volume_changed(bus_name: String, value: float) -> void:
	if not js_window:
		return
	var dom_id: String = _get_slider_id_for_bus(bus_name)
	if dom_id != "":
		js_bridge_wrapper.eval("document.getElementById('%s').value = %s" % [dom_id, str(value)])


func _on_godot_mute_toggled(bus_name: String, is_muted: bool) -> void:
	if not js_window:
		return
	var dom_id: String = _get_mute_id_for_bus(bus_name)
	if dom_id != "":
		js_bridge_wrapper.eval("document.getElementById('%s').checked = %s" % [dom_id, str(not is_muted).to_lower()])


func _sync_all_dom_values() -> void:
	for bus: String in AudioConstants.BUS_CONFIG.keys():
		var state: Dictionary = AudioManager.get_bus_state(bus)
		_on_godot_volume_changed(bus, state["volume"])
		_on_godot_mute_toggled(bus, state["muted"])


# ==========================================
# JS -> GODOT (Handling Browser Inputs)
# ==========================================

func _on_change_volume_js(args: Array, bus_name: String) -> void:
	var value := _validate_volume_args(args)
	if value < 0.0:
		return
		
	# Check parent mute states before allowing sub-bus adjustments
	if bus_name != AudioConstants.BUS_MASTER and AudioManager.master_muted:
		return
	if bus_name in [AudioConstants.BUS_SFX_WEAPON, AudioConstants.BUS_SFX_ROTORS, AudioConstants.BUS_SFX_MENU] and AudioManager.sfx_muted:
		return
		
	AudioManager.set_volume(bus_name, value)
	AudioManager.apply_volume_to_bus(bus_name, value, AudioManager.get_muted(bus_name))
	AudioManager.save_volumes()

func _on_toggle_mute_js(args: Array, bus_name: String) -> void:
	var checked: Variant = _validate_mute_args(args)
	if checked == null:
		return
		
	var is_muted: bool = not bool(checked) # Checkbox checked = unmuted
	AudioManager.set_muted(bus_name, is_muted)
	AudioManager.apply_volume_to_bus(bus_name, AudioManager.get_volume(bus_name), is_muted)
	AudioManager.save_volumes()

# Specific callback wrappers required by JavaScriptBridgeWrapper
func _on_change_master_volume_js(args: Array) -> void: _on_change_volume_js(args, AudioConstants.BUS_MASTER)
func _on_change_music_volume_js(args: Array) -> void: _on_change_volume_js(args, AudioConstants.BUS_MUSIC)
func _on_change_sfx_volume_js(args: Array) -> void: _on_change_volume_js(args, AudioConstants.BUS_SFX)
func _on_change_weapon_volume_js(args: Array) -> void: _on_change_volume_js(args, AudioConstants.BUS_SFX_WEAPON)
func _on_change_rotors_volume_js(args: Array) -> void: _on_change_volume_js(args, AudioConstants.BUS_SFX_ROTORS)
func _on_change_menu_volume_js(args: Array) -> void: _on_change_volume_js(args, AudioConstants.BUS_SFX_MENU)

func _on_toggle_mute_master_js(args: Array) -> void: _on_toggle_mute_js(args, AudioConstants.BUS_MASTER)
func _on_toggle_mute_music_js(args: Array) -> void: _on_toggle_mute_js(args, AudioConstants.BUS_MUSIC)
func _on_toggle_mute_sfx_js(args: Array) -> void: _on_toggle_mute_js(args, AudioConstants.BUS_SFX)
func _on_toggle_mute_weapon_js(args: Array) -> void: _on_toggle_mute_js(args, AudioConstants.BUS_SFX_WEAPON)
func _on_toggle_mute_rotors_js(args: Array) -> void: _on_toggle_mute_js(args, AudioConstants.BUS_SFX_ROTORS)
func _on_toggle_mute_menu_js(args: Array) -> void: _on_toggle_mute_js(args, AudioConstants.BUS_SFX_MENU)


func _on_audio_back_button_pressed_js(_args: Array) -> void:
	web_back_requested.emit()


func _on_audio_reset_js(_args: Array) -> void:
	web_reset_requested.emit()


# ==========================================
# HELPERS
# ==========================================

func _register_all_callbacks() -> void:
	_audio_back_button_pressed_cb = _register_js_callback("_on_audio_back_button_pressed_js", "audioBackPressed")
	_audio_reset_cb = _register_js_callback("_on_audio_reset_js", "audioResetPressed")
	
	_change_master_volume_cb = _register_js_callback("_on_change_master_volume_js", "changeMasterVolume")
	_change_music_volume_cb = _register_js_callback("_on_change_music_volume_js", "changeMusicVolume")
	_change_sfx_volume_cb = _register_js_callback("_on_change_sfx_volume_js", "changeSfxVolume")
	_change_weapon_volume_cb = _register_js_callback("_on_change_weapon_volume_js", "changeWeaponVolume")
	_change_rotors_volume_cb = _register_js_callback("_on_change_rotors_volume_js", "changeRotorsVolume")
	_change_menu_volume_cb = _register_js_callback("_on_change_menu_volume_js", "changeMenuVolume")
	
	_toggle_mute_master_cb = _register_js_callback("_on_toggle_mute_master_js", "toggleMuteMaster")
	_toggle_mute_music_cb = _register_js_callback("_on_toggle_mute_music_js", "toggleMuteMusic")
	_toggle_mute_sfx_cb = _register_js_callback("_on_toggle_mute_sfx_js", "toggleMuteSfx")
	_toggle_mute_weapon_cb = _register_js_callback("_on_toggle_mute_weapon_js", "toggleMuteWeapon")
	_toggle_mute_rotors_cb = _register_js_callback("_on_toggle_mute_rotors_js", "toggleMuteRotors")
	_toggle_mute_menu_cb = _register_js_callback("_on_toggle_mute_menu_js", "toggleMuteMenu")


func _register_js_callback(callback_method: String, window_property: String) -> Variant:
	var callback: Variant = js_bridge_wrapper.create_callback(Callable(self, callback_method))
	js_window[window_property] = callback
	return callback


func _validate_volume_args(args: Array) -> float:
	if args.is_empty() or typeof(args[0]) != TYPE_OBJECT or (typeof(args[0][0]) != TYPE_FLOAT and typeof(args[0][0]) != TYPE_INT):
		Globals.log_message("AudioWebBridge: Invalid volume args", Globals.LogLevel.ERROR)
		return -1.0
	return clamp(float(args[0][0]), 0.0, 1.0)


func _validate_mute_args(args: Array) -> Variant:
	if args.is_empty() or typeof(args[0]) != TYPE_OBJECT or (typeof(args[0][0]) != TYPE_BOOL and typeof(args[0][0]) != TYPE_INT and typeof(args[0][0]) != TYPE_FLOAT):
		Globals.log_message("AudioWebBridge: Invalid mute args", Globals.LogLevel.ERROR)
		return null
	return bool(args[0][0])


func _get_slider_id_for_bus(bus_name: String) -> String:
	match bus_name:
		AudioConstants.BUS_MASTER: return "master-slider"
		AudioConstants.BUS_MUSIC: return "music-slider"
		AudioConstants.BUS_SFX: return "sfx-slider"
		AudioConstants.BUS_SFX_WEAPON: return "weapon-slider"
		AudioConstants.BUS_SFX_ROTORS: return "rotors-slider"
		AudioConstants.BUS_SFX_MENU: return "menu-slider"
	return ""


func _get_mute_id_for_bus(bus_name: String) -> String:
	match bus_name:
		AudioConstants.BUS_MASTER: return "mute-master"
		AudioConstants.BUS_MUSIC: return "mute-music"
		AudioConstants.BUS_SFX: return "mute-sfx"
		AudioConstants.BUS_SFX_WEAPON: return "mute-weapon"
		AudioConstants.BUS_SFX_ROTORS: return "mute-rotors"
		AudioConstants.BUS_SFX_MENU: return "mute-menu"
	return ""
