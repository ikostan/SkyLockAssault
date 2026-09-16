## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_weapon_resource.gd
##
## GUT unit tests for WeaponResource.
## Validates array bounds, ammo clamping, and signal crossing semantics.

extends "res://addons/gut/test.gd"

var weapon_res: WeaponResource

func before_each() -> void:
	weapon_res = WeaponResource.new()
	watch_signals(weapon_res)

func after_each() -> void:
	weapon_res.free()

# ==========================================
# BOUNDARY & INVARIANT TESTS
# ==========================================

func test_ammo_clamps_to_bounds() -> void:
	gut.p("Testing: current_ammo cannot exceed [0, max_ammo].")
	weapon_res.max_ammo = 100
	
	weapon_res.current_ammo = 150
	assert_eq(weapon_res.current_ammo, 100, "current_ammo should clamp to max_ammo.")
	
	weapon_res.current_ammo = -10
	assert_eq(weapon_res.current_ammo, 0, "current_ammo should clamp to 0.")


func test_max_ammo_clamps_current_ammo() -> void:
	gut.p("Testing: Shrinking max_ammo clamps current_ammo and emits signal.")
	weapon_res.max_ammo = 100
	weapon_res.current_ammo = 100
	watch_signals(weapon_res)
	
	weapon_res.max_ammo = 50
	assert_eq(weapon_res.current_ammo, 50, "current_ammo must shrink to new max_ammo.")
	assert_signal_emitted_with_parameters(weapon_res, "ammo_updated", [50, 50])


func test_weapon_index_clamps_to_available_array() -> void:
	gut.p("Testing: current_index clamps based on available_weapons array bounds.")
	weapon_res.available_weapons = ["Cannon", "Missile", "Laser"]
	
	weapon_res.current_index = 5
	assert_eq(weapon_res.current_index, 2, "Index must clamp to array size - 1.")
	
	weapon_res.current_index = -3
	assert_eq(weapon_res.current_index, 0, "Index must clamp to 0.")


func test_shrinking_array_clamps_current_index() -> void:
	gut.p("Testing: Removing available weapons safely clamps the current_index.")
	weapon_res.available_weapons = ["Cannon", "Missile", "Laser"]
	weapon_res.current_index = 2 # Selected Laser
	
	# Shrink the inventory
	weapon_res.available_weapons = ["Cannon"]
	assert_eq(weapon_res.current_index, 0, "Index must clamp down when weapons are removed.")

# ==========================================
# SIGNAL CROSSING SEMANTICS
# ==========================================

func test_ammo_updated_emits_on_effective_change() -> void:
	gut.p("Testing: ammo_updated strictly emits only on effective state change.")
	weapon_res.max_ammo = 100
	weapon_res.current_ammo = 50
	
	assert_signal_emitted_with_parameters(weapon_res, "ammo_updated", [50, 100])
	
	watch_signals(weapon_res)
	
	weapon_res.current_ammo = 50
	assert_signal_not_emitted(weapon_res, "ammo_updated", "Reassigning the same value must not emit.")


func test_weapon_swapped_emits_correctly() -> void:
	gut.p("Testing: weapon_swapped emits with correct index and name.")
	weapon_res.available_weapons = ["Cannon", "Missile"]
	weapon_res.current_index = 0
	watch_signals(weapon_res)
	
	weapon_res.current_index = 1
	assert_signal_emitted_with_parameters(
		weapon_res, 
		"weapon_swapped", 
		[1, "Missile"], 
		"Signal must provide correct index and weapon name."
	)
	
	watch_signals(weapon_res)
	weapon_res.current_index = 1
	assert_signal_not_emitted(weapon_res, "weapon_swapped", "Identical index must not emit.")
