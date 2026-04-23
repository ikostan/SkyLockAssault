## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## game_paths.gd
## Centralized repository for all hardcoded script and scene paths.
## Use this class to reference paths globally to avoid fragility and improve refactoring.

class_name GamePaths
extends RefCounted

# =========================================================
# SCRIPT PATHS
# =========================================================

## Path to the player entity script.
const PLAYER: String = "res://scripts/entities/player.gd"

## Path to the HUD UI script.
const HUD: String = "res://scripts/ui/hud.gd"

## Path to the audio web bridge system script.
const AUDIO_WEB_BRIDGE: String = "res://scripts/system/audio_web_bridge.gd"

## Path to the input remap button component script.
const INPUT_REMAP_BUTTON: String = "res://scripts/ui/components/input_remap_button.gd"

## Path to the gameplay settings menu script.
const GAMEPLAY_SETTINGS: String = "res://scripts/ui/menus/gameplay_settings.gd"

## Path to the core settings singleton/script.
const SETTINGS: String = "res://scripts/core/settings.gd"

# =========================================================
# SCENE PATHS
# =========================================================

## Path to the audio settings menu scene.
const AUDIO_SETTINGS_SCENE: String = "res://scenes/audio_settings.tscn"

## Path to the main game scene.
const MAIN_SCENE: String = "res://scenes/main_scene.tscn"

## Path to the key mapping menu scene.
const KEY_MAPPING_SCENE: String = "res://scenes/key_mapping_menu.tscn"

## Path to the gameplay settings menu scene.
const GAMEPLAY_SETTINGS_SCENE: String = "res://scenes/gameplay_settings.tscn"

## Path to the pause menu scene.
const PAUSE_MENU_SCENE: String = "res://scenes/pause_menu.tscn"

## Path to the options menu scene.
const OPTIONS_MENU_SCENE: String = "res://scenes/options_menu.tscn"
