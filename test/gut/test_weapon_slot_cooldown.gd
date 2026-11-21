## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
##
## test_weapon_slot_cooldown.gd
## Scene test for #1138: two real BulletFirer slots (the shipped bullet.tscn) can't be used to
## bypass the fire rate, because Weapon keeps each slot's firer and its CooldownTimer.

extends GdUnitTestSuite

const WeaponScene: PackedScene = preload("res://scenes/weapon.tscn")
const BulletScene: PackedScene = preload("res://scenes/bullet.tscn")
const GameSettingsResource = preload("res://scripts/resources/game_settings_resource.gd")

var _original_settings: GameSettingsResource


## Fresh settings per test so the difficulty multiplier is known and nothing leaks.
func before_test() -> void:
	_original_settings = Globals.settings
	Globals.settings = GameSettingsResource.new()
	Globals.settings.difficulty = 1.0
	_clear_bullets()


func after_test() -> void:
	_clear_bullets()
	Globals.settings = _original_settings


func _clear_bullets() -> void:
	for bullet: Node in get_tree().get_nodes_in_group("bullets"):
		bullet.free()


func _bullet_count() -> int:
	return get_tree().get_nodes_in_group("bullets").size()


## Fails clearly (instead of a script error) if a swap freed the slot's firer.
func _assert_kept(firer: Variant) -> bool:
	var kept: bool = is_instance_valid(firer)
	assert_bool(kept).override_failure_message("The swap freed the slot's firer.").is_true()
	return kept


func _make_weapon() -> Weapon:
	var weapon: Weapon = auto_free(WeaponScene.instantiate()) as Weapon
	weapon.weapon_types.assign([BulletScene, BulletScene])
	add_child(weapon)  # _ready() equips slot 0
	return weapon


func test_two_bullet_slots_cannot_bypass_cooldown() -> void:
	var weapon: Weapon = _make_weapon()
	await await_idle_frame()
	var ammo_start: int = weapon.weapon_resource.current_ammo
	var first: BulletFirer = weapon.current_weapon as BulletFirer
	assert_object(first).is_not_null()

	weapon.fire()
	weapon.switch_to(1)
	weapon.switch_to(0)
	weapon.fire()  # Same frame: slot 0 is still cooling down

	assert_object(weapon.current_weapon).is_same(first)
	assert_bool(first.can_fire).is_false()
	assert_int(_bullet_count()).is_equal(1)
	assert_int(weapon.weapon_resource.current_ammo).is_equal(ammo_start - 1)

	# default_bullet.tres fire_rate 0.15 s at difficulty 1.0
	await await_millis(300)
	if not _assert_kept(first):
		return
	assert_bool(first.can_fire).is_true()
	weapon.fire()
	assert_int(_bullet_count()).is_equal(2)
	assert_int(weapon.weapon_resource.current_ammo).is_equal(ammo_start - 2)


func test_unused_bullet_slot_fires_straight_after_swap() -> void:
	var weapon: Weapon = _make_weapon()
	await await_idle_frame()

	weapon.fire()
	weapon.switch_to(1)
	var second: BulletFirer = weapon.current_weapon as BulletFirer
	assert_object(second).is_not_same(weapon.get_child(0))
	weapon.fire()

	assert_bool(second.can_fire).is_false()
	assert_int(_bullet_count()).is_equal(2)


func test_hidden_bullet_slot_cooldown_keeps_running() -> void:
	var weapon: Weapon = _make_weapon()
	await await_idle_frame()
	var first: BulletFirer = weapon.current_weapon as BulletFirer

	weapon.fire()
	weapon.switch_to(1)
	assert_bool(first.visible).is_false()
	var cooldown: Timer = first.get_node("CooldownTimer") as Timer
	assert_bool(cooldown.is_stopped()).is_false()

	await await_millis(300)
	if not _assert_kept(first):
		return
	assert_bool(first.can_fire).is_true()
	weapon.switch_to(0)
	weapon.fire()
	assert_int(_bullet_count()).is_equal(2)
