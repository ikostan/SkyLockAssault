## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## Loading Screen Script: loading_screen.gd
##
## Manages background loading of the next scene with smooth progress bar.
## Uses Godot's ResourceLoader for threaded loading.
## Transitions to the loaded scene upon completion.
##
## :vartype progress_bar: ProgressBar
## :vartype label: Label
## :vartype loader_progress: float

extends Control

var loader_progress: float = 0.0  # Current smoothed progress value.
var min_load_time: float = 0.3  # Minimum loading time in seconds for visibility.
var load_start_time: float = 0.0  # Timestamp when loading starts.
var is_scene_loaded: bool = false  # Flag to track if the scene is fully loaded.
var scene: PackedScene = null  # Holder for the loaded scene.
var load_failed: bool = false  # Flag if loading request failed.
var transitioning: bool = false  # Flag to prevent multiple scene changes.

@onready var progress_bar: ProgressBar = $Panel/Container/ProgressBar
@onready var label: Label = $Panel/Container/Label


func _ready() -> void:
	load_start_time = Time.get_ticks_msec() / 1000.0

	if OS.has_feature("web"):
		min_load_time = 0.3
	else:
		min_load_time = 0.2

	if Globals.next_scene == "":
		Globals.log_message("Next scene path is empty!", Globals.LogLevel.ERROR)
		load_failed = true
		return

	# Explicit check to catch missing/invalid paths immediately
	if not ResourceLoader.exists(Globals.next_scene):
		Globals.log_message(
			"Next scene does not exist: " + Globals.next_scene, Globals.LogLevel.ERROR
		)
		load_failed = true
		return

	# Start background loading with sub-threads
	var err: int = ResourceLoader.load_threaded_request(Globals.next_scene, "", true)
	if err != OK:
		Globals.log_message("Failed to start loading: " + str(err), Globals.LogLevel.ERROR)
		load_failed = true
	else:
		Globals.log_message("Loading started successfully.", Globals.LogLevel.DEBUG)


func _process(delta: float) -> void:
	var elapsed_time: float = (Time.get_ticks_msec() / 1000.0) - load_start_time

	var real_progress: float = 0.0
	if is_scene_loaded:
		real_progress = 100.0
	elif load_failed:
		real_progress = 0.0
	else:
		var progress_array: Array = []
		var status: int = ResourceLoader.load_threaded_get_status(
			Globals.next_scene, progress_array
		)

		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if progress_array.size() > 0:
				real_progress = progress_array[0] * 100.0
		elif status == ResourceLoader.THREAD_LOAD_LOADED:
			real_progress = 100.0
			if not is_scene_loaded:
				is_scene_loaded = true
				scene = ResourceLoader.load_threaded_get(Globals.next_scene)
				Globals.log_message("Scene loaded successfully.", Globals.LogLevel.DEBUG)
		elif (
			status
			in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]
		):
			Globals.log_message("Loading failed or invalid.", Globals.LogLevel.ERROR)
			load_failed = true

	var target_progress: float = 100.0 if load_failed else real_progress

	# Smooth progress bar movement
	loader_progress = move_toward(loader_progress, target_progress, delta * 120.0)
	progress_bar.value = loader_progress

	# Proceed when resource is ready, bar visually reached 100%, and minimum display time elapsed
	if (
		(is_scene_loaded or load_failed)
		and loader_progress >= 99.9
		and elapsed_time >= min_load_time
		and not transitioning
	):
		transitioning = true
		_change_to_next_scene()


func _change_to_next_scene() -> void:
	# Ensure the bar visually fills completely to 100%
	progress_bar.value = 100.0

	# Cache and reset global scene path synchronously before yielding
	var target_path: String = Globals.next_scene
	Globals.next_scene = ""

	# 1. Log in-engine completion ticks right before starting the hold
	Globals.log_message(
		"Scene loaded successfully. (ticks: %d)" % Time.get_ticks_msec(), Globals.LogLevel.DEBUG
	)

	# 1-second pause at 100% so the player clearly sees completion
	await get_tree().create_timer(1.0).timeout

	if target_path == "":
		Globals.log_message("Empty next_scene - returning to main menu.", Globals.LogLevel.ERROR)
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return

	if load_failed or scene == null:
		Globals.log_message("Fallback: Loading scene directly.", Globals.LogLevel.WARNING)
		get_tree().change_scene_to_file(target_path)
		return

	# 2. Log in-engine instantiate ticks immediately before instantiation
	Globals.log_message(
		"[SWAP TIMING] 1. .instantiate() (ticks: %d)" % Time.get_ticks_msec(),
		Globals.LogLevel.DEBUG
	)
	var new_scene_node := scene.instantiate()

	# 2. Add to Root and trigger _enter_tree() & _ready()
	get_tree().root.add_child(new_scene_node)

	# 3. Swap active scene and free the loading screen
	get_tree().current_scene = new_scene_node
	queue_free()
