## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later

@warning_ignore("unused_parameter")
extends GdUnitTestSuite

var bullet_scene := preload("res://scenes/bullet.tscn")


func test_bullet_collision() -> void:
	# Instantiate with auto_free to prevent leaks/orphans
	var bullet: Variant = auto_free(bullet_scene.instantiate())

	# Add to root (more reliable in CI / headless runs)
	get_tree().root.add_child(bullet)
	bullet.global_position = Vector2.ZERO
	bullet.global_rotation = 0

	# Safer than physics_frame for tree settling
	await await_idle_frame()

	# Create a dummy Area2D that implements take_damage
	# (area_entered signal requires an Area2D argument)
	var dummy: Area2D = auto_free(Area2D.new())
	var script := GDScript.new()
	script.source_code = """
extends Area2D

func take_damage(_d: int) -> void:
	pass
"""
	script.reload()
	dummy.set_script(script)

	# Simulate a hit by emitting the area_entered signal
	bullet.get_node("Area2D").area_entered.emit(dummy)

	# Bullet should be queued for deletion after a successful hit
	assert_that(bullet).is_queued_for_deletion()
