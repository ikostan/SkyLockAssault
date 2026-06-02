## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_volume_slider.gd
## Unit tests for volume_slider.gd.
##
## Covers initialization, value changes, and debounce.
##
## Uses GdUnitTestSuite for assertions.

extends GdUnitTestSuite

var slider: VolumeSlider

# Explicitly preload the script to bypass GdUnit4's class_name registry bugs
const VolumeSliderScript = preload("res://scripts/ui/components/volume_slider.gd")

func before_test() -> void:
	# 1. Reset state BEFORE triggering _ready()
	AudioManager.master_volume = 1.0
	AudioManager.apply_all_volumes() # Ensure AudioServer matches the manager
	
	# 2. Instantiate safely using the preloaded script resource
	slider = auto_free(VolumeSliderScript.new())
	
	# Use the constant instead of a hardcoded string to prevent typos
	slider.bus_name = AudioConstants.BUS_MASTER
	
	# FIX: Replicate the Inspector settings to prevent float snapping!
	slider.max_value = 1.0
	slider.step = 0.001
	
	add_child(slider)  # Trigger _ready


func after_test() -> void:
	AudioManager.master_volume = 1.0
	AudioManager.apply_all_volumes()


func test_ready_sets_value_and_timer() -> void:
	assert_int(slider.bus_index).is_equal(AudioServer.get_bus_index(AudioConstants.BUS_MASTER))
	assert_float(slider.value).is_equal(db_to_linear(AudioServer.get_bus_volume_db(slider.bus_index)))
	assert_bool(slider.value_changed.is_connected(slider._on_value_changed)).is_true()
	assert_object(slider.save_debounce_timer).is_not_null()
	assert_float(slider.save_debounce_timer.wait_time).is_equal(0.5)
	assert_bool(slider.save_debounce_timer.one_shot).is_true()


func test_value_changed_updates_volume_and_starts_timer() -> void:
	var test_value: float = 0.5
	slider._on_value_changed(test_value)
	
	assert_float(AudioServer.get_bus_volume_db(slider.bus_index)).is_equal_approx(linear_to_db(test_value), 0.0001)
	assert_float(AudioManager.master_volume).is_equal(test_value)
	
	# Cleaner assertion for the timer state
	assert_bool(slider.save_debounce_timer.is_stopped()).is_false()
