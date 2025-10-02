# Contributing to Sky Lock Assault

Thanks for your interest in contributing! This is a learning-focused Godot 4.5
project on Windows 10 64-bit, building a top-down web shooter. We welcome
contributions from beginners—focus on clear, tested changes.

## Beginner Tasks

Check issues labeled "good first issue" for easy starts, like:

- Adding sound effects (e.g., button clicks in main_menu.gd).
- Simple UI tweaks (e.g., options menu enhancements).
- Browse [open issues](https://github.com/ikostan/SkyLockAssault/issues?q=is%3Aopen+label%3A%22good+first+issue%22)

## Code Style

- **GDScript**: Use snake_case for variables/functions. Prefer typed variables
  (e.g., `var speed: float = 100.0`) for better readability and error catching.
- **Indentation**: 4 spaces (Godot default).
- **Comments**: Add inline comments for learning (e.g., explain quit logic).
- **Best Practices**: Follow Godot docs (e.g., use signals for UI events).

## How to Contribute

1. **Fork the Repo**: Click "Fork" on GitHub.
2. **Clone Locally**: Use GitHub Desktop: Clone your fork.
3. **Create a Branch**: `git checkout -b feature/your-feature-name`
   (e.g., feature/add-sound-effects).
4. **Make Changes**: Open in Godot 4.5; edit scenes/scripts
   (e.g., main_menu.gd for quit handling).
5. **Test**: 
   - Run in editor (F5).
   - Export to HTML5 and test via Docker (`cd infra/ && docker compose up -d`,
     open http://localhost:9090).
   - On Win10: Verify no errors in console; test fullscreen/quit.
6. **Commit**: `git add . && git commit -m "Descriptive message (closes #issue-number)"`.
7. **Push and PR**: Push branch > Open Pull Request on GitHub
   (describe changes, link issue).

## Reporting Bugs

- Open an issue: https://github.com/ikostan/SkyLockAssault/issues/new
- Include: Godot version (4.5), OS (Win10 64-bit), steps to reproduce, screenshots if
  UI/export-related.
- Use templates if available (e.g., bug_report.md).

## Optional: Issue Templates

To standardize, we've added templates in .github/ISSUE_TEMPLATE/:

- bug_report.md: For bugs (fields: Godot version, OS, steps).
- feature_request.md: For new ideas.

Questions? Comment on an issue or PR. Happy coding—let's learn Godot together!
