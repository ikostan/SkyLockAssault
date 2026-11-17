## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## weapon_resource.gd
##
## DATA CONTAINER: Manages weapon states and ammo.
## Operates as an independent, platform-agnostic Subject in the Observer Pattern.
## Firing tuning (fire_rate, damage) lives only in BulletResource (#1146).
class_name WeaponResource
extends Resource

## Emitted when the active weapon changes.
##
## Fires when [member current_index] changes, including when shrinking
## [member available_weapons] clamps the index. It also fires when assigning
## [member available_weapons] changes the weapon name at the current index, even
## though the index stays the same. Listeners must not treat this signal as proof
## that the index changed.
##
## [param index]: The active weapon index, which may be unchanged.
## [param weapon_name]: The name of the active weapon.
signal weapon_swapped(index: int, weapon_name: String)

## Emitted strictly when the effective ammo count changes.
##
## [param current]: The current ammo count.
## [param max_ammo]: The maximum capacity for ammo.
signal ammo_updated(current: int, max_ammo: int)

## Name returned for a missing weapon, and the placeholder list when an empty list is assigned.
const NO_WEAPON_NAME: String = "None"

# --- State Properties ---

## The weapon names. The getter returns a copy, so outside code can't change the list
## without going through the setter. Read one name with [method get_weapon_name], which
## doesn't copy the list (#1150).
@export var available_weapons: Array[String] = ["Machine Gun"]:
	set(value):
		# 1. Cache the old active weapon name
		var old_name: String = get_weapon_name(current_index)

		# 2. Update the array (with duplicate() to prevent reference mutation)
		if value.is_empty():
			_weapons = [NO_WEAPON_NAME]
		else:
			_weapons = value.duplicate()

		# 3. Check for clamping or silent swaps
		if current_index >= _weapons.size():
			# The array shrank. Triggering self.current_index will handle clamping
			# and automatically emit the signal since the index number is changing.
			self.current_index = maxi(0, _weapons.size() - 1)
		else:
			# The index stayed the same. Did the weapon name at this index change?
			var new_name: String = _weapons[current_index]
			if old_name != new_name:
				weapon_swapped.emit(current_index, new_name)
	get:
		# Protect the output boundary: return a copy so external callers cannot
		# mutate the internal array by reference and bypass the setter validations.
		return _weapons.duplicate()

@export var current_index: int = 0:
	set(value):
		# Invariant: Cannot select a weapon outside the available array bounds
		var new_index: int = clampi(value, 0, maxi(0, _weapons.size() - 1))

		if current_index == new_index:
			return

		current_index = new_index
		weapon_swapped.emit(current_index, get_weapon_name(current_index))

@export var max_ammo: int = 1000:
	set(value):
		var new_max: int = maxi(1, value)
		if max_ammo == new_max:
			return

		max_ammo = new_max

		# Invariant: Shrinking max_ammo must clamp current_ammo
		if current_ammo > max_ammo:
			self.current_ammo = max_ammo

@export var current_ammo: int = 1000:
	set(value):
		var old_ammo: int = current_ammo
		var new_ammo: int = clampi(value, 0, max_ammo)

		if old_ammo == new_ammo:
			return

		current_ammo = new_ammo
		ammo_updated.emit(current_ammo, max_ammo)

## Storage behind [member available_weapons]. Godot 4 runs a property's getter even when
## its own class reads it, and that getter copies the list, so code in this class reads
## and writes this array instead (#1150). Starts with the same value as the export default.
var _weapons: Array[String] = ["Machine Gun"]


func _init() -> void:
	current_ammo = max_ammo


## Returns the weapon name at [param index], or [constant NO_WEAPON_NAME] ("None") if the
## index is out of range. Unlike [member available_weapons], it doesn't copy the list.
##
## [param index]: The weapon index to look up.
func get_weapon_name(index: int) -> String:
	if index < 0 or index >= _weapons.size():
		return NO_WEAPON_NAME
	return _weapons[index]
