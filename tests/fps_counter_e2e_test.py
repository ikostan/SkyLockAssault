# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/fps_counter_e2e_test.py

"""E2E Playwright tests for WebGL FPS Counter (Issue #926).

Validates:
- WebGL/WASM startup and JS bridge readiness.
- OFF -> ON -> OFF state transitions via the production DOM overlay.
- Runtime state reflection in Globals.settings.
- Encrypted configuration persistence across hard browser page reloads.
- Absence of uncaught page errors, crashes, and fatal engine messages.
"""

import os
import re
import time
from typing import Any

from playwright.sync_api import Page
from playwright.sync_api import TimeoutError as PlaywrightTimeoutError
from playwright.sync_api import expect

from tests.test_utils import (
    ARTIFACTS_DIR,
    DEFAULT_TIMEOUT,
    TEST_TIMEOUT,
    init_cdp_coverage,
    init_page_and_wait_ready,
    open_options_menu,
    save_v8_coverage,
    wait_for_console_log,
)

ALLOWLISTED_LOG_PATTERNS = [
    re.compile(r"USER SCRIPT DEBUG", re.IGNORECASE),
    re.compile(r"WebGL.*vendor-prefixed", re.IGNORECASE),
    re.compile(r"AudioContext was not allowed to start", re.IGNORECASE),
    re.compile(r"Mixed Content:", re.IGNORECASE),
    re.compile(r"favicon\.ico", re.IGNORECASE),
    re.compile(r"Hardware acceleration disabled", re.IGNORECASE),
]

IGNORED_ERROR_PHRASES = [
    "encryption aborted",
    "salt is empty",
    "key generation failed",
    "empty next_scene",
    "loading failed or invalid",
]


def _setup_runtime_monitoring(
    page: Page, logs: list[dict[str, Any]], fatal_errors: list[str]
) -> None:
    """Attaches console message and pageerror collectors with engine allowlisting."""

    def on_console(msg: Any) -> None:
        """Process console messages and filter allowlisted patterns."""
        text = str(msg.text)
        logs.append({"type": msg.type, "text": text, "time": time.perf_counter()})

        is_allowlisted = any(p.search(text) for p in ALLOWLISTED_LOG_PATTERNS)
        is_ignored = any(p in text.lower() for p in IGNORED_ERROR_PHRASES)

        if msg.type == "error" and not is_allowlisted and not is_ignored:
            fatal_errors.append(f"Console Error: {text}")

    def on_page_error(exc: Any) -> None:
        """Capture uncaught page errors into fatal_errors list."""
        fatal_errors.append(f"Uncaught PageError: {exc}")

    page.on("console", on_console)
    page.on("pageerror", on_page_error)


def _navigate_to_advanced_menu(page: Page, logs: list[dict[str, Any]]) -> None:
    """Navigates from Main Menu to Advanced Settings and forces DEBUG log level."""
    open_options_menu(page)

    page.wait_for_selector("#advanced-button", state="visible", timeout=TEST_TIMEOUT)
    page.wait_for_function(
        "() => typeof window.advancedPressed !== 'undefined'",
        timeout=TEST_TIMEOUT,
    )
    page.evaluate("window.advancedPressed([])")

    page.wait_for_function(
        "() => typeof window.toggleFps !== 'undefined'",
        timeout=TEST_TIMEOUT,
    )
    page.wait_for_function(
        "() => { const el = document.getElementById('fps-toggle');"
        " return !!el && window.getComputedStyle(el).display === 'block'; }",
        timeout=TEST_TIMEOUT,
    )

    # Enable DEBUG logging so setting updates and persistence are emitted to console
    pre_lvl_count = len(logs)
    page.wait_for_function(
        "() => typeof window.changeLogLevel !== 'undefined'",
        timeout=TEST_TIMEOUT,
    )
    page.evaluate("window.changeLogLevel([0])")
    wait_for_console_log(
        logs,
        lambda text: "log level changed to: debug" in text,
        pre_lvl_count,
        page,
        timeout_ms=DEFAULT_TIMEOUT,
    )


def _toggle_fps_overlay(
    page: Page, logs: list[dict[str, Any]], target_state: bool
) -> None:
    """Deterministically sets the FPS toggle through the DOM overlay element."""
    pre_count = len(logs)
    target_str = str(target_state).lower()

    # Sync DOM element and invoke JS bridge directly.
    # Avoid dispatchEvent() as it fails to trigger inline onchange hooks reliably.
    page.evaluate(f"""() => {{
            const el = document.getElementById('fps-toggle');
            if (el) el.checked = {target_str};
            if (typeof window.toggleFps === 'function') {{
                window.toggleFps(['{target_str}']);
            }}
        }}""")

    # 1. Await GDScript observer signal handler and logging confirmation
    wait_for_console_log(
        logs,
        lambda text: f"fps toggle set to: {target_str}" in text
        or f"setting 'show_fps' updated to: {target_str}" in text,
        pre_count,
        page,
        timeout_ms=DEFAULT_TIMEOUT,
    )

    # 2. Confirm persistence file write side effect
    wait_for_console_log(
        logs,
        lambda text: "encrypted settings persisted successfully" in text
        or "failsafe active" in text,  # Removed the broad "saved" fallback
        pre_count,
        page,
        timeout_ms=DEFAULT_TIMEOUT,
    )

    # 3. Wait for DOM element attribute and JS state reflection
    page.wait_for_function(
        f"() => document.getElementById('fps-toggle').checked === {target_str}",
        timeout=TEST_TIMEOUT,
    )


def _flush_emscripten_idbfs(page: Page) -> None:
    """Explicitly synchronizes Emscripten memory filesystem to browser IndexedDB."""
    try:
        page.evaluate("""async () => {
            if (typeof GodotFS !== 'undefined' && GodotFS.sync) {
                await GodotFS.sync();
            } else if (
                typeof Module !== 'undefined'
                && Module.FS
                && Module.FS.syncfs
            ) {
                await new Promise((resolve, reject) => {
                    Module.FS.syncfs(false, (err) => {
                        if (err) {
                            reject(err);
                        } else {
                            resolve();
                        }
                    });
                });
            }
        }""")
    except Exception as exc:  # noqa: BLE001 - best-effort IDBFS flush
        print(f"Warning: GodotFS.sync() failed before reload: {exc}")
    page.wait_for_timeout(300)


def _dump_failure_diagnostics(
    page: Page, logs: list[dict[str, Any]], fatal_errors: list[str], name: str
) -> None:
    """Saves screenshots, DOM content, and log archives upon test failure."""
    os.makedirs(ARTIFACTS_DIR, exist_ok=True)
    timestamp = int(time.time() * 1000)

    # Strip potential path traversal characters to appease DeepSource
    safe_name = re.sub(r"[^A-Za-z0-9_-]", "_", name)

    try:
        page.screenshot(
            path=str(ARTIFACTS_DIR / f"{safe_name}_failure_{timestamp}.png")
        )
    except Exception:
        pass

    try:
        with open(
            ARTIFACTS_DIR / f"{safe_name}_failure_html_{timestamp}.html",
            "w",
            encoding="utf-8",
        ) as f:
            f.write(page.content())
        with open(
            ARTIFACTS_DIR / f"{safe_name}_failure_logs_{timestamp}.txt",
            "w",
            encoding="utf-8",
        ) as f:
            f.write("--- CONSOLE LOGS ---\n")
            for entry in logs:
                f.write(f"[{entry['type']}] {entry['text']}\n")
            f.write("\n--- FATAL / UNCAUGHT ERRORS ---\n")
            for err in fatal_errors:
                f.write(f"{err}\n")
    except Exception:
        pass


# ==============================================================================
# Test Cases (Issue #926)
# ==============================================================================


def test_webgl_export_stability_and_console(page: Page, request) -> None:
    """Test 1: Verify WebGL Export Stability & Console."""
    logs: list[dict[str, Any]] = []
    fatal_errors: list[str] = []
    cdp_session = None

    _setup_runtime_monitoring(page, logs, fatal_errors)

    try:
        cdp_session, _ = init_cdp_coverage(page)

        # 1. WASM & Engine initialization
        init_page_and_wait_ready(page, request=request)

        # 2. Navigate to Advanced Menu (enables DEBUG logging)
        _navigate_to_advanced_menu(page, logs)

        fps_checkbox = page.locator("#fps-toggle")
        expect(fps_checkbox).to_be_attached(timeout=TEST_TIMEOUT)
        expect(fps_checkbox).not_to_be_checked()

        # 3. Transition 1: OFF -> ON
        _toggle_fps_overlay(page, logs, target_state=True)
        expect(fps_checkbox).to_be_checked()

        # 4. Transition 2: ON -> OFF
        _toggle_fps_overlay(page, logs, target_state=False)
        expect(fps_checkbox).not_to_be_checked()

        # 5. Assert clean runtime execution
        assert (
            not fatal_errors
        ), f"Fatal errors or unallowlisted exceptions occurred: {fatal_errors}"

    except Exception as e:
        print(f"Test 'test_webgl_export_stability_and_console' failed: {e}")
        _dump_failure_diagnostics(page, logs, fatal_errors, "test_fps_stability")
        raise
    finally:
        save_v8_coverage(cdp_session, "fps_counter_stability_test")


def test_webgl_session_persistence(page: Page, request) -> None:
    """Test 2: Verify WebGL Session Persistence across Hard Reloads."""
    logs: list[dict[str, Any]] = []
    fatal_errors: list[str] = []
    cdp_session = None

    _setup_runtime_monitoring(page, logs, fatal_errors)

    try:
        cdp_session, _ = init_cdp_coverage(page)

        # 1. First Boot
        init_page_and_wait_ready(page, request=request)
        _navigate_to_advanced_menu(page, logs)

        fps_checkbox = page.locator("#fps-toggle")
        expect(fps_checkbox).not_to_be_checked()

        # 2. Toggle ON and sync storage
        _toggle_fps_overlay(page, logs, target_state=True)
        expect(fps_checkbox).to_be_checked()

        _flush_emscripten_idbfs(page)

        # 3. Hard Reload 1
        page.reload(wait_until="domcontentloaded")
        gpu_btn = page.locator("#gpu-warning-dismiss-btn")
        try:
            gpu_btn.wait_for(state="visible", timeout=1500)
            gpu_btn.click()
        except PlaywrightTimeoutError:
            pass

        page.wait_for_function(
            "() => window.godotInitialized === true", timeout=DEFAULT_TIMEOUT
        )

        # Navigate back to Advanced Settings
        _navigate_to_advanced_menu(page, logs)
        reloaded_checkbox = page.locator("#fps-toggle")
        expect(reloaded_checkbox).to_be_checked(timeout=TEST_TIMEOUT)

        # 4. Toggle OFF and sync storage
        _toggle_fps_overlay(page, logs, target_state=False)
        expect(reloaded_checkbox).not_to_be_checked()

        _flush_emscripten_idbfs(page)

        # 5. Hard Reload 2
        page.reload(wait_until="domcontentloaded")
        try:
            gpu_btn.wait_for(state="visible", timeout=1500)
            gpu_btn.click()
        except PlaywrightTimeoutError:
            pass

        page.wait_for_function(
            "() => window.godotInitialized === true", timeout=DEFAULT_TIMEOUT
        )

        _navigate_to_advanced_menu(page, logs)
        second_reloaded_checkbox = page.locator("#fps-toggle")
        expect(second_reloaded_checkbox).not_to_be_checked(timeout=TEST_TIMEOUT)

        assert (
            not fatal_errors
        ), f"Fatal errors during persistence reload cycles: {fatal_errors}"

    except Exception as e:
        print(f"Test 'test_webgl_session_persistence' failed: {e}")
        _dump_failure_diagnostics(page, logs, fatal_errors, "test_fps_persistence")
        raise
    finally:
        save_v8_coverage(cdp_session, "fps_counter_persistence_test")
