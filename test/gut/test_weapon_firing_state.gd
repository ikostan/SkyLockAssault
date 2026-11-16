## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

extends "res://addons/gut/test.gd"

const WEAPON_SCRIPT: GDScript = preload("res://scripts/entities/weapon.gd")
const BULLET_SCENE: PackedScene = preload("res://scenes/bullet.tscn")
const BULLET_SCRIPT: GDScript = preload("res://scripts/entities/bullet.gd")

var weapon: Node2D
var child_weapon: FireResultWeapon


class FireResultWeapon extends Node2D:
	var succeeds: bool = true
	var fire_calls: int = 0

	func fire() -> bool:
		fire_calls += 1
		return succeeds


class TunedWeapon extends Node2D:
	@export var weapon_name: String = "Test Cannon"
	@export var fire_rate: float = 0.65
	@export var damage: float = 31.0


class RateOnlyWeapon extends Node2D:
	@export var fire_rate: float = 0.8


class DamageOnlyWeapon extends Node2D:
	@export var damage: float = 53.0


func before_each() -> void:
	# Keep the controller outside the tree: _ready requires an equipped scene.
	weapon = autofree(WEAPON_SCRIPT.new())
	child_weapon = FireResultWeapon.new()
	weapon.add_child(child_weapon)
	weapon.current_weapon = child_weapon
	weapon.weapon_resource.current_ammo = 3
	watch_signals(weapon)


func _pack(node: Node2D) -> PackedScene:
	var packed := PackedScene.new()
	assert_eq(packed.pack(node), OK)
	node.free()
	return packed


func test_successful_shot_emits_once_after_ammo_is_deducted() -> void:
	var observed_ammo: Array[int] = []
	weapon.weapon_fired.connect(
		func(_remaining: int) -> void: observed_ammo.append(weapon.weapon_resource.current_ammo)
	)
	weapon.fire()

	assert_eq(child_weapon.fire_calls, 1)
	assert_eq(weapon.weapon_resource.current_ammo, 2)
	assert_signal_emit_count(weapon, "weapon_fired", 1)
	assert_signal_emitted_with_parameters(weapon, "weapon_fired", [2])
	assert_eq(observed_ammo.size(), 1)
	assert_eq(observed_ammo[0], 2, "Signal listeners must observe the updated resource.")


func test_failed_shot_preserves_ammo_and_emits_nothing() -> void:
	child_weapon.succeeds = false
	weapon.fire()

	assert_eq(child_weapon.fire_calls, 1)
	assert_eq(weapon.weapon_resource.current_ammo, 3)
	assert_signal_not_emitted(weapon, "weapon_fired")


func test_empty_magazine_does_not_delegate_or_emit() -> void:
	weapon.weapon_resource.current_ammo = 0
	weapon.fire()

	assert_eq(child_weapon.fire_calls, 0)
	assert_eq(weapon.weapon_resource.current_ammo, 0)
	assert_signal_not_emitted(weapon, "weapon_fired")


func test_last_round_emits_zero_once_and_blocks_subsequent_shot() -> void:
	weapon.weapon_resource.current_ammo = 1
	weapon.fire()
	weapon.fire()

	assert_eq(child_weapon.fire_calls, 1)
	assert_eq(weapon.weapon_resource.current_ammo, 0)
	assert_signal_emit_count(weapon, "weapon_fired", 1)
	assert_signal_emitted_with_parameters(weapon, "weapon_fired", [0])


func test_failed_shot_between_successes_does_not_create_signal_or_ammo_gap() -> void:
	weapon.fire()
	child_weapon.succeeds = false
	weapon.fire()
	child_weapon.succeeds = true
	weapon.fire()

	assert_eq(child_weapon.fire_calls, 3)
	assert_eq(weapon.weapon_resource.current_ammo, 1)
	assert_signal_emit_count(weapon, "weapon_fired", 2)
	assert_signal_emitted_with_parameters(weapon, "weapon_fired", [2], 0)
	assert_signal_emitted_with_parameters(weapon, "weapon_fired", [1], 1)


func test_missing_active_weapon_does_not_emit() -> void:
	weapon.current_weapon = null
	weapon.fire()

	assert_push_error("current_weapon null or no 'fire()' method")
	assert_eq(weapon.weapon_resource.current_ammo, 3)
	assert_signal_not_emitted(weapon, "weapon_fired")


func test_active_node_without_fire_method_does_not_emit() -> void:
	var inert := Node2D.new()
	weapon.add_child(inert)
	weapon.current_weapon = inert
	weapon.fire()

	assert_push_error("current_weapon null or no 'fire()' method")
	assert_eq(weapon.weapon_resource.current_ammo, 3)
	assert_signal_not_emitted(weapon, "weapon_fired")


## Swapping to a node with its own stat properties keeps the shared WeaponResource and its
## ammo, and leaves the node's properties alone (#1146: nothing is copied anymore).
func test_switch_keeps_shared_resource_and_node_stats() -> void:
	weapon.weapon_types.assign([_pack(TunedWeapon.new())])
	var shared: WeaponResource = weapon.weapon_resource
	weapon.switch_to(0)

	assert_eq(weapon.weapon_resource, shared)
	assert_eq(shared.available_weapons[0], "Test Cannon")
	assert_eq(shared.current_index, 0)
	assert_eq(shared.current_ammo, 3)
	assert_eq(weapon.current_weapon.fire_rate, 0.65, "node stats must not be rewritten")
	assert_eq(weapon.current_weapon.damage, 31.0, "node stats must not be rewritten")
	assert_signal_not_emitted(weapon, "weapon_fired")


## Swapping to the next weapon updates the name and index, and the new node keeps its stats.
func test_switch_to_next_weapon_updates_name_and_index() -> void:
	var second := TunedWeapon.new()
	second.weapon_name = "Heavy Cannon"
	second.fire_rate = 1.2
	second.damage = 75.0
	weapon.weapon_types.assign([_pack(TunedWeapon.new()), _pack(second)])
	weapon.switch_to(0)
	weapon.switch_to(1)

	assert_eq(weapon.weapon_resource.current_index, 1)
	assert_eq(weapon.weapon_resource.available_weapons[1], "Heavy Cannon")
	assert_eq(weapon.weapon_resource.current_ammo, 3)
	assert_eq(weapon.current_weapon.fire_rate, 1.2)
	assert_eq(weapon.current_weapon.damage, 75.0)
	assert_signal_not_emitted(weapon, "weapon_fired")


## A weapon node with no stats or name still equips, with the "Machine Gun" fallback name.
func test_switch_without_optional_stats_still_equips() -> void:
	weapon.weapon_types.assign([_pack(Node2D.new())])
	weapon.switch_to(0)

	assert_not_null(weapon.current_weapon)
	assert_eq(weapon.current_index, 0)
	assert_eq(weapon.weapon_resource.current_index, 0)
	assert_eq(weapon.weapon_resource.available_weapons[0], "Machine Gun")


## A node with only fire_rate equips and updates the name and index.
func test_switch_with_only_fire_rate_updates_name_and_index() -> void:
	weapon.weapon_types.assign([_pack(Node2D.new()), _pack(RateOnlyWeapon.new())])
	watch_signals(weapon.weapon_resource)
	weapon.switch_to(1)

	assert_eq(weapon.weapon_resource.current_index, 1)
	assert_eq(weapon.weapon_resource.available_weapons[1], "Machine Gun")
	assert_signal_emitted_with_parameters(
		weapon.weapon_resource, "weapon_swapped", [1, "Machine Gun"]
	)
	assert_eq(weapon.current_weapon.fire_rate, 0.8)


## A node with only damage equips and updates the name and index.
func test_switch_with_only_damage_updates_name_and_index() -> void:
	weapon.weapon_types.assign([_pack(Node2D.new()), _pack(DamageOnlyWeapon.new())])
	watch_signals(weapon.weapon_resource)
	weapon.switch_to(1)

	assert_eq(weapon.weapon_resource.current_index, 1)
	assert_eq(weapon.weapon_resource.available_weapons[1], "Machine Gun")
	assert_signal_emitted_with_parameters(
		weapon.weapon_resource, "weapon_swapped", [1, "Machine Gun"]
	)
	assert_eq(weapon.current_weapon.damage, 53.0)


## Out-of-range tuning is clamped by BulletResource itself, so the equipped bullet fires with
## the clamped values. The bounds used to be applied by switch_to() through WeaponResource.
func test_switch_to_bullet_uses_resource_bounds() -> void:
	var bullet: Node2D = BULLET_SCENE.instantiate()
	var bullet_config := BulletResource.new()
	bullet_config.fire_rate = 0.0
	bullet_config.damage = -5
	bullet.config = bullet_config
	weapon.weapon_types.assign([_pack(bullet)])
	weapon.switch_to(0)

	assert_eq(weapon.current_weapon.config.fire_rate, 0.01)
	assert_eq(weapon.current_weapon.config.damage, 0)


## Regression: bullet tuning moved from node properties into BulletResource. After a swap the
## firer uses its own config, unchanged.
func test_switch_to_configured_bullet_uses_its_own_config() -> void:
	var bullet: Node2D = BULLET_SCENE.instantiate()
	var bullet_config := BulletResource.new()
	bullet_config.fire_rate = 0.75
	bullet_config.damage = 48
	bullet.config = bullet_config
	weapon.weapon_types.assign([_pack(bullet)])
	weapon.switch_to(0)

	assert_eq(weapon.current_weapon.config.fire_rate, 0.75)
	assert_eq(weapon.current_weapon.config.damage, 48)
	assert_eq(weapon.weapon_resource.current_ammo, 3)


## A bullet without its own config uses the shared default_bullet.tres. Equipping it, in the
## tree so bullet._ready() assigns the default, and swapping again leave that file unchanged.
func test_switch_leaves_default_bullet_config_unchanged() -> void:
	var default_config: BulletResource = BULLET_SCRIPT.DEFAULT_BULLET_CONFIG
	var fire_rate_before: float = default_config.fire_rate
	var damage_before: int = default_config.damage
	var firer: Node2D = WEAPON_SCRIPT.new()
	firer.weapon_types.assign([BULLET_SCENE])
	add_child_autofree(firer)  # _ready() equips index 0
	firer.switch_to(0)

	assert_eq(firer.current_weapon.config, default_config, "default config must be used")
	assert_eq(default_config.fire_rate, fire_rate_before)
	assert_eq(default_config.damage, damage_before)
	assert_eq(default_config.fire_rate, 0.15, "default_bullet.tres fire_rate")
	assert_eq(default_config.damage, 10, "default_bullet.tres damage")


## Two firers sharing one BulletResource both use it, and swaps leave its values unchanged.
func test_two_firers_sharing_one_config_stay_unchanged_after_swaps() -> void:
	var shared_config := BulletResource.new()
	shared_config.fire_rate = 0.3
	shared_config.damage = 21
	var first_bullet: Node2D = BULLET_SCENE.instantiate()
	first_bullet.config = shared_config
	var second_bullet: Node2D = BULLET_SCENE.instantiate()
	second_bullet.config = shared_config
	var other := TunedWeapon.new()

	var first_firer: Node2D = autofree(WEAPON_SCRIPT.new())
	first_firer.weapon_types.assign([_pack(first_bullet), _pack(other)])
	var second_firer: Node2D = autofree(WEAPON_SCRIPT.new())
	second_firer.weapon_types.assign([_pack(second_bullet)])

	first_firer.switch_to(0)
	second_firer.switch_to(0)
	first_firer.switch_to(1)
	first_firer.switch_to(0)

	assert_eq(first_firer.current_weapon.config, shared_config)
	assert_eq(second_firer.current_weapon.config, shared_config)
	assert_eq(shared_config.fire_rate, 0.3)
	assert_eq(shared_config.damage, 21)
