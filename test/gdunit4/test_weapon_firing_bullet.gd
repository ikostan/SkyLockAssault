## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

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


## #1141: firing plays the shot sound through the SfxManager pool on the Weapon bus and adds
## no audio player to the scene root.
func test_firing_adds_no_sound_player_to_root() -> void:
	await await_millis(500)  # Let the previous shot's cooldown end.
	for b in get_tree().get_nodes_in_group("bullets"):
		b.queue_free()
	SfxManager.stop_all_sfx()
	var root_audio_before := _root_audio_players()
	var pool_children := SfxManager.get_child_count()
	var shot_sound: AudioStream = load("res://config_resources/default_bullet.tres").shot_sound

	runner.simulate_action_press("fire")
	runner.simulate_action_release("fire")
	await runner.simulate_frames(2)

	assert_int(get_tree().get_nodes_in_group("bullets").size()).is_equal(1)
	assert_array(_root_audio_players()).is_equal(root_audio_before)
	assert_int(SfxManager.get_child_count()).is_equal(pool_children)
	var shot_players: Array[AudioStreamPlayer] = []
	for player: AudioStreamPlayer in SfxManager.get_sfx_pool_players():
		# The stream stays assigned after a short sound ends, so this doesn't race playback.
		if is_instance_valid(player) and player.stream == shot_sound:
			shot_players.append(player)
	assert_int(shot_players.size()).is_equal(1)
	if shot_players.size() == 1:
		assert_str(shot_players[0].bus).is_equal(AudioConstants.BUS_SFX_WEAPON)


func _root_audio_players() -> Array[Node]:
	var result: Array[Node] = []
	for node in get_tree().root.get_children():
		if node is AudioStreamPlayer2D or node is AudioStreamPlayer:
			result.append(node)
	return result
