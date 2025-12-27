# audio_constants.gd
# Centralized audio bus name constants as autoload singleton.
# Use as AudioConstants.BUS_MASTER, etc., to prevent typos and ease renaming.
# Extends Node for autoload compatibility.

extends Node

const BUS_MASTER: String = "Master"
const BUS_MUSIC: String = "Music"
const BUS_SFX: String = "SFX"
const BUS_SFX_ROTORS: String = "SFX_Rotors"
