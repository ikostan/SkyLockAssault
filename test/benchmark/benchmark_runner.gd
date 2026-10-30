## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## benchmark_runner.gd
##
## Performance baseline harness for Issue #1079 (Part 1) and its Part 2 rerun.
## Runs the fixed scenario once and reports results as "BENCH,..." console lines
## (scraped by Playwright on web). On desktop it also writes CSV files.
##
## Desktop: godot --headless --path . res://test/benchmark/benchmark_runner.tscn -- --out=<dir>
## Exit code: 0 = valid run, 2 = invalid run (fuel/ammo/speed check failed),
## 1 = setup failed (settings file could not be backed up; nothing was changed),
## 3 = settings file could not be restored (original kept as the .bench_backup file).
##
## Drives the game only through input and public state; changes no gameplay code.

extends Node

## Scenario constants. Part 2 must use identical values.
const DIFFICULTY: float = 0.5
const LOG_LEVEL: int = 1  # Globals.LogLevel.INFO, the project default
## Persisted gameplay/display settings pinned to their defaults, so a saved value
## (for example a low max_fuel) cannot change the scenario.
const MAX_FUEL: float = 100.0
const ENABLE_DEBUG_LOGGING: bool = false
const SHOW_FPS: bool = false
const DESKTOP_MAX_FPS: int = 60
const WARMUP_S: float = 5.0
const MEASURE_S: float = 60.0
const RELOAD_CYCLES: int = 10
const BULLET_CLEAR_TIMEOUT_S: float = 10.0
## Pause before quitting so the audio server can release playbacks of the last freed scene;
## quitting right after freeing playing AudioStreamPlayer2Ds reports them as leaked at exit.
const EXIT_SETTLE_S: float = 1.0

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

## Godot updates TIME_PROCESS / TIME_PHYSICS_PROCESS once per second with the WORST frame of
## that second, so these hold one value per second, not per frame.
var _proc_worst_ms: Array[float] = []
var _phys_worst_ms: Array[float] = []
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
	if not _backup_settings():
		# Nothing has been changed yet; stop before touching the real settings file.
		_emit("done", ["invalid"])
		get_tree().quit(1)
		return
	_apply_scenario_settings()
	if not _is_web:
		Engine.max_fps = DESKTOP_MAX_FPS

	var root_children_before: int = get_tree().root.get_child_count()
	var valid: Dictionary = await _run_gameplay_phase()
	await _wait_for_bullets_to_clear(root_children_before)
	await _run_reload_phase()

	_report(valid)
	var restored: bool = _restore_settings()
	# A run that leaves the user's settings changed is never reported as valid.
	_emit("done", ["valid" if valid["ok"] and restored else "invalid"])
	await get_tree().create_timer(EXIT_SETTLE_S).timeout
	if not restored:
		get_tree().quit(3)
	else:
		get_tree().quit(0 if valid["ok"] else 2)


## Pins every persisted setting (Globals.persisted_schema) and the volumes, so
## each run uses the same scenario whatever the settings file contained.
## Runs before main_scene is loaded: the player reads max_fuel in its setup.
func _apply_scenario_settings() -> void:
	Globals.settings.current_log_level = LOG_LEVEL
	Globals.settings.difficulty = DIFFICULTY
	Globals.settings.enable_debug_logging = ENABLE_DEBUG_LOGGING
	Globals.settings.max_fuel = MAX_FUEL
	Globals.settings.show_fps = SHOW_FPS
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
	var proc_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_proc_worst_ms.append(proc_ms)
	_phys_worst_ms.append(phys_ms)
	var row: Array = [
		snappedf(_elapsed, 0.001),
		Performance.get_monitor(Performance.TIME_FPS),
		snappedf(proc_ms, 0.0001),
		snappedf(phys_ms, 0.0001),
		int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)),
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		_saves,
	]
	# Buffered, not printed: console output during the measured window would be measured too.
	_sec_rows.append(",".join(row.map(func(v: Variant) -> String: return str(v))))


## Counts settings saves: outside settings loading, each emission triggers one save.
func _on_setting_changed(_setting_name: String, _new_value: Variant) -> void:
	if _measuring:
		_saves += 1


## Prints the summary and, on desktop, writes CSV files.
func _report(valid: Dictionary) -> void:
	var p: Dictionary = _stats(_proc_worst_ms)
	var ph: Dictionary = _stats(_phys_worst_ms)
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
	for row: String in _sec_rows:
		print("BENCH,sec," + row)
	for row: String in _reload_rows:
		print("BENCH,reload," + row)
	if _is_web:
		# The web build writes no CSV files, so the per-frame intervals go to the console
		# as one line (values joined by ";") for run_web.py to save as frames_interval_ms.csv.
		print("BENCH,frames," + ";".join(_to_strings(_frame_ms)))
	_emit("summary", summary)

	if _is_web or _out_dir.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_write_csv(
		"seconds.csv",
		(
			"t_s,fps,proc_worst_ms,phys_worst_ms,"
			+ "mem_static,mem_static_max,objects,nodes,resources,orphans,saves"
		),
		_sec_rows
	)
	_write_csv("reload.csv", "cycle,orphans,objects", _reload_rows)
	_write_csv("frames_interval_ms.csv", "interval_ms", _to_strings(_frame_ms))
	_write_csv(
		"summary.csv",
		(
			"godot,os,env,"
			+ "proc_worst_n,proc_worst_avg_ms,proc_worst_p95_ms,proc_worst_max_ms,"
			+ "phys_worst_n,phys_worst_avg_ms,phys_worst_p95_ms,phys_worst_max_ms,"
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
## Returns false, without changing anything, if the copy cannot be made safely.
func _backup_settings() -> bool:
	if _is_web:
		return true
	var backup_abs: String = ProjectSettings.globalize_path(_backup_path)
	if FileAccess.file_exists(_backup_path):
		# Left by an interrupted run and possibly the only copy of the original file.
		push_error("Benchmark: %s already exists; restore or delete it first." % backup_abs)
		return false
	_had_settings_file = FileAccess.file_exists(_settings_path)
	if not _had_settings_file:
		return true
	var err: Error = DirAccess.copy_absolute(
		ProjectSettings.globalize_path(_settings_path), backup_abs
	)
	if err != OK:
		push_error("Benchmark: cannot back up settings (%s)." % error_string(err))
		return false
	return true


## Puts the original settings file back. The backup is only deleted after a
## successful restore, so a failed copy never loses the original.
## Returns false if the settings file could not be put back.
func _restore_settings() -> bool:
	if _is_web:
		return true
	var settings_abs: String = ProjectSettings.globalize_path(_settings_path)
	var backup_abs: String = ProjectSettings.globalize_path(_backup_path)
	if _had_settings_file:
		var err: Error = DirAccess.copy_absolute(backup_abs, settings_abs)
		if err != OK:
			push_error(
				(
					"Benchmark: cannot restore settings (%s); original kept at %s"
					% [error_string(err), backup_abs]
				)
			)
			return false
		DirAccess.remove_absolute(backup_abs)
	elif FileAccess.file_exists(_settings_path):
		# There was no settings file before the run, so remove the one the run created.
		var err: Error = DirAccess.remove_absolute(settings_abs)
		if err != OK:
			push_error(
				"Benchmark: cannot remove settings created by the run (%s)." % error_string(err)
			)
			return false
	return true
