## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## Exercise the real player's _ready() with the existing lightweight scene fixture.
extends "res://addons/gut/test.gd"

const PLAYER_HELPER = preload("res://test/gut/gut_test_helper.gd")
const DEFAULT_STATS = preload("res://config_resources/default_player_stats.tres")

var _original_settings: GameSettingsResource
var _viewport: SubViewport


func before_each() -> void:
	_original_settings = Globals.settings
	Globals.settings = GameSettingsResource.new()
	Globals.settings.current_log_level = Globals.LogLevel.NONE
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1000, 600)
	# _ready still runs; fuel, physics, and animations cannot advance between assertions.
	_viewport.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_viewport)


func after_each() -> void:
	# Disconnect players from the isolated settings before restoring the singleton.
	_viewport.free()
	Globals.settings = _original_settings


func _config(scale_value: float, fallback: Vector2) -> PlayerStatsResource:
	var config := PlayerStatsResource.new()
	config.hitbox_scale = scale_value
	config.fallback_sprite_size = fallback
	return config


func _texture(size: Vector2) -> Texture2D:
	var texture := PlaceholderTexture2D.new()
	texture.size = size
	return texture


func _spawn(config: PlayerStatsResource, texture: Texture2D) -> Node2D:
	var fixture := PLAYER_HELPER.build_mock_player_scene()
	var player: Node2D = fixture.get_node("Player")
	# Only the player participates in these tests; discard the helper's HUD siblings.
	fixture.remove_child(player)
	fixture.free()
	player.stats = config
	var sprite: Sprite2D = player.get_node("CharacterBody2D/Sprite2D")
	sprite.texture = texture
	_viewport.add_child(player)
	return player


func _assert_bounds(player: Node2D, expected: Vector4) -> void:
	# Literal expected values keep the oracle independent of the production formula.
	assert_almost_eq(player.player_x_min, expected.x, 0.001, "Left boundary")
	assert_almost_eq(player.player_x_max, expected.y, 0.001, "Right boundary")
	assert_almost_eq(player.player_y_min, expected.z, 0.001, "Top boundary")
	assert_almost_eq(player.player_y_max, expected.w, 0.001, "Bottom boundary")


func test_unassigned_stats_use_shipped_defaults_with_texture() -> void:
	var player := _spawn(null, _texture(Vector2(200, 80)))
	assert_eq(player.stats, DEFAULT_STATS)
	assert_eq(player.screen_size, Vector2(1000, 600))
	_assert_bounds(player, Vector4(-450, 450, -478, 80))


func test_unassigned_stats_and_missing_texture_preserve_legacy_margins() -> void:
	var player := _spawn(null, null)
	assert_eq(player.stats, DEFAULT_STATS)
	_assert_bounds(player, Vector4(-456.5, 456.5, -465, 67))


func test_custom_stats_are_preserved_and_texture_overrides_fallback() -> void:
	var config := _config(0.5, Vector2(900, 700))
	var player := _spawn(config, _texture(Vector2(200, 80)))
	assert_eq(player.stats, config, "The Inspector-assigned resource must be retained.")
	_assert_bounds(player, Vector4(-400, 400, -458, 60))
	assert_eq(config.hitbox_scale, 0.5, "Spawning must not rewrite authored values.")
	assert_eq(config.fallback_sprite_size, Vector2(900, 700))


func test_missing_texture_uses_custom_fallback_on_both_axes() -> void:
	var player := _spawn(_config(0.5, Vector2(120, 40)), null)
	_assert_bounds(player, Vector4(-440, 440, -478, 80))


func test_hitbox_scale_range_and_smallest_editor_step(
	case: Array = use_parameters([
		[0.0, Vector4(-500, 500, -498, 100)],
		[0.01, Vector4(-498, 498, -497.2, 99.2)],
		[1.0, Vector4(-300, 300, -418, 20)],
	])
) -> void:
	var player := _spawn(_config(case[0], Vector2(200, 80)), null)
	_assert_bounds(player, case[1])


func test_zero_fallback_size_adds_no_margin() -> void:
	var player := _spawn(_config(1.0, Vector2.ZERO), null)
	_assert_bounds(player, Vector4(-500, 500, -498, 100))


func test_bounds_use_actual_viewport_dimensions() -> void:
	_viewport.size = Vector2i(800, 480)
	var player := _spawn(_config(0.5, Vector2(120, 40)), null)
	assert_eq(player.screen_size, Vector2(800, 480))
	_assert_bounds(player, Vector4(-340, 340, -378.4, 60))


func test_players_with_different_configs_have_independent_bounds() -> void:
	var custom := _spawn(_config(0.5, Vector2(120, 40)), null)
	var default_player := _spawn(null, null)
	_assert_bounds(custom, Vector4(-440, 440, -478, 80))
	_assert_bounds(default_player, Vector4(-456.5, 456.5, -465, 67))
	assert_eq(DEFAULT_STATS.hitbox_scale, 0.25)
	assert_eq(DEFAULT_STATS.fallback_sprite_size, Vector2(174, 132))


func test_runtime_config_changes_apply_only_to_subsequent_spawns() -> void:
	var config := _config(0.5, Vector2(120, 40))
	var original := _spawn(config, null)
	_assert_bounds(original, Vector4(-440, 440, -478, 80))
	config.hitbox_scale = 1.0
	config.fallback_sprite_size = Vector2(200, 80)
	await get_tree().process_frame
	var next := _spawn(config, null)
	assert_eq(original.stats, config)
	assert_eq(next.stats, config)
	_assert_bounds(original, Vector4(-440, 440, -478, 80))
	_assert_bounds(next, Vector4(-300, 300, -418, 20))
