## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## test_player_tuning_copy.gd
##
## GUT tests for how the player copies tuning values from GameSettingsResource into its
## SpeedResource and FuelResource at spawn (#1148). The settings fields are plain exports,
## so invalid values reach the player as written; the entity resources must reject or
## clamp them.

extends "res://addons/gut/test.gd"

const PlayerScene: PackedScene = preload("res://scenes/Player.tscn")

var _original_settings: GameSettingsResource


func before_each() -> void:
	_original_settings = Globals.settings
	Globals.settings = GameSettingsResource.new()
	Globals.settings.current_log_level = Globals.LogLevel.NONE


func after_each() -> void:
	Globals.settings = _original_settings


## Spawns a real player scene with the current Globals.settings.
## The real scene, not the shared mock: the mock's HUD panel lacks weapon and ammo
## nodes, and their engine errors would be charged to the test calling this.
## :rtype: Variant
func _spawn_player() -> Variant:
	var player: Variant = PlayerScene.instantiate()
	add_child_autoqfree(player)
	return player


## test_invalid_speed_limits_keep_the_defaults | Speed Limits
func test_invalid_speed_limits_keep_the_defaults() -> void:
	gut.p("Testing: An inverted speed pair in settings is rejected and the defaults kept.")
	Globals.settings.min_speed = 900.0
	Globals.settings.max_speed = 800.0

	var player: Variant = _spawn_player()

	assert_push_warning("SpeedResource: rejected speed limits")
	assert_eq(player.speed_resource.min_speed, 95.0, "min_speed must keep its default.")
	assert_eq(player.speed_resource.max_speed, 713.0, "max_speed must keep its default.")


## test_zero_fuel_restore_uses_the_applied_min_speed | Speed Limits
## After a rejected pair, refueling must restore the default min_speed, not the
## settings value (900, which SpeedResource would clamp to 713).
func test_zero_fuel_restore_uses_the_applied_min_speed() -> void:
	gut.p("Testing: Refueling restores the min_speed applied at spawn.")
	Globals.settings.min_speed = 900.0
	Globals.settings.max_speed = 800.0
	var player: Variant = _spawn_player()
	assert_push_warning("SpeedResource: rejected speed limits")

	player.fuel_resource.current_fuel = 0.0
	assert_eq(player.speed_resource.min_speed, 0.0, "Flameout must drop min_speed to 0.")

	player.fuel_resource.current_fuel = player.fuel_resource.max_fuel
	player._physics_process(1.0 / 60.0)

	assert_eq(player.speed_resource.min_speed, 95.0, "Refueling must restore the applied min_speed.")


## test_negative_speed_tuning_is_clamped_to_zero | Speed Tuning
func test_negative_speed_tuning_is_clamped_to_zero(
	prop: String = use_parameters(["acceleration", "deceleration", "lateral_speed"])
) -> void:
	gut.p("Testing: A negative %s in settings is clamped to 0 by SpeedResource." % prop)
	Globals.settings.set(prop, -50.0)

	var player: Variant = _spawn_player()

	assert_eq(player.speed_resource.get(prop), 0.0, "%s must clamp to 0." % prop)


## test_out_of_range_fractions_are_clamped | Speed Tuning
func test_out_of_range_fractions_are_clamped() -> void:
	gut.p("Testing: Speed warning fractions above 1 are clamped by SpeedResource.")
	Globals.settings.high_yellow_fraction = 1.5
	Globals.settings.low_yellow_fraction = 1.2

	var player: Variant = _spawn_player()

	assert_eq(player.speed_resource.high_yellow_fraction, 1.0, "high_yellow_fraction must clamp to 1.")
	assert_eq(player.speed_resource.low_yellow_fraction, 1.0, "low_yellow_fraction must clamp to 1.")


## test_low_fraction_above_high_is_clamped | Speed Tuning
func test_low_fraction_above_high_is_clamped() -> void:
	gut.p("Testing: A low fraction above the high fraction is clamped down to it.")
	Globals.settings.high_yellow_fraction = 0.5
	Globals.settings.low_yellow_fraction = 0.95

	var player: Variant = _spawn_player()

	assert_eq(player.speed_resource.high_yellow_fraction, 0.5, "A valid high fraction must apply.")
	assert_eq(player.speed_resource.low_yellow_fraction, 0.5, "low must clamp to high.")


## test_out_of_order_fuel_thresholds_keep_the_defaults | Fuel Thresholds
## The settings fields no longer keep the thresholds ordered, so FuelResource must.
func test_out_of_order_fuel_thresholds_keep_the_defaults() -> void:
	gut.p("Testing: Out-of-order fuel thresholds in settings are rejected.")
	Globals.settings.high_fuel_threshold = 20.0
	Globals.settings.medium_fuel_threshold = 60.0

	var player: Variant = _spawn_player()

	assert_push_warning("FuelResource: rejected fuel thresholds")
	var fuel: FuelResource = player.fuel_resource
	var thresholds: Array = [
		fuel.high_fuel_threshold,
		fuel.medium_fuel_threshold,
		fuel.low_fuel_threshold,
		fuel.no_fuel_threshold,
	]
	assert_eq(thresholds, [90.0, 50.0, 30.0, 15.0], "The thresholds must keep their defaults.")


## Refueling restores the spawn tuning even if global tuning has since changed.
func test_refuel_restores_custom_spawn_minimum(
	limits: Array = use_parameters([[900.0, 1000.0], [10.0, 50.0]])
) -> void:
	Globals.settings.min_speed = limits[0]
	Globals.settings.max_speed = limits[1]
	var player: Variant = _spawn_player()
	assert_eq(player.speed_resource.min_speed, limits[0])
	assert_eq(player.speed_resource.max_speed, limits[1])
	Globals.settings.min_speed = 25.0
	player.fuel_resource.current_fuel = 0.0
	assert_eq(player.speed_resource.min_speed, 0.0)
	assert_eq(player.current_speed, 0.0)
	player.fuel_resource.refuel(1.0)
	player._set_speed(0.0)
	assert_eq(player.speed_resource.min_speed, limits[0])
	assert_eq(player.current_speed, limits[0])
	assert_false(player.fuel_timer.is_stopped())
