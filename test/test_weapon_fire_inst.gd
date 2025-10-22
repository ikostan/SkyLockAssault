extends GdUnitTestSuite

var weapon: Variant

# Optional: Setup before all tests (e.g., mock globals)
func before() -> void:
	weapon = preload("res://scenes/weapon.tscn").instantiate()

# Optional: Teardown after all tests
func after() -> void:
	weapon = null

func test_fire_instantiation() -> void:
	add_child(weapon)
	weapon._fire()
	await get_tree().physics_frame
	var bullets: = get_tree().get_nodes_in_group("bullets")
	assert_int(bullets.size()).is_between(1, 3)
	var bullet: = bullets[0]
	assert_float(bullet.linear_velocity.y).is_equal_approx(-350.0, 50.0)
	weapon.queue_free()
