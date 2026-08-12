#!/usr/bin/env python3
# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
"""Security-isolated HTTP server for hosting Godot Web exports in CI/testing environments."""

import http.server
import mimetypes
import os
import socketserver
import sys
from urllib.parse import urlsplit


class OptimizedGodotHandler(http.server.SimpleHTTPRequestHandler):
    """HTTP Request Handler with custom security headers and cache-control rules."""

    def end_headers(self) -> None:
        """Inject security headers and cache policies before completing response."""
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")

        clean_path = urlsplit(self.path).path

        if clean_path.endswith((".wasm", ".pck", ".js", ".css")):
            self.send_header("Cache-Control", "public, max-age=3600")
        elif clean_path.endswith(".html") or clean_path.endswith("/"):
            self.send_header("Cache-Control", "no-cache, must-revalidate")
        else:
            self.send_header("Cache-Control", "public, max-age=1800")

        super().end_headers()


class ThreadedHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    """Threaded HTTP server supporting address reuse."""

    daemon_threads = True
    allow_reuse_address = True


def main() -> None:
    """Parse arguments and start the HTTP server."""
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    export_dir = sys.argv[2] if len(sys.argv) > 2 else "export/web_thread_off"

    mimetypes.add_type("application/wasm", ".wasm")

    if not os.path.exists(export_dir):
        print(
            f"❌ Error: Export directory '{export_dir}' does not exist.",
            file=sys.stderr,
        )
        sys.exit(1)

    os.chdir(export_dir)

    with ThreadedHTTPServer(("", port), OptimizedGodotHandler) as httpd:
        print(
            f"🚀 Security-isolated server starting on port {port} for directory: {export_dir}..."
        )
        httpd.serve_forever()


if __name__ == "__main__":
    main()
