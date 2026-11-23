## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## weapon_firer.gd
##
## Base type for anything [code]Weapon[/code] can equip in one of its slots (#1138).
##
## [code]Weapon[/code] keeps one instance per slot and only hides the inactive ones, so a firer
## keeps its own cooldown state across swaps. Subclasses must override [method fire].
##
## The level injects a projectile parent through [method Weapon.set_projectile_parent], so
## anything a firer spawns is freed with that level (#1140).

class_name WeaponFirer
extends Node2D

## Display name written into [member WeaponResource.available_weapons] when the slot is
## equipped, and shown by the HUD.
@export var weapon_name: String = "Machine Gun"

## Node that receives anything this firer spawns, such as projectiles. Set by
## [method set_projectile_parent]; [code]null[/code] until the level injects one.
var projectile_parent: Node


## Sets the node that receives anything this firer spawns.
##
## The level passes its [code]Projectiles[/code] container through
## [method Weapon.set_projectile_parent]. Passing [code]null[/code] clears it.
##
## [param parent]: The level-owned container, or [code]null[/code].
func set_projectile_parent(parent: Node) -> void:
	projectile_parent = parent


## Fires one shot if the firer is ready.
##
## The base implementation only reports that a subclass forgot to override it.
## Returns [code]true[/code] only when a shot was fired.
func fire() -> bool:
	push_error("WeaponFirer.fire() must be overridden.")
	return false
