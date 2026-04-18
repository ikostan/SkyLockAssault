## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## parallax_manager.gd
## Manages the scrolling speed of the parallax background based on player velocity.
## Decoupled via Dependency Injection and the Observer Pattern.

class_name ParallaxManager
extends ParallaxBackground

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


## Observer callback triggered when the player's speed changes.
## @param new_speed: float - The new forward speed of the player.
## @param _max_speed: float - The maximum speed threshold (unused).
## @return: void
func _on_player_speed_changed(new_speed: float, _max_speed: float) -> void:
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
## Updates scroll offset based entirely on cached local variables.
## @param delta: float - The elapsed time since the previous frame.
## @return: void
func _process(delta: float) -> void:
	if _out_of_fuel:
		scroll_offset = Vector2.ZERO
	else:
		var scroll_amount: float = _current_speed * delta * _difficulty * 0.8
		scroll_offset.y += scroll_amount
