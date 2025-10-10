extends GdUnitTestSuite

var bullet_scene: = preload("res://scenes/bullet.tscn")

func test_fire_instantiation() -> void:
	var weapon: = preload("res://scenes/weapon.tscn").instantiate()
	add_child(weapon)
	weapon._fire()
	await get_tree().physics_frame
	var bullets: = get_tree().get_nodes_in_group("bullets")
	assert_int(bullets.size()).is_equal(1)
	var bullet: = bullets[0]
	assert_float(bullet.linear_velocity.y).is_equal_approx(-800.0, 10.0)  # Up
	weapon.queue_free()


func test_firing_bullet() -> void:
	var runner: = scene_runner("res://scenes/main_scene.tscn")
	await await_millis(500)
	var player: = runner.find_child("Player")
	assert_object(player).is_not_null()
	runner.simulate_action_pressed("fire")
	await runner.simulate_frames(1)
	var bullets: = get_tree().get_nodes_in_group("bullets")
	assert_int(bullets.size()).is_equal(1)
	var bullet: = bullets[0]
	assert_float(bullet.linear_velocity.y).is_equal_approx(-800.0, 10.0)
	assert_float(bullet.linear_velocity.x).is_equal_approx(0.0, 10.0)
	assert_float(bullet.global_position.y).is_equal_approx(-25.0, 5.0)  # Offset up
	assert_float(bullet.global_position.x).is_equal_approx(0.0, 5.0)
