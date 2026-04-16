## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_decor_layer_transformations.gd
##
## GUT unit tests for verifying randomized rotations, scaling,
## and flipping applied to the main scene's decor layer.

extends "res://addons/gut/test.gd"

const GutHelper = preload("res://test/gut/gut_test_helper.gd")

var main_scene: MainScene
var viewport_mock: Vector2 = Vector2(1920, 1080)


func before_each() -> void:
	await get_tree().process_frame
	main_scene = preload("res://scenes/main_scene.tscn").instantiate()
	add_child(main_scene)
	await get_tree().process_frame

func after_each() -> void:
	# Use the helper's static method
	if is_instance_valid(main_scene):
		GutHelper.safe_hard_free(main_scene)
	await get_tree().process_frame


## test_decor_sprites_have_valid_cardinal_rotations |
## Verifies every decor sprite is snapped to exactly 0, 90, 180, or -90 degrees.
## :rtype: void
func test_decor_sprites_have_valid_cardinal_rotations() -> void:
	gut.p("Testing: All decor sprites must use strict cardinal rotations.")
	
	main_scene.setup_decor_layer(viewport_mock)
	
	var active_sprites: Array[Node] = main_scene.decor_layer.get_children().filter(
		func(c: Node) -> bool: return not c.is_queued_for_deletion()
	)
	
	var allowed_radians: Array[float] = [
		0.0, 
		deg_to_rad(90.0), 
		deg_to_rad(180.0), 
		deg_to_rad(-90.0)
	]
	
	var invalid_rotations: Array[float] = []
	
	for node in active_sprites:
		var sprite := node as Sprite2D
		var is_valid := false
		
		# Check if the sprite's rotation matches any allowed radian (using approx to handle float drift)
		for allowed_rad in allowed_radians:
			if is_equal_approx(sprite.rotation, allowed_rad):
				is_valid = true
				break
				
		if not is_valid:
			invalid_rotations.append(sprite.rotation)
			
	assert_eq(invalid_rotations.size(), 0, "Found decor sprites with non-cardinal rotations.")


## test_decor_sprites_have_valid_scale_ranges |
## Verifies every decor sprite scale falls between 0.5 and 1.5, and is uniformly scaled.
## :rtype: void
func test_decor_sprites_have_valid_scale_ranges() -> void:
	gut.p("Testing: All decor sprites must be uniformly scaled between 0.5 and 1.5.")
	
	main_scene.setup_decor_layer(viewport_mock)
	
	var active_sprites: Array[Node] = main_scene.decor_layer.get_children().filter(
		func(c: Node) -> bool: return not c.is_queued_for_deletion()
	)
	
	var out_of_bounds_scales: Array[Vector2] = []
	var non_uniform_scales: Array[Vector2] = []
	
	for node in active_sprites:
		var sprite := node as Sprite2D
		var s: Vector2 = sprite.scale
		
		# Check bounds (using 0.49 and 1.51 to safely absorb floating point precision errors)
		if s.x < 0.49 or s.x > 1.51:
			out_of_bounds_scales.append(s)
			
		# Check uniformity (x scale must equal y scale)
		if not is_equal_approx(s.x, s.y):
			non_uniform_scales.append(s)
			
	assert_eq(out_of_bounds_scales.size(), 0, "Found decor sprites outside the 0.5 - 1.5 scale range.")
	assert_eq(non_uniform_scales.size(), 0, "Found decor sprites with non-uniform (squished/stretched) scaling.")


## test_decor_sprites_have_boolean_flips |
## Verifies that flip_h and flip_v properties are actively being randomized.
## :rtype: void
func test_decor_sprites_have_boolean_flips() -> void:
	gut.p("Testing: Decor sprites should successfully randomize horizontal and vertical flips.")
	
	main_scene.setup_decor_layer(viewport_mock)
	
	var active_sprites: Array[Node] = main_scene.decor_layer.get_children().filter(
		func(c: Node) -> bool: return not c.is_queued_for_deletion()
	)
	
	var found_h_true: bool = false
	var found_h_false: bool = false
	var found_v_true: bool = false
	var found_v_false: bool = false
	
	for node in active_sprites:
		var sprite := node as Sprite2D
		
		# Track horizontal flip states
		if sprite.flip_h:
			found_h_true = true
		else:
			found_h_false = true
			
		# Track vertical flip states
		if sprite.flip_v:
			found_v_true = true
		else:
			found_v_false = true
			
	# Assert that our generation loop produced at least one of every state
	assert_true(found_h_true and found_h_false, "Expected a randomized mix of true and false for horizontal flips.")
	assert_true(found_v_true and found_v_false, "Expected a randomized mix of true and false for vertical flips.")
