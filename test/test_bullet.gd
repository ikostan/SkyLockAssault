extends GdUnitTestSuite

var bullet_scene: = preload("res://scenes/bullet.tscn")

func test_bullet_collision() -> void:
	var bullet: = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = Vector2.ZERO
	bullet.global_rotation = 0
	await get_tree().physics_frame
	# Simulate a hit body with take_damage method
	var dummy: Node2D = Node2D.new()
	var script: = GDScript.new()
	script.source_code = """
extends Node2D

func take_damage(d: int) -> void:
    pass
	"""
	script.reload()
	dummy.set_script(script)
	bullet.get_node("Area2D").area_entered.emit(dummy)
	assert_that(bullet).is_queued_for_deletion()  # Verify despawn on hit
	dummy.free()
	bullet.queue_free()
