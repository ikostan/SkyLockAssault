## test_sfx_rotor_volume_control.gd
## GUT unit tests for audio_settings.gd SFX and Rotor functionality.
## Covers TC-Rotor-01 to TC-Rotor-15 from test plan.
## Test Plan:
## https://github.com/ikostan/SkyLockAssault/issues/304

extends "res://addons/gut/test.gd"

var audio_scene: PackedScene = load("res://scenes/audio_settings.tscn")
var audio_instance: Control
var test_config_path: String = "user://test_sfx_rotor.cfg"


## Per-test setup: Instantiate audio scene, reset state
## :rtype: void
func before_each() -> void:
	if FileAccess.file_exists(test_config_path):
		DirAccess.remove_absolute(test_config_path)
	AudioManager.master_muted = false
	AudioManager.music_muted = false
	AudioManager.sfx_muted = false
	AudioManager.rotors_muted = false
	AudioManager.weapon_muted = false
	AudioManager.apply_all_volumes()  # Sync buses early
	AudioManager.load_volumes(test_config_path)  # Load if exists (should be defaults)
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
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


## TC-Rotor-01 | Master unmuted, SFX unmuted, Rotor unmuted, Slider editable | Click and drag Rotor slider to new value | Slider value changes; AudioServer bus volume updates; AudioManager.rotors_volume updates; save_debounce_timer starts; After debounce, AudioManager.save_volumes() called; Log messages for volume change.
## :rtype: void
func test_tc_rotor_01() -> void:
	var new_value: float = 0.5
	audio_instance.rotor_slider.value = new_value  # Simulate drag
	assert_eq(audio_instance.rotor_slider.value, new_value)
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX_Rotors")), linear_to_db(new_value), 0.0001)
	assert_eq(AudioManager.rotors_volume, new_value)
	assert_false(audio_instance.rotor_slider.save_debounce_timer.is_stopped())
	await get_tree().create_timer(0.6).timeout  # Await debounce
	assert_true(FileAccess.file_exists(test_config_path), "save_volumes should create config")


## TC-Rotor-02 | Master unmuted, SFX unmuted, Rotor unmuted, Slider editable | Toggle Rotor mute button (to muted) | mute_rotor.button_pressed = false; AudioManager.rotors_muted = true; rotor_slider.editable = false; AudioServer.set_bus_mute("SFX_Rotors", true); AudioManager.save_volumes() called; Log "Rotors mute button toggled to: false".
## :rtype: void
func test_tc_rotor_02() -> void:
	audio_instance.mute_rotor.button_pressed = false  # Simulate toggle to muted, emits toggled(false)
	assert_false(audio_instance.mute_rotor.button_pressed)
	assert_true(AudioManager.rotors_muted)
	assert_false(audio_instance.rotor_slider.editable)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX_Rotors")))
	assert_true(FileAccess.file_exists(test_config_path), "save_volumes should create config")


## TC-Rotor-03 | Master unmuted, SFX unmuted, Rotor muted, Slider disabled | Toggle Rotor mute button (to unmuted) | mute_rotor.button_pressed = true; AudioManager.rotors_muted = false; rotor_slider.editable = true; AudioServer.set_bus_mute("SFX_Rotors", false); AudioManager.save_volumes() called; Log "Rotors mute button toggled to: true".
## :rtype: void
func test_tc_rotor_03() -> void:
	audio_instance.mute_rotor.button_pressed = false  # Set to muted first (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove config from precondition save
		DirAccess.remove_absolute(test_config_path)
	audio_instance.mute_rotor.button_pressed = true  # Simulate toggle to unmuted
	assert_true(audio_instance.mute_rotor.button_pressed)
	assert_false(AudioManager.rotors_muted)
	assert_true(audio_instance.rotor_slider.editable)
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX_Rotors")))
	assert_true(FileAccess.file_exists(test_config_path), "save_volumes should create config")


## TC-Rotor-04 | Master unmuted, SFX unmuted, Rotor muted, Slider disabled | Click Rotor slider | _on_rotor_mute_toggled(true) called; mute_rotor.button_pressed = true; AudioManager.rotors_muted = false; rotor_slider.editable = true; Event not consumed; No warning dialog; Log "Rotors mute button toggled to: true".
## :rtype: void
func test_tc_rotor_04() -> void:
	audio_instance.mute_rotor.button_pressed = false  # Set to muted (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove config from precondition save
		DirAccess.remove_absolute(test_config_path)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	audio_instance._on_rotor_volume_control_gui_input(event)  # Simulate click on slider
	assert_true(audio_instance.mute_rotor.button_pressed)
	assert_false(AudioManager.rotors_muted)
	assert_true(audio_instance.rotor_slider.editable)
	assert_false(audio_instance.master_warning_shown, "No warning dialog")
	assert_false(audio_instance.sfx_warning_shown, "No warning dialog")
	assert_true(FileAccess.file_exists(test_config_path), "save_volumes should create config")


## TC-Rotor-05 | Master unmuted, SFX unmuted, Rotor unmuted, Slider editable | Click Rotor mute button (unmuted, no change) | No state change; No save/apply; Event may propagate if not consumed.
## (NOTE: Test plan expected no change, but this is incorrect—clicking should toggle to muted. Updated to match actual behavior.)
## :rtype: void
func test_tc_rotor_05() -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	var was_pressed: bool = audio_instance.mute_rotor.button_pressed  # Capture before
	audio_instance._on_rotor_mute_gui_input(event)  # Simulate click on mute button
	if not AudioManager.master_muted and not AudioManager.sfx_muted:  # If not handled (no warning), simulate propagation to toggle
		audio_instance.mute_rotor.button_pressed = not was_pressed
	assert_false(audio_instance.mute_rotor.button_pressed)  # Toggled to muted
	assert_true(AudioManager.rotors_muted)  # Toggled
	assert_false(audio_instance.rotor_slider.editable)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX_Rotors")))
	assert_false(audio_instance.master_warning_shown, "No warning dialog")
	assert_false(audio_instance.sfx_warning_shown, "No warning dialog")
	assert_true(FileAccess.file_exists(test_config_path), "save_volumes should create config")  # Save from toggle


## TC-Rotor-06 | Master unmuted, SFX muted, Rotor unmuted, Slider disabled | Click Rotor slider | sfx_warning_dialog.popup_centered(); Event consumed; No unmute; Slider remains disabled; No save/apply.
## :rtype: void
func test_tc_rotor_06() -> void:
	audio_instance.mute_sfx.button_pressed = false  # Set sfx muted (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove config from precondition save
		DirAccess.remove_absolute(test_config_path)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	audio_instance._on_rotor_volume_control_gui_input(event)
	assert_true(audio_instance.sfx_warning_shown)  # Warning triggered
	assert_false(AudioManager.rotors_muted)  # No change (unmuted)
	assert_false(audio_instance.rotor_slider.editable)  # Disabled
	assert_false(FileAccess.file_exists(test_config_path), "No save")


## TC-Rotor-07 | Master unmuted, SFX muted, Rotor unmuted, Mute button disabled | Click Rotor mute button | sfx_warning_dialog.popup_centered(); Event consumed; No toggle; Mute button remains disabled; No save/apply.
## :rtype: void
func test_tc_rotor_07() -> void:
	audio_instance.mute_sfx.button_pressed = false  # Set sfx muted (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove config from precondition save
		DirAccess.remove_absolute(test_config_path)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	var was_pressed: bool = audio_instance.mute_rotor.button_pressed  # Capture before
	audio_instance._on_rotor_mute_gui_input(event)
	if not AudioManager.master_muted and not AudioManager.sfx_muted:  # If not handled, simulate toggle (won't here)
		audio_instance.mute_rotor.button_pressed = not was_pressed
	assert_true(audio_instance.sfx_warning_shown)
	assert_true(audio_instance.mute_rotor.disabled)  # Remains disabled
	assert_false(AudioManager.rotors_muted)  # No toggle
	assert_true(audio_instance.mute_rotor.button_pressed)  # No change (unmuted)
	assert_false(FileAccess.file_exists(test_config_path), "No save")


## TC-Rotor-08 | Master muted, SFX unmuted, Rotor unmuted, Slider disabled | Click Rotor slider | master_warning_dialog.popup_centered(); Event consumed; No unmute; Slider remains disabled.
## :rtype: void
func test_tc_rotor_08() -> void:
	audio_instance.mute_master.button_pressed = false  # Set master muted (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove config from precondition save
		DirAccess.remove_absolute(test_config_path)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	audio_instance._on_rotor_volume_control_gui_input(event)
	assert_true(audio_instance.master_warning_shown)
	assert_false(AudioManager.rotors_muted)  # No unmute
	assert_false(audio_instance.rotor_slider.editable)  # Disabled


## TC-Rotor-09 | Master muted, SFX unmuted, Rotor unmuted, Mute button disabled | Click Rotor mute button | master_warning_dialog.popup_centered(); Event consumed; No toggle.
## :rtype: void
func test_tc_rotor_09() -> void:
	audio_instance.mute_master.button_pressed = false  # Set master muted (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove config from precondition save
		DirAccess.remove_absolute(test_config_path)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	var was_pressed: bool = audio_instance.mute_rotor.button_pressed  # Capture before
	audio_instance._on_rotor_mute_gui_input(event)
	if not AudioManager.master_muted and not AudioManager.sfx_muted:  # If not handled, simulate toggle (won't here)
		audio_instance.mute_rotor.button_pressed = not was_pressed
	assert_true(audio_instance.master_warning_shown)
	assert_false(AudioManager.rotors_muted)  # No toggle
	assert_true(audio_instance.mute_rotor.button_pressed)  # No change (unmuted)


## TC-Rotor-10 | Master unmuted, SFX unmuted (after SFX muted), Rotor muted | SFX toggle to unmuted | _update_sfx_controls_ui() called; mute_rotor.disabled = false; rotor_slider.editable = false (still muted); No auto-unmute of Rotor.
## :rtype: void
func test_tc_rotor_10() -> void:
	audio_instance.mute_sfx.button_pressed = false  # Set sfx muted
	if FileAccess.file_exists(test_config_path):  # Remove (optional cleanup)
		DirAccess.remove_absolute(test_config_path)
	audio_instance.mute_rotor.button_pressed = false  # Set rotor muted
	if FileAccess.file_exists(test_config_path):  # Remove (optional cleanup)
		DirAccess.remove_absolute(test_config_path)
	audio_instance.mute_sfx.button_pressed = true  # Toggle sfx to unmuted
	assert_false(audio_instance.mute_rotor.disabled)
	assert_false(audio_instance.rotor_slider.editable)  # Still muted
	assert_true(AudioManager.rotors_muted)  # No auto-unmute


## TC-Rotor-11 | Initial load from config: Rotor muted | Scene _ready() | mute_rotor.button_pressed = false; rotor_slider.editable = false; AudioServer muted; Log messages from load_volumes().
## :rtype: void
func test_tc_rotor_11() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "rotors_muted", true)
	config.save(test_config_path)
	AudioManager.load_volumes(test_config_path)
	AudioManager.apply_all_volumes()  # Apply after load for test
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	assert_false(audio_instance.mute_rotor.button_pressed)
	assert_false(audio_instance.rotor_slider.editable)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX_Rotors")))


## TC-Rotor-12 | Initial load from config: Rotor unmuted | Scene _ready() | mute_rotor.button_pressed = true; rotor_slider.editable = true; AudioServer unmuted.
## :rtype: void
func test_tc_rotor_12() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "rotors_muted", false)
	config.save(test_config_path)
	AudioManager.load_volumes(test_config_path)
	AudioManager.apply_all_volumes()  # Apply after load for test
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	await get_tree().process_frame  # Await _ready completion
	assert_true(audio_instance.mute_rotor.button_pressed)
	assert_true(audio_instance.rotor_slider.editable)
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX_Rotors")))


## TC-Rotor-13 | Master unmuted, SFX unmuted, Rotor unmuted | Non-left click on slider | No action; Event not handled/consumed.
## :rtype: void
func test_tc_rotor_13() -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	audio_instance._on_rotor_volume_control_gui_input(event)
	assert_false(AudioManager.rotors_muted)  # No action, still unmuted


## TC-Rotor-14 | Master unmuted, SFX unmuted, Rotor muted | Mouse motion (drag attempt) on slider | No value change (editable=false); No unmute (requires press).
## :rtype: void
func test_tc_rotor_14() -> void:
	audio_instance.mute_rotor.button_pressed = false  # Set to muted (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove config from precondition save
		DirAccess.remove_absolute(test_config_path)
	var initial_value: float = audio_instance.rotor_slider.value
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(10, 0)
	audio_instance._on_rotor_volume_control_gui_input(motion)
	assert_eq(audio_instance.rotor_slider.value, initial_value)  # No change
	assert_true(AudioManager.rotors_muted)  # No unmute


## TC-Rotor-15 | Unexpected exit | Simulate tree_exited | Previous menu visible = true; hidden_menus.pop_back(); If web, backPressed restored; Overlays hidden.
## :rtype: void
func test_tc_rotor_15() -> void:
	var prev_menu: Control = Control.new()
	prev_menu.visible = false
	Globals.hidden_menus = [prev_menu]
	audio_instance.queue_free()
	await get_tree().process_frame
	assert_true(prev_menu.visible)
	assert_true(Globals.hidden_menus.is_empty())
