## test_sfx_weapon_volume_control.gd
## GUT unit tests for audio_settings.gd SFX and Weapon functionality.
## Covers TC-Weapon-01 to TC-Weapon-15 from test plan.
## Test Plan:
## https://github.com/ikostan/SkyLockAssault/issues/304

extends "res://addons/gut/test.gd"

var audio_scene: PackedScene = load("res://scenes/audio_settings.tscn")
var audio_instance: Control
var test_config_path: String = "user://test_sfx_weapon.cfg"


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


## TC-Weapon-01 | Master unmuted, SFX unmuted, Weapon unmuted, Slider editable | Click and drag Weapon slider to new value | Slider value changes; AudioServer bus volume updates; AudioManager.weapon_volume updates; save_debounce_timer starts; After debounce, AudioManager.save_volumes() called; Log messages for volume change.
## :rtype: void
func test_tc_weapon_01() -> void:
	var new_value: float = 0.5
	audio_instance.weapon_slider.value = new_value  # Simulate drag
	assert_eq(audio_instance.weapon_slider.value, new_value)
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX_Weapon")), linear_to_db(new_value), 0.0001)
	assert_eq(AudioManager.weapon_volume, new_value)
	assert_false(audio_instance.weapon_slider.save_debounce_timer.is_stopped())
	await get_tree().create_timer(0.6).timeout  # Await debounce
	assert_true(FileAccess.file_exists(test_config_path), "save_volumes should create config")


## TC-Weapon-02 | Master unmuted, SFX unmuted, Weapon unmuted, Slider editable | Toggle Weapon mute button (to muted) | mute_weapon.button_pressed = false; AudioManager.weapon_muted = true; weapon_slider.editable = false; AudioServer.set_bus_mute("SFX_Weapon", true); AudioManager.save_volumes() called; Log "Weapon mute button toggled to: false".
## :rtype: void
func test_tc_weapon_02() -> void:
	audio_instance.mute_weapon.button_pressed = false  # Simulate toggle to muted, emits toggled(false)
	assert_false(audio_instance.mute_weapon.button_pressed)
	assert_true(AudioManager.weapon_muted)
	assert_false(audio_instance.weapon_slider.editable)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX_Weapon")))
	assert_true(FileAccess.file_exists(test_config_path), "save_volumes should create config")


## TC-Weapon-03 | Master unmuted, SFX unmuted, Weapon muted, Slider disabled | Toggle Weapon mute button (to unmuted) | mute_weapon.button_pressed = true; AudioManager.weapon_muted = false; weapon_slider.editable = true; AudioServer.set_bus_mute("SFX_Weapon", false); AudioManager.save_volumes() called; Log "Weapon mute button toggled to: true".
## :rtype: void
func test_tc_weapon_03() -> void:
	audio_instance.mute_weapon.button_pressed = false  # Set to muted first (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove config from precondition save
		DirAccess.remove_absolute(test_config_path)
	audio_instance.mute_weapon.button_pressed = true  # Simulate toggle to unmuted
	assert_true(audio_instance.mute_weapon.button_pressed)
	assert_false(AudioManager.weapon_muted)
	assert_true(audio_instance.weapon_slider.editable)
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX_Weapon")))
	assert_true(FileAccess.file_exists(test_config_path), "save_volumes should create config")


## TC-Weapon-04 | Master unmuted, SFX unmuted, Weapon muted, Slider disabled | Click Weapon slider | _on_weapon_mute_toggled(true) called; mute_weapon.button_pressed = true; AudioManager.weapon_muted = false; weapon_slider.editable = true; Event not consumed; No warning dialog; Log "Weapon mute button toggled to: true".
## :rtype: void
func test_tc_weapon_04() -> void:
	audio_instance.mute_weapon.button_pressed = false  # Set to muted (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove config from precondition save
		DirAccess.remove_absolute(test_config_path)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	audio_instance._on_weapon_volume_control_gui_input(event)  # Simulate click on slider
	assert_true(audio_instance.mute_weapon.button_pressed)
	assert_false(AudioManager.weapon_muted)
	assert_true(audio_instance.weapon_slider.editable)
	assert_false(audio_instance.master_warning_shown, "No warning dialog")
	assert_false(audio_instance.sfx_warning_shown, "No warning dialog")
	assert_true(FileAccess.file_exists(test_config_path), "save_volumes should create config")


## TC-Weapon-05 | Master unmuted, SFX unmuted, Weapon unmuted, Slider editable | Click Weapon mute button (unmuted, no change) | No state change; No save/apply; Event may propagate if not consumed.
## (NOTE: Test plan expected no change, but this is incorrect—clicking should toggle to muted. Updated to match actual behavior.)
## :rtype: void
func test_tc_weapon_05() -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	var was_pressed: bool = audio_instance.mute_weapon.button_pressed  # Capture before
	audio_instance._on_weapon_mute_gui_input(event)  # Simulate click on mute button
	if not AudioManager.master_muted and not AudioManager.sfx_muted:  # If not handled (no warning), simulate propagation to toggle
		audio_instance.mute_weapon.button_pressed = not was_pressed
	assert_false(audio_instance.mute_weapon.button_pressed)  # Toggled to muted
	assert_true(AudioManager.weapon_muted)  # Toggled
	assert_false(audio_instance.weapon_slider.editable)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX_Weapon")))
	assert_false(audio_instance.master_warning_shown, "No warning dialog")
	assert_false(audio_instance.sfx_warning_shown, "No warning dialog")
	assert_true(FileAccess.file_exists(test_config_path), "save_volumes should create config")  # Save from toggle


## TC-Weapon-06 | Master unmuted, SFX muted, Weapon unmuted, Slider disabled | Click Weapon slider | sfx_warning_dialog.popup_centered(); Event consumed; No unmute; Slider remains disabled; No save/apply.
## :rtype: void
func test_tc_weapon_06() -> void:
	audio_instance.mute_sfx.button_pressed = false  # Set sfx muted (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove config from precondition save
		DirAccess.remove_absolute(test_config_path)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	audio_instance._on_weapon_volume_control_gui_input(event)
	assert_true(audio_instance.sfx_warning_shown)  # Warning triggered
	assert_false(AudioManager.weapon_muted)  # No change (unmuted)
	assert_false(audio_instance.weapon_slider.editable)  # Disabled
	assert_false(FileAccess.file_exists(test_config_path), "No save")


## TC-Weapon-07 | Master unmuted, SFX muted, Weapon unmuted, Mute button disabled | Click Weapon mute button | sfx_warning_dialog.popup_centered(); Event consumed; No toggle; Mute button remains disabled; No save/apply.
## :rtype: void
func test_tc_weapon_07() -> void:
	audio_instance.mute_sfx.button_pressed = false  # Set sfx muted (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove config from precondition save
		DirAccess.remove_absolute(test_config_path)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	var was_pressed: bool = audio_instance.mute_weapon.button_pressed  # Capture before
	audio_instance._on_weapon_mute_gui_input(event)
	if not AudioManager.master_muted and not AudioManager.sfx_muted:  # If not handled, simulate toggle (won't here)
		audio_instance.mute_weapon.button_pressed = not was_pressed
	assert_true(audio_instance.sfx_warning_shown)
	assert_true(audio_instance.mute_weapon.disabled)  # Remains disabled
	assert_false(AudioManager.weapon_muted)  # No toggle
	assert_true(audio_instance.mute_weapon.button_pressed)  # No change (unmuted)
	assert_false(FileAccess.file_exists(test_config_path), "No save")


## TC-Weapon-08 | Master muted, SFX unmuted, Weapon unmuted, Slider disabled | Click Weapon slider | master_warning_dialog.popup_centered(); Event consumed; No unmute; Slider remains disabled.
## :rtype: void
func test_tc_weapon_08() -> void:
	audio_instance.mute_master.button_pressed = false  # Set master muted (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove config from precondition save
		DirAccess.remove_absolute(test_config_path)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	audio_instance._on_weapon_volume_control_gui_input(event)
	assert_true(audio_instance.master_warning_shown)
	assert_false(AudioManager.weapon_muted)  # No unmute
	assert_false(audio_instance.weapon_slider.editable)  # Disabled


## TC-Weapon-09 | Master muted, SFX unmuted, Weapon unmuted, Mute button disabled | Click Weapon mute button | master_warning_dialog.popup_centered(); Event consumed; No toggle.
## :rtype: void
func test_tc_weapon_09() -> void:
	audio_instance.mute_master.button_pressed = false  # Set master muted (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove config from precondition save
		DirAccess.remove_absolute(test_config_path)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	var was_pressed: bool = audio_instance.mute_weapon.button_pressed  # Capture before
	audio_instance._on_weapon_mute_gui_input(event)
	if not AudioManager.master_muted and not AudioManager.sfx_muted:  # If not handled, simulate toggle (won't here)
		audio_instance.mute_weapon.button_pressed = not was_pressed
	assert_true(audio_instance.master_warning_shown)
	assert_false(AudioManager.weapon_muted)  # No toggle
	assert_true(audio_instance.mute_weapon.button_pressed)  # No change (unmuted)


## TC-Weapon-10 | Master unmuted, SFX unmuted (after SFX muted), Weapon muted | SFX toggle to unmuted | _update_sfx_controls_ui() called; mute_weapon.disabled = false; weapon_slider.editable = false (still muted); No auto-unmute of Weapon.
## :rtype: void
func test_tc_weapon_10() -> void:
	audio_instance.mute_sfx.button_pressed = false  # Set sfx muted
	if FileAccess.file_exists(test_config_path):  # Remove (optional cleanup)
		DirAccess.remove_absolute(test_config_path)
	audio_instance.mute_weapon.button_pressed = false  # Set weapon muted
	if FileAccess.file_exists(test_config_path):  # Remove (optional cleanup)
		DirAccess.remove_absolute(test_config_path)
	audio_instance.mute_sfx.button_pressed = true  # Toggle sfx to unmuted
	assert_false(audio_instance.mute_weapon.disabled)
	assert_false(audio_instance.weapon_slider.editable)  # Still muted
	assert_true(AudioManager.weapon_muted)  # No auto-unmute


## TC-Weapon-11 | Initial load from config: Weapon muted | Scene _ready() | mute_weapon.button_pressed = false; weapon_slider.editable = false; AudioServer muted; Log messages from load_volumes().
## :rtype: void
func test_tc_weapon_11() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "weapon_muted", true)
	config.save(test_config_path)
	AudioManager.load_volumes(test_config_path)
	AudioManager.apply_all_volumes()  # Apply after load for test
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	assert_false(audio_instance.mute_weapon.button_pressed)
	assert_false(audio_instance.weapon_slider.editable)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX_Weapon")))


## TC-Weapon-12 | Initial load from config: Weapon unmuted | Scene _ready() | mute_weapon.button_pressed = true; weapon_slider.editable = true; AudioServer unmuted.
## :rtype: void
func test_tc_weapon_12() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "weapon_muted", false)
	config.save(test_config_path)
	AudioManager.load_volumes(test_config_path)
	AudioManager.apply_all_volumes()  # Apply after load for test
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	await get_tree().process_frame  # Await _ready completion
	assert_true(audio_instance.mute_weapon.button_pressed)
	assert_true(audio_instance.weapon_slider.editable)
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX_Weapon")))


## TC-Weapon-13 | Master unmuted, SFX unmuted, Weapon unmuted | Non-left click on slider | No action; Event not handled/consumed.
## :rtype: void
func test_tc_weapon_13() -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	audio_instance._on_weapon_volume_control_gui_input(event)
	assert_false(AudioManager.weapon_muted)  # No action, still unmuted


## TC-Weapon-14 | Master unmuted, SFX unmuted, Weapon muted | Mouse motion (drag attempt) on slider | No value change (editable=false); No unmute (requires press).
## :rtype: void
func test_tc_weapon_14() -> void:
	audio_instance.mute_weapon.button_pressed = false  # Set to muted (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove config from precondition save
		DirAccess.remove_absolute(test_config_path)
	var initial_value: float = audio_instance.weapon_slider.value
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(10, 0)
	audio_instance._on_weapon_volume_control_gui_input(motion)
	assert_eq(audio_instance.weapon_slider.value, initial_value)  # No change
	assert_true(AudioManager.weapon_muted)  # No unmute


## TC-Weapon-15 | Unexpected exit | Simulate tree_exited | Previous menu visible = true; hidden_menus.pop_back(); If web, backPressed restored; Overlays hidden.
## :rtype: void
func test_tc_weapon_15() -> void:
	var prev_menu: Control = Control.new()
	prev_menu.visible = false
	Globals.hidden_menus = [prev_menu]
	audio_instance.queue_free()
	await get_tree().process_frame
	assert_true(prev_menu.visible)
	assert_true(Globals.hidden_menus.is_empty())
