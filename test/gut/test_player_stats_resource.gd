## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## Unit tests for developer-authored player boundary configuration.
extends "res://addons/gut/test.gd"

const DEFAULT_STATS = preload("res://config_resources/default_player_stats.tres")


func test_new_resource_preserves_legacy_boundary_defaults() -> void:
	var stats := PlayerStatsResource.new()
	assert_eq(stats.hitbox_scale, 0.25)
	assert_eq(stats.fallback_sprite_size, Vector2(174.0, 132.0))


func test_shipped_resource_has_expected_type_and_defaults() -> void:
	assert_true(DEFAULT_STATS is PlayerStatsResource)
	assert_eq(DEFAULT_STATS.hitbox_scale, 0.25)
	assert_eq(DEFAULT_STATS.fallback_sprite_size, Vector2(174.0, 132.0))


func test_customizing_duplicate_does_not_modify_shipped_or_new_defaults() -> void:
	var custom := DEFAULT_STATS.duplicate() as PlayerStatsResource
	custom.hitbox_scale = 0.75
	custom.fallback_sprite_size = Vector2(320.0, 80.0)
	assert_eq(custom.hitbox_scale, 0.75)
	assert_eq(custom.fallback_sprite_size, Vector2(320.0, 80.0))
	assert_eq(DEFAULT_STATS.hitbox_scale, 0.25)
	assert_eq(DEFAULT_STATS.fallback_sprite_size, Vector2(174.0, 132.0))
	var fresh := PlayerStatsResource.new()
	assert_eq(fresh.hitbox_scale, 0.25)
	assert_eq(fresh.fallback_sprite_size, Vector2(174.0, 132.0))
