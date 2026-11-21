## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## weapon.gd
##
## Owns the player's weapon slots and the shared [code]WeaponResource[/code] (ammo, names, index).
##
## Each slot's [code]WeaponFirer[/code] is created the first time the slot is selected and kept as a
## hidden child while another slot is active, so its cooldown keeps running and a swap can't
## bypass the fire rate (#1138). The firers are freed with this node.

class_name Weapon
extends Node2D

# Added for HUD/Bot decoupling
## Emitted when the weapon is fired successfully.
##
## [param ammo_remaining]: The amount of ammunition left in the magazine after firing.
signal weapon_fired(ammo_remaining: int)

## One scene per slot. Each must instantiate as a [code]WeaponFirer[/code], such as bullet.tscn.
@export var weapon_types: Array[PackedScene] = []

## The equipped firer, or [code]null[/code] if no slot could be equipped.
var current_weapon: WeaponFirer
## Ammo, weapon names and the active slot index. [member WeaponResource.current_index] is the
## only copy of the index (#1138).
var weapon_resource: WeaponResource = WeaponResource.new()

# Cached firer per slot, indexed like weapon_types. null until the slot is first selected.
var _slots: Array[WeaponFirer] = []


func _ready() -> void:
	Globals.log_message(
		"Weapon _ready: Types size " + str(weapon_types.size()), Globals.LogLevel.DEBUG
	)
	if weapon_types.is_empty():
		push_error("Weapon: No weapon_types assigned!")
		return
	switch_to(0)


## Switch the active weapon to the specified slot.
##
## Creates the slot's firer the first time it's selected, then reuses it. The outgoing firer is
## hidden, not freed, so its cooldown keeps running. Updates the resource's weapon name and
## index, which emits [signal WeaponResource.weapon_swapped]. Firing stats stay in each
## firer's own BulletResource and are never copied or written back (#1146).
##
## An invalid index, an empty slot, or a scene that isn't a [code]WeaponFirer[/code] reports an
## error and leaves the current weapon equipped.
##
## [param index]: The array index of the weapon type to activate.
func switch_to(index: int) -> void:
	if index < 0 or index >= weapon_types.size():
		push_warning("Weapon: Invalid index " + str(index))
		return

	var scene: PackedScene = weapon_types[index]
	Globals.log_message(
		"Switching to " + str(index) + ": " + (scene.resource_path if scene else "<empty slot>"),
		Globals.LogLevel.DEBUG
	)

	var incoming: WeaponFirer = _get_or_create_slot(index)
	if incoming == null:
		return  # Already reported; the current weapon stays equipped.

	if is_instance_valid(current_weapon) and current_weapon != incoming:
		current_weapon.hide()
	incoming.show()
	current_weapon = incoming

	# Sync the resource's available_weapons array
	var updated_weapons: Array[String] = weapon_resource.available_weapons
	if updated_weapons.size() < weapon_types.size():
		updated_weapons.resize(weapon_types.size())
	updated_weapons[index] = incoming.weapon_name
	weapon_resource.available_weapons = updated_weapons

	# Update the resource index (this automatically triggers the weapon_swapped signal)
	weapon_resource.current_index = index

	Globals.log_message("Switched to " + incoming.weapon_name, Globals.LogLevel.INFO)


## Switch to the next slot, wrapping around after the last one.
##
## Does nothing when there is only one weapon (or none).
func switch_to_next() -> void:
	var count: int = weapon_types.size()
	if count <= 1:
		return
	switch_to((weapon_resource.current_index + 1) % count)


## Trigger the active weapon and deduct ammo if successful.
##
## Delegates firing to the active [code]WeaponFirer[/code], validates ammo availability strictly,
## and emits the weapon_fired signal upon success.
func fire() -> void:
	if not is_instance_valid(current_weapon):
		push_error("Weapon.fire(): no weapon equipped! Types: " + str(weapon_types.size()))
		return

	# Strictly require ammo to fire (no infinite ammo checks)
	if weapon_resource.current_ammo <= 0:
		Globals.log_message("Weapon.fire(): Out of ammo!", Globals.LogLevel.WARNING)
		return

	Globals.log_message(
		"Weapon.fire() delegating to " + str(current_weapon.name), Globals.LogLevel.DEBUG
	)

	# Deduct ammo ONLY if the weapon successfully fired a projectile
	if current_weapon.fire():
		weapon_resource.current_ammo -= 1
		weapon_fired.emit(weapon_resource.current_ammo)


## Return the total number of weapon types available.
## Returns the size of the weapon types array.
func get_num_weapons() -> int:
	return weapon_types.size()


# Returns the cached firer for a slot, creating it on first use. Returns null and reports an
# error if the slot is empty or its scene doesn't instantiate as a WeaponFirer.
func _get_or_create_slot(index: int) -> WeaponFirer:
	if _slots.size() < weapon_types.size():
		_slots.resize(weapon_types.size())
	if is_instance_valid(_slots[index]):
		return _slots[index]

	var scene: PackedScene = weapon_types[index]
	if scene == null:
		push_error("Weapon: weapon_types[" + str(index) + "] is empty!")
		return null

	var instance: Node = scene.instantiate()
	if instance == null:
		push_error(
			"Failed to instantiate weapon_types[" + str(index) + "] - check scene/script errors!"
		)
		return null

	var firer: WeaponFirer = instance as WeaponFirer
	if firer == null:
		push_error(
			(
				"Weapon: weapon_types[%d] is a %s, not a WeaponFirer! Keeping the current weapon."
				% [index, instance.get_class()]
			)
		)
		instance.free()
		return null

	firer.position = Vector2.ZERO
	firer.hide()  # switch_to() shows the active firer
	add_child(firer)
	_slots[index] = firer
	return firer
