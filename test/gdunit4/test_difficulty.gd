## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# test_difficulty.gd (extends GdUnitTestSuite)
# Unit tests for difficulty scaling in player.gd using GdUnit4.

extends GdUnitTestSuite

const PlayerScene: PackedScene = preload("res://scenes/Player.tscn")
const PlayerScript = preload("res://scripts/entities/player.gd")
const GameSettingsResource = preload("res://scripts/resources/game_settings_resource.gd")


## The live settings resource, swapped out for each test and put back afterwards.
var _original_settings: GameSettingsResource


## Gives each test a fresh settings resource, like the GUT player suites do. Every write
## during the test (difficulty, max_fuel, and the player's fuel bridge mirroring
## current_fuel until #1143) lands on that copy, so nothing leaks into later suites.
func before_test() -> void:
	_original_settings = Globals.settings
	Globals.settings = GameSettingsResource.new()


func after_test() -> void:
	Globals.settings = _original_settings


## Tests fuel depletion scaling with difficulty levels.
func test_fuel_depletion_with_difficulty() -> void:
	# Statically type the settings resource to eliminate all UNSAFE_PROPERTY_ACCESS warnings
	var settings: GameSettingsResource = Globals.settings as GameSettingsResource
	assert_object(settings).is_not_null()

	# Statically type player node
	var player_inst: PlayerScript = auto_free(PlayerScene.instantiate()) as PlayerScript
	add_child(player_inst)
	await await_idle_frame()

	# Fuel state lives on the player's FuelResource; the settings resource holds tuning only.
	var fuel: FuelResource = player_inst.fuel_resource
	var start_fuel: float = fuel.max_fuel

	# 1. Test Difficulty 1.0
	fuel.current_fuel = start_fuel
	settings.difficulty = 1.0

	var normalized_speed: float = player_inst.current_speed / settings.max_speed
	var dep_1: float = settings.base_consumption_rate * normalized_speed * settings.difficulty

	player_inst._on_fuel_timer_timeout()
	assert_float(fuel.current_fuel).is_equal_approx(start_fuel - dep_1, 0.01)

	# 2. Test Difficulty 2.0
	fuel.current_fuel = start_fuel
	settings.difficulty = 2.0

	normalized_speed = player_inst.current_speed / settings.max_speed
	var dep_2: float = settings.base_consumption_rate * normalized_speed * settings.difficulty

	player_inst._on_fuel_timer_timeout()
	assert_float(fuel.current_fuel).is_equal_approx(start_fuel - dep_2, 0.01)

	# 3. Test Difficulty 0.5
	fuel.current_fuel = start_fuel
	settings.difficulty = 0.5

	normalized_speed = player_inst.current_speed / settings.max_speed
	var dep_05: float = settings.base_consumption_rate * normalized_speed * settings.difficulty

	player_inst._on_fuel_timer_timeout()
	assert_float(fuel.current_fuel).is_equal_approx(start_fuel - dep_05, 0.01)
