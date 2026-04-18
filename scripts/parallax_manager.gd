## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## parallax_manager.gd
## Manages the scrolling speed of the parallax background based on player velocity.
## Decoupled from direct physics polling via the Observer Pattern.

class_name ParallaxManager
extends ParallaxBackground

var _current_speed: float = 0.0


## Observer callback triggered when the player's speed changes.
## Updates the internal speed used for parallax scrolling.
## @param new_speed: float - The new forward speed of the player.
## @param _max_speed: float - The maximum speed threshold (unused).
## @return: void
func _on_player_speed_changed(new_speed: float, _max_speed: float) -> void:
	_current_speed = new_speed


## Called every physics/rendering frame. Updates the vertical scroll offset
## based on the cached player speed and current game difficulty.
## Explicitly resets the scroll offset to zero if the player runs out of fuel.
## @param delta: float - The elapsed time since the previous frame.
## @return: void
func _process(delta: float) -> void:
	var difficulty: float = 1.0
	var current_fuel: float = 1.0  # Default to > 0 to prevent accidental resets if Globals is null

	if is_instance_valid(Globals) and is_instance_valid(Globals.settings):
		difficulty = Globals.settings.difficulty
		current_fuel = Globals.settings.current_fuel

	# Enforce the legacy behavior: reset offset immediately on flameout
	if current_fuel <= 0.0:
		scroll_offset = Vector2.ZERO
	else:
		var scroll_amount: float = _current_speed * delta * difficulty * 0.8
		scroll_offset.y += scroll_amount
