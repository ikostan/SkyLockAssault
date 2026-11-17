## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
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

## #1146: fire_rate and damage live only in BulletResource, so WeaponResource must not
## bring back the mirror fields that switch_to() used to copy into.
func test_has_no_firing_tuning_fields() -> void:
	assert_false("fire_rate" in weapon_res, "fire_rate belongs to BulletResource.")
	assert_false("damage" in weapon_res, "damage belongs to BulletResource.")


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
	gut.p("Testing: Removing available weapons safely clamps the current_index and emits signal.")
	weapon_res.available_weapons = ["Cannon", "Missile", "Laser"]
	weapon_res.current_index = 2 # Selected Laser
	
	# Start watching after setup to isolate the clamping emission
	watch_signals(weapon_res)
	
	# Shrink the inventory
	weapon_res.available_weapons = ["Cannon"]
	
	assert_eq(weapon_res.current_index, 0, "Index must clamp down when weapons are removed.")
	
	# Assert the UI was notified of the clamp
	assert_signal_emitted_with_parameters(weapon_res, "weapon_swapped", [0, "Cannon"])
	assert_signal_emit_count(
		weapon_res, 
		"weapon_swapped", 
		1, 
		"Clamping the index must emit weapon_swapped exactly once."
	)

# ==========================================
# SINGLE-NAME LOOKUP (#1150)
# ==========================================

## get_weapon_name() returns the name at each valid index.
func test_get_weapon_name_returns_names_by_index() -> void:
	weapon_res.available_weapons = ["Cannon", "Missile", "Laser"]
	assert_eq(weapon_res.get_weapon_name(0), "Cannon")
	assert_eq(weapon_res.get_weapon_name(1), "Missile")
	assert_eq(weapon_res.get_weapon_name(2), "Laser")


## Out-of-range indexes return "None" instead of failing.
func test_get_weapon_name_out_of_range_returns_none(
	index: int = use_parameters([-1, -50, 2, 99])
) -> void:
	weapon_res.available_weapons = ["Cannon", "Missile"]
	assert_eq(weapon_res.get_weapon_name(index), "None", "Index %d must return 'None'." % index)
	assert_eq(WeaponResource.NO_WEAPON_NAME, "None")


## Assigning an empty list stores the "None" placeholder, which get_weapon_name() returns.
func test_get_weapon_name_after_empty_list() -> void:
	weapon_res.available_weapons = []
	assert_eq(weapon_res.get_weapon_name(0), "None")
	assert_eq(weapon_res.get_weapon_name(1), "None")
	assert_eq(weapon_res.available_weapons, ["None"] as Array[String])


## A new resource starts with the export default, and the lookup reads the same list
## the getter returns (they share one internal array).
func test_default_weapon_list_matches_lookup() -> void:
	assert_eq(weapon_res.available_weapons, ["Machine Gun"] as Array[String])
	assert_eq(weapon_res.get_weapon_name(0), "Machine Gun")
	assert_eq(weapon_res.current_index, 0)


## get_weapon_name() returns a String, so changing it can't change the stored list.
func test_get_weapon_name_result_does_not_alias_list() -> void:
	weapon_res.available_weapons = ["Cannon"]
	var weapon_name: String = weapon_res.get_weapon_name(0)
	weapon_name += " Mk2"
	assert_eq(weapon_res.get_weapon_name(0), "Cannon")


## The exported list and index still save to and load from a .tres file through
## the setter and getter, now that the list lives in an internal array.
func test_weapon_list_survives_save_and_load() -> void:
	var path: String = "user://test_weapon_resource_round_trip.tres"
	weapon_res.available_weapons = ["Cannon", "Missile", "Laser"]
	weapon_res.current_index = 2
	assert_eq(ResourceSaver.save(weapon_res, path), OK)

	var loaded: WeaponResource = ResourceLoader.load(
		path, "", ResourceLoader.CACHE_MODE_IGNORE
	) as WeaponResource
	DirAccess.remove_absolute(path)

	assert_not_null(loaded)
	if loaded == null:
		return
	assert_eq(loaded.available_weapons, ["Cannon", "Missile", "Laser"] as Array[String])
	assert_eq(loaded.current_index, 2)
	assert_eq(loaded.get_weapon_name(loaded.current_index), "Laser")


## Resource.duplicate() copies the list, and the copy doesn't share it with the original.
func test_duplicate_copies_weapon_list() -> void:
	weapon_res.available_weapons = ["Cannon", "Missile"]
	weapon_res.current_index = 1
	var copy: WeaponResource = weapon_res.duplicate() as WeaponResource

	assert_eq(copy.available_weapons, ["Cannon", "Missile"] as Array[String])
	assert_eq(copy.get_weapon_name(copy.current_index), "Missile")
	copy.available_weapons = ["Laser"]
	assert_eq(weapon_res.get_weapon_name(1), "Missile", "The original must keep its own list.")


## weapon_swapped carries the same names as before the lookup was added, on every path:
## an index change, a list change at the same index, and a clamp after shrinking.
func test_weapon_swapped_names_on_every_path() -> void:
	weapon_res.available_weapons = ["Cannon", "Missile", "Laser"]
	watch_signals(weapon_res)

	weapon_res.current_index = 2
	weapon_res.available_weapons = ["Cannon", "Missile", "Railgun"]
	weapon_res.available_weapons = ["Pistol"]

	assert_signal_emit_count(weapon_res, "weapon_swapped", 3)
	assert_signal_emitted_with_parameters(weapon_res, "weapon_swapped", [2, "Laser"], 0)
	assert_signal_emitted_with_parameters(weapon_res, "weapon_swapped", [2, "Railgun"], 1)
	assert_signal_emitted_with_parameters(weapon_res, "weapon_swapped", [0, "Pistol"], 2)


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


## Read-only lookups, including misses, must not select weapons or notify the HUD.
func test_lookup_does_not_change_selection_or_emit_signals() -> void:
	weapon_res.available_weapons = ["Cannon", "Missile"]
	weapon_res.current_index = 1
	watch_signals(weapon_res)

	assert_eq(weapon_res.get_weapon_name(0), "Cannon")
	assert_eq(weapon_res.get_weapon_name(-1), "None")
	assert_eq(weapon_res.get_weapon_name(2), "None")
	assert_eq(weapon_res.current_index, 1)
	assert_eq(weapon_res.get_weapon_name(1), "Missile")
	assert_signal_not_emitted(weapon_res, "weapon_swapped")
	assert_signal_not_emitted(weapon_res, "ammo_updated")


## Clearing an inventory must clamp a selected last slot and notify exactly once.
func test_empty_assignment_clamps_selection_and_can_be_repopulated() -> void:
	weapon_res.available_weapons = ["Cannon", "Missile"]
	weapon_res.current_index = 1
	watch_signals(weapon_res)

	weapon_res.available_weapons = []
	assert_eq(weapon_res.current_index, 0)
	assert_eq(weapon_res.get_weapon_name(0), "None")
	assert_signal_emitted_with_parameters(weapon_res, "weapon_swapped", [0, "None"], 0)

	weapon_res.available_weapons = []
	assert_signal_emit_count(weapon_res, "weapon_swapped", 1, "Repeated clear is a no-op.")
	weapon_res.available_weapons = ["Railgun"]
	assert_eq(weapon_res.get_weapon_name(0), "Railgun")
	assert_signal_emit_count(weapon_res, "weapon_swapped", 2)
	assert_signal_emitted_with_parameters(weapon_res, "weapon_swapped", [0, "Railgun"], 1)


## Even identical names in different slots must announce an effective index change.
func test_shrink_emits_when_clamped_weapon_has_same_name() -> void:
	weapon_res.available_weapons = ["Cannon", "Cannon"]
	weapon_res.current_index = 1
	watch_signals(weapon_res)

	weapon_res.available_weapons = ["Cannon"]

	assert_eq(weapon_res.current_index, 0)
	assert_eq(weapon_res.get_weapon_name(0), "Cannon")
	assert_signal_emit_count(weapon_res, "weapon_swapped", 1)
	assert_signal_emitted_with_parameters(weapon_res, "weapon_swapped", [0, "Cannon"])


## Copies at both array boundaries must also protect the direct lookup path.
func test_lookup_is_isolated_from_input_and_output_array_edits() -> void:
	var supplied: Array[String] = ["Cannon", "Missile"]
	weapon_res.available_weapons = supplied
	weapon_res.current_index = 1
	var returned: Array[String] = weapon_res.available_weapons
	watch_signals(weapon_res)

	supplied[1] = "External input"
	returned[1] = "External output"
	returned.append("Extra slot")

	assert_eq(weapon_res.get_weapon_name(1), "Missile")
	assert_eq(weapon_res.get_weapon_name(2), "None")
	assert_eq(weapon_res.current_index, 1)
	assert_signal_not_emitted(weapon_res, "weapon_swapped")


## The new backing array must belong to each instance, including default instances.
func test_weapon_lists_are_isolated_between_instances() -> void:
	var other := WeaponResource.new()
	weapon_res.available_weapons = ["Cannon", "Missile"]
	weapon_res.current_index = 1
	assert_eq(other.get_weapon_name(0), "Machine Gun")
	assert_eq(other.get_weapon_name(1), "None")
	assert_eq(other.current_index, 0)


## Names are opaque data; lookup must preserve empty strings, case and whitespace.
func test_lookup_preserves_weapon_name_text() -> void:
	weapon_res.available_weapons = ["", " Heavy Laser ", "MiXeD"]
	assert_eq(weapon_res.get_weapon_name(0), "")
	assert_eq(weapon_res.get_weapon_name(1), " Heavy Laser ")
	assert_eq(weapon_res.get_weapon_name(2), "MiXeD")
