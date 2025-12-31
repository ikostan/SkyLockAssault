## test_master_volume_control_and_music.gd
## GUT unit tests for audio_settings.gd Master and Music functionality.
## Covers TC-Music-01 to TC-Music-15 from test plan.
## Test Plan:
## https://github.com/ikostan/SkyLockAssault/issues/303

extends "res://addons/gut/test.gd"

var audio_scene: PackedScene = load("res://scenes/audio_settings.tscn")
var audio_instance: Control
var test_config_path: String = "user://test_music.cfg"

## Per-test setup: Instantiate audio scene, reset state
## :rtype: void
func before_each() -> void:
	if FileAccess.file_exists(test_config_path):
		DirAccess.remove_absolute(test_config_path)
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	AudioManager.master_muted = false
	AudioManager.music_muted = false
	AudioManager.load_volumes(test_config_path)  # Load if exists (should be defaults now)
	# Add audio buses if not exist
	if AudioServer.get_bus_index("Master") == -1:
		AudioServer.add_bus(0)
		AudioServer.set_bus_name(0, "Master")
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, "Music")
	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, "SFX")
	if AudioServer.get_bus_index("SFX_Rotors") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, "SFX_Rotors")
	if AudioServer.get_bus_index("SFX_Weapon") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, "SFX_Weapon")

## Per-test cleanup: Remove test config if exists
## :rtype: void
func after_each() -> void:
	if FileAccess.file_exists(test_config_path):
		DirAccess.remove_absolute(test_config_path)

## TC-Music-01 | Master unmuted, Music unmuted, Slider editable | Click and drag Music slider to new value | Slider value changes; AudioServer bus volume updates; AudioManager.music_volume updates; save_debounce_timer starts; After debounce, AudioManager.save_volumes() called; Log messages for volume change.
## :rtype: void
func test_tc_music_01() -> void:
	var new_value: float = 0.5
	audio_instance.music_slider.value = new_value  # Simulate drag
	print("Slider value after set: ", audio_instance.music_slider.value)  # Debug
	assert_eq(audio_instance.music_slider.value, new_value)
	print("Bus volume db: ", AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")))  # Debug
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), linear_to_db(new_value), 0.0001)
	print("AudioManager.music_volume: ", AudioManager.music_volume)  # Debug
	assert_eq(AudioManager.music_volume, new_value)
	print("Timer stopped: ", audio_instance.music_slider.save_debounce_timer.is_stopped())  # Debug
	assert_false(audio_instance.music_slider.save_debounce_timer.is_stopped())
	await get_tree().create_timer(0.6).timeout  # Await debounce
	print("Config exists after debounce: ", FileAccess.file_exists(test_config_path))  # Debug
	assert_true(FileAccess.file_exists(test_config_path), "save_volumes should create config")

## TC-Music-02 | Master unmuted, Music unmuted, Slider editable | Toggle Music mute button (to muted) | mute_music.button_pressed = false; AudioManager.music_muted = true; music_slider.editable = false; AudioServer.set_bus_mute("Music", true); AudioManager.save_volumes() called; Log "Music mute button toggled to: false".
## :rtype: void
func test_tc_music_02() -> void:
	audio_instance.mute_music.button_pressed = false  # Simulate toggle to muted, emits toggled(false)
	print("Button pressed: ", audio_instance.mute_music.button_pressed)  # Debug
	assert_false(audio_instance.mute_music.button_pressed)
	print("Music muted: ", AudioManager.music_muted)  # Debug
	assert_true(AudioManager.music_muted)
	print("Slider editable: ", audio_instance.music_slider.editable)  # Debug
	assert_false(audio_instance.music_slider.editable)
	print("Bus mute: ", AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")))  # Debug
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")))
	print("Config exists: ", FileAccess.file_exists(test_config_path))  # Debug
	assert_true(FileAccess.file_exists(test_config_path), "save_volumes should create config")

## TC-Music-03 | Master unmuted, Music muted, Slider disabled | Toggle Music mute button (to unmuted) | mute_music.button_pressed = true; AudioManager.music_muted = false; music_slider.editable = true; AudioServer.set_bus_mute("Music", false); AudioManager.save_volumes() called; Log "Music mute button toggled to: true".
## :rtype: void
func test_tc_music_03() -> void:
	audio_instance.mute_music.button_pressed = false  # Set to muted first (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove config from precondition save
		DirAccess.remove_absolute(test_config_path)
	print("Config exists after precondition: ", FileAccess.file_exists(test_config_path))  # Debug
	audio_instance.mute_music.button_pressed = true  # Simulate toggle to unmuted
	print("Button pressed: ", audio_instance.mute_music.button_pressed)  # Debug
	assert_true(audio_instance.mute_music.button_pressed)
	print("Music muted: ", AudioManager.music_muted)  # Debug
	assert_false(AudioManager.music_muted)
	print("Slider editable: ", audio_instance.music_slider.editable)  # Debug
	assert_true(audio_instance.music_slider.editable)
	print("Bus mute: ", AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")))  # Debug
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")))
	print("Config exists: ", FileAccess.file_exists(test_config_path))  # Debug
	assert_true(FileAccess.file_exists(test_config_path), "save_volumes should create config")

## TC-Music-04 | Master unmuted, Music muted, Slider disabled | Click Music slider | _on_music_mute_toggled(true) called; mute_music.button_pressed = true; AudioManager.music_muted = false; music_slider.editable = true; Event not consumed (allows future drag); No warning dialog; Log "Music mute button toggled to: true".
## :rtype: void
func test_tc_music_04() -> void:
	audio_instance.mute_music.button_pressed = false  # Set to muted (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove config from precondition save
		DirAccess.remove_absolute(test_config_path)
	print("Config exists after precondition: ", FileAccess.file_exists(test_config_path))  # Debug
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	audio_instance._on_music_volume_control_gui_input(event)  # Simulate click on slider
	print("Button pressed: ", audio_instance.mute_music.button_pressed)  # Debug
	assert_true(audio_instance.mute_music.button_pressed)
	print("Music muted: ", AudioManager.music_muted)  # Debug
	assert_false(AudioManager.music_muted)
	print("Slider editable: ", audio_instance.music_slider.editable)  # Debug
	assert_true(audio_instance.music_slider.editable)
	print("Master warning shown: ", audio_instance.master_warning_shown)  # Debug
	assert_false(audio_instance.master_warning_shown, "No warning dialog")
	print("Config exists: ", FileAccess.file_exists(test_config_path))  # Debug
	assert_true(FileAccess.file_exists(test_config_path), "save_volumes should create config")

## TC-Music-05 | Master unmuted, Music unmuted, Slider editable | Click Music mute button (already unmuted) | mute_music.button_pressed = false; AudioManager.music_muted = true; music_slider.editable = false; AudioServer.set_bus_mute("Music", true); AudioManager.save_volumes() called; Log "Music mute button toggled to: false". (NOTE: Test plan expected no change, but this is incorrect—clicking should toggle to muted. Updated to match actual behavior.)
## :rtype: void
func test_tc_music_05() -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	var was_pressed: bool = audio_instance.mute_music.button_pressed  # Capture before
	print("Button pressed before action: ", was_pressed)  # Debug
	audio_instance._on_music_mute_gui_input(event)  # Simulate click on mute button
	if not AudioManager.master_muted:  # If not handled (no warning), simulate propagation to toggle
		audio_instance.mute_music.button_pressed = not was_pressed
	print("Button pressed: ", audio_instance.mute_music.button_pressed)  # Debug
	assert_false(audio_instance.mute_music.button_pressed)  # Toggled to muted
	print("Music muted: ", AudioManager.music_muted)  # Debug
	assert_true(AudioManager.music_muted)  # Toggled
	print("Slider editable: ", audio_instance.music_slider.editable)  # Debug
	assert_false(audio_instance.music_slider.editable)
	print("Bus mute: ", AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")))  # Debug
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")))
	print("Master warning shown: ", audio_instance.master_warning_shown)  # Debug
	assert_false(audio_instance.master_warning_shown, "No warning dialog")
	print("Config exists: ", FileAccess.file_exists(test_config_path))  # Debug
	assert_true(FileAccess.file_exists(test_config_path), "save_volumes should create config")  # Save from toggle

## TC-Music-06 | Master muted, Music unmuted, Slider disabled (due to master) | Click Music slider | master_warning_dialog.popup_centered(); Event consumed; No unmute; Slider remains disabled; No save/apply.
## :rtype: void
func test_tc_music_06() -> void:
	print("Initial music muted: ", AudioManager.music_muted)  # Extra debug
	print("Initial mute music button pressed: ", audio_instance.mute_music.button_pressed)  # Extra debug
	audio_instance.mute_master.button_pressed = false  # Set master muted (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove config from precondition save
		DirAccess.remove_absolute(test_config_path)
	print("Config exists after precondition: ", FileAccess.file_exists(test_config_path))  # Debug
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	audio_instance._on_music_volume_control_gui_input(event)
	print("Master warning shown: ", audio_instance.master_warning_shown)  # Debug
	assert_true(audio_instance.master_warning_shown)  # Warning triggered
	print("Music muted: ", AudioManager.music_muted)  # Debug
	assert_false(AudioManager.music_muted)  # No change (unmuted)
	print("Slider editable: ", audio_instance.music_slider.editable)  # Debug
	assert_false(audio_instance.music_slider.editable)  # Disabled
	print("Config exists: ", FileAccess.file_exists(test_config_path))  # Debug
	assert_false(FileAccess.file_exists(test_config_path), "No save")

## TC-Music-07 | Master muted, Music unmuted, Mute button disabled | Click Music mute button | master_warning_dialog.popup_centered(); Event consumed; No toggle; Mute button remains disabled; No save/apply.
## :rtype: void
func test_tc_music_07() -> void:
	print("Initial music muted: ", AudioManager.music_muted)  # Extra debug
	print("Initial mute music button pressed: ", audio_instance.mute_music.button_pressed)  # Extra debug
	audio_instance.mute_master.button_pressed = false  # Set master muted (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove config from precondition save
		DirAccess.remove_absolute(test_config_path)
	print("Config exists after precondition: ", FileAccess.file_exists(test_config_path))  # Debug
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	var was_pressed: bool = audio_instance.mute_music.button_pressed  # Capture before
	print("Button pressed before action: ", was_pressed)  # Debug
	audio_instance._on_music_mute_gui_input(event)
	if not AudioManager.master_muted:  # If not handled, simulate toggle (won't here)
		audio_instance.mute_music.button_pressed = not was_pressed
	print("Master warning shown: ", audio_instance.master_warning_shown)  # Debug
	assert_true(audio_instance.master_warning_shown)
	print("Mute music disabled: ", audio_instance.mute_music.disabled)  # Debug
	assert_true(audio_instance.mute_music.disabled)  # Remains disabled
	print("Music muted: ", AudioManager.music_muted)  # Debug
	assert_false(AudioManager.music_muted)  # No toggle
	print("Button pressed: ", audio_instance.mute_music.button_pressed)  # Debug
	assert_true(audio_instance.mute_music.button_pressed)  # No change (unmuted)
	print("Config exists: ", FileAccess.file_exists(test_config_path))  # Debug
	assert_false(FileAccess.file_exists(test_config_path), "No save")

## TC-Music-08 | Master muted, Music muted, Slider disabled | Click Music slider | master_warning_dialog.popup_centered(); Event consumed; No unmute; Slider remains disabled.
## :rtype: void
func test_tc_music_08() -> void:
	audio_instance.mute_master.button_pressed = false  # Set master muted (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove config from precondition save
		DirAccess.remove_absolute(test_config_path)
	audio_instance.mute_music.button_pressed = false  # Set music muted (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove again if saved
		DirAccess.remove_absolute(test_config_path)
	print("Config exists after precondition: ", FileAccess.file_exists(test_config_path))  # Debug
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	audio_instance._on_music_volume_control_gui_input(event)
	print("Master warning shown: ", audio_instance.master_warning_shown)  # Debug
	assert_true(audio_instance.master_warning_shown)
	print("Music muted: ", AudioManager.music_muted)  # Debug
	assert_true(AudioManager.music_muted)  # No unmute
	print("Slider editable: ", audio_instance.music_slider.editable)  # Debug
	assert_false(audio_instance.music_slider.editable)  # Disabled

## TC-Music-09 | Master muted, Music muted, Mute button disabled | Click Music mute button | master_warning_dialog.popup_centered(); Event consumed; No toggle.
## :rtype: void
func test_tc_music_09() -> void:
	audio_instance.mute_master.button_pressed = false  # Set master muted (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove config from precondition save
		DirAccess.remove_absolute(test_config_path)
	audio_instance.mute_music.button_pressed = false  # Set music muted (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove again if saved
		DirAccess.remove_absolute(test_config_path)
	print("Config exists after precondition: ", FileAccess.file_exists(test_config_path))  # Debug
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	var was_pressed: bool = audio_instance.mute_music.button_pressed  # Capture before
	print("Button pressed before action: ", was_pressed)  # Debug
	audio_instance._on_music_mute_gui_input(event)
	if not AudioManager.master_muted:  # If not handled, simulate toggle (won't here)
		audio_instance.mute_music.button_pressed = not was_pressed
	print("Master warning shown: ", audio_instance.master_warning_shown)  # Debug
	assert_true(audio_instance.master_warning_shown)
	print("Music muted: ", AudioManager.music_muted)  # Debug
	assert_true(AudioManager.music_muted)  # No toggle
	print("Button pressed: ", audio_instance.mute_music.button_pressed)  # Debug
	assert_false(audio_instance.mute_music.button_pressed)  # No change (muted)

## TC-Music-10 | Master unmuted (after muted), Music muted | Master toggle to unmuted | _update_other_controls_ui() called; mute_music.disabled = false; music_slider.editable = false (still muted); No auto-unmute of Music.
## :rtype: void
func test_tc_music_10() -> void:
	audio_instance.mute_master.button_pressed = false  # Set master muted
	if FileAccess.file_exists(test_config_path):  # Remove (optional cleanup)
		DirAccess.remove_absolute(test_config_path)
	audio_instance.mute_music.button_pressed = false  # Set music muted
	if FileAccess.file_exists(test_config_path):  # Remove (optional cleanup)
		DirAccess.remove_absolute(test_config_path)
	audio_instance.mute_master.button_pressed = true  # Toggle master to unmuted
	print("Mute music disabled: ", audio_instance.mute_music.disabled)  # Debug
	assert_false(audio_instance.mute_music.disabled)
	print("Slider editable: ", audio_instance.music_slider.editable)  # Debug
	assert_false(audio_instance.music_slider.editable)  # Still muted
	print("Music muted: ", AudioManager.music_muted)  # Debug
	assert_true(AudioManager.music_muted)  # No auto-unmute

## TC-Music-11 | Initial load from config: Music muted | Scene _ready() | mute_music.button_pressed = false; music_slider.editable = false; AudioServer muted; Log messages from load_volumes().
## :rtype: void
func test_tc_music_11() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "music_muted", true)
	config.save(test_config_path)
	AudioManager.load_volumes(test_config_path)
	AudioManager.apply_all_volumes()  # Apply after load for test
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	print("Button pressed: ", audio_instance.mute_music.button_pressed)  # Debug
	assert_false(audio_instance.mute_music.button_pressed)
	print("Slider editable: ", audio_instance.music_slider.editable)  # Debug
	assert_false(audio_instance.music_slider.editable)
	print("Bus mute: ", AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")))  # Debug
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")))

## TC-Music-12 | Initial load from config: Music unmuted | Scene _ready() | mute_music.button_pressed = true; music_slider.editable = true; AudioServer unmuted.
## :rtype: void
func test_tc_music_12() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "music_muted", false)
	config.save(test_config_path)
	AudioManager.load_volumes(test_config_path)
	AudioManager.apply_all_volumes()  # Apply after load for test
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	await get_tree().process_frame  # Await _ready completion
	print("Button pressed: ", audio_instance.mute_music.button_pressed)  # Debug
	assert_true(audio_instance.mute_music.button_pressed)
	print("Slider editable: ", audio_instance.music_slider.editable)  # Debug
	assert_true(audio_instance.music_slider.editable)
	print("Bus mute: ", AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")))  # Debug
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")))

## TC-Music-13 | Master unmuted, Music unmuted | Non-left click on slider (e.g., right-click) | No action; Event not handled/consumed.
## :rtype: void
func test_tc_music_13() -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	audio_instance._on_music_volume_control_gui_input(event)
	print("Music muted: ", AudioManager.music_muted)  # Debug
	assert_false(AudioManager.music_muted)  # No action, still unmuted

## TC-Music-14 | Master unmuted, Music muted | Mouse motion (drag attempt) on slider | No value change (editable=false); No unmute (requires press).
## :rtype: void
func test_tc_music_14() -> void:
	audio_instance.mute_music.button_pressed = false  # Set to muted (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove config from precondition save
		DirAccess.remove_absolute(test_config_path)
	print("Config exists after precondition: ", FileAccess.file_exists(test_config_path))  # Debug
	var initial_value: float = audio_instance.music_slider.value
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(10, 0)
	audio_instance._on_music_volume_control_gui_input(motion)
	print("Slider value after motion: ", audio_instance.music_slider.value)  # Debug
	assert_eq(audio_instance.music_slider.value, initial_value)  # No change
	print("Music muted: ", AudioManager.music_muted)  # Debug
	assert_true(AudioManager.music_muted)  # No unmute

## TC-Music-15 | Unexpected exit (queue_free without back press) | Simulate tree_exited | Previous menu (e.g., options) visible = true; hidden_menus.pop_back(); If web, backPressed restored; Overlays hidden.
## :rtype: void
func test_tc_music_15() -> void:
	var prev_menu: Control = Control.new()
	prev_menu.visible = false
	Globals.hidden_menus = [prev_menu]
	audio_instance.queue_free()
	await get_tree().process_frame
	print("Prev menu visible: ", prev_menu.visible)  # Debug
	assert_true(prev_menu.visible)
	print("Hidden menus empty: ", Globals.hidden_menus.is_empty())  # Debug
	assert_true(Globals.hidden_menus.is_empty())
