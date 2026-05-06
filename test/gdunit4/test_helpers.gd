## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## Shared test helpers for SkyLockAssault unit tests.
## Contains utility functions for calculations.

extends RefCounted


## Calculates the expected fuel depletion based on the global GameSettingsResource.
static func calculate_expected_depletion(player_root: Node, difficulty: float) -> float:
	# NEW: Use Globals.settings.max_speed instead of player_root.MAX_SPEED
	var normalized_speed: float = player_root.current_speed / Globals.settings.max_speed
	
	# NEW: Use Globals.settings.base_consumption_rate instead of player_root.base_fuel_drain
	return Globals.settings.base_consumption_rate * normalized_speed * difficulty
