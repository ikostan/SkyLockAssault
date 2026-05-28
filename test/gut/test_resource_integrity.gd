## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_resource_integrity.gd
##
## Automation test suite that validates resource importing integrity.
## Catches malformed asset files that fail to cook correctly in headless environments.

extends "res://addons/gut/test.gd"

# Target directories to scan for raw audio resources
const AUDIO_SFX_DIR = "res://files/sounds/sfx/"
const AUDIO_MUSIC_DIR = "res://files/sounds/music/"


## Orchestrates the validation scan across asset targets
## :rtype: void
func test_audio_assets_integrity() -> void:
	_scan_and_validate_directory(AUDIO_SFX_DIR)
	_scan_and_validate_directory(AUDIO_MUSIC_DIR)


## Dynamically crawls a directory path to verify raw files and their compiled imports
## :param dir_path: The project directory resource path string.
## :type dir_path: String
## :rtype: void
func _scan_and_validate_directory(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	
	if not dir:
		fail_test("CRITICAL: Failed to open asset validation target directory: " + dir_path)
		return
		
	dir.list_dir_begin()
	var file_name := dir.get_next()
	
	while file_name != "":
		# Skip hidden files, system directories, and the explicit .import configuration files
		if not dir.current_is_dir() and not file_name.begins_with(".") and not file_name.ends_with(".import"):
			
			# We focus explicitly on wave formats which are susceptible to codec mismatches
			if file_name.ends_with(".wav"):
				var file_resource_path := dir_path + file_name
				_validate_wav_resource(file_resource_path)
				
		file_name = dir.get_next()
		
	dir.list_dir_end()


## Asserts engine capability to map, load, and parse the data structure of the asset
## :param path: The absolute resource path to the audio asset.
## :type path: String
## :rtype: void
func _validate_wav_resource(path: String) -> void:
	# 1. Verify the ResourceLoader doesn't fail outright
	var raw_resource := ResourceLoader.load(path)
	assert_not_null(raw_resource, "Asset Loader Failure: '%s' is corrupted or uses an unsupported codec format." % path)
	
	if raw_resource == null:
		return
		
	# 2. Verify the loaded asset type matches the expected audio stream layout
	var wav_stream := raw_resource as AudioStreamWAV
	assert_not_null(wav_stream, "Data Type Mismatch: '%s' could not be cast to an AudioStreamWAV resource." % path)
	
	if wav_stream:
		# 3. Catch the 0-byte dummy asset file bug
		# If the file format isn't uncompressed PCM or IEEE float, the importer writes out an empty data block.
		var data_size := wav_stream.data.size()
		assert_gt(
			data_size, 
			0, 
			"Resource Integrity Breach: '%s' contains a 0-byte data stream. Ensure file is encoded as uncompressed PCM or IEEE Float." % path
		)
