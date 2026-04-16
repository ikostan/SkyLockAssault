## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_main_scene_parallax_chunks.gd
##
## GUT unit tests for verifying the expanded parallax background chunk size
## and sprite density to prevent visual repetition.

extends "res://addons/gut/test.gd"

var main_scene: MainScene
var viewport_mock: Vector2 = Vector2(1920, 1080)


## Per-test setup: Instantiate MainScene and allow it to initialize.
## :rtype: void
func before_each() -> void:
	# Flush frame before setup to prevent global state pollution
	await get_tree().process_frame
	
	main_scene = preload("res://scenes/main_scene.tscn").instantiate()
	add_child_autofree(main_scene)
	
	# Allow the scene to initialize (_ready, etc.) before running tests
	await get_tree().process_frame


## Per-test teardown: Ensure aggressive cleanup to protect subsequent tests.
## :rtype: void
func after_each() -> void:
	if is_instance_valid(main_scene):
		main_scene.free()
	await get_tree().process_frame


## test_bushes_layer_chunk_size_and_density |
## Verify the bushes layer mirrors at exactly 20 screens tall and spawns 5x the sprites.
## :rtype: void
func test_bushes_layer_chunk_size_and_density() -> void:
	gut.p("Testing: Bushes layer should use a 20-screen chunk size and 5x density.")

	# 1. Re-run setup to use our specific mock viewport
	main_scene.setup_bushes_layer(viewport_mock)

	# 2. Verify Chunk Size (Height)
	var expected_height: float = viewport_mock.y * 20.0
	assert_eq(
		main_scene.bushes_layer.motion_mirroring.y, 
		expected_height, 
		"Bushes layer mirroring should be exactly 20 screens tall."
	)

	# 3. Calculate Expected Density based on the Preloader
	var bush_ids: Array = Array(main_scene.texture_preloader.get_resource_list()).filter(
		func(id: String) -> bool: return id.begins_with("bush_")
	)
	var expected_count: int = bush_ids.size() * 5

	# 4. Count only active nodes (filtering out anything queued for deletion from the _ready call)
	var active_children: int = main_scene.bushes_layer.get_children().filter(
		func(c: Node) -> bool: return not c.is_queued_for_deletion()
	).size()
	
	assert_eq(
		active_children, 
		expected_count, 
		"Bushes layer should spawn exactly 5 times the number of available bush sprites."
	)


## test_decor_layer_chunk_size_and_density |
## Verify the decor layer mirrors at exactly 20 screens tall and spawns 5x the sprites.
## :rtype: void
func test_decor_layer_chunk_size_and_density() -> void:
	gut.p("Testing: Decor layer should use a 20-screen chunk size and 5x density.")

	# 1. Re-run setup
	main_scene.setup_decor_layer(viewport_mock)

	# 2. Verify Chunk Size (Height)
	var expected_height: float = viewport_mock.y * 20.0
	assert_eq(
		main_scene.decor_layer.motion_mirroring.y, 
		expected_height, 
		"Decor layer mirroring should be exactly 20 screens tall."
	)

	# 3. Calculate Expected Density based on the Preloader
	var decor_ids: Array = Array(main_scene.texture_preloader.get_resource_list()).filter(
		func(id: String) -> bool: return id.begins_with("decor_")
	)
	var expected_count: int = decor_ids.size() * 5

	# 4. Filter out queued nodes
	var active_children: int = main_scene.decor_layer.get_children().filter(
		func(c: Node) -> bool: return not c.is_queued_for_deletion()
	).size()
	
	assert_eq(
		active_children, 
		expected_count, 
		"Decor layer should spawn exactly 5 times the number of available decor sprites."
	)
