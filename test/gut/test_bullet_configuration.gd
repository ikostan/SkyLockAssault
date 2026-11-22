## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

extends "res://addons/gut/test.gd"

const BULLET_SCENE: PackedScene = preload("res://scenes/bullet.tscn")

var firer: Node2D
var config: BulletResource
var original_settings: GameSettingsResource
var original_filter: int
var original_root_children: Array[Node]


## Collects logs while it is added with OS.add_logger(): printed lines (Globals.log_message)
## in [member lines], and warnings and errors from Godot's error callback, such as
## push_warning(), in [member error_events]. GUT doesn't fail a test on push_warning().
class LogCapture:
	extends Logger
	var lines: Array[String] = []
	var error_events: Array[String] = []
	var _mutex: Mutex = Mutex.new()

	func _log_message(message: String, _error: bool) -> void:
		_mutex.lock()
		lines.append(message)
		_mutex.unlock()

	func _log_error(
		function: String,
		_file: String,
		_line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		error_type: int,
		_script_backtraces: Array[ScriptBacktrace]
	) -> void:
		_mutex.lock()
		error_events.append("[type %d] %s: %s %s" % [error_type, function, code, rationale])
		_mutex.unlock()


class DamageTarget extends Area2D:
	var hits: Array[int] = []

	func take_damage(amount: int) -> void:
		hits.append(amount)


func before_each() -> void:
	original_settings = Globals.settings
	Globals.settings = GameSettingsResource.new()
	original_filter = get_viewport().canvas_item_default_texture_filter
	original_root_children = get_tree().root.get_children()
	config = BulletResource.new()
	config.fire_rate = 0.4
	config.muzzle_offset = Vector2(13, -41)
	config.projectile_speed = 720.0
	config.projectile_lifetime = 1.75
	config.damage = 37
	config.scale = Vector2(0.6, 0.4)
	config.collision_radius = 6.5
	config.projectile_texture = GradientTexture2D.new()
	config.shot_sound = null
	SfxManager.stop_all_sfx()
	firer = autofree(BULLET_SCENE.instantiate())
	firer.config = config
	add_child(firer)


func after_each() -> void:
	# Projectiles are parented to root, outside GUT's fixture. Sound players are freed too,
	# in case a regression brings back a per-shot player.
	for node in get_tree().root.get_children():
		if node not in original_root_children:
			if node is RigidBody2D or node is AudioStreamPlayer2D or node is AudioStreamPlayer:
				node.free()
	SfxManager.stop_all_sfx()
	Globals.settings = original_settings
	get_viewport().canvas_item_default_texture_filter = original_filter


func _projectiles() -> Array[Node]:
	var result: Array[Node] = []
	for node in get_tree().get_nodes_in_group("bullets"):
		if node not in original_root_children:
			result.append(node)
	return result


func _spawn_projectile() -> RigidBody2D:
	firer.spawn_projectile()
	var projectiles := _projectiles()
	assert_eq(projectiles.size(), 1, "One projectile should be created per spawn.")
	return projectiles[0] as RigidBody2D if projectiles.size() == 1 else null


## Audio players added to the scene root since before_each(). Shot sounds use the SfxManager
## pool (#1141), so firing must never add one.
func _root_sound_players() -> Array[Node]:
	var result: Array[Node] = []
	for node in get_tree().root.get_children():
		if node in original_root_children:
			continue
		if node is AudioStreamPlayer2D or node is AudioStreamPlayer:
			result.append(node)
	return result


## Pooled SfxManager players that are currently playing [param stream].
func _pool_players_playing(stream: AudioStream) -> Array[AudioStreamPlayer]:
	var result: Array[AudioStreamPlayer] = []
	for player: AudioStreamPlayer in SfxManager.get_sfx_pool_players():
		if is_instance_valid(player) and player.playing and player.stream == stream:
			result.append(player)
	return result


func _child_of_type(parent: Node, type_name: String) -> Node:
	# Runtime-created nodes have generated names; select by their role instead.
	var children := parent.find_children("*", type_name, false, false)
	assert_eq(children.size(), 1, "Expected one %s child." % type_name)
	return children[0] if children.size() == 1 else null


func test_unconfigured_scenes_receive_independent_default_resources() -> void:
	var first: Node2D = add_child_autofree(BULLET_SCENE.instantiate())
	var second: Node2D = add_child_autofree(BULLET_SCENE.instantiate())
	assert_true(first.config is BulletResource)
	assert_eq(first.config, second.config, "Default bullets share one preloaded resource.")
	assert_eq(second.config.fire_rate, 0.15)


## #1150: a firer without its own config fires with the assets from default_bullet.tres,
## the same sprite and sound as before the script defaults were removed. The test goes
## through fire(), so it also fails if the firing path stops spawning or playing the sound.
func test_default_config_firer_uses_assets_from_default_bullet_tres() -> void:
	var default_firer: Node2D = add_child_autofree(BULLET_SCENE.instantiate())
	var default_config: BulletResource = load("res://config_resources/default_bullet.tres")
	assert_eq(default_firer.config, default_config, "A config-less firer uses default_bullet.tres.")
	assert_eq(
		default_firer.config.projectile_texture.resource_path,
		"res://files/sprite/laser_sprites/01.png"
	)
	assert_eq(
		default_firer.config.shot_sound.resource_path,
		"res://files/sounds/sfx/retro-laser-1-236669.mp3"
	)

	assert_true(default_firer.fire(), "The first shot of a ready firer must fire.")

	var projectiles := _projectiles()
	assert_eq(projectiles.size(), 1, "fire() must spawn one projectile.")
	if projectiles.size() == 1:
		var sprite := _child_of_type(projectiles[0], "Sprite2D") as Sprite2D
		assert_not_null(sprite, "The projectile must have a Sprite2D.")
		if sprite:
			assert_eq(sprite.texture, default_config.projectile_texture)

	var players := _pool_players_playing(default_config.shot_sound)
	assert_eq(players.size(), 1, "fire() must play the shot sound through the SFX pool.")
	if players.size() == 1:
		assert_eq(players[0].bus, AudioConstants.BUS_SFX_WEAPON)
	assert_eq(_root_sound_players().size(), 0, "fire() must not add a sound player to the root.")


func test_ready_preserves_injected_resource() -> void:
	assert_eq(firer.config, config, "Inspector configuration must not be replaced by defaults.")
	assert_eq(firer.config.damage, 37)
	assert_eq(firer.config.collision_radius, 6.5)


func test_fire_scales_configured_cooldown_with_difficulty(
	difficulty: float = use_parameters([0.5, 1.0, 2.0])
) -> void:
	Globals.settings.difficulty = difficulty
	assert_true(firer.fire())
	assert_almost_eq(firer.timer.wait_time, 0.4 * difficulty, 0.0001)
	assert_true(firer.timer.one_shot)
	assert_false(firer.timer.is_stopped())
	assert_false(firer.can_fire)
	assert_eq(_projectiles().size(), 1)


func test_cooldown_rejects_second_shot_until_timeout() -> void:
	assert_true(firer.fire())
	assert_false(firer.fire())
	assert_eq(_projectiles().size(), 1, "Rejected shots must not create another projectile.")
	# Drive the timeout deterministically instead of sleeping for a real cooldown.
	firer.timer.stop()
	firer.timer.timeout.emit()
	assert_true(firer.can_fire)
	assert_true(firer.fire())
	assert_eq(_projectiles().size(), 2)


func test_cooldown_rejection_does_not_play_another_shot_sound() -> void:
	var sound := AudioStreamWAV.new()
	sound.data = PackedByteArray([0, 0, 0, 0])
	config.shot_sound = sound

	assert_true(firer.fire())
	assert_eq(_pool_players_playing(sound).size(), 1)
	assert_false(firer.fire())
	assert_eq(_pool_players_playing(sound).size(), 1, "A rejected shot must not play audio.")
	assert_eq(_root_sound_players().size(), 0)

	firer.timer.stop()
	firer.timer.timeout.emit()
	assert_true(firer.fire())
	assert_eq(_pool_players_playing(sound).size(), 2, "The next accepted shot plays normally.")


func test_projectile_uses_configured_motion_and_global_muzzle_offset() -> void:
	var mount: Node2D = add_child_autofree(Node2D.new())
	firer.reparent(mount)
	mount.position = Vector2(80, 30)
	firer.position = Vector2(25, 50)
	var expected_position := firer.global_position + config.muzzle_offset
	var projectile := _spawn_projectile()
	if projectile == null:
		return
	assert_eq(projectile.global_position, expected_position)
	assert_eq(projectile.linear_velocity, Vector2(0, -720))
	assert_eq(projectile.gravity_scale, 0.0)
	assert_eq(projectile.get_parent(), get_tree().root)
	assert_true(projectile is Projectile, "Projectiles come from projectile.tscn (#1139).")
	assert_eq(projectile.scene_file_path, "res://scenes/projectile.tscn")


func test_projectile_uses_configured_texture_scale_and_hitbox() -> void:
	var projectile := _spawn_projectile()
	if projectile == null:
		return
	var sprite := _child_of_type(projectile, "Sprite2D") as Sprite2D
	var area := _child_of_type(projectile, "Area2D")
	var collision := _child_of_type(area, "CollisionShape2D") as CollisionShape2D
	assert_eq(sprite.texture, config.projectile_texture)
	assert_eq(sprite.scale, Vector2(0.6, 0.4))
	assert_true(collision.shape is CircleShape2D)
	assert_eq(collision.shape.radius, 6.5)


func test_projectile_lifetime_uses_config_and_frees_only_projectile() -> void:
	var projectile := _spawn_projectile()
	if projectile == null:
		return
	var lifetime := _child_of_type(projectile, "Timer") as Timer
	assert_eq(lifetime.wait_time, 1.75)
	assert_true(lifetime.one_shot)
	assert_false(lifetime.is_stopped())
	lifetime.stop()
	lifetime.timeout.emit()
	assert_true(projectile.is_queued_for_deletion())
	assert_false(firer.is_queued_for_deletion())


func test_collision_delivers_configured_damage(damage: int = use_parameters([0, 37])) -> void:
	config.damage = damage
	var target: DamageTarget = autofree(DamageTarget.new())
	var projectile := _spawn_projectile()
	if projectile == null:
		return
	var area := _child_of_type(projectile, "Area2D") as Area2D
	area.area_entered.emit(target)
	assert_eq(target.hits.size(), 1)
	assert_eq(target.hits[0], damage)
	assert_true(projectile.is_queued_for_deletion())
	assert_false(firer.is_queued_for_deletion())


func test_collision_without_damage_receiver_still_removes_projectile() -> void:
	var target: Area2D = autofree(Area2D.new())
	var projectile := _spawn_projectile()
	if projectile == null:
		return
	var area := _child_of_type(projectile, "Area2D") as Area2D
	area.area_entered.emit(target)
	assert_true(projectile.is_queued_for_deletion())
	assert_false(target.is_queued_for_deletion())


func test_missing_texture_and_zero_speed_still_create_collision_projectile() -> void:
	config.projectile_texture = null
	config.projectile_speed = 0.0
	config.muzzle_offset = Vector2.ZERO
	var projectile := _spawn_projectile()
	if projectile == null:
		return
	var sprite := _child_of_type(projectile, "Sprite2D") as Sprite2D
	assert_null(sprite.texture)
	assert_eq(projectile.linear_velocity, Vector2.ZERO)
	assert_eq(projectile.global_position, firer.global_position)
	var area := _child_of_type(projectile, "Area2D")
	var collision := _child_of_type(area, "CollisionShape2D") as CollisionShape2D
	assert_not_null(collision.shape)


## A null shot sound fires silently: nothing plays, no player is added, and nothing is
## logged as a warning or error (#1141).
func test_null_sound_allows_silent_firing() -> void:
	var log_capture := LogCapture.new()
	OS.add_logger(log_capture)
	var fired: bool = firer.fire()
	OS.remove_logger(log_capture)

	assert_true(fired)
	assert_eq(_projectiles().size(), 1)
	assert_eq(_root_sound_players().size(), 0)
	assert_false(SfxManager.is_any_sfx_playing(), "A null shot sound must not use the pool.")
	for line: String in log_capture.lines:
		assert_false(line.contains("WARNING"), "Silent firing logged a warning: " + line)
		assert_false(line.contains("ERROR"), "Silent firing logged an error: " + line)
	assert_eq(
		log_capture.error_events,
		[] as Array[String],
		"Silent firing must not raise a warning or error (push_warning() included)."
	)


## #1141: the shot sound plays on a pooled, non-positional player on the Weapon bus, adds no
## player to the root, and leaves the player in the pool when it finishes.
func test_configured_sound_uses_weapon_bus_and_cleans_up_on_finish() -> void:
	var sound := AudioStreamWAV.new()
	sound.data = PackedByteArray([0, 0, 0, 0])
	config.shot_sound = sound
	var pool_size: int = SfxManager.get_sfx_pool_players().size()
	var manager_children: int = SfxManager.get_child_count()

	firer.play_shot_sound()

	var players := _pool_players_playing(sound)
	assert_eq(players.size(), 1, "The shot sound must play on one pooled player.")
	assert_eq(_root_sound_players().size(), 0, "No sound player may be added to the root.")
	assert_eq(SfxManager.get_child_count(), manager_children, "The pool must not grow.")
	if players.size() != 1:
		return
	var player := players[0]
	assert_true(player is AudioStreamPlayer, "Pooled players are non-positional.")
	assert_eq(player.bus, AudioConstants.BUS_SFX_WEAPON)
	assert_eq(player.volume_db, 0.0)
	assert_eq(player.pitch_scale, 1.0)
	player.stop()
	player.finished.emit()
	assert_false(player.is_queued_for_deletion(), "Pooled players are reused, not freed.")
	assert_eq(SfxManager.get_sfx_pool_players().size(), pool_size)


## #1139: the firer no longer sets the viewport-wide default texture filter; the project
## setting (nearest) decides it.
func test_firer_does_not_change_viewport_texture_filter() -> void:
	var viewport := get_viewport()
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	var another: Node2D = add_child_autofree(BULLET_SCENE.instantiate())
	assert_true(another.fire())
	assert_eq(
		viewport.canvas_item_default_texture_filter,
		Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR,
		"A firer must not write the viewport's default texture filter."
	)
	assert_eq(
		ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter"),
		0,
		"Projectiles rely on the project-wide nearest filter."
	)


## A fresh resource has no assets (#1150): firing with it spawns an untextured projectile
## and plays no sound, and default_bullet.tres keeps its own assets.
func test_fresh_resource_fires_without_inheriting_default_assets() -> void:
	var fresh := BulletResource.new()
	firer.config = fresh

	assert_true(firer.fire())
	assert_eq(firer.config, fresh)
	var projectiles := _projectiles()
	assert_eq(projectiles.size(), 1)
	if projectiles.size() == 1:
		var sprite := _child_of_type(projectiles[0], "Sprite2D") as Sprite2D
		assert_not_null(sprite)
		if sprite:
			assert_null(sprite.texture)
	assert_eq(_root_sound_players().size(), 0, "A fresh resource explicitly means silent firing.")
	assert_false(SfxManager.is_any_sfx_playing(), "A fresh resource must not use the SFX pool.")
	var defaults: BulletResource = load("res://config_resources/default_bullet.tres")
	assert_not_null(defaults.projectile_texture, "Silent firing must not modify shared defaults.")
	assert_not_null(defaults.shot_sound)
