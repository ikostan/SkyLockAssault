## test_version_display.gd
## GUT unit tests for version display in options_menu.gd and globals.gd.
## Covers loading and displaying game version from ProjectSettings.
## Test Plan: Based on version functionality in globals and options_menu.

extends "res://addons/gut/test.gd"

var options_scene: PackedScene = load("res://scenes/options_menu.tscn")
var options_instance: CanvasLayer


## Per-test setup: Reset ProjectSettings and Globals (no instantiation here).
## :rtype: void
func before_each() -> void:
	if ProjectSettings.has_setting("application/config/version"):
		ProjectSettings.clear("application/config/version")
	Globals.game_version = ProjectSettings.get_setting("application/config/version", "n/a") as String


## Per-test cleanup: Free instance if exists.
## :rtype: void
func after_each() -> void:
	if is_instance_valid(options_instance):
		options_instance.queue_free()
		await get_tree().process_frame  # Wait for free (helps leaks)


## TC-Version-01 | No version in ProjectSettings | Load globals.game_version | Equals "n/a" (default).
## :rtype: void
func test_tc_version_01() -> void:
	assert_eq(Globals.game_version, "n/a")


## TC-Version-02 | Version set in ProjectSettings | Load globals.game_version | Equals set value (e.g., "v1.0.0").
## :rtype: void
func test_tc_version_02() -> void:
	ProjectSettings.set_setting("application/config/version", "v1.0.0")
	Globals.game_version = ProjectSettings.get_setting("application/config/version", "n/a") as String
	assert_eq(Globals.game_version, "v1.0.0")


## TC-Version-03 | Default version | Options menu _ready | VersionLabel.text = "Version: n/a".
## :rtype: void
func test_tc_version_03() -> void:
	options_instance = options_scene.instantiate() as CanvasLayer
	add_child_autofree(options_instance)
	await get_tree().process_frame  # Await _ready
	var version_label: Label = options_instance.get_node("Panel/OptionsVBoxContainer/VersionLabel")
	assert_eq(version_label.text, "Version: n/a")


## TC-Version-04 | Custom version set | Options menu _ready | VersionLabel.text = "Version: v1.1.1".
## :rtype: void
func test_tc_version_04() -> void:
	ProjectSettings.set_setting("application/config/version", "v1.1.1")
	Globals.game_version = ProjectSettings.get_setting("application/config/version", "n/a") as String
	options_instance = options_scene.instantiate() as CanvasLayer
	add_child_autofree(options_instance)
	await get_tree().process_frame  # Await _ready
	var version_label: Label = options_instance.get_node("Panel/OptionsVBoxContainer/VersionLabel")
	assert_eq(Globals.game_version, "v1.1.1")
	assert_eq(version_label.text, "Version: v1.1.1")


## TC-Version-05 | Empty string in ProjectSettings | Load globals.game_version | Equals "" (overrides default).
## :rtype: void
func test_tc_version_05() -> void:
	ProjectSettings.set_setting("application/config/version", "")
	Globals.game_version = ProjectSettings.get_setting("application/config/version", "n/a") as String
	assert_eq(Globals.game_version, "")
