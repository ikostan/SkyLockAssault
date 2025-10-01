extends GdUnitTestSuite


# Optional: Setup before all tests (e.g., mock globals)
func before() -> void:
	pass


# Optional: Teardown after all tests
func after() -> void:
	pass


func test_player_present(timeout: int = 4000) -> void:
	var runner: GdUnitSceneRunner = scene_runner("res://scenes/main_scene.tscn")
	# Wait for _ready() delays/fades (timer 0.5s + tweens 0.5s + 0.3s)
	await await_millis(500)  # Or await runner.simulate_frames(60) for ~1s at 60fps
	var player: Node2D = runner.find_child("Player")
	assert_object(player).is_instanceof(Node2D)
	assert_object(player).is_not_null()
	assert_bool(player.visible).is_true()  # Check post-fade
