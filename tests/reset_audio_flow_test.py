# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/reset_audio_flow_test.py
"""
Reset Functionality Test Suite (Playwright + UI Automation with DOM Overlays)
============================================================================

Overview
--------
E2E tests for RESET-01 to RESET-05 and STATE-01 to STATE-02: Validate reset button
behavior in audio menu, including defaults restoration, no-op on defaults, partial
changes, persistence after navigation/reload, rapid clicks, and isolation.

Navigates to audio menu, adjusts sliders/mutes, resets, verifies states/logs.
"""

import json
import os
import time
from typing import Any

import pytest
from playwright.sync_api import Page

from tests.test_utils import (
    DEFAULT_TIMEOUT,
    TEST_TIMEOUT,
    init_page_and_wait_ready,
    wait_for_console_log,
)


def _has_log(logs: list[dict[str, str]], keyword: str) -> bool:
    """Check if any log entry contains the specified keyword."""
    return any(keyword in log["text"].lower() for log in logs)


def _get_unignored_errors(
    logs_subset: list[dict[str, str]], ignored_phrases: list[str]
) -> list[str]:
    """Extract error messages from logs excluding ignored phrases."""
    actual_errors = []
    for log in logs_subset:
        text = log["text"].lower()
        if "error" in text and not any(ignored in text for ignored in ignored_phrases):
            actual_errors.append(log["text"])
    return actual_errors


@pytest.mark.timeout(90)
def test_reset_flow(shared_page: Page) -> None:
    """Main test suite for reset functionality using DOM overlays."""
    logs: list[dict[str, str]] = []
    cdp_session = None

    def on_console(msg: Any) -> None:
        """Console message handler to capture logs."""
        logs.append({"type": msg.type, "text": msg.text})

    shared_page.on("console", on_console)

    ignored_phrases = [
        "encryption aborted",
        "salt is empty",
        "key generation failed",
    ]

    try:
        # Start CDP session for V8 JS coverage
        cdp_session = shared_page.context.new_cdp_session(shared_page)
        cdp_session.send("Profiler.enable")
        cdp_session.send(
            "Profiler.startPreciseCoverage", {"callCount": True, "detailed": True}
        )

        # Standardized deterministic page & canvas load
        init_page_and_wait_ready(shared_page)

        # Open options
        shared_page.wait_for_selector(
            "#options-button", state="visible", timeout=TEST_TIMEOUT
        )
        shared_page.wait_for_function(
            "() => typeof window.optionsPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.optionsPressed([])")

        # Go to Advanced settings
        shared_page.wait_for_selector(
            "#advanced-button", state="visible", timeout=TEST_TIMEOUT
        )
        shared_page.wait_for_function(
            "() => typeof window.advancedPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.advancedPressed([])")
        shared_page.wait_for_function(
            "() => typeof window.changeLogLevel !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.wait_for_function(
            "() => window.getComputedStyle("
            "document.getElementById('log-level-select')"
            ").display === 'block'",
            timeout=TEST_TIMEOUT,
        )

        # Set log level DEBUG
        pre_change_log_count = len(logs)
        shared_page.evaluate("window.changeLogLevel([0])")
        wait_for_console_log(
            logs,
            lambda text: "log level changed to: debug" in text,
            pre_change_log_count,
            shared_page,
        )

        # Go back to Options menu
        shared_page.wait_for_selector(
            "#advanced-back-button", state="visible", timeout=TEST_TIMEOUT
        )
        shared_page.wait_for_function(
            "() => typeof window.advancedBackPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.advancedBackPressed([])")

        # Navigate to audio sub-menu
        shared_page.wait_for_selector(
            "#audio-button", state="visible", timeout=TEST_TIMEOUT
        )
        pre_change_log_count = len(logs)
        shared_page.wait_for_function(
            "() => typeof window.audioPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.audioPressed([])")

        shared_page.wait_for_function(
            "() => window.getComputedStyle("
            "document.getElementById('master-slider')"
            ").display === 'block'",
            timeout=TEST_TIMEOUT,
        )
        wait_for_console_log(
            logs,
            lambda text: "audio button pressed." in text,
            pre_change_log_count,
            shared_page,
        )

        # RESET-01: Reset all buses to defaults
        shared_page.wait_for_function(
            "() => typeof window.changeMasterVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.changeMasterVolume([0.5])")
        shared_page.wait_for_function(
            "() => typeof window.changeMusicVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.changeMusicVolume([0.3])")
        shared_page.wait_for_function(
            "() => typeof window.changeSfxVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.changeSfxVolume([0.7])")
        shared_page.wait_for_function(
            "() => typeof window.toggleMuteMusic !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.toggleMuteMusic([0])")
        shared_page.wait_for_function(
            "() => typeof window.toggleMuteMaster !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.toggleMuteMaster([0])")

        pre_change_log_count = len(logs)
        shared_page.wait_for_function(
            "() => typeof window.audioResetPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.audioResetPressed([])")

        wait_for_console_log(
            logs,
            lambda text: "audio volumes reset to defaults" in text,
            pre_change_log_count,
            shared_page,
        )

        for bus in ("master", "music", "sfx", "weapon", "rotors"):
            shared_page.wait_for_function(
                "(id) => parseFloat("
                "document.getElementById(id + '-slider').value) === 1.0",
                arg=bus,
                timeout=TEST_TIMEOUT,
            )

        new_logs = logs[pre_change_log_count:]
        assert _has_log(new_logs, "audio reset pressed"), "Reset log missing"
        assert _has_log(
            new_logs, "audio volumes reset to defaults"
        ), "Reset log missing"

        # RESET-02: Reset on defaults is a safe no-op
        pre_reset_logs = len(logs)
        shared_page.wait_for_function(
            "() => typeof window.audioResetPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.audioResetPressed([])")
        wait_for_console_log(
            logs,
            lambda text: "audio volumes reset to defaults" in text,
            pre_reset_logs,
            shared_page,
        )

        actual_errors = _get_unignored_errors(logs[pre_reset_logs:], ignored_phrases)
        assert not actual_errors, f"Errors on default reset: {actual_errors}"

        # RESET-03: Reset after partial volume changes
        shared_page.wait_for_function(
            "() => typeof window.changeMasterVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.changeMasterVolume([0.4])")
        shared_page.wait_for_function(
            "() => typeof window.changeRotorsVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.changeRotorsVolume([0.6])")

        pre_change_log_count = len(logs)
        shared_page.wait_for_function(
            "() => typeof window.audioResetPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.audioResetPressed([])")
        wait_for_console_log(
            logs,
            lambda text: "audio volumes reset to defaults" in text,
            pre_change_log_count,
            shared_page,
        )

        for bus in ("master", "rotors"):
            shared_page.wait_for_function(
                "(id) => parseFloat("
                "document.getElementById(id + '-slider').value) === 1.0",
                arg=bus,
                timeout=TEST_TIMEOUT,
            )

        # RESET-04: Reset persists across Back navigation
        pre_sfx_count = len(logs)
        shared_page.wait_for_function(
            "() => typeof window.changeSfxVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("""() => {
            const el = document.getElementById('sfx-slider');
            if (el) el.value = '0.2';
            if (typeof window.changeSfxVolume === 'function') {
                window.changeSfxVolume([0.2]);
            }
        }""")
        wait_for_console_log(
            logs,
            lambda text: "applied loaded sfx volume to audioserver: 0.2" in text,
            pre_sfx_count,
            shared_page,
        )

        pre_change_log_count = len(logs)
        shared_page.wait_for_function(
            "() => typeof window.audioResetPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.audioResetPressed([])")
        wait_for_console_log(
            logs,
            lambda text: "audio volumes reset to defaults" in text,
            pre_change_log_count,
            shared_page,
        )

        shared_page.wait_for_function(
            "() => typeof window.audioBackPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.audioBackPressed([])")
        shared_page.wait_for_selector(
            "#audio-button", state="visible", timeout=TEST_TIMEOUT
        )
        shared_page.wait_for_function(
            "() => typeof window.audioPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.audioPressed([])")

        shared_page.wait_for_function(
            "() => window.getComputedStyle("
            "document.getElementById('master-slider')"
            ").display === 'block'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.wait_for_function(
            "() => parseFloat(" "document.getElementById('sfx-slider').value) === 1.0",
            timeout=TEST_TIMEOUT,
        )

        # RESET-05: Rapid Reset button clicks
        shared_page.wait_for_function(
            "() => typeof window.changeMasterVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.changeMasterVolume([0.5])")

        pre_change_log_count = len(logs)
        for _ in range(3):
            shared_page.wait_for_function(
                "() => typeof window.audioResetPressed !== 'undefined'",
                timeout=TEST_TIMEOUT,
            )
            shared_page.evaluate("window.audioResetPressed([])")

        wait_for_console_log(
            logs,
            lambda text: "audio volumes reset to defaults" in text,
            pre_change_log_count,
            shared_page,
        )

        shared_page.wait_for_function(
            "() => parseFloat("
            "document.getElementById('master-slider').value) === 1.0",
            timeout=TEST_TIMEOUT,
        )

        # STATE-01: Reset button state persists across page reload
        pre_change_log_count = len(logs)
        shared_page.wait_for_function(
            "() => typeof window.audioResetPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.audioResetPressed([])")

        wait_for_console_log(
            logs,
            lambda text: "audio volumes reset to defaults" in text,
            pre_change_log_count,
            shared_page,
        )
        wait_for_console_log(
            logs,
            lambda text: "encrypted settings persisted successfully" in text
            or "saved volumes to config" in text,
            pre_change_log_count,
            shared_page,
        )

        # Synchronize Emscripten IDBFS to IndexedDB before page reload
        try:
            shared_page.evaluate("""async () => {
                    if (typeof GodotFS !== 'undefined' && GodotFS.sync) {
                        await GodotFS.sync();
                    } else if (typeof Module !== 'undefined' && Module.FS && Module.FS.syncfs) {
                        await new Promise((resolve) => Module.FS.syncfs(false, resolve));
                    }
                }""")
        except Exception as exc:  # noqa: BLE001 - best-effort IDBFS flush
            print(f"Warning: GodotFS.sync() failed before reload: {exc}")
        shared_page.wait_for_timeout(timeout=TEST_TIMEOUT)

        # Reload page deterministically via domcontentloaded
        pre_reload_log_count = len(logs)
        shared_page.reload(wait_until="domcontentloaded")

        # Wait for WASM initialization
        shared_page.wait_for_function(
            "() => window.godotInitialized === true", timeout=DEFAULT_TIMEOUT
        )

        # Wait for GDScript async settings initialization log before touching the UI
        wait_for_console_log(
            logs,
            lambda text: "applied loaded" in text or "audio server initialized" in text,
            pre_reload_log_count,
            shared_page,
        )

        # Navigate to audio sub-menu post-initialization
        shared_page.wait_for_selector(
            "#options-button", state="visible", timeout=TEST_TIMEOUT
        )
        shared_page.wait_for_function(
            "() => typeof window.optionsPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.optionsPressed([])")

        shared_page.wait_for_selector(
            "#audio-button", state="visible", timeout=TEST_TIMEOUT
        )
        shared_page.wait_for_function(
            "() => typeof window.audioPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.audioPressed([])")

        shared_page.wait_for_function(
            "() => window.getComputedStyle("
            "document.getElementById('master-slider')"
            ").display === 'block'",
            timeout=TEST_TIMEOUT,
        )

        # Sliders should all be at default volume post-reload
        for bus in ("master", "music", "sfx", "weapon", "rotors"):
            shared_page.wait_for_function(
                "(id) => parseFloat("
                "document.getElementById(id + '-slider').value) === 1.0",
                arg=bus,
                timeout=TEST_TIMEOUT,
            )

        # STATE-02: Audio reset doesn't affect gameplay settings
        shared_page.wait_for_function(
            "() => typeof window.audioBackPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.audioBackPressed([])")
        shared_page.wait_for_function(
            "() => window.getComputedStyle("
            "document.getElementById('master-slider')"
            ").display === 'none'",
            timeout=TEST_TIMEOUT,
        )

        initial_difficulty = float(
            shared_page.evaluate("document.getElementById('difficulty-slider').value")
        )
        assert initial_difficulty == 1.0, "Unexpected default difficulty value"

        shared_page.wait_for_selector(
            "#audio-button", state="visible", timeout=TEST_TIMEOUT
        )
        shared_page.wait_for_function(
            "() => typeof window.audioPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.audioPressed([])")
        shared_page.wait_for_function(
            "() => window.getComputedStyle("
            "document.getElementById('master-slider')"
            ").display === 'block'",
            timeout=TEST_TIMEOUT,
        )

        pre_change_log_count = len(logs)
        shared_page.wait_for_function(
            "() => typeof window.audioResetPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.audioResetPressed([])")
        wait_for_console_log(
            logs,
            lambda text: "audio volumes reset to defaults" in text,
            pre_change_log_count,
            shared_page,
        )

        shared_page.wait_for_function(
            "() => typeof window.audioBackPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.audioBackPressed([])")
        shared_page.wait_for_function(
            "() => window.getComputedStyle("
            "document.getElementById('master-slider')"
            ").display === 'none'",
            timeout=TEST_TIMEOUT,
        )

        assert (
            float(
                shared_page.evaluate(
                    "document.getElementById('difficulty-slider').value"
                )
            )
            == initial_difficulty
        ), "Gameplay difficulty modified by audio reset"

    except Exception as e:
        print(f"Test suite failed: {e!s}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp: int = int(time.time())
        shared_page.screenshot(
            path=f"artifacts/test_reset_failure_screenshot_{timestamp}.png"
        )
        with open(
            f"artifacts/test_reset_failure_console_logs_{timestamp}.txt",
            "w",
            encoding="utf-8",
        ) as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        raise
    finally:
        if cdp_session:
            coverage = cdp_session.send("Profiler.takePreciseCoverage")["result"]
            cdp_session.send("Profiler.stopPreciseCoverage")
            cdp_session.send("Profiler.disable")
            with open("v8_coverage_reset_flow_test.json", "w") as f:
                json.dump(coverage, f)
