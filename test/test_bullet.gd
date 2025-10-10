extends GdUnitTestSuite

var bullet_scene: = preload("res://scenes/bullet.tscn")

func test_bullet_movement() -> void:
	var bullet: = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = Vector2.ZERO
	bullet.global_rotation = 0  # Rightward
	await get_tree().physics_frame  # Initial frame
	await get_tree().create_timer(0.1).timeout  # Allow 0.1s for movement (~80 units at 800 speed)
	assert_float(bullet.global_position.x).is_greater(0.0).with_margin(70.0)  # ~80 units with tolerance
	bullet.queue_free()

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
func take_damage(d: int) -> void:
    pass
    """
	script.reload()
	dummy.set_script(script)
	bullet.get_node("Area2D").area_entered.emit(dummy)
	assert_that(bullet).is_queued_for_deletion()  # Verify despawn on hit
	dummy.free()
	bullet.queue_free()
