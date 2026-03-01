## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later

extends GdUnitTestSuite

var runner: Variant

# Optional: Setup before all tests (e.g., mock globals)
func before() -> void:
	runner = scene_runner("res://scenes/main_scene.tscn")


# Optional: Teardown after all tests
func after() -> void:
	runner = null  # Optional: Explicitly drop reference (safe for RefCounted)


func test_firing_bullet() -> void:
	await await_millis(500)
	var player: Node2D = runner.find_child("Player")
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
