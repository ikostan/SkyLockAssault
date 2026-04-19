## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## parallax_manager.gd
## Manages the scrolling speed of the parallax background based on player velocity.
## Decoupled via Dependency Injection and the Observer Pattern.

class_name ParallaxManager
extends ParallaxBackground

## Base multiplier applied to the final scroll math to scale the speed visually.
const SCROLL_MULTIPLIER: float = 0.8

## Optional wrap limit to prevent float32 precision degradation over long sessions.
## Should be a common multiple of the layers' (motion_mirroring.y / motion_scale.y).
@export var wrap_period: float = 0.0

var _current_speed: float = 0.0
var _difficulty: float = 1.0
var _out_of_fuel: bool = false


## Injects the game settings resource and wires up observer signals.
## Prevents tight coupling to global singletons in the process loop.
## @param settings: GameSettingsResource - The configuration resource.
## @return: void
func setup(settings: GameSettingsResource) -> void:
	if not is_instance_valid(settings):
		return

	_difficulty = settings.difficulty
	_out_of_fuel = (settings.current_fuel <= 0.0)

	if not settings.setting_changed.is_connected(_on_setting_changed):
		settings.setting_changed.connect(_on_setting_changed)
	if not settings.fuel_depleted.is_connected(_on_fuel_depleted):
		settings.fuel_depleted.connect(_on_fuel_depleted)


## Public method to prime the background's initial speed.
## Keeps private signal handlers properly encapsulated.
## @param initial_speed: float - The starting forward speed.
## @return: void
func prime_speed(initial_speed: float) -> void:
	_current_speed = initial_speed


## Public method to dynamically calculate the optimal wrap limit
## based on the properties of its ParallaxLayer children.
## Must be called after all layers have had their mirroring and scale set.
## @return: void
func auto_calculate_wrap_period() -> void:
	var max_period: float = 0.0

	# Iterate through all children to find the longest required wrap period
	for child in get_children():
		if child is ParallaxLayer:
			var layer_scale: float = child.motion_scale.y
			var layer_mirror: float = child.motion_mirroring.y

			if layer_scale > 0.0 and layer_mirror > 0.0:
				var period: float = layer_mirror / layer_scale
				if period > max_period:
					max_period = period

	# 1. Only overwrite the exported wrap_period if we successfully calculated a new one.
	# This protects values set manually via the Godot Inspector.
	if max_period > 0.0:
		wrap_period = max_period

	# 2. Warn the developer if the background is scrolling forever with no safeguard
	if wrap_period <= 0.0:
		push_warning(
			(
				"ParallaxManager: No valid wrap limit calculated or set. "
				+ "Float precision degradation may occur during long sessions."
			)
		)


## Public method to update the scrolling speed.
## Designed to be safely connected to external speed_changed signals.
## @param new_speed: float - The new forward speed.
## @param _max_speed: float - The maximum speed threshold (unused, defaults to 0.0).
## @return: void
func update_speed(new_speed: float, _max_speed: float = 0.0) -> void:
	_current_speed = new_speed


## Observer callback for specific setting updates (difficulty and refueling).
## @param setting_name: String - The name of the changed setting.
## @param new_value: Variant - The updated value.
## @return: void
func _on_setting_changed(setting_name: String, new_value: Variant) -> void:
	if setting_name == "difficulty":
		_difficulty = float(new_value)
	elif setting_name == "current_fuel" and float(new_value) > 0.0:
		_out_of_fuel = false


## Observer callback to instantly snap the background when fuel runs out.
## @return: void
func _on_fuel_depleted() -> void:
	_out_of_fuel = true
	scroll_offset = Vector2.ZERO


## Called every physics/rendering frame.
## Updates scroll offset based entirely on cached local variables
## and wraps to preserve float precision.
## @param delta: float - The elapsed time since the previous frame.
## @return: void
func _process(delta: float) -> void:
	if _out_of_fuel:
		scroll_offset = Vector2.ZERO
	else:
		var scroll_amount: float = _current_speed * delta * _difficulty * SCROLL_MULTIPLIER
		scroll_offset.y += scroll_amount

		# Prevent float precision degradation by wrapping modulo the period
		if wrap_period > 0.0:
			scroll_offset.y = wrapf(scroll_offset.y, 0.0, wrap_period)
