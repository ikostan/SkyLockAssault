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
	# REMOVED: watch_signals(weapon_res) -> We will only watch when needed.

func after_each() -> void:
	pass

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
	
	watch_signals(weapon_res)
	
	weapon_res.current_ammo = 50
	assert_signal_emit_count(weapon_res, "ammo_updated", 1)
	
	weapon_res.current_ammo = 50
	# FIX: Check that the total count remains 1
	assert_signal_emit_count(weapon_res, "ammo_updated", 1, "Reassigning the same value must not emit.")


func test_weapon_swapped_emits_correctly() -> void:
	gut.p("Testing: weapon_swapped emits with correct index and name.")
	weapon_res.available_weapons = ["Cannon", "Missile"]
	weapon_res.current_index = 0
	
	watch_signals(weapon_res)
	
	weapon_res.current_index = 1
	assert_signal_emitted_with_parameters(weapon_res, "weapon_swapped", [1, "Missile"])
	assert_signal_emit_count(weapon_res, "weapon_swapped", 1)
	
	weapon_res.current_index = 1
	# FIX: Check that the total count remains 1
	assert_signal_emit_count(weapon_res, "weapon_swapped", 1, "Identical index must not emit.")


func test_available_weapons_prevents_external_mutation() -> void:
	gut.p("Testing: available_weapons duplicates the input array to prevent external reference mutations.")
	
	var external_array: Array[String] = ["Laser", "Plasma", "Railgun"]
	weapon_res.available_weapons = external_array
	weapon_res.current_index = 2 # Selected Railgun
	
	# Mutate the external array (should NOT affect the resource)
	external_array.clear()
	
	assert_eq(
		weapon_res.available_weapons.size(), 
		3, 
		"Resource array must remain unchanged when the external array is mutated."
	)
	assert_eq(
		weapon_res.current_index, 
		2, 
		"current_index must not be invalidated by external array mutations."
	)


func test_replacing_array_emits_if_active_weapon_changes() -> void:
	gut.p("Testing: Replacing array emits weapon_swapped if active weapon name changes, even if index stays the same.")
	weapon_res.available_weapons = ["Pistol", "Shotgun"]
	weapon_res.current_index = 0 # Active is Pistol
	
	watch_signals(weapon_res)

	# Replace array, same size, index 0 is now "Rifle"
	weapon_res.available_weapons = ["Rifle", "Sniper"]

	assert_signal_emitted_with_parameters(weapon_res, "weapon_swapped", [0, "Rifle"])
	assert_signal_emit_count(weapon_res, "weapon_swapped", 1)


func test_replacing_array_does_not_emit_if_active_weapon_unchanged() -> void:
	gut.p("Testing: Replacing array does not emit if the active weapon name at the current index is identical.")
	weapon_res.available_weapons = ["Pistol", "Shotgun"]
	weapon_res.current_index = 0 # Active is Pistol
	
	watch_signals(weapon_res)

	# Replace array, same size, index 0 is STILL "Pistol"
	weapon_res.available_weapons = ["Pistol", "Sniper"]

	# FIX: Because watch_signals started right before this, the count should be 0
	assert_signal_emit_count(
		weapon_res,
		"weapon_swapped",
		0,
		"Must not emit weapon_swapped if the active weapon name and index remain exactly the same."
	)


func test_available_weapons_getter_prevents_external_mutation() -> void:
	gut.p("Testing: Getter returns a duplicate so external mutations do not corrupt internal state.")
	weapon_res.available_weapons = ["Pistol", "Shotgun"]
	
	# Retrieve the array and attempt to maliciously mutate it
	var retrieved_array: Array[String] = weapon_res.available_weapons
	retrieved_array.clear()
	
	# The internal array should remain completely intact
	assert_eq(
		weapon_res.available_weapons.size(), 
		2, 
		"Internal array must resist mutation from getter references."
	)
	assert_eq(weapon_res.available_weapons[0], "Pistol", "Array data must remain intact.")
