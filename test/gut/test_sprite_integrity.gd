## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_sprite_integrity.gd
##
## Automation test suite that recursively validates texture/sprite importing integrity
## across all specified graphics asset directories and their nested subfolders.

extends "res://addons/gut/test.gd"

# Exact directories specified by the project layout
const TARGET_DIRECTORIES: Array[String] = [
	"res://files/ground_tilesest/",
	"res://files/img/",
	"res://files/p38_sprites/",
	"res://files/random_decor/",
	"res://files/rotor/",
	"res://files/sprite/",
	"res://files/trees/"
]

var _total_files_scanned: int = 0


## Orchestrates the deep recursive scan across all target graphic directories
## :rtype: void
func test_sprite_assets_integrity() -> void:
	_total_files_scanned = 0
	
	for dir_path in TARGET_DIRECTORIES:
		_scan_directory_recursive(dir_path)
		
	# Output a clean summary metrics block to the console output log
	print("\n==============================================")
	print(" GRAPHICS ASSET INTEGRITY REPORT")
	print("==============================================")
	print(" Total texture assets scanned & verified: %d" % _total_files_scanned)
	print("==============================================\n")


## Recursively crawls folders to find raw image formats with graceful fallback skipping
## :param dir_path: The project directory resource path string.
## :type dir_path: String
## :rtype: void
func _scan_directory_recursive(dir_path: String) -> void:
	# SOFT GAARDRAIL: Check directory existence to reduce maintenance brittleness
	if not DirAccess.dir_exists_absolute(dir_path):
		print("[SKIPPED] Optional target asset subdirectory is missing or moved: %s" % dir_path)
		return

	var dir := DirAccess.open(dir_path)
	if not dir:
		print("[WARNING] Could not open valid directory track path: %s" % dir_path)
		return
		
	dir.list_dir_begin()
	var item_name := dir.get_next()
	
	while item_name != "":
		if item_name.begins_with(".") or item_name.ends_with(".import"):
			item_name = dir.get_next()
			continue
			
		var full_path := dir_path + item_name
		
		if dir.current_is_dir():
			_scan_directory_recursive(full_path + "/")
		else:
			var ext := item_name.get_extension().to_lower()
			if ext in ["png", "webp", "jpg", "jpeg"]:
				print("Checking asset: %s" % full_path)
				_validate_texture_resource(full_path)
				_total_files_scanned += 1
				
		item_name = dir.get_next()
		
	dir.list_dir_end()


## Asserts engine capability to map, load, and extract raw pixels from the texture
## :param path: The absolute resource path to the image asset.
## :type path: String
## :rtype: void
func _validate_texture_resource(path: String) -> void:
	# 1. Verify the ResourceLoader doesn't return null (Catches completely corrupted files/headers)
	var raw_resource := ResourceLoader.load(path)
	assert_not_null(raw_resource, "Asset Loader Failure: '%s' is corrupted or could not be opened by the engine." % path)
	
	if raw_resource == null:
		return
		
	# 2. Verify the asset can cast safely to a Texture2D base class
	var texture := raw_resource as Texture2D
	assert_not_null(texture, "Data Type Mismatch: '%s' failed to cast to a Texture2D resource type." % path)
	
	if texture:
		# 3. Check for valid dimensions. Broken headless imports collapse to a 0x0 size grid.
		var width := texture.get_width()
		var height := texture.get_height()
		
		assert_gt(width, 0, "Resource Integrity Breach: '%s' has an invalid width of 0 pixels." % path)
		assert_gt(height, 0, "Resource Integrity Breach: '%s' has an invalid height of 0 pixels." % path)
		
		# 4. Extract the underlying Image data payload
		# This handles the VRAM texture compilation phase check on a headless runner.
		var img := texture.get_image()
		assert_not_null(img, "Decompression Failure: Underlying Image payload for '%s' is null." % path)
		
		if img:
			assert_false(img.is_empty(), "Resource Integrity Breach: Data payload for '%s' parsed as an empty image stream." % path)
			assert_gt(img.get_data().size(), 0, "Resource Integrity Breach: Byte payload size for '%s' is 0 bytes." % path)
