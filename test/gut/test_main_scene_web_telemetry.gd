## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## Focused scene integration test for telemetry creation and platform gating.
extends "res://addons/gut/test.gd"

const TelemetryAdapter = preload("res://scripts/system/web_telemetry_adapter.gd")


func test_main_scene_creates_telemetry_with_platform_appropriate_lifetime() -> void:
	var scene: MainScene = preload(GamePaths.MAIN_SCENE).instantiate()
	# Prevent gameplay from changing fuel while checking scene initialization.
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	add_child_autofree(scene)
	var adapter: Node = scene.web_telemetry_adapter
	assert_true(is_instance_valid(adapter), "MainScene must create the telemetry adapter.")
	if not is_instance_valid(adapter):
		return
	assert_eq(adapter.get_script(), TelemetryAdapter)
	assert_eq(adapter.get_parent(), scene, "Scene lifetime must own telemetry lifetime.")

	if OS.has_feature("web"):
		assert_false(adapter.is_queued_for_deletion())
		assert_true(scene.player.fuel_resource.fuel_changed.is_connected(adapter._on_fuel_changed))
		assert_eq(adapter._fuel_resource, scene.player.fuel_resource)
	else:
		assert_true(adapter.is_queued_for_deletion())
		assert_false(scene.player.fuel_resource.fuel_changed.is_connected(adapter._on_fuel_changed))
		await get_tree().process_frame
		assert_false(is_instance_valid(adapter), "Native scenes must release the adapter.")
