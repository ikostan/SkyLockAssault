# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# tests/unmute_from_zero_test.py
"""
Unmute-From-Zero E2E Suite (Issues #1046 / #1048)
=================================================

Overview
--------
Verifies in a real browser that unmuting a bus at zero volume restores an audible
level and that the HTML DOM slider follows it:

- ZERO-UNMUTE-01: last committed audible volume (0.3) is restored on unmute.
- ZERO-UNMUTE-02: after a reload (in-memory history lost) the fallback (0.495) is used.

The DOM sliders use step="0.01", so the browser snaps 0.495 to 0.49 or 0.5; the
exact restored value is asserted through Godot's DEBUG log instead.

Prerequisites
-------------
- http://localhost:8080/index.html (HTML5 export with custom_shell.html overlays).
- `pip install pytest playwright; playwright install chromium`

Running
-------
pytest -k unmute_from_zero -q
"""

import time
from typing import Any

from playwright.sync_api import Page
from playwright.sync_api import TimeoutError as PlaywrightTimeoutError

from tests.test_utils import (
    DEFAULT_TIMEOUT,
    TEST_TIMEOUT,
    init_page_and_wait_ready,
    open_audio_menu,
    open_options_menu,
    set_log_level,
    wait_for_console_log,
)

FALLBACK_VOLUME = 0.495  # AudioConstants.UNMUTE_FROM_ZERO_FALLBACK_VOLUME
DOM_STEP = 0.01  # step attribute of the DOM range inputs


def _collect_logs(page: Page) -> list[dict[str, str]]:
    """Attach a console collector and return the shared log list."""
    logs: list[dict[str, str]] = []

    def on_console(msg: Any) -> None:
        """Store each console message."""
        logs.append({"type": msg.type, "text": str(msg.text)})

    page.on("console", on_console)
    return logs


def _open_audio_with_debug_logs(page: Page, logs: list[dict[str, str]]) -> None:
    """Main Menu -> Options, force DEBUG logs, then open Audio Settings."""
    open_options_menu(page)
    set_log_level(page, logs, level_index=0)  # DEBUG surfaces restore + save logs
    open_audio_menu(page, logs)


def _call_bridge(page: Page, fn: str, arg: str) -> None:
    """Wait for a bridge callback to exist, then invoke it."""
    page.wait_for_function(
        f"() => typeof window.{fn} !== 'undefined'", timeout=TEST_TIMEOUT
    )
    page.evaluate(f"window.{fn}([{arg}])")


def _set_music_volume(page: Page, logs: list[dict[str, str]], value: str) -> None:
    """Set the Music volume through the bridge and wait for the save."""
    start = len(logs)
    _call_bridge(page, "changeMusicVolume", value)
    wait_for_console_log(logs, lambda t: "saved volumes to config" in t, start, page)


def _toggle_music_mute(page: Page, logs: list[dict[str, str]], checked: bool) -> None:
    """Toggle the Music mute checkbox (checked = unmuted) and wait for the save."""
    start = len(logs)
    _call_bridge(page, "toggleMuteMusic", "1" if checked else "0")
    wait_for_console_log(
        logs,
        lambda t: f"music mute button toggled to: {str(checked).lower()}" in t,
        start,
        page,
    )
    wait_for_console_log(logs, lambda t: "saved volumes to config" in t, start, page)


def _dom_music_value(page: Page) -> float:
    """Current value of the DOM Music slider."""
    return float(page.evaluate("document.getElementById('music-slider').value"))


def _dom_music_checked(page: Page) -> bool:
    """Current state of the DOM Music mute checkbox (checked = unmuted)."""
    return bool(page.evaluate("document.getElementById('mute-music').checked"))


def _flush_idbfs(page: Page) -> None:
    """Commit Godot's in-memory filesystem to IndexedDB before a reload."""
    try:
        page.evaluate("""async () => {
            if (typeof GodotFS !== 'undefined' && GodotFS.sync) {
                await GodotFS.sync();
            } else if (typeof Module !== 'undefined' && Module.FS && Module.FS.syncfs) {
                await new Promise((resolve, reject) => {
                    Module.FS.syncfs(false, (err) => (err ? reject(err) : resolve()));
                });
            }
        }""")
    except Exception as exc:  # noqa: BLE001
        print(f"Warning: filesystem sync before reload failed: {exc}")
    # Godot's own syncfs runs async after a save; give IndexedDB time to commit.
    page.wait_for_timeout(TEST_TIMEOUT)


def _reload_and_wait(page: Page) -> None:
    """Hard reload, dismiss the GPU modal if shown, and wait for Godot."""
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


def test_unmute_from_zero_restores_last_audible_volume(page: Page) -> None:
    """
    ZERO-UNMUTE-01: Music saved at 0.3, set to 0, muted, unmuted -> DOM shows 0.3.

    The explicit mute is needed because a DOM slider change to 0 does not
    auto-mute yet (#725).

    :param page: Function-scoped Playwright page (clean storage per test).
    :type page: Page
    :rtype: None
    """
    logs = _collect_logs(page)
    init_page_and_wait_ready(page)
    _open_audio_with_debug_logs(page, logs)

    _set_music_volume(page, logs, "0.3")  # committed audible level
    _set_music_volume(page, logs, "0")
    _toggle_music_mute(page, logs, checked=False)
    assert not _dom_music_checked(page), "Precondition: Music muted"
    assert _dom_music_value(page) == 0.0, "Precondition: Music at 0"

    start = len(logs)
    _toggle_music_mute(page, logs, checked=True)
    wait_for_console_log(
        logs, lambda t: "unmuted music at zero volume; restoring 0.3" in t, start, page
    )
    page.wait_for_function(
        "() => parseFloat(document.getElementById('music-slider').value) === 0.3",
        timeout=TEST_TIMEOUT,
    )

    assert _dom_music_checked(page), "Music must be unmuted"
    assert _dom_music_value(page) == 0.3, "DOM slider must follow the restored volume"


def test_unmute_from_zero_after_reload_uses_fallback(page: Page) -> None:
    """
    ZERO-UNMUTE-02: Music saved muted at 0, page reloaded, unmuted -> 0.495.

    :param page: Function-scoped Playwright page (clean storage per test).
    :type page: Page
    :rtype: None
    """
    logs = _collect_logs(page)
    init_page_and_wait_ready(page)
    _open_audio_with_debug_logs(page, logs)

    _set_music_volume(page, logs, "0")
    _toggle_music_mute(page, logs, checked=False)
    _flush_idbfs(page)

    _reload_and_wait(page)
    _open_audio_with_debug_logs(page, logs)
    assert not _dom_music_checked(page), "Precondition: muted state persisted"
    assert _dom_music_value(page) == 0.0, "Precondition: zero volume persisted"

    start = len(logs)
    _toggle_music_mute(page, logs, checked=True)
    wait_for_console_log(
        logs,
        lambda t: f"unmuted music at zero volume; restoring {FALLBACK_VOLUME}" in t,
        start,
        page,
    )
    deadline = time.monotonic() + TEST_TIMEOUT / 1000
    while _dom_music_value(page) == 0.0 and time.monotonic() < deadline:
        page.wait_for_timeout(50)

    assert _dom_music_checked(page), "Music must be unmuted"
    assert abs(_dom_music_value(page) - FALLBACK_VOLUME) <= DOM_STEP, (
        f"DOM slider must show ~{FALLBACK_VOLUME} (step {DOM_STEP}), "
        f"got {_dom_music_value(page)}"
    )
