## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_main_scene_orphan_nodes.gd

extends "res://addons/gut/test.gd"

var main_scene: MainScene
var viewport_mock: Vector2 = Vector2(1920, 1080)

## Standardized safe free to eliminate orphan windows and double-frees
func safe_hard_free(node: Node) -> void:
	if not is_instance_valid(node) or node.is_queued_for_deletion():
		return
	if node.is_inside_tree():
		node.get_parent().remove_child(node)
	node.free()

func before_each() -> void:
	await get_tree().process_frame
	main_scene = preload("res://scenes/main_scene.tscn").instantiate()
	add_child(main_scene)
	await get_tree().process_frame

func after_each() -> void:
	# CRITICAL: If the test already freed the scene, this skips gracefully
	if is_instance_valid(main_scene):
		safe_hard_free(main_scene)
	await get_tree().process_frame

func verify_no_orphan_leaks(baseline_orphans: int, context: String) -> void:
	var current_orphans: int = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	assert_eq(current_orphans, baseline_orphans, context)

func test_teardown_memory_sync() -> void:
	var baseline_orphans: int = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	
	main_scene.setup_bushes_layer(viewport_mock)
	main_scene.setup_decor_layer(viewport_mock)
	
	await get_tree().process_frame
	
	# FIX: Free manually AND nullify so after_each ignores it
	safe_hard_free(main_scene)
	main_scene = null 
	
	await get_tree().process_frame
	verify_no_orphan_leaks(baseline_orphans, "Expected orphans to return to baseline.")

func test_repeated_setup_call_stability() -> void:
	var baseline_orphans: int = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	for i in range(50):
		main_scene.setup_bushes_layer(viewport_mock)
	await get_tree().process_frame
	verify_no_orphan_leaks(baseline_orphans, "No accumulated orphans after 50 calls.")

## Immediate Rebuild Integrity Test |
func test_immediate_rebuild_integrity() -> void:
	await get_tree().process_frame
	main_scene.setup_bushes_layer(viewport_mock)
	
	# Added -> bool to the lambda
	var initial_active_count: int = main_scene.bushes_layer.get_children().filter(
		func(c: Node) -> bool: return not c.is_queued_for_deletion()
	).size()
	
	main_scene.setup_bushes_layer(viewport_mock)
	
	# Added -> bool to the lambda
	var new_active_count: int = main_scene.bushes_layer.get_children().filter(
		func(c: Node) -> bool: return not c.is_queued_for_deletion()
	).size()
	
	assert_eq(new_active_count, initial_active_count, "Child count should remain stable.")

func test_layer_isolation() -> void:
	main_scene.setup_bushes_layer(viewport_mock)
	main_scene.setup_decor_layer(viewport_mock)
	await get_tree().process_frame
	
	var initial_decor: int = main_scene.decor_layer.get_child_count()
	main_scene.setup_bushes_layer(viewport_mock)
	await get_tree().process_frame
	assert_eq(main_scene.decor_layer.get_child_count(), initial_decor, "Decor count stable.")

func test_scene_reload_lifecycle() -> void:
	var baseline_orphans: int = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	
	# FIX: Use safe_hard_free and nullify baseline scene
	safe_hard_free(main_scene)
	main_scene = null
	await get_tree().process_frame
	
	var reloaded_scene: MainScene = preload("res://scenes/main_scene.tscn").instantiate()
	add_child(reloaded_scene)
	reloaded_scene.setup_bushes_layer(viewport_mock)
	await get_tree().process_frame
	
	# Clean up the reloaded instance manually too
	safe_hard_free(reloaded_scene)
	await get_tree().process_frame
	verify_no_orphan_leaks(baseline_orphans, "Clean teardown after reload.")

func test_stress_input_simulation() -> void:
	var baseline_orphans: int = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	for i in range(10):
		main_scene.setup_bushes_layer(viewport_mock)
		main_scene.setup_decor_layer(viewport_mock)
		await get_tree().process_frame
	verify_no_orphan_leaks(baseline_orphans, "Stable memory after stress.")
