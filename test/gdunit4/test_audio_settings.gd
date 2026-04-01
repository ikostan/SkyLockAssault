## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_audio_settings.gd
## Unit tests for audio_settings.gd functionality.
##
## Covers UI initialization, back handling, and unexpected exits.
## Web integration tests have been migrated to the AudioWebBridge suite.
extends GdUnitTestSuite

var audio_menu: Control


func before_test() -> void:
	Globals.hidden_menus = []
	# Reset AudioManager to a known clean state before each test
	AudioManager._init_to_defaults()
	AudioManager.apply_all_volumes()

func after_test() -> void:
	if is_instance_valid(audio_menu):
		audio_menu.queue_free()
	Globals.hidden_menus = []
	# Clean up any stray states
	AudioManager._init_to_defaults()


func test_ui_sync_on_ready() -> void:
	## Verifies that the UI grabs the correct initial state from AudioManager.
	# Set a specific state in the manager before instancing the UI
	AudioManager.master_muted = true
	AudioManager.master_volume = 0.75
	
	audio_menu = auto_free(load("res://scenes/audio_settings.tscn").instantiate())
	add_child(audio_menu)
	
	# UI mute buttons act as "Unmuted" toggles in the visual logic 
	# (button_pressed = true means sound is ON).
	# So if muted is true, pressed is false.
	assert_bool(audio_menu.mute_master.button_pressed).is_false()
	assert_float(audio_menu.master_slider.value).is_equal(0.75)


func test_back_button_pops_and_frees() -> void:
	## Verifies intentional back navigation restores the previous menu.
	
	# Create mock manually so GdUnit4's auto_free doesn't destroy it before audio_menu's tree_exited fires
	var mock_prev: Control = Control.new()
	add_child(mock_prev)
	mock_prev.visible = false
	Globals.hidden_menus.push_back(mock_prev)
	
	audio_menu = auto_free(load("res://scenes/audio_settings.tscn").instantiate())
	add_child(audio_menu)
	
	# Simulate player clicking "Back" using the unified function
	audio_menu._on_back_button_pressed()
	await get_tree().process_frame
	
	# Assert previous menu is restored
	assert_bool(Globals.hidden_menus.is_empty()).is_true()
	assert_bool(mock_prev.visible).is_true()
	
	# Clean up manual mock
	mock_prev.queue_free()


func test_tree_exited_restores_if_stuck() -> void:
	## Verifies that an unexpected queue_free still restores the previous menu.
	var mock_prev: Control = Control.new()
	add_child(mock_prev)
	mock_prev.visible = false
	Globals.hidden_menus.push_back(mock_prev)
	
	audio_menu = auto_free(load("res://scenes/audio_settings.tscn").instantiate())
	add_child(audio_menu)
	
	# Simulate an unexpected free (e.g., scene change or crash)
	audio_menu.queue_free()
	await get_tree().process_frame
	
	# Assert safety net caught the exit
	assert_bool(Globals.hidden_menus.is_empty()).is_true()
	assert_bool(mock_prev.visible).is_true()
	
	mock_prev.queue_free()


func test_double_pop_prevented() -> void:
	## Verifies that clicking Back doesn't trigger the tree_exited safety net twice.
	var mock_prev: Control = Control.new()
	add_child(mock_prev)
	mock_prev.visible = false
	Globals.hidden_menus.push_back(mock_prev)
	
	# Add a second menu to the stack to ensure we don't accidentally pop it
	var mock_prev_2: Control = Control.new()
	add_child(mock_prev_2)
	mock_prev_2.visible = false
	Globals.hidden_menus.push_back(mock_prev_2)
	
	audio_menu = auto_free(load("res://scenes/audio_settings.tscn").instantiate())
	add_child(audio_menu)
	
	# Trigger intentional exit using unified function
	audio_menu._on_back_button_pressed()
	
	# Manually trigger tree_exited to simulate the node dying right after
	audio_menu._on_tree_exited() 
	
	# Assert exactly ONE pop occurred (stack length goes from 2 down to 1)
	assert_int(Globals.hidden_menus.size()).is_equal(1)
	assert_bool(mock_prev_2.visible).is_true()
	
	mock_prev.queue_free()
	mock_prev_2.queue_free()
