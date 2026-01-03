## test_version_display.gd
## GUT unit tests for version display in options_menu.gd and globals.gd.
## Covers loading and displaying game version from ProjectSettings.

extends "res://addons/gut/test.gd"

var options_scene: PackedScene = load("res://scenes/options_menu.tscn")  # Options scene preload.
var options_instance: CanvasLayer  # Options instance.

## Per-test setup: Clear setting for default.
## :rtype: void
func before_each() -> void:
	if ProjectSettings.has_setting("application/config/version"):
		ProjectSettings.clear("application/config/version")


## Per-test cleanup: Free instance.
## :rtype: void
func after_each() -> void:
	if is_instance_valid(options_instance):
		options_instance.queue_free()
		await get_tree().process_frame


## TC-Version-01 | No version | Equals "n/a".
## :rtype: void
func test_tc_version_01() -> void:
	assert_eq(Globals.get_game_version(), "n/a")


## TC-Version-02 | Set version | Equals set value.
## :rtype: void
func test_tc_version_02() -> void:
	Globals.set_game_version_for_tests("v1.0.0")
	assert_eq(Globals.get_game_version(), "v1.0.0")


## TC-Version-03 | Default in menu.
## :rtype: void
func test_tc_version_03() -> void:
	options_instance = options_scene.instantiate() as CanvasLayer
	add_child_autofree(options_instance)
	await get_tree().process_frame
	var version_label: Label = options_instance.get_node("Panel/OptionsVBoxContainer/VersionLabel")
	assert_eq(version_label.text, "Version: n/a")


## TC-Version-04 | Custom in menu.
## :rtype: void
func test_tc_version_04() -> void:
	Globals.set_game_version_for_tests("v1.1.1")
	options_instance = options_scene.instantiate() as CanvasLayer
	add_child_autofree(options_instance)
	await get_tree().process_frame
	var version_label: Label = options_instance.get_node("Panel/OptionsVBoxContainer/VersionLabel")
	assert_eq(Globals.get_game_version(), "v1.1.1")
	assert_eq(version_label.text, "Version: v1.1.1")


## TC-Version-05 | Empty string | Equals "".
## :rtype: void
func test_tc_version_05() -> void:
	Globals.set_game_version_for_tests("")
	assert_eq(Globals.get_game_version(), "")
