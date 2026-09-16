## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## weapon_resource.gd
##
## DATA CONTAINER: Manages weapon states, ammo, and firing configurations.
## Operates as an independent, platform-agnostic Subject in the Observer Pattern.
class_name WeaponResource
extends Resource

## Emitted strictly when the active weapon index changes.
signal weapon_swapped(index: int, weapon_name: String)

## Emitted strictly when the effective ammo count changes.
signal ammo_updated(current: int, max_ammo: int)

# --- Backing Fields ---
var _available_weapons: Array[String] = ["Machine Gun"]
var _current_index: int = 0
var _max_ammo: int = 1000
var _current_ammo: int = 1000
var _fire_rate: float = 0.1
var _damage: float = 10.0

# --- State Properties ---

@export var available_weapons: Array[String] = ["Machine Gun"]:
	set(value):
		if value.is_empty():
			_available_weapons = ["None"]
		else:
			_available_weapons = value

		# Invariant: Clamp index if the new array is smaller than the current index
		if _current_index >= _available_weapons.size():
			self.current_index = max(0, _available_weapons.size() - 1)
	get:
		return _available_weapons

@export var current_index: int = 0:
	set(value):
		# Invariant: Cannot select a weapon outside the available array bounds
		var new_index: int = clampi(value, 0, max(0, _available_weapons.size() - 1))

		if _current_index == new_index:
			return

		_current_index = new_index

		var w_name: String = (
			_available_weapons[_current_index] if not _available_weapons.is_empty() else "None"
		)
		weapon_swapped.emit(_current_index, w_name)
	get:
		return _current_index

@export var max_ammo: int = 1000:
	set(value):
		var new_max: int = maxi(1, value)
		if _max_ammo == new_max:
			return

		_max_ammo = new_max

		# Invariant: Shrinking max_ammo must clamp current_ammo
		if _current_ammo > _max_ammo:
			self.current_ammo = _max_ammo
	get:
		return _max_ammo

@export var current_ammo: int = 1000:
	set(value):
		var old_ammo: int = _current_ammo
		var new_ammo: int = clampi(value, 0, _max_ammo)

		if old_ammo == new_ammo:
			return

		_current_ammo = new_ammo
		ammo_updated.emit(_current_ammo, _max_ammo)
	get:
		return _current_ammo

# --- Tuning Properties ---

@export var fire_rate: float = 0.1:
	set(value):
		_fire_rate = max(0.01, value)
	get:
		return _fire_rate

@export var damage: float = 10.0:
	set(value):
		_damage = max(0.0, value)
	get:
		return _damage


func _init() -> void:
	_current_ammo = _max_ammo
