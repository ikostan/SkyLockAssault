# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# audio_constants.gd
# Centralized audio bus name constants and config as autoload singleton.
# Use as AudioConstants.BUS_MASTER, etc., to prevent typos and ease renaming.
# Extends Node for autoload compatibility.

extends Node


# --- Audio Bus Names ---
const BUS_MASTER: String = "Master"
const BUS_MUSIC: String = "Music"
const BUS_SFX: String = "SFX"
const BUS_SFX_ROTORS: String = "SFX_Rotors"
const BUS_SFX_WEAPON: String = "SFX_Weapon"
const BUS_SFX_MENU: String = "SFX_Menu"

# --- SFX Asset IDs ---
const SFX_SLIDER: String = "slider"
const SFX_MUTE_TOGGLE: String = "mute_toggle"  # For future CheckButton task
const SFX_UI_NAVIGATION: String = "ui_navigation"

# Centralized config with defaults and var mappings
const BUS_CONFIG: Dictionary = {
	BUS_MASTER:
	{
		"volume_var": "master_volume",
		"muted_var": "master_muted",
		"default_volume": 1.0,
		"default_muted": false
	},
	BUS_MUSIC:
	{
		"volume_var": "music_volume",
		"muted_var": "music_muted",
		"default_volume": 1.0,
		"default_muted": false
	},
	BUS_SFX:
	{
		"volume_var": "sfx_volume",
		"muted_var": "sfx_muted",
		"default_volume": 1.0,
		"default_muted": false
	},
	BUS_SFX_WEAPON:
	{
		"volume_var": "weapon_volume",
		"muted_var": "weapon_muted",
		"default_volume": 1.0,
		"default_muted": false
	},
	BUS_SFX_ROTORS:
	{
		"volume_var": "rotors_volume",
		"muted_var": "rotors_muted",
		"default_volume": 1.0,
		"default_muted": false
	},
	BUS_SFX_MENU:
	{
		"volume_var": "menu_volume",
		"muted_var": "menu_muted",
		"default_volume": 1.0,
		"default_muted": false
	}
}

# --- Global UI SFX Mappings (Issue #490 Compliance) ---
# Decoupled from file extensions and folder layouts to prevent silent breaks on asset moves
const UI_SFX: Dictionary = {
	"ui_up": "ui_navigation",
	"ui_down": "ui_navigation",
	"ui_left": "ui_navigation",
	"ui_right": "ui_navigation",
	"ui_focus_next": "ui_navigation",
	"ui_focus_prev": "ui_navigation",
	"ui_accept": "ui_accept",
	"ui_cancel": "ui_cancel"
}

# --- SFX Asset Path Resolution Map ---
# Maps logical SFX identifiers to their exact filenames with extensions.
# This prevents asset changes from requiring script alterations.
const SFX_ASSET_MAP: Dictionary = {
	"slider": "slider.wav",
	"mute_toggle": "check.wav",
	"ui_navigation": "ui_navigation.wav",
	"ui_accept": "ui_accept.wav",
	"ui_cancel": "ui_cancel.wav",
	"airplane_prop": "airplane_prop.ogg",
	"retro_laser": "retro-laser-1-236669.mp3"
}
