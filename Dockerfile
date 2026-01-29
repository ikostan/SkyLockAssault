# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# Use Ubuntu 24.04 as base (matches GitHub Actions runner)
FROM ubuntu:24.04

# Install base dependencies (added nodejs, npm, libglib2.0-bin, kio, gvfs, xvfb)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip wget unzip curl git zip libxml2-utils netcat-openbsd python3-venv nodejs npm \
    libglib2.0-bin kio gvfs xvfb ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user to run the container (fixes DS002)
RUN useradd -m -s /bin/bash godotuser  # Creates 'godotuser' with home dir /home/godotuser

# Set up artifacts dir with permissions (after useradd)
RUN mkdir -p /project/artifacts \
    && chown -R godotuser:godotuser /project  # Added early for artifacts

# Set Godot config path to non-root user's home
ENV GODOT_VERSION="4.5.stable" \
    XDG_DATA_HOME="/home/godotuser/.local/share"

# Create and activate virtual environment for Python tools
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Upgrade pip, setuptools, and wheel in venv
RUN pip install --upgrade pip setuptools wheel

# Install GDToolkit for GDScript lint/format (gdtoolkit==4.* for Godot 4.x)
RUN pip install gdtoolkit==4.*

# Install yamllint
RUN pip install yamllint

# Install pytest plugins for html/timeout (fixes unrecognized arguments)
RUN pip install pytest-html pytest-timeout

# Install markdownlint-cli2 via npm (Node.js tool)
RUN npm install -g markdownlint-cli2

# Download Godot v4.5 binary and export templates
RUN wget https://github.com/godotengine/godot/releases/download/4.5-stable/Godot_v4.5-stable_linux.x86_64.zip \
    && unzip Godot_v4.5-stable_linux.x86_64.zip \
    && mv Godot_v4.5-stable_linux.x86_64 /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm Godot_v4.5-stable_linux.x86_64.zip

# Download and extract export templates, placing them in the user-specific location
RUN wget https://github.com/godotengine/godot/releases/download/4.5-stable/Godot_v4.5-stable_export_templates.tpz \
    && mkdir -p "${XDG_DATA_HOME}/godot/export_templates/${GODOT_VERSION}" \
    && unzip Godot_v4.5-stable_export_templates.tpz -d /tmp/templates \
    && mv /tmp/templates/templates/* "${XDG_DATA_HOME}/godot/export_templates/${GODOT_VERSION}/" \
    && rm -rf /tmp/templates Godot_v4.5-stable_export_templates.tpz \
    && chown -R godotuser:godotuser "${XDG_DATA_HOME}"

# Install GDUnit4 v6
RUN mkdir -p /project/addons \
    && wget https://github.com/MikeSchulze/gdUnit4/archive/refs/tags/v6.0.0.zip \
    && unzip v6.0.0.zip -d /project/addons \
    && mv /project/addons/gdUnit4-6.0.0/addons/gdUnit4 /project/addons/gdUnit4 \
    && rm -rf /project/addons/gdUnit4-6.0.0 v6.0.0.zip \
    && chown -R godotuser:godotuser /project  # Make project dir accessible

# Install Playwright Python packages and system deps (as root)
RUN pip install playwright pytest-playwright pytest-asyncio \
    && playwright install-deps \
    && playwright install --with-deps chromium

# Switch to non-root user (fixes DS002; all subsequent commands run as godotuser)
USER godotuser

# Install Playwright browsers (as godotuser, to place in user's cache)
RUN playwright install

# Optional: Add a simple HEALTHCHECK to verify Godot is runnable (addresses DS026, though LOW severity)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD /usr/local/bin/godot --version || exit 1

# Set working directory
WORKDIR /project

# Default command (overridden when running the script)
CMD ["/bin/bash"]
