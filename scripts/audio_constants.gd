# audio_constants.gd
# Centralized audio bus name constants as autoload singleton.
# Use as AudioConstants.BUS_MASTER, etc., to prevent typos and ease renaming.
# Extends Node for autoload compatibility.

extends Node

const BUS_MASTER: String = "Master"
const BUS_MUSIC: String = "Music"
const BUS_SFX: String = "SFX"
const BUS_SFX_ROTORS: String = "SFX_Rotors"
const BUS_SFX_WEAPON: String = "SFX_Weapon"

# Defaults
const DEFAULT_VOLUMES: Dictionary = {
	BUS_MASTER: {"volume": 1.0, "muted": false},
	BUS_MUSIC: {"volume": 1.0, "muted": false},
	BUS_SFX: {"volume": 1.0, "muted": false},
	BUS_SFX_WEAPON: {"volume": 1.0, "muted": false},
	BUS_SFX_ROTORS: {"volume": 1.0, "muted": false}
}
