## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
##
## test_difficulty_integration.gd
## Integration tests for difficulty scaling across Player fuel depletion
## and Weapon cooldown systems (Godot 4.7.1 + GdUnit4).

extends GdUnitTestSuite

const PlayerScene: PackedScene = preload("res://scenes/Player.tscn")
const PlayerScript = preload("res://scripts/entities/player.gd")
const GameSettingsResource = preload("res://scripts/resources/game_settings_resource.gd")

## The live settings resource, swapped out for each test and put back afterwards.
var _original_settings: GameSettingsResource


## Gives each test a fresh settings resource, like the GUT player suites do. Every write
## during the test (difficulty, max_fuel) lands on that copy, so nothing leaks into later
## suites.
func before_test() -> void:
	_original_settings = Globals.settings
	Globals.settings = GameSettingsResource.new()


func after_test() -> void:
	Globals.settings = _original_settings


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

	# Fuel state lives on the player's FuelResource; the settings resource holds tuning only.
	var fuel: FuelResource = player.fuel_resource
	var start_fuel: float = fuel.max_fuel
	fuel.current_fuel = start_fuel

	# --- TEST 1: Fuel depletion scales with difficulty ---
	var normalized_speed: float = player.current_speed / settings.max_speed
	var expected_depletion: float = (
		settings.base_consumption_rate * normalized_speed * settings.difficulty
	)

	player._on_fuel_timer_timeout()

	var expected_fuel: float = start_fuel - expected_depletion
	assert_float(fuel.current_fuel).is_equal_approx(expected_fuel, 0.01)

	# --- TEST 2: Weapon cooldown scales with difficulty ---
	# Expected: base fire_rate 0.15 * difficulty 2.0 = 0.30
	weapon.fire()
	var bullet_firer: Node2D = weapon.get_child(0)
	var cooldown_timer: Timer = bullet_firer.get_node("CooldownTimer") as Timer
	assert_float(cooldown_timer.wait_time).is_equal_approx(0.30, 0.001)


## Confirms the directions documented at GameSettingsResource.difficulty (#1151): higher
## difficulty lengthens the fire cooldown, burns fuel faster and scrolls faster. Lower
## difficulty does the opposite.
func test_higher_difficulty_lengthens_cooldown_burns_fuel_and_scrolls_faster() -> void:
	var settings: GameSettingsResource = Globals.settings as GameSettingsResource
	var player: PlayerScript = auto_free(PlayerScene.instantiate()) as PlayerScript
	add_child(player)
	await await_idle_frame()
	var weapon: Weapon = player.weapon
	var fuel: FuelResource = player.fuel_resource

	var parallax: ParallaxManager = auto_free(ParallaxManager.new()) as ParallaxManager
	add_child(parallax)
	parallax.set_process(false)
	parallax.setup(player.speed_resource, fuel, settings)

	var cooldowns: Array[float] = []
	var burns: Array[float] = []
	var scrolls: Array[float] = []
	for difficulty: float in [0.5, 1.0, 2.0]:
		settings.difficulty = difficulty

		var firer: Node2D = weapon.current_weapon
		var cooldown_timer: Timer = firer.get_node("CooldownTimer") as Timer
		firer.can_fire = true
		weapon.fire()
		cooldowns.append(cooldown_timer.wait_time)

		fuel.current_fuel = fuel.max_fuel
		player._on_fuel_timer_timeout()
		burns.append(fuel.max_fuel - fuel.current_fuel)

		parallax.scroll_offset = Vector2.ZERO
		parallax._process(0.1)
		scrolls.append(parallax.scroll_offset.y)

	for i: int in range(1, 3):
		assert_float(cooldowns[i]).is_greater(cooldowns[i - 1])
		assert_float(burns[i]).is_greater(burns[i - 1])
		assert_float(scrolls[i]).is_greater(scrolls[i - 1])
	# Each effect is proportional to difficulty: 2.0 is twice Normal.
	assert_float(cooldowns[2]).is_equal_approx(cooldowns[1] * 2.0, 0.0001)
	assert_float(burns[2]).is_equal_approx(burns[1] * 2.0, 0.0001)
	assert_float(scrolls[2]).is_equal_approx(scrolls[1] * 2.0, 0.0001)
