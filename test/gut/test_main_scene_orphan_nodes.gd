## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_main_scene_orphan_nodes.gd
##
## GUT unit tests for verifying the absence of orphan node leaks in MainScene.
## Covers the Orphan Node Leak Fix Test Plan (Issue #549).

extends "res://addons/gut/test.gd"

var main_scene: MainScene
var viewport_mock: Vector2 = Vector2(1920, 1080)


## Per-test setup: Instantiate MainScene and allow it to initialize.
## :rtype: void
func before_each() -> void:
	main_scene = preload("res://scenes/main_scene.tscn").instantiate()
	add_child_autofree(main_scene)
	
	# Allow the scene to initialize (_ready, etc.) before running tests
	await get_tree().process_frame


## Custom assertion to check if any new orphan nodes leaked during the test.
## :param baseline_orphans: The initial orphan count taken before the test logic.
## :param context: A description of the scenario being tested for the log output.
## :rtype: void
func verify_no_orphan_leaks(baseline_orphans: int, context: String) -> void:
	var current_orphans: int = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	assert_eq(current_orphans, baseline_orphans, context)


## Manual Orphan Node Check & GUT Teardown Memory Test (Frame Sync) |
## Instantiate MainScene, call setup methods multiple times, flush the frame,
## free the scene, and verify no orphan nodes exist.
## :rtype: void
func test_teardown_memory_sync() -> void:
	var baseline_orphans: int = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	
	main_scene.setup_bushes_layer(viewport_mock)
	main_scene.setup_decor_layer(viewport_mock)
	
	# Re-trigger to execute the clearing logic on existing sprites
	main_scene.setup_bushes_layer(viewport_mock)
	main_scene.setup_decor_layer(viewport_mock)
	
	# CRITICAL: Flush the frame to allow queue_free() to complete its cleanup
	await get_tree().process_frame
	
	# Free the scene explicitly to test teardown
	main_scene.queue_free()
	await get_tree().process_frame
	
	verify_no_orphan_leaks(baseline_orphans, "Expected orphan nodes to return to baseline after frame sync and teardown.")


## Repeated Setup Call Stability Test |
## Call setup methods 50 times in a tight loop to simulate heavy reset load,
## then await a frame and check for memory leaks or node accumulation.
## :rtype: void
func test_repeated_setup_call_stability() -> void:
	var baseline_orphans: int = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	
	# 1. Call setup_bushes_layer() 50 times in a loop
	for i in range(50):
		main_scene.setup_bushes_layer(viewport_mock)
		
	# 2. Await one frame after loop
	await get_tree().process_frame
	
	verify_no_orphan_leaks(baseline_orphans, "No accumulated orphan nodes after 50 rapid setup calls.")


## Immediate Rebuild Integrity Test |
## Call setup, then immediately repopulate the layer in the exact same frame.
## Verifies old nodes do not double-up with new nodes by filtering out queued items.
## :rtype: void
func test_immediate_rebuild_integrity() -> void:
	# Flush out any leftover nodes queued by _ready() first
	await get_tree().process_frame
	
	main_scene.setup_bushes_layer(viewport_mock)
	
	# Count only nodes that are NOT queued for deletion
	var initial_active_count: int = main_scene.bushes_layer.get_children().filter(func(c: Node) -> bool: return not c.is_queued_for_deletion()).size()
	
	# Immediately repopulate in the same frame
	main_scene.setup_bushes_layer(viewport_mock)
	
	var new_active_count: int = main_scene.bushes_layer.get_children().filter(func(c: Node) -> bool: return not c.is_queued_for_deletion()).size()
	
	# The active count should remain consistent, confirming old nodes aren't interfering
	assert_eq(new_active_count, initial_active_count, "Child count should remain stable during rapid repopulation.")


## Layer Isolation Test |
## Runs setup on one layer and inspects the other to ensure no unintended 
## cross-layer deletions occur.
## :rtype: void
func test_layer_isolation() -> void:
	gut.p("Testing: Layers should operate independently without cross-deletions.")
	
	# Step 0: Populate both layers first to establish a baseline
	main_scene.setup_bushes_layer(viewport_mock)
	main_scene.setup_decor_layer(viewport_mock)
	
	# CRITICAL FIX: Flush the frame so the initial nodes spawned by _ready() are fully swept
	# before we take our baseline counts.
	await get_tree().process_frame
	
	var initial_decor_count: int = main_scene.decor_layer.get_child_count()
	var initial_bushes_count: int = main_scene.bushes_layer.get_child_count()
	
	# Step 1: Run setup_bushes_layer() only.
	main_scene.setup_bushes_layer(viewport_mock)
	await get_tree().process_frame
	
	# Step 2: Verify decor layer operates independently
	var final_decor_count: int = main_scene.decor_layer.get_child_count()
	assert_eq(final_decor_count, initial_decor_count, "Decor layer child count should not change when bushes layer is reset.")
	assert_gt(final_decor_count, 0, "Decor layer should not be empty.")
	
	# Step 3: Run setup_decor_layer() only.
	main_scene.setup_decor_layer(viewport_mock)
	await get_tree().process_frame
	
	# Step 4: Verify bushes layer operates independently
	var final_bushes_count: int = main_scene.bushes_layer.get_child_count()
	assert_eq(final_bushes_count, initial_bushes_count, "Bushes layer child count should not change when decor layer is reset.")
	assert_gt(final_bushes_count, 0, "Bushes layer should not be empty.")


## Scene Reload Lifecycle Test |
## Simulates a full scene reload via tree structure replacements.
## Monitors orphan nodes before and after to ensure clean teardown.
## :rtype: void
func test_scene_reload_lifecycle() -> void:
	var baseline_orphans: int = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	
	main_scene.setup_bushes_layer(viewport_mock)
	main_scene.setup_decor_layer(viewport_mock)
	
	# Simulate change_scene by tearing down and instantiating a new one
	main_scene.queue_free()
	await get_tree().process_frame
	
	var reloaded_scene: MainScene = preload("res://scenes/main_scene.tscn").instantiate()
	add_child_autofree(reloaded_scene)
	await get_tree().process_frame
	
	reloaded_scene.setup_bushes_layer(viewport_mock)
	reloaded_scene.setup_decor_layer(viewport_mock)
	await get_tree().process_frame
	
	verify_no_orphan_leaks(baseline_orphans, "No orphan nodes should persist across scene reload simulation.")


## Stress Input Test (Runtime Simulation) |
## Simulates a user rapidly spamming a debug key across multiple frames
## to ensure no compounding leaks or engine crashes happen.
## :rtype: void
func test_stress_input_simulation() -> void:
	var baseline_orphans: int = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	
	# Spam setups across consecutive frames
	for i in range(10):
		main_scene.setup_bushes_layer(viewport_mock)
		main_scene.setup_decor_layer(viewport_mock)
		await get_tree().process_frame
		
	# Final flush and check
	await get_tree().process_frame
	
	verify_no_orphan_leaks(baseline_orphans, "Memory must remain completely stable after sustained stress input.")
