## test_audio_music.gd
## GUT unit tests for audio_settings.gd Music functionality.
## Unit tests for audio_settings.gd Music functionality.
## Covers TC-Music-01 to TC-Music-15 from test plan.
## Test Plan:
## https://github.com/ikostan/SkyLockAssault/issues/303

extends "res://addons/gut/test.gd"

var audio_scene: PackedScene = load("res://scenes/audio_settings.tscn")
var audio_instance: Control
var test_config_path: String = "user://test_music.cfg"

func before_each() -> void:
	# Per-test setup: Instantiate audio scene, reset state
	audio_instance = audio_scene.instantiate()
	add_child_autofree(audio_instance)
	AudioManager.master_muted = false
	AudioManager.music_muted = false
	AudioManager.load_volumes(test_config_path)  # Load if exists

func after_each() -> void:
	# Per-test cleanup: Remove test config if exists
	if FileAccess.file_exists(test_config_path):
		DirAccess.remove_absolute(test_config_path)

func test_tc_music_01() -> void:
	# TC-Music-01 | Master unmuted, Music unmuted, Slider editable | Click and drag Music slider to new value | Slider value changes; AudioServer bus volume updates; AudioManager.music_volume updates; save_debounce_timer starts; After debounce, AudioManager.save_volumes() called; Log messages for volume change.
	var new_value: float = 0.5
	audio_instance.music_slider.value = new_value  # Simulate drag
	assert_eq(audio_instance.music_slider.value, new_value)
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), linear_to_db(new_value), 0.0001)  # Fixed: use almost eq for floats
	assert_eq(AudioManager.music_volume, new_value)
	assert_false(audio_instance.music_slider.save_debounce_timer.is_stopped())
	await get_tree().create_timer(0.6).timeout  # Await debounce
	# Assert save_volumes called - spy if needed
	# Log messages - spy if needed

func test_tc_music_02() -> void:
	# TC-Music-02 | Master unmuted, Music unmuted, Slider editable | Toggle Music mute button (to muted) | mute_music.button_pressed = false; AudioManager.music_muted = true; music_slider.editable = false; AudioServer.set_bus_mute("Music", true); AudioManager.save_volumes() called; Log "Music mute button toggled to: false".
	audio_instance._on_music_mute_toggled(false)  # Simulate toggle to muted (call handler directly)
	assert_false(audio_instance.mute_music.button_pressed)
	assert_true(AudioManager.music_muted)
	assert_false(audio_instance.music_slider.editable)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")))
	# Assert save_volumes called
	# Assert log message

func test_tc_music_03() -> void:
	# TC-Music-03 | Master unmuted, Music muted, Slider disabled | Toggle Music mute button (to unmuted) | mute_music.button_pressed = true; AudioManager.music_muted = false; music_slider.editable = true; AudioServer.set_bus_mute("Music", false); AudioManager.save_volumes() called; Log "Music mute button toggled to: true".
	AudioManager.music_muted = true
	audio_instance._on_music_mute_toggled(true)  # Simulate toggle to unmuted
	assert_true(audio_instance.mute_music.button_pressed)
	assert_false(AudioManager.music_muted)
	assert_true(audio_instance.music_slider.editable)
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")))
	# Assert save_volumes called
	# Assert log message

func test_tc_music_04() -> void:
	# TC-Music-04 | Master unmuted, Music muted, Slider disabled | Click Music slider | _on_music_mute_toggled(true) called; mute_music.button_pressed = true; AudioManager.music_muted = false; music_slider.editable = true; Event not consumed (allows future drag); No warning dialog; Log "Music mute button toggled to: true".
	AudioManager.music_muted = true
	var event: = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	audio_instance._on_music_volume_control_gui_input(event)  # Call handler directly (since gui_input is signal handler)
	assert_true(audio_instance.mute_music.button_pressed)
	assert_false(AudioManager.music_muted)
	assert_true(audio_instance.music_slider.editable)
	# Assert no warning dialog
	# Assert log message

func test_tc_music_05() -> void:
	# TC-Music-05 | Master unmuted, Music unmuted, Slider editable | Click Music mute button (but since unmuted, no change needed) | No state change (button already pressed); No save/apply; Event may propagate if not consumed.
	var event: = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	audio_instance._on_music_mute_gui_input(event)  # Call handler directly
	assert_true(audio_instance.mute_music.button_pressed)  # No change
	assert_false(AudioManager.music_muted)  # No change
	# Assert no save/apply

func test_tc_music_06() -> void:
	# TC-Music-06 | Master muted, Music unmuted, Slider disabled (due to master) | Click Music slider | master_warning_dialog.popup_centered(); Event consumed; No unmute; Slider remains disabled; No save/apply.
	AudioManager.master_muted = true
	var event: = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	audio_instance._on_music_volume_control_gui_input(event)
	# Assert master_warning_dialog.popup_centered called (spy if needed)
	# Assert event consumed (spy on viewport)
	assert_true(AudioManager.music_muted)  # No unmute
	assert_false(audio_instance.music_slider.editable)  # Disabled
	# Assert no save/apply

func test_tc_music_07() -> void:
	# TC-Music-07 | Master muted, Music unmuted, Mute button disabled | Click Music mute button | master_warning_dialog.popup_centered(); Event consumed; No toggle; Mute button remains disabled; No save/apply.
	AudioManager.master_muted = true
	var event: = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	audio_instance._on_music_mute_gui_input(event)
	# Assert master_warning_dialog.popup_centered called
	# Assert event consumed
	assert_true(audio_instance.mute_music.disabled)  # Remains disabled
	# No toggle
	# No save/apply

func test_tc_music_08() -> void:
	# TC-Music-08 | Master muted, Music muted, Slider disabled | Click Music slider | master_warning_dialog.popup_centered(); Event consumed; No unmute; Slider remains disabled.
	AudioManager.master_muted = true
	AudioManager.music_muted = true
	var event: = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	audio_instance._on_music_volume_control_gui_input(event)
	# Assert master_warning_dialog.popup_centered called
	# Assert event consumed
	assert_true(AudioManager.music_muted)  # No unmute
	assert_false(audio_instance.music_slider.editable)  # Disabled

func test_tc_music_09() -> void:
	# TC-Music-09 | Master muted, Music muted, Mute button disabled | Click Music mute button | master_warning_dialog.popup_centered(); Event consumed; No toggle.
	AudioManager.master_muted = true
	AudioManager.music_muted = true
	var event: = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	audio_instance._on_music_mute_gui_input(event)
	# Assert master_warning_dialog.popup_centered called
	# Assert event consumed
	# No toggle

func test_tc_music_10() -> void:
	# TC-Music-10 | Master unmuted (after muted), Music muted | Master toggle to unmuted | _update_other_controls_ui() called; mute_music.disabled = false; music_slider.editable = false (still muted); No auto-unmute of Music.
	AudioManager.master_muted = true
	AudioManager.music_muted = true
	audio_instance._on_master_mute_toggled(true)  # To unmuted
	assert_false(audio_instance.mute_music.disabled)
	assert_false(audio_instance.music_slider.editable)  # Still muted
	assert_true(AudioManager.music_muted)  # No auto-unmute

func test_tc_music_11() -> void:
	# TC-Music-11 | Initial load from config: Music muted | Scene _ready() | mute_music.button_pressed = false; music_slider.editable = false; AudioServer muted; Log messages from load_volumes().
	var config: = ConfigFile.new()
	config.set_value("audio", "music_muted", true)
	config.save(test_config_path)
	AudioManager.load_volumes(test_config_path)
	audio_instance = audio_scene.instantiate()
	add_child_autofree(audio_instance)
	assert_false(audio_instance.mute_music.button_pressed)
	assert_false(audio_instance.music_slider.editable)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")))
	# Assert log messages from load_volumes

func test_tc_music_12() -> void:
	# TC-Music-12 | Initial load from config: Music unmuted | Scene _ready() | mute_music.button_pressed = true; music_slider.editable = true; AudioServer unmuted.
	var config: = ConfigFile.new()
	config.set_value("audio", "music_muted", false)
	config.save(test_config_path)
	AudioManager.load_volumes(test_config_path)
	audio_instance = audio_scene.instantiate()
	add_child_autofree(audio_instance)
	assert_true(audio_instance.mute_music.button_pressed)
	assert_true(audio_instance.music_slider.editable)
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")))

func test_tc_music_13() -> void:
	# TC-Music-13 | Master unmuted, Music unmuted | Non-left click on slider (e.g., right-click) | No action; Event not handled/consumed.
	var event: = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	audio_instance._on_music_volume_control_gui_input(event)
	# Assert no action (e.g., no unmute, no dialog)
	# Assert not consumed

func test_tc_music_14() -> void:
	# TC-Music-14 | Master unmuted, Music muted | Mouse motion (drag attempt) on slider | No value change (editable=false); No unmute (requires press).
	AudioManager.music_muted = true
	var motion: = InputEventMouseMotion.new()
	motion.relative = Vector2(10, 0)
	audio_instance._on_music_volume_control_gui_input(motion)
	assert_eq(audio_instance.music_slider.value, db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))))  # No change
	assert_true(AudioManager.music_muted)  # No unmute

func test_tc_music_15() -> void:
	# TC-Music-15 | Unexpected exit (queue_free without back press) | Simulate tree_exited | Previous menu (e.g., options) visible = true; hidden_menus.pop_back(); If web, backPressed restored; Overlays hidden.
	var prev_menu: = Control.new()
	prev_menu.visible = false
	Globals.hidden_menus = [prev_menu]
	audio_instance.queue_free()
	await get_tree().process_frame
	assert_true(prev_menu.visible)
	assert_true(Globals.hidden_menus.is_empty())
	# If web: Assert backPressed restored, overlays hidden (mock if needed)
