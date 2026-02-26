## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## Shared test helpers for SkyLockAssault unit tests.
## Contains utility functions for calculations.

extends RefCounted

## Calculates expected fuel depletion based on current formula.
## @param player: The player node instance.
## @param difficulty: The difficulty level to use.
## @return: The expected depletion amount.
static func calculate_expected_depletion(player: Node, difficulty: float) -> float:
	return player.base_fuel_drain * (player.speed["speed"] / player.MAX_SPEED) * difficulty
