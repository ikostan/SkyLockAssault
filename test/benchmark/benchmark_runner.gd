## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## benchmark_runner.gd
##
## Performance baseline harness for Issue #1079 (Part 1) and its Part 2 rerun.
## Runs the fixed scenario once and reports results as "BENCH,..." console lines
## (scraped by Playwright on web). On desktop it also writes CSV files.
##
## Desktop: godot --headless --path . res://test/benchmark/benchmark_runner.tscn -- --out=<dir>
## Exit code: 0 = valid run, 2 = invalid run (fuel/ammo/speed check failed).
##
## Drives the game only through input and public state; changes no gameplay code.

extends Node

## Scenario constants. Part 2 must use identical values.
const DIFFICULTY: float = 0.5
const LOG_LEVEL: int = 1  # Globals.LogLevel.INFO, the project default
const DESKTOP_MAX_FPS: int = 60
const WARMUP_S: float = 5.0
const MEASURE_S: float = 60.0
const RELOAD_CYCLES: int = 10
const BULLET_CLEAR_TIMEOUT_S: float = 10.0

var _out_dir: String = ""
var _is_web: bool = OS.has_feature("web")
var _settings_path: String = Settings.CONFIG_PATH
var _backup_path: String = Settings.CONFIG_PATH + ".bench_backup"
var _had_settings_file: bool = false

var _firing: bool = false
var _measuring: bool = false
var _sec_accum: float = 0.0
var _elapsed: float = 0.0
var _saves: int = 0

var _process_ms: Array[float] = []
var _physics_ms: Array[float] = []
var _frame_ms: Array[float] = []
var _last_frame_usec: int = 0
var _sec_rows: Array[String] = []
var _reload_rows: Array[String] = []

var _fire_press := InputEventAction.new()
var _fire_release := InputEventAction.new()


func _ready() -> void:
	_fire_press.action = "fire"
	_fire_press.pressed = true
	_fire_release.action = "fire"
	_fire_release.pressed = false
	_parse_args()
	_run.call_deferred()


## Reads "--out=<dir>" from the user arguments after "--".
func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")


## Full scenario: setup, gameplay load, bullet drain, reload loop, report, restore.
func _run() -> void:
	_backup_settings()
	_apply_scenario_settings()
	if not _is_web:
		Engine.max_fps = DESKTOP_MAX_FPS

	var root_children_before: int = get_tree().root.get_child_count()
	var valid: Dictionary = await _run_gameplay_phase()
	await _wait_for_bullets_to_clear(root_children_before)
	await _run_reload_phase()

	_report(valid)
	_restore_settings()
	_emit("done", ["valid" if valid["ok"] else "invalid"])
	get_tree().quit(0 if valid["ok"] else 2)


## Fixed difficulty, log level and default (unmuted) volumes for every run.
func _apply_scenario_settings() -> void:
	Globals.settings.current_log_level = LOG_LEVEL
	Globals.settings.difficulty = DIFFICULTY
	AudioManager.reset_volumes()


## Gameplay load: 5 s warm-up, then 60 s measured. Returns the validity check.
func _run_gameplay_phase() -> Dictionary:
	var main: Node = load(GamePaths.MAIN_SCENE).instantiate()
	add_child(main)
	await get_tree().process_frame

	Globals.settings.setting_changed.connect(_on_setting_changed)
	Input.action_press("speed_up")
	_firing = true

	await get_tree().create_timer(WARMUP_S).timeout
	_last_frame_usec = 0
	_measuring = true
	await get_tree().create_timer(MEASURE_S).timeout
	_measuring = false

	var player: Node = main.get("player")
	var fuel: float = player.fuel_resource.current_fuel
	var speed: float = player.speed_resource.current_speed
	var max_speed: float = player.speed_resource.max_speed
	var ammo: int = player.weapon.weapon_resource.current_ammo

	_firing = false
	Input.action_release("speed_up")
	Globals.settings.setting_changed.disconnect(_on_setting_changed)
	remove_child(main)
	main.free()

	var ok: bool = fuel > 0.0 and ammo > 0 and speed >= max_speed * 0.99
	return {"ok": ok, "fuel": fuel, "ammo": ammo, "speed": speed, "max_speed": max_speed}


## Bullets live under the scene root until their lifetime timer expires; wait for them so
## they don't pollute the reload-loop counts.
func _wait_for_bullets_to_clear(root_children_before: int) -> void:
	var waited: float = 0.0
	while get_tree().root.get_child_count() > root_children_before:
		if waited >= BULLET_CLEAR_TIMEOUT_S:
			push_warning("Benchmark: bullets still alive after %.0f s" % BULLET_CLEAR_TIMEOUT_S)
			return
		await get_tree().process_frame
		waited += get_process_delta_time()


## Reload loop: load and free main_scene, wait 2 frames, record orphans each cycle.
func _run_reload_phase() -> void:
	for cycle: int in range(1, RELOAD_CYCLES + 1):
		var main: Node = load(GamePaths.MAIN_SCENE).instantiate()
		add_child(main)
		await get_tree().process_frame
		remove_child(main)
		main.free()
		await get_tree().process_frame
		await get_tree().process_frame
		var orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
		var objects: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
		_reload_rows.append("%d,%d,%d" % [cycle, orphans, objects])
		_emit("reload", [cycle, orphans, objects])


func _physics_process(_delta: float) -> void:
	if _measuring:
		_physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)


func _process(delta: float) -> void:
	if _firing:
		# One shot per press event (player.gd uses event.is_action_pressed), so inject a
		# press every frame; the weapon cooldown decides which become shots. Done here, not in
		# _physics_process, because physics can step twice in one frame and Godot warns when
		# the same event object is parsed twice in a frame.
		Input.parse_input_event(_fire_press)
		Input.parse_input_event(_fire_release)
	if not _measuring:
		return
	_process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	# Wall-clock interval between frames: what a player actually experiences as a hitch.
	var now_usec: int = Time.get_ticks_usec()
	if _last_frame_usec > 0:
		_frame_ms.append((now_usec - _last_frame_usec) / 1000.0)
	_last_frame_usec = now_usec
	_elapsed += delta
	_sec_accum += delta
	if _sec_accum >= 1.0:
		_sec_accum -= 1.0
		_sample_second()


## Once-per-second monitors.
func _sample_second() -> void:
	var row: Array = [
		snappedf(_elapsed, 0.001),
		Performance.get_monitor(Performance.TIME_FPS),
		int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)),
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		_saves,
	]
	_sec_rows.append(",".join(row.map(func(v: Variant) -> String: return str(v))))
	_emit("sec", row)


## Counts settings saves: outside settings loading, each emission triggers one save.
func _on_setting_changed(_setting_name: String, _new_value: Variant) -> void:
	if _measuring:
		_saves += 1


## Prints the summary and, on desktop, writes CSV files.
func _report(valid: Dictionary) -> void:
	var p: Dictionary = _stats(_process_ms)
	var ph: Dictionary = _stats(_physics_ms)
	var fr: Dictionary = _stats(_frame_ms)
	var summary: Array = [
		Engine.get_version_info()["string"],
		OS.get_name(),
		"web" if _is_web else "desktop",
		p["n"],
		p["avg"],
		p["p95"],
		p["max"],
		ph["n"],
		ph["avg"],
		ph["p95"],
		ph["max"],
		fr["n"],
		fr["avg"],
		fr["p95"],
		fr["max"],
		_saves,
		valid["fuel"],
		valid["ammo"],
		valid["speed"],
		valid["ok"],
	]
	_emit("summary", summary)

	if _is_web or _out_dir.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_write_csv(
		"seconds.csv",
		"t_s,fps,mem_static,mem_static_max,objects,nodes,resources,orphans,saves",
		_sec_rows
	)
	_write_csv("reload.csv", "cycle,orphans,objects", _reload_rows)
	_write_csv("frames_process_ms.csv", "process_ms", _to_strings(_process_ms))
	_write_csv("frames_physics_ms.csv", "physics_ms", _to_strings(_physics_ms))
	_write_csv("frames_interval_ms.csv", "interval_ms", _to_strings(_frame_ms))
	_write_csv(
		"summary.csv",
		(
			"godot,os,env,proc_n,proc_avg_ms,proc_p95_ms,proc_max_ms,"
			+ "phys_n,phys_avg_ms,phys_p95_ms,phys_max_ms,"
			+ "frame_n,frame_avg_ms,frame_p95_ms,frame_max_ms,"
			+ "saves,fuel_end,ammo_end,speed_end,valid"
		),
		[",".join(summary.map(func(v: Variant) -> String: return str(v)))]
	)


## avg / p95 (nearest rank) / max of a sample list, in ms.
func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"n": 0, "avg": 0.0, "p95": 0.0, "max": 0.0}
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var total: float = 0.0
	for v: float in sorted:
		total += v
	var idx: int = clampi(ceili(0.95 * sorted.size()) - 1, 0, sorted.size() - 1)
	return {
		"n": sorted.size(),
		"avg": snappedf(total / sorted.size(), 0.0001),
		"p95": snappedf(sorted[idx], 0.0001),
		"max": snappedf(sorted[sorted.size() - 1], 0.0001),
	}


func _to_strings(values: Array[float]) -> Array[String]:
	var out: Array[String] = []
	for v: float in values:
		out.append(str(snappedf(v, 0.0001)))
	return out


func _write_csv(file_name: String, header: String, rows: Array[String]) -> void:
	var f := FileAccess.open(_out_dir.path_join(file_name), FileAccess.WRITE)
	if f == null:
		push_error("Benchmark: cannot write %s (%s)" % [file_name, FileAccess.get_open_error()])
		return
	f.store_line(header)
	for row: String in rows:
		f.store_line(row)
	f.close()


## Prints one machine-readable line: BENCH,<kind>,<values...>
func _emit(kind: String, values: Array) -> void:
	print("BENCH,%s,%s" % [kind, ",".join(values.map(func(v: Variant) -> String: return str(v)))])


## Desktop only: every setting change writes the real settings file, so keep a copy.
## Web runs use a fresh browser context instead.
func _backup_settings() -> void:
	if _is_web:
		return
	_had_settings_file = FileAccess.file_exists(_settings_path)
	if _had_settings_file:
		DirAccess.copy_absolute(
			ProjectSettings.globalize_path(_settings_path),
			ProjectSettings.globalize_path(_backup_path)
		)


func _restore_settings() -> void:
	if _is_web:
		return
	var settings_abs: String = ProjectSettings.globalize_path(_settings_path)
	var backup_abs: String = ProjectSettings.globalize_path(_backup_path)
	if _had_settings_file:
		DirAccess.copy_absolute(backup_abs, settings_abs)
		DirAccess.remove_absolute(backup_abs)
	elif FileAccess.file_exists(_settings_path):
		DirAccess.remove_absolute(settings_abs)
