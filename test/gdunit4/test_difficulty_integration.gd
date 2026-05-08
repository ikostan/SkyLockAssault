## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
# test_difficulty_integration.gd (extends GdUnitTestSuite) - FIXED: fire() + bullet timer path/math
# Updated for speed-scaled fuel depletion (issue: outdated fixed assert)

extends GdUnitTestSuite

const TestHelpers = preload("res://test/gdunit4/test_helpers.gd")

var original_difficulty: float  # Snapshot holder
# NEW: Added snapshot holders for global fuel state to prevent test leakage
var original_current_fuel: float
var original_max_fuel: float


func before_test() -> void:
	original_difficulty = Globals.settings.difficulty  # Snapshot before each test
	# NEW: Snapshot fuel state
	original_current_fuel = Globals.settings.current_fuel
	original_max_fuel = Globals.settings.max_fuel


func after_test() -> void:
	Globals.settings.difficulty = original_difficulty  # Restore after each test
	# NEW: Restore fuel state so other tests start clean
	Globals.settings.max_fuel = original_max_fuel
	Globals.settings.current_fuel = original_current_fuel


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
	
	var original_difficulty: float = Globals.settings.difficulty
	Globals.settings.difficulty = 2.0

	# NEW: Derive the starting baseline dynamically to avoid clamping issues if max_fuel changed
	var start_fuel: float = Globals.settings.max_fuel

	# TEST 1: Fuel depletion scales (derive from constants)
	# OLD: player.fuel["fuel"] = 100.0
	# NEW: Set the fuel level using the dynamic baseline instead of hardcoded 100.0
	Globals.settings.current_fuel = start_fuel
	
	# NEW: Calculate normalized speed using the global max_speed, as MAX_SPEED was removed from player.gd
	var normalized_speed: float = player.current_speed / Globals.settings.max_speed
	
	# OLD: var expected_depletion: float = player.base_fuel_drain * normalized_speed * Globals.settings.difficulty
	# NEW: Reference base_consumption_rate from the global resource since it was removed from the player script
	var expected_depletion: float = Globals.settings.base_consumption_rate * normalized_speed * Globals.settings.difficulty
	
	player._on_fuel_timer_timeout()
	var expected_fuel: float = start_fuel - expected_depletion
	
	# OLD: assert_float(player.fuel["fuel"]).is_equal_approx(expected_fuel, 0.01)  # Larger delta for precision
	# NEW: Verify the depletion amount against the global resource current_fuel
	assert_float(Globals.settings.current_fuel).is_equal_approx(expected_fuel, 0.01)  # Larger delta for precision

	# TEST 2: Weapon cooldown scales (fire_rate 0.15 * 2.0 = 0.30)
	weapon.fire()  # FIXED: fire() not _fire(); delegates → BulletFirer.fire() → timer.start(0.30)
	var bullet_firer: Node2D = weapon.get_child(0)  # Weapon child 0 = BulletFirer
	var cooldown_timer: Timer = bullet_firer.get_node("CooldownTimer")
	assert_float(cooldown_timer.wait_time).is_equal_approx(0.30, 0.001)  # Tolerance for float

	Globals.settings.difficulty = original_difficulty
