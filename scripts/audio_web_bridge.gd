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


## Initializes the web bridge.
## Destroys itself if not running in a web environment.
## Otherwise, registers JS callbacks and connects to AudioManager signals.
## :rtype: void
func _ready() -> void:
	# 1. Self-Destruct if not on web
	if not os_wrapper.has_feature("web"):
		queue_free()
		return

	js_window = js_bridge_wrapper.get_interface("window")
	if not js_window:
		Globals.log_message(
			"AudioWebBridge: Failed to get JS window interface.", Globals.LogLevel.ERROR
		)
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


## Toggles visibility of all audio DOM overlays in the HTML shell.
## Instantly syncs Godot values to the DOM when shown.
## :param show: Pass true to display elements ("block"), false to hide ("none").
## :type show: bool
## :rtype: void
func toggle_dom_visibility(show: bool) -> void:
	if not js_window:
		return

	var visibility: String = "block" if show else "none"
	var ids: Array[String] = [
		"audio-back-button",
		"audio-reset-button",
		"master-slider",
		"music-slider",
		"sfx-slider",
		"weapon-slider",
		"rotors-slider",
		"menu-slider",
		"mute-master",
		"mute-music",
		"mute-sfx",
		"mute-weapon",
		"mute-rotors",
		"mute-menu"
	]

	for id: String in ids:
		js_bridge_wrapper.eval(
			"document.getElementById('%s').style.display = '%s';" % [id, visibility]
		)

	# If showing the menu, immediately sync the DOM to current Godot values
	if show:
		_sync_all_dom_values()


# ==========================================
# GODOT -> JS (Updating the DOM)
# ==========================================


## Signal listener for AudioManager.volume_changed.
## Injects JavaScript to update the corresponding HTML range input.
## :param bus_name: The name of the audio bus.
## :type bus_name: String
## :param value: The new volume level (0.0 to 1.0).
## :type value: float
## :rtype: void
func _on_godot_volume_changed(bus_name: String, value: float) -> void:
	if not js_window:
		return
	var dom_id: String = _get_slider_id_for_bus(bus_name)
	if dom_id != "":
		js_bridge_wrapper.eval("document.getElementById('%s').value = %s" % [dom_id, str(value)])


## Signal listener for AudioManager.mute_toggled.
## Injects JavaScript to update the corresponding HTML checkbox.
## Note: Godot tracks "muted" (true = silent), while HTML tracks "checked" (true = sound on).
## :param bus_name: The name of the audio bus.
## :type bus_name: String
## :param is_muted: The new muted state.
## :type is_muted: bool
## :rtype: void
func _on_godot_mute_toggled(bus_name: String, is_muted: bool) -> void:
	if not js_window:
		return
	var dom_id: String = _get_mute_id_for_bus(bus_name)
	if dom_id != "":
		js_bridge_wrapper.eval(
			"document.getElementById('%s').checked = %s" % [dom_id, str(not is_muted).to_lower()]
		)


## Iterates through all audio buses and forces a DOM update for sliders and checkboxes.
## Keeps the web UI perfectly in sync with Godot's internal state.
## :rtype: void
func _sync_all_dom_values() -> void:
	for bus: String in AudioConstants.BUS_CONFIG.keys():
		var state: Dictionary = AudioManager.get_bus_state(bus)
		_on_godot_volume_changed(bus, state["volume"])
		_on_godot_mute_toggled(bus, state["muted"])


# ==========================================
# JS -> GODOT (Handling Browser Inputs)
# ==========================================


## Generic handler for when an HTML range slider is moved.
## Validates the input and updates the AudioManager if parent buses allow it.
## :param args: Raw arguments passed from JavaScript.
## :type args: Array
## :param bus_name: The target audio bus.
## :type bus_name: String
## :rtype: void
func _on_change_volume_js(args: Array, bus_name: String) -> void:
	var value := _validate_volume_args(args)
	if value < 0.0:
		return

	# Check parent mute states before allowing sub-bus adjustments
	if bus_name != AudioConstants.BUS_MASTER and AudioManager.master_muted:
		return
	if (
		(
			bus_name
			in [
				AudioConstants.BUS_SFX_WEAPON,
				AudioConstants.BUS_SFX_ROTORS,
				AudioConstants.BUS_SFX_MENU
			]
		)
		and AudioManager.sfx_muted
	):
		return

	AudioManager.set_volume(bus_name, value)
	AudioManager.apply_volume_to_bus(bus_name, value, AudioManager.get_muted(bus_name))
	AudioManager.save_volumes()


## Generic handler for when an HTML mute checkbox is toggled.
## Validates the input and updates the AudioManager.
## :param args: Raw arguments passed from JavaScript.
## :type args: Array
## :param bus_name: The target audio bus.
## :type bus_name: String
## :rtype: void
func _on_toggle_mute_js(args: Array, bus_name: String) -> void:
	var checked: Variant = _validate_mute_args(args)
	if checked == null:
		return

	var is_muted: bool = not bool(checked)  # Checkbox checked = unmuted
	AudioManager.set_muted(bus_name, is_muted)
	AudioManager.apply_volume_to_bus(bus_name, AudioManager.get_volume(bus_name), is_muted)
	AudioManager.save_volumes()


# --- Specific callback wrappers required by JavaScriptBridgeWrapper ---


## JS Callback for Master volume slider changes.
## :param args: Raw arguments passed from JavaScript.
## :type args: Array
## :rtype: void
func _on_change_master_volume_js(args: Array) -> void:
	_on_change_volume_js(args, AudioConstants.BUS_MASTER)


## JS Callback for Music volume slider changes.
## :param args: Raw arguments passed from JavaScript.
## :type args: Array
## :rtype: void
func _on_change_music_volume_js(args: Array) -> void:
	_on_change_volume_js(args, AudioConstants.BUS_MUSIC)


## JS Callback for SFX volume slider changes.
## :param args: Raw arguments passed from JavaScript.
## :type args: Array
## :rtype: void
func _on_change_sfx_volume_js(args: Array) -> void:
	_on_change_volume_js(args, AudioConstants.BUS_SFX)


## JS Callback for Weapon volume slider changes.
## :param args: Raw arguments passed from JavaScript.
## :type args: Array
## :rtype: void
func _on_change_weapon_volume_js(args: Array) -> void:
	_on_change_volume_js(args, AudioConstants.BUS_SFX_WEAPON)


## JS Callback for Rotors volume slider changes.
## :param args: Raw arguments passed from JavaScript.
## :type args: Array
## :rtype: void
func _on_change_rotors_volume_js(args: Array) -> void:
	_on_change_volume_js(args, AudioConstants.BUS_SFX_ROTORS)


## JS Callback for Menu volume slider changes.
## :param args: Raw arguments passed from JavaScript.
## :type args: Array
## :rtype: void
func _on_change_menu_volume_js(args: Array) -> void:
	_on_change_volume_js(args, AudioConstants.BUS_SFX_MENU)


## JS Callback for Master mute checkbox toggles.
## :param args: Raw arguments passed from JavaScript.
## :type args: Array
## :rtype: void
func _on_toggle_mute_master_js(args: Array) -> void:
	_on_toggle_mute_js(args, AudioConstants.BUS_MASTER)


## JS Callback for Music mute checkbox toggles.
## :param args: Raw arguments passed from JavaScript.
## :type args: Array
## :rtype: void
func _on_toggle_mute_music_js(args: Array) -> void:
	_on_toggle_mute_js(args, AudioConstants.BUS_MUSIC)


## JS Callback for SFX mute checkbox toggles.
## :param args: Raw arguments passed from JavaScript.
## :type args: Array
## :rtype: void
func _on_toggle_mute_sfx_js(args: Array) -> void:
	_on_toggle_mute_js(args, AudioConstants.BUS_SFX)


## JS Callback for Weapon mute checkbox toggles.
## :param args: Raw arguments passed from JavaScript.
## :type args: Array
## :rtype: void
func _on_toggle_mute_weapon_js(args: Array) -> void:
	_on_toggle_mute_js(args, AudioConstants.BUS_SFX_WEAPON)


## JS Callback for Rotors mute checkbox toggles.
## :param args: Raw arguments passed from JavaScript.
## :type args: Array
## :rtype: void
func _on_toggle_mute_rotors_js(args: Array) -> void:
	_on_toggle_mute_js(args, AudioConstants.BUS_SFX_ROTORS)


## JS Callback for Menu mute checkbox toggles.
## :param args: Raw arguments passed from JavaScript.
## :type args: Array
## :rtype: void
func _on_toggle_mute_menu_js(args: Array) -> void:
	_on_toggle_mute_js(args, AudioConstants.BUS_SFX_MENU)


## JS Callback for the HTML Back button.
## Emits a signal for the UI to handle menu navigation.
## :param _args: Unused raw arguments passed from JavaScript.
## :type _args: Array
## :rtype: void
func _on_audio_back_button_pressed_js(_args: Array) -> void:
	web_back_requested.emit()


## JS Callback for the HTML Reset button.
## Emits a signal for the UI to handle default restoration.
## :param _args: Unused raw arguments passed from JavaScript.
## :type _args: Array
## :rtype: void
func _on_audio_reset_js(_args: Array) -> void:
	web_reset_requested.emit()


# ==========================================
# HELPERS
# ==========================================


## Centralizes the creation and registration of all JavaScript callbacks.
## Maps GDScript methods to window properties accessible in HTML.
## :rtype: void
func _register_all_callbacks() -> void:
	_audio_back_button_pressed_cb = _register_js_callback(
		"_on_audio_back_button_pressed_js", "audioBackPressed"
	)
	_audio_reset_cb = _register_js_callback("_on_audio_reset_js", "audioResetPressed")

	_change_master_volume_cb = _register_js_callback(
		"_on_change_master_volume_js", "changeMasterVolume"
	)
	_change_music_volume_cb = _register_js_callback(
		"_on_change_music_volume_js", "changeMusicVolume"
	)
	_change_sfx_volume_cb = _register_js_callback("_on_change_sfx_volume_js", "changeSfxVolume")
	_change_weapon_volume_cb = _register_js_callback(
		"_on_change_weapon_volume_js", "changeWeaponVolume"
	)
	_change_rotors_volume_cb = _register_js_callback(
		"_on_change_rotors_volume_js", "changeRotorsVolume"
	)
	_change_menu_volume_cb = _register_js_callback("_on_change_menu_volume_js", "changeMenuVolume")

	_toggle_mute_master_cb = _register_js_callback("_on_toggle_mute_master_js", "toggleMuteMaster")
	_toggle_mute_music_cb = _register_js_callback("_on_toggle_mute_music_js", "toggleMuteMusic")
	_toggle_mute_sfx_cb = _register_js_callback("_on_toggle_mute_sfx_js", "toggleMuteSfx")
	_toggle_mute_weapon_cb = _register_js_callback("_on_toggle_mute_weapon_js", "toggleMuteWeapon")
	_toggle_mute_rotors_cb = _register_js_callback("_on_toggle_mute_rotors_js", "toggleMuteRotors")
	_toggle_mute_menu_cb = _register_js_callback("_on_toggle_mute_menu_js", "toggleMuteMenu")


## Helper to create a JavaScript wrapper for a Callable and expose it globally.
## :param callback_method: The name of the GDScript function to bind.
## :type callback_method: String
## :param window_property: The desired property name on the JS 'window' object.
## :type window_property: String
## :rtype: Variant
func _register_js_callback(callback_method: String, window_property: String) -> Variant:
	var callback: Variant = js_bridge_wrapper.create_callback(Callable(self, callback_method))
	js_window[window_property] = callback
	return callback


## Validates volume arguments passed from JavaScript.
## Ensures the payload exists, is numeric, and clamps the result between 0.0 and 1.0.
## :param args: Raw arguments passed from JavaScript.
## :type args: Array
## :rtype: float (-1.0 on failure)
func _validate_volume_args(args: Array) -> float:
	if (
		args.is_empty()
		or typeof(args[0]) != TYPE_OBJECT
		or (typeof(args[0][0]) != TYPE_FLOAT and typeof(args[0][0]) != TYPE_INT)
	):
		Globals.log_message("AudioWebBridge: Invalid volume args", Globals.LogLevel.ERROR)
		return -1.0
	return clamp(float(args[0][0]), 0.0, 1.0)


## Validates mute arguments passed from JavaScript.
## Ensures the payload exists and handles bool/int/float parsing for checkbox states.
## :param args: Raw arguments passed from JavaScript.
## :type args: Array
## :rtype: Variant (null on failure, bool on success)
func _validate_mute_args(args: Array) -> Variant:
	if (
		args.is_empty()
		or typeof(args[0]) != TYPE_OBJECT
		or (
			typeof(args[0][0]) != TYPE_BOOL
			and typeof(args[0][0]) != TYPE_INT
			and typeof(args[0][0]) != TYPE_FLOAT
		)
	):
		Globals.log_message("AudioWebBridge: Invalid mute args", Globals.LogLevel.ERROR)
		return null
	return bool(args[0][0])


## Maps an internal Godot bus name to its corresponding HTML input element ID.
## :param bus_name: The name of the audio bus.
## :type bus_name: String
## :rtype: String
func _get_slider_id_for_bus(bus_name: String) -> String:
	var mapping: Dictionary = {
		AudioConstants.BUS_MASTER: "master-slider",
		AudioConstants.BUS_MUSIC: "music-slider",
		AudioConstants.BUS_SFX: "sfx-slider",
		AudioConstants.BUS_SFX_WEAPON: "weapon-slider",
		AudioConstants.BUS_SFX_ROTORS: "rotors-slider",
		AudioConstants.BUS_SFX_MENU: "menu-slider"
	}
	return mapping.get(bus_name, "")


## Maps an internal Godot bus name to its corresponding HTML checkbox element ID.
## :param bus_name: The name of the audio bus.
## :type bus_name: String
## :rtype: String
func _get_mute_id_for_bus(bus_name: String) -> String:
	var mapping: Dictionary = {
		AudioConstants.BUS_MASTER: "mute-master",
		AudioConstants.BUS_MUSIC: "mute-music",
		AudioConstants.BUS_SFX: "mute-sfx",
		AudioConstants.BUS_SFX_WEAPON: "mute-weapon",
		AudioConstants.BUS_SFX_ROTORS: "mute-rotors",
		AudioConstants.BUS_SFX_MENU: "mute-menu"
	}
	return mapping.get(bus_name, "")
