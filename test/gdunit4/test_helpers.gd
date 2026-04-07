## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## Shared test helpers for SkyLockAssault unit tests.
## Contains utility functions for calculations.

class_name TestHelpers
extends RefCounted

## Calculates expected fuel depletion based on current formula.
## @param player: The player node instance.
## @param difficulty: The difficulty level to use.
## @return: The expected depletion amount.
static func calculate_expected_depletion(player_root: Node, difficulty: float) -> float:
	var normalized_speed: float = player_root.speed["speed"] / player_root.MAX_SPEED
	# OLD: return player_root.base_fuel_drain * normalized_speed * difficulty
	# NEW: Fetch the consumption rate from the new global resource since the local drain variable was removed
	return Globals.settings.base_consumption_rate * normalized_speed * difficulty
