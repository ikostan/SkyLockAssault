# test_weapon_difficulty.gd (extends GdUnitTestSuite)
extends GdUnitTestSuite

func test_weapon_cooldown_with_difficulty() -> void:
	# Setup: Instance weapon, add to tree for _ready(), and save original difficulty
	var original_difficulty: float = Globals.difficulty
	var weapon_inst: Variant = auto_free(load("res://scenes/weapon.tscn").instantiate())
	add_child(weapon_inst)  # Triggers _ready() to init timer
	
	# Spy on _fire() to avoid actual bullet add (prevents orphans in CI)
	var fire_spy: Variant = spy(weapon_inst)
	
	# Normal (1.0) — cooldown = base 0.5
	Globals.difficulty = 1.0
	weapon_inst._fire()
	assert_float(weapon_inst.timer.wait_time).is_equal(0.5)
	
	# Hard (2.0) — doubled cooldown (1.0)
	Globals.difficulty = 2.0
	weapon_inst._fire()
	assert_float(weapon_inst.timer.wait_time).is_equal(1.0)
	
	# Easy (0.5) — halved cooldown (0.25)
	Globals.difficulty = 0.5
	weapon_inst._fire()
	assert_float(weapon_inst.timer.wait_time).is_equal(0.25)
	
	# Verify spy calls (optional, for learning)
	verify(fire_spy, 3)._fire()
	
	# Reset original
	Globals.difficulty = original_difficulty
