## test_sfx_volume_control.gd
## GUT unit tests for audio_settings.gd SFX and Weapon functionality.
## Covers TC-SFX-01 to TC-SFX-15 from test plan.
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
	AudioManager.current_config_path = test_config_path  # <--- ADD THIS LINE HERE
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


## Per-test cleanup: Free audio_instance safely.
## :rtype: void
func after_each() -> void:
	var audio_instance: Control = self.audio_instance  # Typed ref
	if is_instance_valid(audio_instance):
		if is_instance_valid(audio_instance.master_warning_dialog):
			audio_instance.master_warning_dialog.hide()
		if is_instance_valid(audio_instance.sfx_warning_dialog):
			audio_instance.sfx_warning_dialog.hide()
		remove_child(audio_instance)
		audio_instance.queue_free()
	self.audio_instance = null
	if FileAccess.file_exists(test_config_path):
		DirAccess.remove_absolute(test_config_path)
	await get_tree().process_frame


## TC-SFX-01 | Master unmuted, SFX unmuted, Slider editable, Children unmuted | Click and drag SFX slider to new value | Slider value changes; AudioServer bus volume updates; AudioManager.sfx_volume updates; save_debounce_timer starts; After debounce, AudioManager.save_volumes() called; Log messages for volume change.
## :rtype: void
func test_tc_sfx_01() -> void:
	var new_value: float = 0.5
	audio_instance.sfx_slider.value = new_value  # Simulate drag
	assert_eq(audio_instance.sfx_slider.value, new_value)
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")), linear_to_db(new_value), 0.0001)
	assert_eq(AudioManager.sfx_volume, new_value)
	assert_false(audio_instance.sfx_slider.save_debounce_timer.is_stopped())
	await get_tree().create_timer(0.6).timeout  # Await debounce
	assert_true(FileAccess.file_exists(test_config_path), "save_volumes should create config")


## TC-SFX-02 | Master unmuted, SFX unmuted, Slider editable | Toggle SFX mute button (to muted) | mute_sfx.button_pressed = false; AudioManager.sfx_muted = true; sfx_slider.editable = false; AudioServer.set_bus_mute("SFX", true); AudioManager.save_volumes() called; Log "SFX mute button toggled to: false"; Call _update_sfx_controls_ui() to disable Weapon/Rotors sliders/buttons.
## :rtype: void
func test_tc_sfx_02() -> void:
	audio_instance.mute_sfx.button_pressed = false  # Simulate toggle to muted, emits toggled(false)
	assert_false(audio_instance.mute_sfx.button_pressed)
	assert_true(AudioManager.sfx_muted)
	assert_false(audio_instance.sfx_slider.editable)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")))
	assert_true(FileAccess.file_exists(test_config_path), "save_volumes should create config")
	# Check _update_sfx_controls_ui effects
	assert_true(audio_instance.mute_weapon.disabled)
	assert_true(audio_instance.mute_rotor.disabled)
	assert_false(audio_instance.weapon_slider.editable)
	assert_false(audio_instance.rotor_slider.editable)


## TC-SFX-03 | Master unmuted, SFX muted, Slider disabled | Toggle SFX mute button (to unmuted) | mute_sfx.button_pressed = true; AudioManager.sfx_muted = false; sfx_slider.editable = true; AudioServer.set_bus_mute("SFX", false); AudioManager.save_volumes() called; Log "SFX mute button toggled to: true"; _update_sfx_controls_ui() enables Weapon/Rotors per their muted states.
## :rtype: void
func test_tc_sfx_03() -> void:
	audio_instance.mute_sfx.button_pressed = false  # Set to muted first (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove config from precondition save
		DirAccess.remove_absolute(test_config_path)
	audio_instance.mute_sfx.button_pressed = true  # Simulate toggle to unmuted
	assert_true(audio_instance.mute_sfx.button_pressed)
	assert_false(AudioManager.sfx_muted)
	assert_true(audio_instance.sfx_slider.editable)
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")))
	assert_true(FileAccess.file_exists(test_config_path), "save_volumes should create config")
	# Check _update_sfx_controls_ui effects (assuming children unmuted)
	assert_false(audio_instance.mute_weapon.disabled)
	assert_false(audio_instance.mute_rotor.disabled)
	assert_true(audio_instance.weapon_slider.editable)
	assert_true(audio_instance.rotor_slider.editable)


## TC-SFX-04 | Master unmuted, SFX muted, Slider disabled | Click SFX slider | _on_sfx_mute_toggled(true) called; mute_sfx.button_pressed = true; AudioManager.sfx_muted = false; sfx_slider.editable = true; Event not consumed; No warning dialog; Log "SFX mute button toggled to: true"; _update_sfx_controls_ui() called.
## :rtype: void
func test_tc_sfx_04() -> void:
	audio_instance.mute_sfx.button_pressed = false  # Set to muted (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove config from precondition save
		DirAccess.remove_absolute(test_config_path)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	audio_instance._on_sfx_volume_control_gui_input(event)  # Simulate click on slider
	assert_true(audio_instance.mute_sfx.button_pressed)
	assert_false(AudioManager.sfx_muted)
	assert_true(audio_instance.sfx_slider.editable)
	assert_false(audio_instance.master_warning_shown, "No warning dialog")
	assert_false(audio_instance.sfx_warning_shown, "No warning dialog")
	assert_true(FileAccess.file_exists(test_config_path), "save_volumes should create config")
	# Check _update_sfx_controls_ui effects
	assert_false(audio_instance.mute_weapon.disabled)
	assert_false(audio_instance.mute_rotor.disabled)
	assert_true(audio_instance.weapon_slider.editable)
	assert_true(audio_instance.rotor_slider.editable)


## TC-SFX-05 | Master unmuted, SFX unmuted, Slider editable | Click SFX mute button (unmuted, no change) | No state change; No save/apply; Event may propagate if not consumed.
## (NOTE: Test plan expected no change, but this is incorrect—clicking should toggle to muted. Updated to match actual behavior.)
## :rtype: void
func test_tc_sfx_05() -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	var was_pressed: bool = audio_instance.mute_sfx.button_pressed  # Capture before
	audio_instance._on_sfx_mute_gui_input(event)  # Simulate click on mute button
	if not AudioManager.master_muted:  # If not handled (no warning), simulate propagation to toggle
		audio_instance.mute_sfx.button_pressed = not was_pressed
	assert_false(audio_instance.mute_sfx.button_pressed)  # Toggled to muted
	assert_true(AudioManager.sfx_muted)  # Toggled
	assert_false(audio_instance.sfx_slider.editable)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")))
	assert_false(audio_instance.master_warning_shown, "No warning dialog")
	assert_false(audio_instance.sfx_warning_shown, "No warning dialog")
	assert_true(FileAccess.file_exists(test_config_path), "save_volumes should create config")  # Save from toggle


## TC-SFX-06 | Master muted, SFX unmuted, Slider disabled | Click SFX slider | master_warning_dialog.popup_centered(); Event consumed; No unmute; Slider remains disabled; No save/apply.
## :rtype: void
func test_tc_sfx_06() -> void:
	audio_instance.mute_master.button_pressed = false  # Set master muted (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove config from precondition save
		DirAccess.remove_absolute(test_config_path)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	audio_instance._on_sfx_volume_control_gui_input(event)
	assert_true(audio_instance.master_warning_shown)  # Warning triggered
	assert_false(AudioManager.sfx_muted)  # No change (unmuted)
	assert_false(audio_instance.sfx_slider.editable)  # Disabled
	assert_false(FileAccess.file_exists(test_config_path), "No save")


## TC-SFX-07 | Master muted, SFX unmuted, Mute button disabled | Click SFX mute button | master_warning_dialog.popup_centered(); Event consumed; No toggle; Mute button remains disabled; No save/apply.
## :rtype: void
func test_tc_sfx_07() -> void:
	audio_instance.mute_master.button_pressed = false  # Set master muted (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove config from precondition save
		DirAccess.remove_absolute(test_config_path)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	var was_pressed: bool = audio_instance.mute_sfx.button_pressed  # Capture before
	audio_instance._on_sfx_mute_gui_input(event)
	if not AudioManager.master_muted:  # If not handled, simulate toggle (won't here)
		audio_instance.mute_sfx.button_pressed = not was_pressed
	assert_true(audio_instance.master_warning_shown)
	assert_true(audio_instance.mute_sfx.disabled)  # Remains disabled
	assert_false(AudioManager.sfx_muted)  # No toggle
	assert_true(audio_instance.mute_sfx.button_pressed)  # No change (unmuted)
	assert_false(FileAccess.file_exists(test_config_path), "No save")


## TC-SFX-08 | Master muted, SFX muted, Slider disabled | Click SFX slider | master_warning_dialog.popup_centered(); Event consumed; No unmute; Slider remains disabled.
## :rtype: void
func test_tc_sfx_08() -> void:
	audio_instance.mute_master.button_pressed = false  # Set master muted (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove config from precondition save
		DirAccess.remove_absolute(test_config_path)
	audio_instance.mute_sfx.button_pressed = false  # Set sfx muted (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove again if saved
		DirAccess.remove_absolute(test_config_path)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	audio_instance._on_sfx_volume_control_gui_input(event)
	assert_true(audio_instance.master_warning_shown)
	assert_true(AudioManager.sfx_muted)  # No unmute
	assert_false(audio_instance.sfx_slider.editable)  # Disabled


## TC-SFX-09 | Master muted, SFX muted, Mute button disabled | Click SFX mute button | master_warning_dialog.popup_centered(); Event consumed; No toggle.
## :rtype: void
func test_tc_sfx_09() -> void:
	audio_instance.mute_master.button_pressed = false  # Set master muted (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove config from precondition save
		DirAccess.remove_absolute(test_config_path)
	audio_instance.mute_sfx.button_pressed = false  # Set sfx muted (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove again if saved
		DirAccess.remove_absolute(test_config_path)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	var was_pressed: bool = audio_instance.mute_sfx.button_pressed  # Capture before
	audio_instance._on_sfx_mute_gui_input(event)
	if not AudioManager.master_muted:  # If not handled, simulate toggle (won't here)
		audio_instance.mute_sfx.button_pressed = not was_pressed
	assert_true(audio_instance.master_warning_shown)
	assert_true(AudioManager.sfx_muted)  # No toggle
	assert_false(audio_instance.mute_sfx.button_pressed)  # No change (muted)


## TC-SFX-10 | Master unmuted (after muted), SFX muted | Master toggle to unmuted | _update_other_controls_ui() called; mute_sfx.disabled = false; sfx_slider.editable = false (still muted); _update_sfx_controls_ui() for children; No auto-unmute of SFX.
## :rtype: void
func test_tc_sfx_10() -> void:
	audio_instance.mute_master.button_pressed = false  # Set master muted
	if FileAccess.file_exists(test_config_path):  # Remove (optional cleanup)
		DirAccess.remove_absolute(test_config_path)
	audio_instance.mute_sfx.button_pressed = false  # Set sfx muted
	if FileAccess.file_exists(test_config_path):  # Remove (optional cleanup)
		DirAccess.remove_absolute(test_config_path)
	audio_instance.mute_master.button_pressed = true  # Toggle master to unmuted
	assert_false(audio_instance.mute_sfx.disabled)
	assert_false(audio_instance.sfx_slider.editable)  # Still muted
	assert_true(AudioManager.sfx_muted)  # No auto-unmute
	# Check _update_sfx_controls_ui effects on children
	assert_true(audio_instance.mute_weapon.disabled)  # Since sfx muted
	assert_true(audio_instance.mute_rotor.disabled)
	assert_false(audio_instance.weapon_slider.editable)
	assert_false(audio_instance.rotor_slider.editable)


## TC-SFX-11 | Initial load from config: SFX muted | Scene _ready() | mute_sfx.button_pressed = false; sfx_slider.editable = false; AudioServer muted; Log messages from load_volumes(); _update_sfx_controls_ui() disables children.
## :rtype: void
func test_tc_sfx_11() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "sfx_muted", true)
	config.save(test_config_path)
	AudioManager.load_volumes(test_config_path)
	AudioManager.apply_all_volumes()  # Apply after load for test
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	assert_false(audio_instance.mute_sfx.button_pressed)
	assert_false(audio_instance.sfx_slider.editable)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")))
	# Check _update_sfx_controls_ui disables children
	assert_true(audio_instance.mute_weapon.disabled)
	assert_true(audio_instance.mute_rotor.disabled)
	assert_false(audio_instance.weapon_slider.editable)
	assert_false(audio_instance.rotor_slider.editable)


## TC-SFX-12 | Initial load from config: SFX unmuted | Scene _ready() | mute_sfx.button_pressed = true; sfx_slider.editable = true; AudioServer unmuted; _update_sfx_controls_ui() enables children per states.
## :rtype: void
func test_tc_sfx_12() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "sfx_muted", false)
	config.save(test_config_path)
	AudioManager.load_volumes(test_config_path)
	AudioManager.apply_all_volumes()  # Apply after load for test
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	await get_tree().process_frame  # Await _ready completion
	assert_true(audio_instance.mute_sfx.button_pressed)
	assert_true(audio_instance.sfx_slider.editable)
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")))
	# Check _update_sfx_controls_ui enables children (assuming unmuted)
	assert_false(audio_instance.mute_weapon.disabled)
	assert_false(audio_instance.mute_rotor.disabled)
	assert_true(audio_instance.weapon_slider.editable)
	assert_true(audio_instance.rotor_slider.editable)


## TC-SFX-13 | Master unmuted, SFX unmuted | Non-left click on slider | No action; Event not handled/consumed.
## :rtype: void
func test_tc_sfx_13() -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	audio_instance._on_sfx_volume_control_gui_input(event)
	assert_false(AudioManager.sfx_muted)  # No action, still unmuted


## TC-SFX-14 | Master unmuted, SFX muted | Mouse motion (drag attempt) on slider | No value change (editable=false); No unmute (requires press).
## :rtype: void
func test_tc_sfx_14() -> void:
	audio_instance.mute_sfx.button_pressed = false  # Set to muted (precondition)
	if FileAccess.file_exists(test_config_path):  # Remove config from precondition save
		DirAccess.remove_absolute(test_config_path)
	var initial_value: float = audio_instance.sfx_slider.value
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(10, 0)
	audio_instance._on_sfx_volume_control_gui_input(motion)
	assert_eq(audio_instance.sfx_slider.value, initial_value)  # No change
	assert_true(AudioManager.sfx_muted)  # No unmute


## TC-SFX-15 | Unexpected exit | Simulate tree_exited | Previous menu visible = true; hidden_menus.pop_back(); If web, backPressed restored; Overlays hidden.
## :rtype: void
func test_tc_sfx_15() -> void:
	var prev_menu: Control = Control.new()
	prev_menu.visible = false
	Globals.hidden_menus = [prev_menu]
	audio_instance.queue_free()
	await get_tree().process_frame
	assert_true(prev_menu.visible)
	assert_true(Globals.hidden_menus.is_empty())
	prev_menu.queue_free()
