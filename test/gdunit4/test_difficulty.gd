## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
# test_difficulty.gd (extends GdUnitTestSuite)
# Unit tests for difficulty scaling in player.gd using GdUnit4.

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


## Tests fuel depletion scaling with difficulty levels.
func test_fuel_depletion_with_difficulty() -> void:
	# Statically type the settings resource to eliminate all UNSAFE_PROPERTY_ACCESS warnings
	var settings: GameSettingsResource = Globals.settings as GameSettingsResource
	assert_object(settings).is_not_null()

	# Statically type player node
	var player_inst: PlayerScript = auto_free(PlayerScene.instantiate()) as PlayerScript
	add_child(player_inst)
	await await_idle_frame()

	var start_fuel: float = settings.max_fuel

	# 1. Test Difficulty 1.0
	settings.current_fuel = start_fuel
	settings.difficulty = 1.0

	var normalized_speed: float = player_inst.current_speed / settings.max_speed
	var dep_1: float = settings.base_consumption_rate * normalized_speed * settings.difficulty

	player_inst._on_fuel_timer_timeout()
	assert_float(settings.current_fuel).is_equal_approx(start_fuel - dep_1, 0.01)

	# 2. Test Difficulty 2.0
	settings.current_fuel = start_fuel
	settings.difficulty = 2.0

	normalized_speed = player_inst.current_speed / settings.max_speed
	var dep_2: float = settings.base_consumption_rate * normalized_speed * settings.difficulty

	player_inst._on_fuel_timer_timeout()
	assert_float(settings.current_fuel).is_equal_approx(start_fuel - dep_2, 0.01)

	# 3. Test Difficulty 0.5
	settings.current_fuel = start_fuel
	settings.difficulty = 0.5

	normalized_speed = player_inst.current_speed / settings.max_speed
	var dep_05: float = settings.base_consumption_rate * normalized_speed * settings.difficulty

	player_inst._on_fuel_timer_timeout()
	assert_float(settings.current_fuel).is_equal_approx(start_fuel - dep_05, 0.01)
