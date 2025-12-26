# test_difficulty_integration.gd (extends GdUnitTestSuite) - FIXED: fire() + bullet timer path/math
# Updated for speed-scaled fuel depletion (issue: outdated fixed assert)

extends GdUnitTestSuite

const TestHelpers = preload("res://test/test_helpers.gd")

func test_difficulty_scales_fuel_and_weapon() -> void:
	# Setup: Load main_scene for full context (PlayerStatsPanel for fuel_bar path)
	var main_scene: Variant = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)  # Add to tree for _ready() (init timers, paths)
	# Await frame to ensure @onready vars set (fixes null in tests/CI)
	await await_idle_frame()
	
	# Get player and weapon (correct path per player.tscn: Player/CharacterBody2D/Weapon)
	var player: Node2D = main_scene.get_node("Player")
	assert_object(player).is_not_null()  
	var weapon: Node2D = player.get_node("CharacterBody2D/Weapon")
	assert_object(weapon).is_not_null()
	
	var original_difficulty: float = Globals.difficulty
	Globals.difficulty = 2.0

	# TEST 1: Fuel depletion scales (derive from constants)
	player.fuel["fuel"] = 100.0
	var normalized_speed: float = player.speed["speed"] / player.MAX_SPEED
	var expected_depletion: float = player.base_fuel_drain * normalized_speed * Globals.difficulty
	player._on_fuel_timer_timeout()
	var expected_fuel: float = 100.0 - expected_depletion
	assert_float(player.fuel["fuel"]).is_equal_approx(expected_fuel, 0.01)  # Larger delta for precision

	# TEST 2: Weapon cooldown scales (fire_rate 0.15 * 2.0 = 0.30)
	weapon.fire()  # FIXED: fire() not _fire(); delegates → BulletFirer.fire() → timer.start(0.30)
	var bullet_firer: Node2D = weapon.get_child(0)  # Weapon child 0 = BulletFirer
	var cooldown_timer: Timer = bullet_firer.get_node("CooldownTimer")
	assert_float(cooldown_timer.wait_time).is_equal_approx(0.30, 0.001)  # Tolerance for float

	Globals.difficulty = original_difficulty
