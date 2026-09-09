## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## Shared test helpers for SkyLockAssault unit tests.
## Contains utility functions for calculations.

class_name TestHelpers
extends RefCounted

const PlayerScript = preload("res://scripts/entities/player.gd")
const GameSettingsResource = preload("res://scripts/resources/game_settings_resource.gd")


## Calculates the expected fuel depletion based on the global GameSettingsResource.
static func calculate_expected_depletion(player_root: Node, difficulty: float) -> float:
	var player: PlayerScript = player_root as PlayerScript
	var settings: GameSettingsResource = Globals.settings as GameSettingsResource
	var normalized_speed: float = float(player.current_speed) / float(settings.max_speed)
	return float(settings.base_consumption_rate) * normalized_speed * float(difficulty)
