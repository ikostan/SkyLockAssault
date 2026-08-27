## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
##
## test_difficulty_integration.gd
## Integration tests for difficulty scaling across Player fuel depletion
## and Weapon cooldown systems (Godot 4.7.1 + GdUnit4).

extends GdUnitTestSuite

const PlayerScene: PackedScene = preload("res://scenes/Player.tscn")
const PlayerScript = preload("res://scripts/entities/player.gd")
const GameSettingsResource = preload("res://scripts/resources/game_settings_resource.gd")

var original_difficulty: float
var original_current_fuel: float
var original_max_fuel: float


func before_test() -> void:
	var settings: GameSettingsResource = Globals.settings as GameSettingsResource
	original_difficulty = settings.difficulty
	original_current_fuel = settings.current_fuel
	original_max_fuel = settings.max_fuel


func after_test() -> void:
	var settings: GameSettingsResource = Globals.settings as GameSettingsResource
	settings.difficulty = original_difficulty
	settings.max_fuel = original_max_fuel
	settings.current_fuel = original_current_fuel


func test_difficulty_scales_fuel_and_weapon() -> void:
	var settings: GameSettingsResource = Globals.settings as GameSettingsResource
	assert_object(settings).is_not_null()

	# Instantiate only the Player scene (lighter than loading main_scene)
	var player: PlayerScript = auto_free(PlayerScene.instantiate()) as PlayerScript
	add_child(player)
	await await_idle_frame()

	# Support both possible Weapon locations in the scene tree
	var weapon: Node2D = player.get_node_or_null("CharacterBody2D/Weapon")
	if weapon == null:
		weapon = player.get_node_or_null("Weapon")
	assert_object(weapon).is_not_null()

	# Force a known difficulty for deterministic assertions
	settings.difficulty = 2.0

	var start_fuel: float = settings.max_fuel
	settings.current_fuel = start_fuel

	# --- TEST 1: Fuel depletion scales with difficulty ---
	var normalized_speed: float = player.current_speed / settings.max_speed
	var expected_depletion: float = (
		settings.base_consumption_rate * normalized_speed * settings.difficulty
	)

	player._on_fuel_timer_timeout()

	var expected_fuel: float = start_fuel - expected_depletion
	assert_float(settings.current_fuel).is_equal_approx(expected_fuel, 0.01)

	# --- TEST 2: Weapon cooldown scales with difficulty ---
	# Expected: base fire_rate 0.15 * difficulty 2.0 = 0.30
	weapon.fire()
	var bullet_firer: Node2D = weapon.get_child(0)
	var cooldown_timer: Timer = bullet_firer.get_node("CooldownTimer") as Timer
	assert_float(cooldown_timer.wait_time).is_equal_approx(0.30, 0.001)
