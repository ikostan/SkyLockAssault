extends GdUnitTestSuite

var bullet_scene: = preload("res://scenes/bullet.tscn")

func test_bullet_collision() -> void:
	# New: auto_free for cleanup (prevents leaks/orphans)
	var bullet: Variant = auto_free(bullet_scene.instantiate())
	# Updated: Use root (reliable in CI/tests)
	get_tree().root.add_child(bullet)
	bullet.global_position = Vector2.ZERO
	bullet.global_rotation = 0
	# New: Safer await for tree settling (physics_frame can be flaky in CI)
	await await_idle_frame()
	
	# Simulate a hit body with take_damage method
	# New: auto_free for dummy cleanup
	var dummy: Node2D = auto_free(Node2D.new())
	var script: = GDScript.new()
	script.source_code = """
extends Node2D

func take_damage(d: int) -> void:
    pass
	"""
	script.reload()
	dummy.set_script(script)
	
	# Emit signal to simulate hit
	bullet.get_node("Area2D").area_entered.emit(dummy)
	
	# Assert bullet queued for deletion after hit
	assert_that(bullet).is_queued_for_deletion()  # Verify despawn on hit
