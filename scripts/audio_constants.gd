# audio_constants.gd
# Centralized audio bus name constants and config as autoload singleton.
# Use as AudioConstants.BUS_MASTER, etc., to prevent typos and ease renaming.
# Extends Node for autoload compatibility.

extends Node

const BUS_MASTER: String = "Master"
const BUS_MUSIC: String = "Music"
const BUS_SFX: String = "SFX"
const BUS_SFX_ROTORS: String = "SFX_Rotors"
const BUS_SFX_WEAPON: String = "SFX_Weapon"

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
	}
}
