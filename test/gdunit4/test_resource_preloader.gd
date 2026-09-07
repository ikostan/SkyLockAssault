## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_resource_preloader.gd
##
## GdUnit4 automated test suite for ResourcePreloader.

extends GdUnitTestSuite

const PRELOADER_SCRIPT: GDScript = preload("res://scripts/managers/resource_preloader.gd")
const TEMP_TEST_DIR: String = "user://test_preloader_sandbox/"
const DUMMY_TXT: String = TEMP_TEST_DIR + "notes.txt"
const REAL_TEXTURE_DIR: String = "res://files/random_decor/"


# ==============================================================================
# FAKE INNER CLASS FOR DEPENDENCY INJECTION
# Bypasses GdUnit4 spy() limitations on native @tool C++ classes.
# ==============================================================================
class FakePreloader extends "res://scripts/managers/resource_preloader.gd":
	var mock_is_in_editor: bool = false
	var mock_load_failure: bool = false
	
	func _is_in_editor() -> bool:
		if mock_is_in_editor:
			return true
		return super._is_in_editor()
		
	# MATCH THE PARENT SIGNATURE EXACTLY
	func _load_resource(path: Variant) -> Texture2D:
		if mock_load_failure:
			return null
		return super._load_resource(path)
# ==============================================================================


func before_test() -> void:
	if not DirAccess.dir_exists_absolute(TEMP_TEST_DIR):
		DirAccess.make_dir_recursive_absolute(TEMP_TEST_DIR)


func after_test() -> void:
	if DirAccess.dir_exists_absolute(TEMP_TEST_DIR):
		var dir: DirAccess = DirAccess.open(TEMP_TEST_DIR)
		if dir:
			dir.list_dir_begin()
			var file_name: String = dir.get_next()
			while file_name != "":
				if not dir.current_is_dir():
					DirAccess.remove_absolute(TEMP_TEST_DIR + file_name)
				file_name = dir.get_next()
			dir.list_dir_end()
		DirAccess.remove_absolute(TEMP_TEST_DIR)


func _create_file(path: String, contents: String = "placeholder") -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(contents)
		f.close()


## Test 1: Verify Initial Default State
## Objective: Ensure `force_reload` strictly initializes to false.
## Description: Instantiate the preloader and inspect the exported toggle.
## Expected Result: The boolean property evaluates to false upon creation.
func test_verify_initial_default_state() -> void:
	var preloader: ResourcePreloader = auto_free(PRELOADER_SCRIPT.new())
	assert_bool(preloader.force_reload).is_false()


## Test 2: Verify Setter Logic in Non-Editor Runtime
## Objective: Ensure calling setter in non-editor runtime bypasses reload and leaves state untouched.
## Description: Invoke `_force_reload(true)` and `_force_reload(false)` directly, then assert `force_reload` remains false.
## Expected Result: Because `Engine.is_editor_hint()` evaluates to false, reload logic is bypassed and `force_reload` stays false.
func test_verify_setter_logic_in_non_editor_runtime() -> void:
	var preloader: ResourcePreloader = auto_free(PRELOADER_SCRIPT.new())
	
	preloader.force_reload = true
	assert_bool(preloader.force_reload).is_false()
	
	preloader._force_reload(false)
	assert_bool(preloader.force_reload).is_false()


## Test 3: Verify Ready Lifecycle Ignored at Runtime
## Objective: Ensure `_ready()` skips disk scanning outside the editor.
## Description: Call `_ready()` directly and verify no resources are loaded into the preloader.
## Expected Result: The resource list remains empty because the editor hint guard passes cleanly.
func test_verify_ready_lifecycle_ignored_at_runtime() -> void:
	var preloader: ResourcePreloader = auto_free(PRELOADER_SCRIPT.new())
	preloader._ready()
	assert_int(preloader.get_resource_list().size()).is_equal(0)


## Test 4: Verify Directory Scanner Ignores Invalid Paths
## Objective: Validate safe error handling when scanning a non-existent directory.
## Description: Pass a non-existent path to `load_textures_from_dir()`.
## Expected Result: The function catches the null directory gracefully and returns an empty array.
func test_verify_directory_scanner_ignores_invalid_paths() -> void:
	var preloader: ResourcePreloader = auto_free(PRELOADER_SCRIPT.new())
	var textures: Array[Texture2D] = preloader.load_textures_from_dir("user://invalid_directory_path_123/")
	assert_array(textures).is_empty()


## Test 5: Verify Directory Scanner Filters Non-PNG Files
## Objective: Ensure non-PNG files are skipped during scanning.
## Description: Create a `.txt` file in the sandbox and run `load_textures_from_dir()`.
## Expected Result: The scanner skips the `.txt` file entirely and returns an empty array.
func test_verify_directory_scanner_filters_non_png_files() -> void:
	_create_file(DUMMY_TXT, "Not an image")
	
	var preloader: ResourcePreloader = auto_free(PRELOADER_SCRIPT.new())
	var textures: Array[Texture2D] = preloader.load_textures_from_dir(TEMP_TEST_DIR)
	assert_array(textures).is_empty()


## Test 6: Verify Valid PNG Assets Load Successfully
## Objective: Verify `load_textures_from_dir()` successfully loads imported Texture2D resources from a project directory.
## Description: Point `load_textures_from_dir()` at the real project asset directory `res://files/random_decor/`.
## Expected Result: The scanner successfully reads valid PNGs, loads them as Texture2D objects, and returns a non-empty array.
func test_verify_valid_png_assets_load_successfully() -> void:
	var preloader: ResourcePreloader = auto_free(PRELOADER_SCRIPT.new())
	var textures: Array[Texture2D] = preloader.load_textures_from_dir(REAL_TEXTURE_DIR)
	
	assert_int(textures.size()).is_greater(0)
	for tex in textures:
		assert_object(tex).is_not_null()


## Test 7: Verify Ready Lifecycle IN Editor (Manual Fake)
## Objective: Ensure `_ready()` successfully scans and populates the resource list when inside the editor.
## Description: Use the manual fake, set `mock_is_in_editor = true`, and invoke `_ready()`.
## Expected Result: The resource list is populated with bush and decor textures natively.
func test_verify_ready_lifecycle_in_editor_fake() -> void:
	var preloader: FakePreloader = auto_free(FakePreloader.new())
	preloader.mock_is_in_editor = true
	
	preloader._ready()
	
	assert_int(preloader.get_resource_list().size()).is_greater(0)


## Test 8: Verify Setter Logic IN Editor (Manual Fake)
## Objective: Ensure setting `force_reload = true` executes the reload routine when inside the editor.
## Description: Use the manual fake, set `mock_is_in_editor = true`, and set `force_reload = true`.
## Expected Result: The block executes, calls `_ready()`, and safely resets `force_reload` back to false.
func test_verify_setter_logic_in_editor_fake() -> void:
	var preloader: FakePreloader = auto_free(FakePreloader.new())
	preloader.mock_is_in_editor = true
	
	preloader.force_reload = true
	
	assert_bool(preloader.force_reload).is_false()
	assert_int(preloader.get_resource_list().size()).is_greater(0)


## Test 9: Verify Corrupted PNG Warning Branch (Manual Fake)
## Objective: Ensure the script warns and skips safely when a texture fails to load.
## Description: Use the manual fake, set `mock_load_failure = true`, and scan the valid directory.
## Expected Result: The scanner processes the files but hits the negative branch, returning an empty array without crashing.
func test_verify_corrupted_png_warning_branch_fake() -> void:
	var preloader: FakePreloader = auto_free(FakePreloader.new())
	preloader.mock_load_failure = true
	
	var textures: Array[Texture2D] = preloader.load_textures_from_dir(REAL_TEXTURE_DIR)
	
	assert_array(textures).is_empty()
