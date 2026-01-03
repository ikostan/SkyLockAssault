## test_version_display.gd
## GUT unit tests for version display in options_menu.gd and globals.gd.
## Covers loading and displaying game version from ProjectSettings.
## Test Plan: Based on version functionality in globals and options_menu.

extends "res://addons/gut/test.gd"

var options_scene: PackedScene = load("res://scenes/options_menu.tscn")
var options_instance: CanvasLayer


## Per-test setup: Reset via helpers.
## :rtype: void
func before_each() -> void:
	Globals.set_game_version_for_tests("")  # Clear to "" (triggers default in get)


## Per-test cleanup: Free instance if exists.
## :rtype: void
func after_each() -> void:
	if is_instance_valid(options_instance):
		options_instance.queue_free()
		await get_tree().process_frame  # Wait for free (helps leaks)


## TC-Version-01 | No version | Equals "n/a".
func test_tc_version_01() -> void:
	assert_eq(Globals.get_game_version(), "n/a")


## TC-Version-02 | Set version | Equals set value.
func test_tc_version_02() -> void:
	Globals.set_game_version_for_tests("v1.0.0")
	assert_eq(Globals.get_game_version(), "v1.0.0")


## TC-Version-03 | Default in menu.
func test_tc_version_03() -> void:
	options_instance = options_scene.instantiate() as CanvasLayer
	add_child_autofree(options_instance)
	await get_tree().process_frame
	var version_label: Label = options_instance.get_node("Panel/OptionsVBoxContainer/VersionLabel")
	assert_eq(version_label.text, "Version: n/a")


## TC-Version-04 | Custom in menu.
func test_tc_version_04() -> void:
	Globals.set_game_version_for_tests("v1.1.1")
	options_instance = options_scene.instantiate() as CanvasLayer
	add_child_autofree(options_instance)
	await get_tree().process_frame
	var version_label: Label = options_instance.get_node("Panel/OptionsVBoxContainer/VersionLabel")
	assert_eq(Globals.get_game_version(), "v1.1.1")
	assert_eq(version_label.text, "Version: v1.1.1")


## TC-Version-05 | Empty string | Equals "".
func test_tc_version_05() -> void:
	Globals.set_game_version_for_tests("")
	assert_eq(Globals.get_game_version(), "")
