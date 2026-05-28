## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_audio_resource_integrity.gd
##
## Automation test suite that recursively validates audio resource importing integrity
## across all specified directories, nested subfolders, and multi-format audio streams.

extends "res://addons/gut/test.gd"

# Target root directories to scan for raw audio resources
const TARGET_DIRECTORIES: Array[String] = [
	"res://files/sounds/music/",
	"res://files/sounds/sfx/"
]

var _total_files_scanned: int = 0


## Orchestrates the deep recursive scan across all target audio directories
## :rtype: void
func test_audio_assets_integrity() -> void:
	_total_files_scanned = 0
	
	for dir_path: String in TARGET_DIRECTORIES:
		_scan_directory_recursive(dir_path)
		
	# Output a clean summary metrics block to the console output log
	print("\n==============================================")
	print(" AUDIO ASSET INTEGRITY REPORT")
	print("==============================================")
	print(" Total audio assets scanned & verified: %d" % _total_files_scanned)
	print("==============================================\n")


## Recursively crawls folders to find sound formats while ignoring system/import meta files
## :param dir_path: The project directory resource path string.
## :type dir_path: String
## :rtype: void
func _scan_directory_recursive(dir_path: String) -> void:
	# FIX: Use DirAccess.open directly to verify folder accessibility headlessly
	var dir: DirAccess = DirAccess.open(dir_path)
	if not dir:
		print("[SKIPPED] Optional target asset subdirectory is missing, moved, or unreachable: %s" % dir_path)
		return
		
	dir.list_dir_begin()
	var item_name: String = dir.get_next()
	
	while item_name != "":
		# Skip hidden files, system directories, and the explicit .import configuration files
		if item_name.begins_with(".") or item_name.ends_with(".import"):
			item_name = dir.get_next()
			continue
			
		var full_path: String = dir_path + item_name
		
		if dir.current_is_dir():
			# Recursive branch: drill down into the subfolder safely preserving the trailing slash
			_scan_directory_recursive(full_path + "/")
		else:
			# Base branch: isolate and evaluate supported engine audio codecs
			var ext: String = item_name.get_extension().to_lower()
			if ext in ["wav", "ogg", "mp3"]:
				print("Checking asset: %s" % full_path)
				_validate_audio_resource(full_path)
				_total_files_scanned += 1
				
		item_name = dir.get_next()
		
	dir.list_dir_end()


## Asserts engine capability to map, load, and verify data payload configurations per audio type
## :param path: The absolute resource path to the audio asset.
## :type path: String
## :rtype: void
func _validate_audio_resource(path: String) -> void:
	# 1. Verify the ResourceLoader doesn't fail outright (Catches corrupted file headers or invalid extensions)
	var raw_resource: Resource = ResourceLoader.load(path)
	assert_not_null(raw_resource, "Asset Loader Failure: '%s' is corrupted or uses an unsupported format." % path)
	
	if raw_resource == null:
		return
		
	# 2. Verify the loaded asset safely casts to the generic AudioStream base class
	var stream: AudioStream = raw_resource as AudioStream
	assert_not_null(stream, "Data Type Mismatch: '%s' could not be cast to an AudioStream resource." % path)
	
	if not stream:
		return
		
	# 3. Global Duration Check: If an importer falls over headlessly, length frequently evaluates to 0.0
	assert_gt(stream.get_length(), 0.0, "Resource Integrity Breach: '%s' has an invalid track length of 0 seconds." % path)
	
	# 4. Format-Specific Structural Verification
	# Targets localized byte array sizes depending on the asset's active wrapper type.
	if stream is AudioStreamWAV:
		var wav_stream: AudioStreamWAV = stream as AudioStreamWAV
		assert_gt(wav_stream.data.size(), 0, "Codec Validation Error: WAV stream '%s' contains a 0-byte data block." % path)
	elif stream is AudioStreamMP3:
		var mp3_stream: AudioStreamMP3 = stream as AudioStreamMP3
		assert_gt(mp3_stream.data.size(), 0, "Codec Validation Error: MP3 stream '%s' contains a 0-byte data block." % path)
	elif stream is AudioStreamOggVorbis:
		var ogg_stream: AudioStreamOggVorbis = stream as AudioStreamOggVorbis
		# OggVorbis loads packets via an internal OggPacketSequence resource rather than a flat data array.
		# A non-zero stream length validates that packets were successfully unrolled by the importer.
		assert_not_null(ogg_stream.packet_sequence, "Codec Validation Error: Ogg Vorbis stream '%s' has an uninitialized packet sequence." % path)
	
