## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_player_lifecycle.gd
## GUT unit tests for player node lifecycle, specifically _exit_tree cleanup.

extends "res://addons/gut/test.gd"

var main_scene: Node
var player_root: Node2D
var original_settings: GameSettingsResource

## Per-test setup: Isolate the environment.
## :rtype: void
func before_each() -> void:
	original_settings = Globals.settings
	Globals.settings = GameSettingsResource.new()

## Per-test cleanup: Restore global state and aggressively free the scene.
## :rtype: void
func after_each() -> void:
	Globals.settings = original_settings
	
	# CRITICAL FIX: Use a hard free() instead of queue_free() or GUT's autofree.
	# This instantly incinerates the scene, ensuring 0 lingering orphan nodes 
	# are left behind to pollute subsequent tests.
	if is_instance_valid(main_scene):
		main_scene.free()
		
	# Flush the frame just to be absolutely certain the tree is stable for the next test
	await get_tree().process_frame

## test_exit_tree_disconnects_signals |
## Lifecycle | Verify clean signal severing without breaking the SceneTree
## :rtype: void
func test_exit_tree_disconnects_signals() -> void:
	gut.p("Testing: Player _exit_tree properly disconnects global signals.")
	
	# 1. Instantiate and add to tree to trigger _ready() and the signal connections
	main_scene = load("res://scenes/main_scene.tscn").instantiate()
	add_child(main_scene)
	player_root = main_scene.get_node("Player")
	
	assert_true(
		Globals.settings.setting_changed.is_connected(player_root._on_setting_changed), 
		"setting_changed must be connected after player enters the tree."
	)
	assert_true(
		Globals.settings.fuel_depleted.is_connected(player_root._on_player_out_of_fuel), 
		"fuel_depleted must be connected after player enters the tree."
	)
	
	# 2. CRITICAL FIX: Manually trigger the lifecycle function instead of using remove_child().
	# remove_child() instantly orphans the node and triggers cascading tree updates
	# that cause false-positive memory leaks during testing.
	player_root._exit_tree()
	
	# 3. Assert the signals were cleanly severed
	assert_false(
		Globals.settings.setting_changed.is_connected(player_root._on_setting_changed), 
		"setting_changed must be completely disconnected after _exit_tree is called."
	)
	assert_false(
		Globals.settings.fuel_depleted.is_connected(player_root._on_player_out_of_fuel), 
		"fuel_depleted must be completely disconnected after _exit_tree is called."
	)

## test_exit_tree_safe_without_globals |
## Safety | Verify no crashes on early exit
## :rtype: void
func test_exit_tree_safe_without_globals() -> void:
	gut.p("Testing: Player _exit_tree does not crash if Globals.settings is null.")
	
	Globals.settings = null
	
	# Instantiate manually without adding to the tree (bypasses _ready)
	main_scene = load("res://scenes/main_scene.tscn").instantiate()
	player_root = main_scene.get_node("Player")
	
	# Safely call _exit_tree in isolation
	player_root._exit_tree()
	
	assert_true(true, "_exit_tree handled a null Globals.settings state gracefully.")
