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

# Resource Caches
var _speed_resource: SpeedResource
var _fuel_resource: FuelResource
var _settings: GameSettingsResource


## Injects the required data resources and wires up observer signals.
## Prevents tight coupling to global singletons in the process loop.
## @param speed: SpeedResource - The player's speed state.
## @param fuel: FuelResource - The player's fuel state.
## @param settings: GameSettingsResource - The configuration resource.
## @return: void
func setup(speed: SpeedResource, fuel: FuelResource, settings: GameSettingsResource) -> void:
	# 1. Disconnect previously observed resources
	_disconnect_signals()

	# 2. Store the new resource references
	_speed_resource = speed
	_fuel_resource = fuel
	_settings = settings

	# 3. Connect required signals and 4. Perform initial state synchronization
	if is_instance_valid(_speed_resource):
		_speed_resource.speed_updated.connect(_on_speed_updated)
		_current_speed = _speed_resource.current_speed

	if is_instance_valid(_fuel_resource):
		_fuel_resource.fuel_changed.connect(_on_fuel_changed)
		_fuel_resource.fuel_depleted.connect(_on_fuel_depleted)
		_out_of_fuel = (_fuel_resource.current_fuel <= 0.0)

	if is_instance_valid(_settings):
		_settings.setting_changed.connect(_on_setting_changed)
		_difficulty = _settings.difficulty


## Helper to disconnect signals during teardown or replacement.
## @return: void
func _disconnect_signals() -> void:
	if (
		is_instance_valid(_speed_resource)
		and _speed_resource.speed_updated.is_connected(_on_speed_updated)
	):
		_speed_resource.speed_updated.disconnect(_on_speed_updated)

	if is_instance_valid(_fuel_resource):
		if _fuel_resource.fuel_changed.is_connected(_on_fuel_changed):
			_fuel_resource.fuel_changed.disconnect(_on_fuel_changed)
		if _fuel_resource.fuel_depleted.is_connected(_on_fuel_depleted):
			_fuel_resource.fuel_depleted.disconnect(_on_fuel_depleted)

	if is_instance_valid(_settings) and _settings.setting_changed.is_connected(_on_setting_changed):
		_settings.setting_changed.disconnect(_on_setting_changed)


## Helper to find the Greatest Common Divisor for LCM calculations.
func _gcd(a: int, b: int) -> int:
	while b != 0:
		var temp: int = b
		b = a % b
		a = temp
	return a


## Helper to find the Least Common Multiple to sync disparate layer periods.
func _lcm(a: int, b: int) -> int:
	if a == 0 or b == 0:
		return 0
	return absi((a * b) / _gcd(a, b))


## Public method to dynamically calculate the optimal wrap limit
## based on the properties of its ParallaxLayer children.
## Uses the Least Common Multiple (LCM) to ensure non-commensurate layers don't jump.
## IMPORTANT: For flawless wrapping, (motion_mirroring.y / motion_scale.y) MUST result
## in a whole number. Fractional periods will be rounded and may cause visual drift over time.
## Must be called after all layers have had their mirroring and scale set.
## @return: void
func auto_calculate_wrap_period() -> void:
	var computed_lcm: int = 1
	var periods: Array[int] = []

	# 1. Collect all valid layer periods as integers (pixels)
	for child in get_children():
		if child is ParallaxLayer:
			var layer_scale: float = child.motion_scale.y
			var layer_mirror: float = child.motion_mirroring.y

			if layer_scale > 0.0 and layer_mirror > 0.0:
				var period: float = layer_mirror / layer_scale
				var rounded_period: int = roundi(period)

				# Drift Safeguard: Warn if the period is not a clean integer
				if not is_equal_approx(period, float(rounded_period)):
					push_warning(
						(
							"ParallaxManager: Layer '"
							+ child.name
							+ "' has a fractional wrap period ("
							+ str(period)
							+ "). Rounding to "
							+ str(rounded_period)
							+ " may cause visual drift. "
							+ "Ensure (motion_mirroring.y / motion_scale.y) yields a whole number."
						)
					)

				periods.append(rounded_period)

	# 2. Calculate the universal LCM of all collected periods
	if periods.size() > 0:
		computed_lcm = periods[0]
		for i in range(1, periods.size()):
			computed_lcm = _lcm(computed_lcm, periods[i])

	# 3. Only overwrite the exported wrap_period if we successfully calculated a valid LCM.
	# This protects values set manually via the Godot Inspector.
	if computed_lcm > 1:
		wrap_period = float(computed_lcm)

	# 4. Warn the developer if the background is scrolling forever with no safeguard
	if wrap_period <= 0.0:
		push_warning(
			(
				"ParallaxManager: No valid wrap limit calculated or set. "
				+ "Float precision degradation may occur during long sessions."
			)
		)


## Observer callback for speed updates.
## @param new_speed: float - The new forward speed.
## @return: void
func _on_speed_updated(new_speed: float) -> void:
	_current_speed = new_speed


## Observer callback for specific setting updates (difficulty).
## @param setting_name: String - The name of the changed setting.
## @param new_value: Variant - The updated value.
## @return: void
func _on_setting_changed(setting_name: String, new_value: Variant) -> void:
	if setting_name == "difficulty":
		_difficulty = float(new_value)


## Observer callback for fuel changes to recover from flameout.
## @param new_value: float - The current fuel value.
## @return: void
func _on_fuel_changed(new_value: float) -> void:
	if new_value > 0.0:
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
