## test_volume_slider.gd
## Unit tests for volume_slider.gd.
##
## Covers initialization, value changes, and debounce.
##
## Uses GdUnitTestSuite for assertions.

extends GdUnitTestSuite

var slider: VolumeSlider
var mock_audio_manager: Node  # Mock for AudioManager
var mock_globals: Node  # Mock for Globals


func before_test() -> void:
	## Per-test setup: Instantiate slider, mock deps.
	##
	## :rtype: void
	slider = auto_free(VolumeSlider.new())
	slider.bus_name = "Master"  # Test with Master
	mock_audio_manager = auto_free(load("res://scripts/audio_manager.gd").new())
	mock_globals = auto_free(load("res://scripts/globals.gd").new())
	# Assume AudioServer mocked or use real for bus_index
	add_child(slider)  # Trigger _ready


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
	
	assert_float(AudioServer.get_bus_volume_db(slider.bus_index)).is_equal(linear_to_db(test_value))
	assert_float(mock_audio_manager.master_volume).is_equal(test_value)
	assert_bool(not slider.save_debounce_timer.is_stopped()).is_true()  # Started


# Better version for the test:
func test_debounce_timeout_saves() -> void:
	## Tests timeout calls save, logs.
	##
	## :rtype: void
	var spied_manager: Node = spy(mock_audio_manager)  # Spy the object
	var spied_globals: Node = spy(mock_globals)  # Spy for log

	slider._on_debounce_timeout()

	verify(spied_manager, 1)._save_volumes()  # Verify method called once
	verify(spied_globals, 1).log_message("Debounced audio settings save triggered.", mock_globals.LogLevel.DEBUG)
