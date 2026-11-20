## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## audio_constants.gd
## Centralized audio bus names, SFX IDs and bus config.
## Use as AudioConstants.BUS_MASTER, etc., to prevent typos and ease renaming.
## A class_name script with constants only, not an autoload (#1149): it has no state or
## functions, so it needs no node in the scene tree.
class_name AudioConstants

## Base path for all UI sound effects.
const SFX_DIR_PATH: String = "res://files/sounds/sfx/"

# --- Audio Bus Names ---
const BUS_MASTER: String = "Master"
const BUS_MUSIC: String = "Music"
const BUS_SFX: String = "SFX"
const BUS_SFX_ROTORS: String = "SFX_Rotors"
## Playback buses of the left and right rotors. Both send to SFX_Rotors, which owns their
## volume and mute, so they are not in BUS_CONFIG.
const BUS_SFX_ROTOR_LEFT: String = "SFX_Rotor_Left"
const BUS_SFX_ROTOR_RIGHT: String = "SFX_Rotor_Right"
const BUS_SFX_WEAPON: String = "SFX_Weapon"
const BUS_SFX_MENU: String = "SFX_Menu"

# --- SFX Asset IDs ---
const SFX_SLIDER: String = "slider"
const SFX_UI_NAVIGATION: String = "ui_navigation"
## Confirmation click for toggles, mute buttons and key binding.
const SFX_CHECK: String = "check"

# --- Auto-Mute / Hardware Timing ---
## Linear volume at or below which a bus is treated as silent and auto-muted
## (and above which an auto-muted bus is restored).
const AUTO_MUTE_VOLUME_THRESHOLD: float = 0.001

## Seconds to defer a hardware mute/volume cutoff so the confirmation click
## can finish streaming to the audio device first.
const MUTE_HARDWARE_DELAY: float = 0.15

## Temporary linear volume a bus on the click's feedback path (SFX_Menu, SFX,
## Master) is held at while an auto-mute confirmation click plays (Issue #1047).
## A volume level, not a duration: it only shares its numeric value with
## MUTE_HARDWARE_DELAY.
const FEEDBACK_HOLD_VOLUME_LINEAR: float = 0.15

## Linear volume a bus is restored to when it is unmuted at or below
## AUTO_MUTE_VOLUME_THRESHOLD and no last audible volume is known yet
## (e.g. after a restart). Sits on the sliders' 0.033 step grid (15 steps).
## Issue #1046.
const UNMUTE_FROM_ZERO_FALLBACK_VOLUME: float = 0.495

## Centralized per-bus config: the AudioManager variable names, defaults, and the parent bus.
## "parent" is the bus whose mute locks this bus's controls ("" for Master). It mirrors the
## sends in default_bus_layout.tres, and AudioManager.get_parent_bus(),
## get_muted_ancestor() and is_effectively_muted() read it (Issue #1154).
const BUS_CONFIG: Dictionary = {
	BUS_MASTER:
	{
		"parent": "",
		"volume_var": "master_volume",
		"muted_var": "master_muted",
		"default_volume": 1.0,
		"default_muted": false
	},
	BUS_MUSIC:
	{
		"parent": BUS_MASTER,
		"volume_var": "music_volume",
		"muted_var": "music_muted",
		"default_volume": 1.0,
		"default_muted": false
	},
	BUS_SFX:
	{
		"parent": BUS_MASTER,
		"volume_var": "sfx_volume",
		"muted_var": "sfx_muted",
		"default_volume": 1.0,
		"default_muted": false
	},
	BUS_SFX_WEAPON:
	{
		"parent": BUS_SFX,
		"volume_var": "weapon_volume",
		"muted_var": "weapon_muted",
		"default_volume": 1.0,
		"default_muted": false
	},
	BUS_SFX_ROTORS:
	{
		"parent": BUS_SFX,
		"volume_var": "rotors_volume",
		"muted_var": "rotors_muted",
		"default_volume": 1.0,
		"default_muted": false
	},
	BUS_SFX_MENU:
	{
		"parent": BUS_SFX,
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
	"check": "check.wav",
	"ui_navigation": "ui_navigation.wav",
	"ui_accept": "ui_accept.wav",
	"ui_cancel": "ui_cancel.wav",
	"airplane_prop": "airplane_prop.ogg",
	"retro_laser": "retro-laser-1-236669.mp3"
}

## Centralized list of UI navigation actions to ensure consistency
## and prevent duplicate definitions across the codebase.
const NAV_ACTIONS: Array[String] = [
	"ui_up", "ui_down", "ui_left", "ui_right", "ui_focus_next", "ui_focus_prev"
]
