# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/gpu_detection_modal_test.py

"""
Playwright automated regression suite for WebGL GPU software rasterizer detection.
Validates pre-boot modal UX, hardware bypass, exception safety, and accessibility.
"""

import json
import os
import time
from typing import Any

import pytest
from playwright.sync_api import Page, expect

from tests.test_utils import TEST_TIMEOUT


def get_webgl_mock_script(
    renderer_string: str = "",
    missing_ext: bool = False,
    missing_context: bool = False,
    throw_exception: bool = False,
) -> str:
    """Helper to generate JS scripts for deterministic WebGL prototype interception."""
    if missing_context:
        return """
        (function() {
            const origGetContext = HTMLCanvasElement.prototype.getContext;
            HTMLCanvasElement.prototype.getContext = function(type, ...args) {
                if (!this.id || this.id !== 'canvas') {
                    return null;
                }
                return origGetContext.call(this, type, ...args);
            };
        })();
        """

    # Injects a prototype override to intercept getExtension and getParameter
    # calls across both WebGLRenderingContext and WebGL2RenderingContext APIs.
    return f"""
    function installMock(proto) {{
        if (!proto) return;
        const origGetExtension = proto.getExtension;
        proto.getExtension = function(name) {{
            if (name === 'WEBGL_debug_renderer_info') {{
                if ('{str(throw_exception).lower()}' === 'true') {{
                    throw new Error("Mocked WebGL Security Exception");
                }}
                if ('{str(missing_ext).lower()}' === 'true') return null;
                return {{
                    UNMASKED_RENDERER_WEBGL: 37446,
                    UNMASKED_VENDOR_WEBGL: 37445
                }};
            }}
            return origGetExtension.call(this, name);
        }};
        const origGetParameter = proto.getParameter;
        proto.getParameter = function(pname) {{
            if (pname === 37446) return "{renderer_string}";
            if (pname === 37445) return "Mocked Vendor";
            return origGetParameter.call(this, pname);
        }};
    }}
    installMock(
        window.WebGLRenderingContext && window.WebGLRenderingContext.prototype
    );
    installMock(
        window.WebGL2RenderingContext && window.WebGL2RenderingContext.prototype
    );
    """


def test_pw_gpu_01_software_rasterizer_triggers_modal(page: Page) -> None:
    """
    PW-GPU-01: Software rasterizer environments trigger the performance warning
    modal over an interactive backdrop prior to engine boot.
    """
    logs: list[dict[str, str]] = []
    cdp_session = None

    def on_console(msg: Any) -> None:
        """Append intercepted console messages to the logs list."""
        logs.append({"type": msg.type, "text": msg.text})

    page.on("console", on_console)

    try:
        cdp_session = page.context.new_cdp_session(page)
        cdp_session.send("Profiler.enable")
        cdp_session.send(
            "Profiler.startPreciseCoverage", {"callCount": True, "detailed": True}
        )

        page.add_init_script(
            get_webgl_mock_script(
                renderer_string="Microsoft Basic Render Driver (Direct3D11)"
            )
        )
        page.goto("http://localhost:8080/index.html")

        modal = page.locator("#gpu-warning-modal")
        expect(modal).to_be_visible(timeout=TEST_TIMEOUT)

        # Dialog accessibility & viewport coverage validation
        expect(modal).to_have_attribute("role", "dialog")
        expect(modal).to_have_attribute("aria-modal", "true")

        # Engine startup is paused prior to dismissal
        is_init = page.evaluate("window.godotInitialized")
        assert is_init in [None, False]

    except Exception as e:
        print(f"Test suite failed: {e!s}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp = int(time.time() * 1000)
        page.screenshot(
            path=f"artifacts/test_pw_gpu_01_failure_screenshot_{timestamp}.png"
        )
        with open(
            f"artifacts/test_pw_gpu_01_failure_html_{timestamp}.html",
            "w",
            encoding="utf-8",
        ) as f:
            f.write(page.content())
        with open(
            f"artifacts/test_pw_gpu_01_failure_console_logs_{timestamp}.txt",
            "w",
            encoding="utf-8",
        ) as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        raise
    finally:
        if cdp_session:
            try:
                coverage = cdp_session.send("Profiler.takePreciseCoverage")["result"]
                cdp_session.send("Profiler.stopPreciseCoverage")
                cdp_session.send("Profiler.disable")
                with open(
                    f"v8_coverage_pw_gpu_01_{int(time.time() * 1000)}.json",
                    "w",
                    encoding="utf-8",
                ) as f:
                    json.dump(coverage, f)
            except Exception as cov_err:
                print(f"Warning: Failed to harvest V8 coverage data: {cov_err}")


def test_pw_gpu_02_modal_dismissal_unblocks_engine(page: Page) -> None:
    """
    PW-GPU-02: Modal dismissal unblocks engine boot, enforces CSS hiding,
    and shifts programmatic focus to the game canvas.
    """
    logs: list[dict[str, str]] = []
    cdp_session = None

    def on_console(msg: Any) -> None:
        """Append intercepted console messages to the logs list."""
        logs.append({"type": msg.type, "text": msg.text})

    page.on("console", on_console)

    try:
        cdp_session = page.context.new_cdp_session(page)
        cdp_session.send("Profiler.enable")
        cdp_session.send(
            "Profiler.startPreciseCoverage", {"callCount": True, "detailed": True}
        )

        page.add_init_script(
            get_webgl_mock_script(renderer_string="Microsoft Basic Render Driver")
        )
        page.goto("http://localhost:8080/index.html")

        dismiss_btn = page.locator("#gpu-warning-dismiss-btn")
        expect(dismiss_btn).to_be_visible(timeout=TEST_TIMEOUT)
        dismiss_btn.click()

        # Modal dismissal unblocks engine boot
        page.wait_for_function(
            "() => window.godotInitialized === true", timeout=TEST_TIMEOUT
        )

        modal = page.locator("#gpu-warning-modal")
        expect(modal).not_to_be_visible()
        expect(modal).to_have_css("display", "none")

        # Focus shifts to the primary game canvas
        canvas_focused = page.evaluate(
            "() => document.activeElement === document.querySelector('#canvas')"
        )
        assert canvas_focused is True

    except Exception as e:
        print(f"Test suite failed: {e!s}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp = int(time.time() * 1000)
        page.screenshot(
            path=f"artifacts/test_pw_gpu_02_failure_screenshot_{timestamp}.png"
        )
        with open(
            f"artifacts/test_pw_gpu_02_failure_html_{timestamp}.html",
            "w",
            encoding="utf-8",
        ) as f:
            f.write(page.content())
        with open(
            f"artifacts/test_pw_gpu_02_failure_console_logs_{timestamp}.txt",
            "w",
            encoding="utf-8",
        ) as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        raise
    finally:
        if cdp_session:
            try:
                coverage = cdp_session.send("Profiler.takePreciseCoverage")["result"]
                cdp_session.send("Profiler.stopPreciseCoverage")
                cdp_session.send("Profiler.disable")
                with open(
                    f"v8_coverage_pw_gpu_02_{int(time.time() * 1000)}.json",
                    "w",
                    encoding="utf-8",
                ) as f:
                    json.dump(coverage, f)
            except Exception as cov_err:
                print(f"Warning: Failed to harvest V8 coverage data: {cov_err}")


@pytest.mark.parametrize(
    "renderer",
    [
        "Google SwiftShader (ANGLE)",
        "llvmpipe (LLVM 12.0.0, 256 bits)",
        "Microsoft Basic Render Driver",
        "Software Rasterizer",
    ],
)
def test_pw_gpu_03_detects_software_strings(page: Page, renderer: str) -> None:
    """
    PW-GPU-03: Production detection path correctly identifies standard
    software rasterizer renderer strings.
    """
    logs: list[dict[str, str]] = []
    cdp_session = None

    def on_console(msg: Any) -> None:
        """Append intercepted console messages to the logs list."""
        logs.append({"type": msg.type, "text": msg.text})

    page.on("console", on_console)

    try:
        cdp_session = page.context.new_cdp_session(page)
        cdp_session.send("Profiler.enable")
        cdp_session.send(
            "Profiler.startPreciseCoverage", {"callCount": True, "detailed": True}
        )

        page.add_init_script(get_webgl_mock_script(renderer_string=renderer))
        page.goto("http://localhost:8080/index.html")

        expect(page.locator("#gpu-warning-modal")).to_be_visible(
            timeout=TEST_TIMEOUT
        )

    except Exception as e:
        print(f"Test suite failed: {e!s}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp = int(time.time() * 1000)
        page.screenshot(
            path=f"artifacts/test_pw_gpu_03_failure_screenshot_{timestamp}.png"
        )
        with open(
            f"artifacts/test_pw_gpu_03_failure_html_{timestamp}.html",
            "w",
            encoding="utf-8",
        ) as f:
            f.write(page.content())
        with open(
            f"artifacts/test_pw_gpu_03_failure_console_logs_{timestamp}.txt",
            "w",
            encoding="utf-8",
        ) as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        raise
    finally:
        if cdp_session:
            try:
                coverage = cdp_session.send("Profiler.takePreciseCoverage")["result"]
                cdp_session.send("Profiler.stopPreciseCoverage")
                cdp_session.send("Profiler.disable")
                with open(
                    f"v8_coverage_pw_gpu_03_{int(time.time() * 1000)}.json",
                    "w",
                    encoding="utf-8",
                ) as f:
                    json.dump(coverage, f)
            except Exception as cov_err:
                print(f"Warning: Failed to harvest V8 coverage data: {cov_err}")


@pytest.mark.parametrize(
    "renderer",
    [
        "ANGLE (NVIDIA, RTX 4070 Direct3D11)",
        "AMD Radeon RX 6700 XT",
        "Intel(R) Iris(R) Xe Graphics",
        "Apple M2",
    ],
)
def test_pw_gpu_04_hardware_bypass(page: Page, renderer: str) -> None:
    """
    PW-GPU-04: Dedicated hardware-accelerated GPU renderers cleanly
    bypass the warning modal display.
    """
    logs: list[dict[str, str]] = []
    cdp_session = None

    def on_console(msg: Any) -> None:
        """Append intercepted console messages to the logs list."""
        logs.append({"type": msg.type, "text": msg.text})

    page.on("console", on_console)

    try:
        cdp_session = page.context.new_cdp_session(page)
        cdp_session.send("Profiler.enable")
        cdp_session.send(
            "Profiler.startPreciseCoverage", {"callCount": True, "detailed": True}
        )

        page.add_init_script(get_webgl_mock_script(renderer_string=renderer))
        page.goto("http://localhost:8080/index.html")

        # Engine initialization begins immediately without blocking
        page.wait_for_function(
            "() => window.godotInitialized === true", timeout=TEST_TIMEOUT
        )

        modal = page.locator("#gpu-warning-modal")
        expect(modal).not_to_be_visible()
        expect(modal).to_have_css("display", "none")

    except Exception as e:
        print(f"Test suite failed: {e!s}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp = int(time.time() * 1000)
        page.screenshot(
            path=f"artifacts/test_pw_gpu_04_failure_screenshot_{timestamp}.png"
        )
        with open(
            f"artifacts/test_pw_gpu_04_failure_html_{timestamp}.html",
            "w",
            encoding="utf-8",
        ) as f:
            f.write(page.content())
        with open(
            f"artifacts/test_pw_gpu_04_failure_console_logs_{timestamp}.txt",
            "w",
            encoding="utf-8",
        ) as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        raise
    finally:
        if cdp_session:
            try:
                coverage = cdp_session.send("Profiler.takePreciseCoverage")["result"]
                cdp_session.send("Profiler.stopPreciseCoverage")
                cdp_session.send("Profiler.disable")
                with open(
                    f"v8_coverage_pw_gpu_04_{int(time.time() * 1000)}.json",
                    "w",
                    encoding="utf-8",
                ) as f:
                    json.dump(coverage, f)
            except Exception as cov_err:
                print(f"Warning: Failed to harvest V8 coverage data: {cov_err}")


def test_pw_gpu_05_missing_extension_degrades_gracefully(page: Page) -> None:
    """
    PW-GPU-05: Missing or null WEBGL_debug_renderer_info extensions degrade
    gracefully.
    """
    logs: list[dict[str, str]] = []
    cdp_session = None

    def on_console(msg: Any) -> None:
        """Append intercepted console messages to the logs list."""
        logs.append({"type": msg.type, "text": msg.text})

    page.on("console", on_console)

    try:
        cdp_session = page.context.new_cdp_session(page)
        cdp_session.send("Profiler.enable")
        cdp_session.send(
            "Profiler.startPreciseCoverage", {"callCount": True, "detailed": True}
        )

        page.add_init_script(get_webgl_mock_script(missing_ext=True))
        page.goto("http://localhost:8080/index.html")

        page.wait_for_function(
            "() => window.godotInitialized === true", timeout=TEST_TIMEOUT
        )
        expect(page.locator("#gpu-warning-modal")).not_to_be_visible()

    except Exception as e:
        print(f"Test suite failed: {e!s}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp = int(time.time() * 1000)
        page.screenshot(
            path=f"artifacts/test_pw_gpu_05_failure_screenshot_{timestamp}.png"
        )
        with open(
            f"artifacts/test_pw_gpu_05_failure_html_{timestamp}.html",
            "w",
            encoding="utf-8",
        ) as f:
            f.write(page.content())
        with open(
            f"artifacts/test_pw_gpu_05_failure_console_logs_{timestamp}.txt",
            "w",
            encoding="utf-8",
        ) as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        raise
    finally:
        if cdp_session:
            try:
                coverage = cdp_session.send("Profiler.takePreciseCoverage")["result"]
                cdp_session.send("Profiler.stopPreciseCoverage")
                cdp_session.send("Profiler.disable")
                with open(
                    f"v8_coverage_pw_gpu_05_{int(time.time() * 1000)}.json",
                    "w",
                    encoding="utf-8",
                ) as f:
                    json.dump(coverage, f)
            except Exception as cov_err:
                print(f"Warning: Failed to harvest V8 coverage data: {cov_err}")


def test_pw_gpu_06_missing_context_safety(page: Page) -> None:
    """
    PW-GPU-06: Absence of WebGL context on detector probe does not crash
    detection or block engine initialization.
    """
    logs: list[dict[str, str]] = []
    cdp_session = None

    def on_console(msg: Any) -> None:
        """Append intercepted console messages to the logs list."""
        logs.append({"type": msg.type, "text": msg.text})

    page.on("console", on_console)

    try:
        cdp_session = page.context.new_cdp_session(page)
        cdp_session.send("Profiler.enable")
        cdp_session.send(
            "Profiler.startPreciseCoverage", {"callCount": True, "detailed": True}
        )

        page.add_init_script(get_webgl_mock_script(missing_context=True))
        page.goto("http://localhost:8080/index.html")

        page.wait_for_function(
            "() => window.godotInitialized === true", timeout=TEST_TIMEOUT
        )
        expect(page.locator("#gpu-warning-modal")).not_to_be_visible()

    except Exception as e:
        print(f"Test suite failed: {e!s}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp = int(time.time() * 1000)
        page.screenshot(
            path=f"artifacts/test_pw_gpu_06_failure_screenshot_{timestamp}.png"
        )
        with open(
            f"artifacts/test_pw_gpu_06_failure_html_{timestamp}.html",
            "w",
            encoding="utf-8",
        ) as f:
            f.write(page.content())
        with open(
            f"artifacts/test_pw_gpu_06_failure_console_logs_{timestamp}.txt",
            "w",
            encoding="utf-8",
        ) as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        raise
    finally:
        if cdp_session:
            try:
                coverage = cdp_session.send("Profiler.takePreciseCoverage")["result"]
                cdp_session.send("Profiler.stopPreciseCoverage")
                cdp_session.send("Profiler.disable")
                with open(
                    f"v8_coverage_pw_gpu_06_{int(time.time() * 1000)}.json",
                    "w",
                    encoding="utf-8",
                ) as f:
                    json.dump(coverage, f)
            except Exception as cov_err:
                print(f"Warning: Failed to harvest V8 coverage data: {cov_err}")


@pytest.mark.parametrize("key", ["Enter", "Space"])
def test_pw_gpu_07_accessible_keyboard_dismissal(page: Page, key: str) -> None:
    """PW-GPU-07: Modal enforces focus placement and accessible keyboard dismissal."""
    logs: list[dict[str, str]] = []
    cdp_session = None

    def on_console(msg: Any) -> None:
        """Append intercepted console messages to the logs list."""
        logs.append({"type": msg.type, "text": msg.text})

    page.on("console", on_console)

    try:
        cdp_session = page.context.new_cdp_session(page)
        cdp_session.send("Profiler.enable")
        cdp_session.send(
            "Profiler.startPreciseCoverage", {"callCount": True, "detailed": True}
        )

        page.add_init_script(
            get_webgl_mock_script(renderer_string="Microsoft Basic Render Driver")
        )
        page.goto("http://localhost:8080/index.html")

        dismiss_btn = page.locator("#gpu-warning-dismiss-btn")
        expect(dismiss_btn).to_be_visible(timeout=TEST_TIMEOUT)

        # Enforce initial focus placement on the dismiss button
        initial_focus = page.evaluate(
            "() => document.activeElement === document.querySelector('#gpu-warning-dismiss-btn')"
        )
        assert initial_focus is True

        # Dispatch keyboard dismissal directly to the button locator
        dismiss_btn.press(key)

        page.wait_for_function(
            "() => window.godotInitialized === true", timeout=TEST_TIMEOUT
        )

        modal = page.locator("#gpu-warning-modal")
        expect(modal).not_to_be_visible()
        expect(modal).to_have_css("display", "none")

        # Focus shifts to the primary game canvas
        post_focus = page.evaluate(
            "() => document.activeElement === document.querySelector('#canvas')"
        )
        assert post_focus is True

    except Exception as e:
        print(f"Test suite failed: {e!s}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp = int(time.time() * 1000)
        page.screenshot(
            path=f"artifacts/test_pw_gpu_07_failure_screenshot_{timestamp}.png"
        )
        with open(
            f"artifacts/test_pw_gpu_07_failure_html_{timestamp}.html",
            "w",
            encoding="utf-8",
        ) as f:
            f.write(page.content())
        with open(
            f"artifacts/test_pw_gpu_07_failure_console_logs_{timestamp}.txt",
            "w",
            encoding="utf-8",
        ) as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        raise
    finally:
        if cdp_session:
            try:
                coverage = cdp_session.send("Profiler.takePreciseCoverage")["result"]
                cdp_session.send("Profiler.stopPreciseCoverage")
                cdp_session.send("Profiler.disable")
                with open(
                    f"v8_coverage_pw_gpu_07_{int(time.time() * 1000)}.json",
                    "w",
                    encoding="utf-8",
                ) as f:
                    json.dump(coverage, f)
            except Exception as cov_err:
                print(f"Warning: Failed to harvest V8 coverage data: {cov_err}")


@pytest.mark.parametrize(
    "renderer",
    [
        "google swiftshader (angle)",
        "GOOGLE SWIFTSHADER",
        "microsoft basic render driver",
    ],
)
def test_pw_gpu_08_case_insensitive_matching(page: Page, renderer: str) -> None:
    """
    PW-GPU-08: Detection path performs case-insensitive matching across software
    renderer string variants.
    """
    logs: list[dict[str, str]] = []
    cdp_session = None

    def on_console(msg: Any) -> None:
        """Append intercepted console messages to the logs list."""
        logs.append({"type": msg.type, "text": msg.text})

    page.on("console", on_console)

    try:
        cdp_session = page.context.new_cdp_session(page)
        cdp_session.send("Profiler.enable")
        cdp_session.send(
            "Profiler.startPreciseCoverage", {"callCount": True, "detailed": True}
        )

        page.add_init_script(get_webgl_mock_script(renderer_string=renderer))
        page.goto("http://localhost:8080/index.html")

        expect(page.locator("#gpu-warning-modal")).to_be_visible(
            timeout=TEST_TIMEOUT
        )

    except Exception as e:
        print(f"Test suite failed: {e!s}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp = int(time.time() * 1000)
        page.screenshot(
            path=f"artifacts/test_pw_gpu_08_failure_screenshot_{timestamp}.png"
        )
        with open(
            f"artifacts/test_pw_gpu_08_failure_html_{timestamp}.html",
            "w",
            encoding="utf-8",
        ) as f:
            f.write(page.content())
        with open(
            f"artifacts/test_pw_gpu_08_failure_console_logs_{timestamp}.txt",
            "w",
            encoding="utf-8",
        ) as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        raise
    finally:
        if cdp_session:
            try:
                coverage = cdp_session.send("Profiler.takePreciseCoverage")["result"]
                cdp_session.send("Profiler.stopPreciseCoverage")
                cdp_session.send("Profiler.disable")
                with open(
                    f"v8_coverage_pw_gpu_08_{int(time.time() * 1000)}.json",
                    "w",
                    encoding="utf-8",
                ) as f:
                    json.dump(coverage, f)
            except Exception as cov_err:
                print(f"Warning: Failed to harvest V8 coverage data: {cov_err}")


def test_pw_gpu_09_exception_safety(page: Page) -> None:
    """
    PW-GPU-09: WebGL API exceptions during probe do not escape into the page
    context or block engine initialization.
    """
    logs: list[dict[str, str]] = []
    cdp_session = None

    def on_console(msg: Any) -> None:
        """Append intercepted console messages to the logs list."""
        logs.append({"type": msg.type, "text": msg.text})

    page.on("console", on_console)

    errors: list[str] = []

    def on_page_error(err: Any) -> None:
        """Record uncaught page errors."""
        errors.append(str(err))

    page.on("pageerror", on_page_error)

    try:
        cdp_session = page.context.new_cdp_session(page)
        cdp_session.send("Profiler.enable")
        cdp_session.send(
            "Profiler.startPreciseCoverage", {"callCount": True, "detailed": True}
        )

        page.add_init_script(get_webgl_mock_script(throw_exception=True))
        page.goto("http://localhost:8080/index.html")

        page.wait_for_function(
            "() => window.godotInitialized === true", timeout=TEST_TIMEOUT
        )
        expect(page.locator("#gpu-warning-modal")).not_to_be_visible()
        assert len(errors) == 0

    except Exception as e:
        print(f"Test suite failed: {e!s}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp = int(time.time() * 1000)
        page.screenshot(
            path=f"artifacts/test_pw_gpu_09_failure_screenshot_{timestamp}.png"
        )
        with open(
            f"artifacts/test_pw_gpu_09_failure_html_{timestamp}.html",
            "w",
            encoding="utf-8",
        ) as f:
            f.write(page.content())
        with open(
            f"artifacts/test_pw_gpu_09_failure_console_logs_{timestamp}.txt",
            "w",
            encoding="utf-8",
        ) as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        raise
    finally:
        if cdp_session:
            try:
                coverage = cdp_session.send("Profiler.takePreciseCoverage")["result"]
                cdp_session.send("Profiler.stopPreciseCoverage")
                cdp_session.send("Profiler.disable")
                with open(
                    f"v8_coverage_pw_gpu_09_{int(time.time() * 1000)}.json",
                    "w",
                    encoding="utf-8",
                ) as f:
                    json.dump(coverage, f)
            except Exception as cov_err:
                print(f"Warning: Failed to harvest V8 coverage data: {cov_err}")
