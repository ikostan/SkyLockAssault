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
	assert_float(bullet.linear_velocity.y).is_equal_approx(-400.0, 10.0)
	weapon.queue_free()

func test_firing_bullet() -> void:
	var runner: = scene_runner("res://scenes/main_scene.tscn")
	await await_millis(500)
	var player: = runner.find_child("Player")
	assert_object(player).is_not_null()
	# Clear any existing bullets to prevent count issues
	for b in get_tree().get_nodes_in_group("bullets"):
		b.queue_free()
	# Simulate a single fire press/release for one bullet
	runner.simulate_action_press("fire")
	runner.simulate_action_release("fire")
	await runner.simulate_frames(5)  # Allow physics to settle
	var bullets: = get_tree().get_nodes_in_group("bullets")
	assert_int(bullets.size()).is_equal(1)
	var bullet: = bullets[0]
	assert_float(bullet.linear_velocity.y).is_equal_approx(-400.0, 10.0)
	assert_float(bullet.linear_velocity.x).is_equal_approx(0.0, 10.0)
