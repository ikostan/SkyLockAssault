## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

extends GdUnitTestSuite

const MAIN_SCENE: PackedScene = preload("res://scenes/main_scene.tscn")

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


## #1140: in a real level, fired projectiles are children of the level's Projectiles
## container, not the scene root.
func test_projectiles_are_children_of_level_container() -> void:
	await await_millis(500)  # Let the previous shot's cooldown end.
	for b in get_tree().get_nodes_in_group("bullets"):
		b.queue_free()
	await runner.simulate_frames(1)
	var level: Node = runner.scene()
	var container: Node = level.get_node("Projectiles")
	assert_object(container).is_not_null()

	runner.simulate_action_press("fire")
	runner.simulate_action_release("fire")
	await runner.simulate_frames(2)

	var bullets := get_tree().get_nodes_in_group("bullets")
	assert_int(bullets.size()).is_equal(1)
	if bullets.size() == 1:
		assert_object(bullets[0].get_parent()).is_same(container)
		assert_bool(bullets[0].get_parent() == get_tree().root).is_false()


## #1140: replacing a level with shots in flight leaves no node in the bullets group.
func test_replacing_level_leaves_no_bullets() -> void:
	var level: MainScene = MAIN_SCENE.instantiate()
	get_tree().root.add_child(level)
	await get_tree().process_frame
	var weapon: Weapon = level.player.weapon
	weapon.weapon_resource.current_ammo = 10
	weapon.fire()
	var fired: Array = []
	for b in get_tree().get_nodes_in_group("bullets"):
		if level.is_ancestor_of(b):
			fired.append(b)
	assert_int(fired.size()).is_equal(1)

	level.free()
	var replacement: MainScene = auto_free(MAIN_SCENE.instantiate())
	get_tree().root.add_child(replacement)
	await get_tree().process_frame

	for b: Variant in fired:
		assert_bool(is_instance_valid(b)).is_false()
	# Every remaining bullet belongs to a level that is still alive (the shared runner's
	# level can still have earlier shots in flight).
	var live_level: Node = runner.scene()
	for b in get_tree().get_nodes_in_group("bullets"):
		var owned: bool = replacement.is_ancestor_of(b) or live_level.is_ancestor_of(b)
		assert_bool(owned or b.is_queued_for_deletion()).is_true()
	get_tree().root.remove_child(replacement)
