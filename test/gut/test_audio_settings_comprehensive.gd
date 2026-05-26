extends "res://addons/gut/test.gd"

# Path definitions matching game repository architecture
const AUDIO_SETTINGS_SCENE = preload("res://scenes/audio_settings.tscn")

var _settings_instance: Control = null

# Core bus registry tracking all system channels for looping coverage
const ALL_BUSES = [
	{"name": "Master", "prop_vol": "master_volume", "prop_mute": "master_muted"},
	{"name": "Music", "prop_vol": "music_volume", "prop_mute": "music_muted"},
	{"name": "SFX", "prop_vol": "sfx_volume", "prop_mute": "sfx_muted"},
	{"name": "SFX_Weapon", "prop_vol": "weapon_volume", "prop_mute": "weapon_muted"},
	{"name": "SFX_Rotors", "prop_vol": "rotors_volume", "prop_mute": "rotors_muted"},
	{"name": "SFX_Menu", "prop_vol": "menu_volume", "prop_mute": "menu_muted"}
]


# Runs automatically before every individual test method execution
func before_each() -> void:
	# Clean backend state before spawning UI nodes
	for bus: Dictionary in ALL_BUSES:
		AudioManager.set_volume(bus["name"], 1.0)
		AudioManager.set_muted(bus["name"], false)
		
	_settings_instance = AUDIO_SETTINGS_SCENE.instantiate()
	add_child(_settings_instance)
	
	# Allow layout engine to complete one lifecycle processing frame safely
	await wait_process_frames(1)


# Runs automatically immediately after an individual test finishes execution
func after_each() -> void:
	if is_instance_valid(_settings_instance):
		_settings_instance.queue_free()
	_settings_instance = null
	
	# Clear tracking monitors on the global Autoload object
	_clear_pool_playback_states()


# ==========================================================================
# TEST CATEGORY 1: MANUAL INTERACTIVE AUTO-MUTE (TC-AM-001 THROUGH 006)
# ==========================================================================

## Verifies that manual slider adjustment down to 0.0 successfully auto-mutes
## and triggers confirmation audio across every individual bus channel.
func test_comprehensive_manual_slider_to_zero_engages_mute_and_audio() -> void:
	for bus: Dictionary in ALL_BUSES:
		var slider: HSlider = _get_slider_node(bus["name"])
		var checkbox: CheckButton = _get_checkbox_node(bus["name"])
		
		assert_not_null(slider, "Setup Error: Slider node not found for bus: %s" % bus["name"])
		assert_not_null(checkbox, "Setup Error: Checkbox node not found for bus: %s" % bus["name"])
		
		# 1. Force state to unmuted, active baseline
		AudioManager.set_volume(bus["name"], 0.7)
		AudioManager.set_muted(bus["name"], false)
		_settings_instance._sync_ui_from_manager()
		
		# 2. Assume layout focus on the targeted slider element to mimic hardware manipulation
		slider.grab_focus()
		assert_true(slider.has_focus(), "UI Error: Failed to assign focus context to slider: %s" % bus["name"])
		
		# 3. Simulate hardware volume adjustment drop down to zero threshold
		_clear_pool_playback_states()
		AudioManager.set_volume(bus["name"], 0.0)
		await wait_process_frames(1)
		
		# 4. Verify backend variables updated symmetrically
		assert_true(
			AudioManager.get_muted(bus["name"]),
			"Failure: Manager mute variable stayed false for bus: %s" % bus["name"]
		)
		
		# 5. Verify frontend visual widget matches backend parameters
		assert_false(
			checkbox.button_pressed,
			"Failure: Checkbox stayed visually checked following auto-mute transition on bus: %s" % bus["name"]
		)
		
		# 6. Verify pool execution status to confirm check.wav fired safely
		assert_true(
			_is_any_pool_player_active(),
			"Failure: Audio feedback failed to stream through object pool for manual zero drop on bus: %s" % bus["name"]
		)
		
		# Release context before continuing iteration blocks
		slider.release_focus()


# ==========================================================================
# TEST CATEGORY 2: AUTOMATION/REMOTE SYNC ISOLATION (TC-AM-007 THROUGH 012)
# ==========================================================================

## Verifies that programmatic state modifications down to 0.0 (WebBridge, Playwright)
## alter visual checkbox states silently without firing any audio feedback elements.
func test_comprehensive_programmatic_sync_to_zero_remains_completely_silent() -> void:
	for bus: Dictionary in ALL_BUSES:
		var slider: HSlider = _get_slider_node(bus["name"])
		var checkbox: CheckButton = _get_checkbox_node(bus["name"])
		
		# 1. Establish unmuted state baseline
		AudioManager.set_volume(bus["name"], 0.5)
		AudioManager.set_muted(bus["name"], false)
		_settings_instance._sync_ui_from_manager()
		
		# 2. Defensively strip focus from the target elements to simulate a background data pipeline
		slider.release_focus()
		checkbox.release_focus()
		assert_false(slider.has_focus(), "Context Error: Slider unexpectedly commands focus state.")
		
		# 3. Process automated value change message down to zero threshold
		_clear_pool_playback_states()
		AudioManager.set_volume(bus["name"], 0.0)
		await wait_process_frames(1)
		
		# 4. Assertions - Variable checks out correctly
		assert_true(AudioManager.get_muted(bus["name"]), "Failure: Flag failed automated mute change update.")
		
		# 5. Assertions - UI drawn correctly
		assert_false(checkbox.button_pressed, "Failure: Checkbox failed to register visual sync switch.")
		
		# 6. Assertions - Absolute Silence Guard (CRITICAL FOR QA PIPELINES)
		assert_false(
			_is_any_pool_player_active(),
			"Security Leak: SFX audio escaped during an automated background data sync on bus: %s" % bus["name"]
		)


# ==========================================================================
# TEST CATEGORY 3: BOUNDARY CONTROLS & HYBRID TRANSITIONS (TC-AM-013 & 014)
# ==========================================================================

## Verifies that updating a volume track which is already muted does not re-trigger
## duplicate overlay playbacks (Idempotency verification).
func test_idempotent_zero_volume_updates_suppress_redundant_audio() -> void:
	var music_slider: HSlider = _settings_instance.music_slider
	
	# Set up initial state directly as pre-muted at zero volume
	AudioManager.set_volume(AudioConstants.BUS_MUSIC, 0.0)
	AudioManager.set_muted(AudioConstants.BUS_MUSIC, true)
	_settings_instance._sync_ui_from_manager()
	
	music_slider.grab_focus()
	_clear_pool_playback_states()
	
	# Simulate a redundant manual update call to 0.0
	AudioManager.set_volume(AudioConstants.BUS_MUSIC, 0.0)
	await wait_process_frames(1)
	
	assert_false(
		_is_any_pool_player_active(),
		"Failure: Redundant volume update to 0.0 re-triggered audio on an already muted bus."
	)


## Verifies that pulling a slider upward out of an auto-muted state cleanly triggers
## the auto-unmute cycle, checking the toggle widget back on.
func test_slider_upward_progression_triggers_correct_auto_unmute_cycle() -> void:
	var sfx_slider: HSlider = _settings_instance.sfx_slider
	var checkbox: CheckButton = _settings_instance.mute_sfx
	
	# Initialize scene as auto-muted at zero
	AudioManager.set_volume(AudioConstants.BUS_SFX, 0.0)
	AudioManager.set_muted(AudioConstants.BUS_SFX, true)
	_settings_instance._sync_ui_from_manager()
	
	sfx_slider.grab_focus()
	
	# Trigger via manager parameter to smoothly run through the verified global hook
	AudioManager.set_volume(AudioConstants.BUS_SFX, 0.15)
	await wait_process_frames(1)
	
	# Assert that the auto-unmute cycle fired successfully
	assert_false(AudioManager.get_muted(AudioConstants.BUS_SFX), "Failure: Bus failed to automatically unmute.")
	assert_true(checkbox.button_pressed, "Failure: Mute checkbox failed to visually re-check during upward adjustment.")


# ==========================================================================
# AUXILIARY UTILITY REFLEX METHODS (LINTING & CLEAN EXIT COMPLIANT)
# ==========================================================================

# Internal node routing helper to satisfy clean execution rules
func _get_slider_node(bus_name: String) -> HSlider:
	match bus_name:
		"Master": return _settings_instance.master_slider
		"Music": return _settings_instance.music_slider
		"SFX": return _settings_instance.sfx_slider
		"SFX_Weapon": return _settings_instance.weapon_slider
		"SFX_Rotors": return _settings_instance.rotor_slider
		"SFX_Menu": return _settings_instance.menu_slider
	return null


# Internal checkbox widget mapping provider
func _get_checkbox_node(bus_name: String) -> CheckButton:
	match bus_name:
		"Master": return _settings_instance.mute_master
		"Music": return _settings_instance.mute_music
		"SFX": return _settings_instance.mute_sfx
		"SFX_Weapon": return _settings_instance.mute_weapon
		"SFX_Rotors": return _settings_instance.mute_rotor
		"SFX_Menu": return _settings_instance.mute_menu
	return null


# Loops through AudioManager's backend object pool to track active play states
func _is_any_pool_player_active() -> bool:
	for player: AudioStreamPlayer in AudioManager._sfx_pool:
		if player.playing:
			return true
	return false


# Force stops pool players between verification steps to isolate test conditions
func _clear_pool_playback_states() -> void:
	for player: AudioStreamPlayer in AudioManager._sfx_pool:
		player.stop()
		player.stream = null
