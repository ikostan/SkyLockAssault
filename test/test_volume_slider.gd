## test_volume_slider.gd
## Unit tests for volume_slider.gd.
##
## Covers initialization, value changes, and debounce.
##
## Uses GdUnitTestSuite for assertions.

extends GdUnitTestSuite

var slider: VolumeSlider

func before_test() -> void:
	## Per-test setup: Instantiate slider, reset state.
	##
	## :rtype: void
	slider = auto_free(VolumeSlider.new())
	slider.bus_name = "Master"  # Test with Master
	add_child(slider)  # Trigger _ready
	AudioManager.master_volume = 1.0  # Reset for consistent test


func after_test() -> void:
	## Cleanup: Reset volume to avoid pollution.
	##
	## :rtype: void
	AudioManager.master_volume = 1.0


func test_ready_sets_value_and_timer() -> void:
	## Tests _ready gets index, sets value, connects, creates timer.
	##
	## :rtype: void
	assert_int(slider.bus_index).is_equal(AudioServer.get_bus_index("Master"))
	assert_float(slider.value).is_equal(db_to_linear(AudioServer.get_bus_volume_db(slider.bus_index)))
	assert_bool(slider.value_changed.is_connected(slider._on_value_changed)).is_true()
	assert_object(slider.save_debounce_timer).is_not_null()
	assert_float(slider.save_debounce_timer.wait_time).is_equal(0.5)
	assert_bool(slider.save_debounce_timer.one_shot).is_true()


func test_value_changed_updates_volume_and_starts_timer() -> void:
	## Tests value change sets db, updates manager, starts timer.
	##
	## :rtype: void
	var test_value: float = 0.5
	slider._on_value_changed(test_value)
	
	assert_float(AudioServer.get_bus_volume_db(slider.bus_index)).is_equal_approx(linear_to_db(test_value), 0.0001)
	assert_float(AudioManager.master_volume).is_equal(test_value)
	assert_bool(not slider.save_debounce_timer.is_stopped()).is_true()  # Started


func test_debounce_timeout_saves() -> void:
	## Tests timeout calls save, logs.
	##
	## :rtype: void
	var original_globals: Node = get_tree().root.get_node("Globals")
	assert_object(original_globals).is_not_null()  # Safety check

	# Load the script, create a new instance, THEN spy on the instance (fixes GdUnit4 spy error)
	var globals_script: Resource = load("res://scripts/globals.gd")
	var globals_instance: Node = globals_script.new()
	var spied_globals: Node = spy(globals_instance)

	# Copy relevant state to avoid side effects or inconsistencies during spy execution
	spied_globals.current_log_level = original_globals.current_log_level
	spied_globals.difficulty = original_globals.difficulty

	# Temporarily replace the autoload with the spy
	get_tree().root.remove_child(original_globals)
	spied_globals.name = "Globals"
	get_tree().root.add_child(spied_globals)

	# Perform the call
	slider._on_debounce_timeout()

	# Verify interactions
	verify(spied_globals, 1)._save_settings()
	verify(spied_globals, 1).log_message("Debounced settings save triggered.", Globals.LogLevel.DEBUG)

	# Restore original autoload
	get_tree().root.remove_child(spied_globals)
	original_globals.name = "Globals"
	get_tree().root.add_child(original_globals)
	
	# Cleanup the spied instance to avoid memory leaks (good practice in tests)
	globals_instance.free()
