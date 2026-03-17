# Development Guide for Sky Lock Assault

This guide provides practical tips and examples for developing
"Sky Lock Assault," a top-down airplane shooter built in Godot v4.5.
It's aimed at beginners learning game dev, focusing on the project's
current features (e.g., menu, movement) and future expansions
(e.g., Milestone 5: fuel/weapons). Expand as needed—contributions welcome!

## 1. Project Overview

- **Engine**: Godot v4.4 (64-bit Windows compatible).
- **Tools**: Docker Desktop v4.45 for local web testing (<http://localhost:9090>),
  GitHub Desktop v3.5 for version control, GDUnit4 v5.1.1 for unit tests.
- **Goal**: Web browser game deployed to itch.io via GitHub Actions.
- **Key Files**:
  - `project.godot`: Entry point.
  - `scenes/main_menu.tscn`: Menu scene with buttons.
  - `scripts/main_menu.gd`: Handles signals, quit logic.
  - `scripts/player.gd`: Top-down movement.
  - `scripts/Globals.gd`: Global vars (e.g., logging).
  - `.github/workflows/`: CI/CD for deploy, tests.

Run locally: Open in Godot editor, F5 for play. For web: Export to HTML5,
use Docker infra/compose.yaml.

## 2. Setup and Environment

1. Clone: `git clone https://github.com/ikostan/SkyLockAssault` via
   GitHub Desktop.
2. Import: Open project.godot in Godot editor.
3. Addons: Install GDUnit4 v5.1.1 from AssetLib for testing
   (e.g., player movement tests).
4. Docker: In infra/, run `docker compose up -d` for web preview.
5. Project Settings: Input > Actions for movement (e.g., "move_up" = W);
   Display > Window > Mode = Windowed.

Best Practice: Use branches for features (e.g., git checkout -b feature/fuel).

## 3. Core Mechanics

### Top-Down Movement (player.gd)

Use CharacterBody2D for physics. Example code:
<!-- markdownlint-disable line-length -->
```gdscript
extends CharacterBody2D

@export var speed: float = 300.0

func _physics_process(delta: float) -> void:
    var direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
    velocity = direction * speed
    move_and_slide()
```

- Tip: Add boundaries with clamp() to prevent off-screen movement.
- Test: Run scene, use arrows/WASD.

### Menu System (main_menu.gd)

Use Control node for UI. Connect buttons with signals:

```gdscript
@onready var start_button: Button = $VBoxContainer/StartButton

func _ready() -> void:
    start_button.pressed.connect(_on_start_pressed)

func _on_start_pressed() -> void:
    get_tree().change_scene_to_file("res://scenes/game_level.tscn")
```

- Web Quit: Use JavaScriptBridge for browser close:

```gdscript
if OS.get_name() == "Web":
    JavaScriptBridge.eval("window.close()")
else:
    get_tree().quit()
```

- Tip: Use Tween for fades (e.g., modulate.a from 0 to 1).

### Working with Game Settings

The project now uses an Observer Pattern for configuration.
When adding a new setting:

1. Define the Property: Add the property to
   `scripts/game_settings_resource.gd` with
   a proper setter that emits the `setting_changed` signal.
2. Update Globals: Add the new property to the `_save_settings()` and
   `_load_settings()` functions in globals.gd to ensure persistence.
3. UI Integration: Connect your UI elements to the `Globals.settings.setting_changed`
   signal. Crucial: Always disconnect this signal in `_on_tree_exited()` to prevent
   memory leaks and stale observers.
4. No Manual Saves: Do not call save functions directly from the UI; changing the
   resource value is sufficient to trigger a save.

### The technical documentation for the "Working with Game Settings" section.

This documentation explicitly defines the signal signature and the specific
files responsible for the **Observer Pattern** architecture.

To modify or observe game settings, interact with the `GameSettingsResource`.
The system uses a decoupled architecture where the UI only modifies data,
and a centralized observer handles persistence and logging.

#### 1. Signal Signature: `setting_changed`

When connecting a UI element or a new system to the settings resource,
use the following signature:

* **Signal Name**: `setting_changed`
* **Parameters**:
  * `setting_name`: **String** (The name of the property that changed, e.g., "difficulty") 
  * `new_value`: **Variant** (The newly assigned, clamped value) 

#### 2. Core Files Reference

| Component                 | File Path                                 | Responsibility                                                                    |
|---------------------------|-------------------------------------------|-----------------------------------------------------------------------------------|
| **Data Source (Subject)** | `res://scripts/game_settings_resource.gd` | Defines properties (difficulty, log level), performs clamping, and emits signals. |
| **Logic Observer** | `res://scripts/globals.gd` | Connects to the resource to trigger centralized logging and `_save_settings()`. |
| **UI Observer (Gameplay)** | `res://scripts/gameplay_settings.gd` | Syncs sliders and labels with the resource state using `set_value_no_signal`. |
| **UI Observer (Advanced)** | `res://scripts/advanced_settings.gd` | Syncs log level dropdowns and handles web-specific JavaScript callbacks. |
| **Persistence Settings** | `res://scripts/settings.gd` | Manages low-level `InputMap` serialization and legacy migration logic. |

#### 3. Connection Example for UI

To prevent infinite recursion, UI handlers should always check for equality or use `no_signal` methods when responding to the resource:

```gdscript
# Example from gameplay_settings.gd
func _ready() -> void:
    [cite_start]Globals.settings.setting_changed.connect(_on_external_setting_changed)

func _on_external_setting_changed(setting_name: String, new_value: Variant) -> void:
    if setting_name == "difficulty":
        [cite_start]difficulty_slider.set_value_no_signal(float(new_value))

```
<!-- markdownlint-enable line-length -->

### Global Utilities (Globals.gd)

Autoload for shared logic (e.g., logging):

```gdscript
extends Node

enum LogLevel { DEBUG, INFO, WARNING, ERROR }

func log_message(message: String, level: LogLevel = LogLevel.INFO) -> void:
    print("[%s] %s" % [LogLevel.keys()[level], message])
```

- Tip: Use for debug in _ready() functions.

## 4. Testing

- **Unit Tests**: GDUnit4 v5.1.1—write in `tests/`
  (e.g., test_player.gd for movement asserts).
- **Functional Tests**: browser_test.py with Playwright—tests web export
  (canvas load, title).
- CI/CD: Actions run on push/PR; check summaries in logs/artifacts.

Best Practice: Test web exports locally with Docker before pushing.

## 5. Deployment

- Export: Project > Export > Web preset to export/web.
- CI: deploy.yml uses Butler to push to itch.io (secrets: BUTLER_CREDENTIALS).
- Tip: Align paths (e.g., build/html5) across workflows.

## 6. Best Practices and Tips

- **Godot Signals**: Prefer over polling for events (e.g., button presses).
- **2D Nodes**: CharacterBody2D for physics, Area2D for collisions (e.g., bullets).
- **Web Optimizations**: Use JavaScriptBridge for browser-specific features;
  test in headless Chrome via Playwright.
- **Version Control**: Commit often; use issues for tasks
  (e.g., #82 for this guide).
- **Resources**: Official Godot docs (docs.godotengine.org);
  GDQuest tutorials for top-down shooters.

## 7. Future Expansions (Milestone 5+)

- Fuel: Timer in player.gd for depletion, ProgressBar UI.
- Weapons: Area2D bullets with _on_body_entered().
- Levels: Multiple tscn scenes, change_scene_to_file().
- Update this guide after implementations.

Contributions: See CONTRIBUTING.md. Report bugs in issues.
