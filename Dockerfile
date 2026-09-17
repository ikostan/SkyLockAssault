# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# Use Ubuntu 24.04 as base (matches GitHub Actions runner)
FROM ubuntu:24.04

# Install base dependencies (added nodejs, npm, libglib2.0-bin, kio, gvfs, xvfb, aria2)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip wget unzip curl git zip libxml2-utils netcat-openbsd python3-venv nodejs npm \
    libglib2.0-bin kio gvfs xvfb ca-certificates aria2 \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user to run the container (fixes DS002)
RUN useradd -m -s /bin/bash godotuser  # Creates 'godotuser' with home dir /home/godotuser

# Set up artifacts dir with permissions (after useradd)
RUN mkdir -p /project/artifacts \
    && chown -R godotuser:godotuser /project  # Added early for artifacts

# Set Godot config path to non-root user's home
ENV GODOT_VERSION="4.7.1.stable" \
    XDG_DATA_HOME="/home/godotuser/.local/share"

# Create and activate virtual environment for Python tools
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Upgrade pip, setuptools, and wheel in venv
RUN pip install --upgrade pip setuptools wheel

# Install markdownlint-cli2 via npm (Node.js tool)
RUN npm install -g markdownlint-cli2@0.12.1

# Download and verify Godot v4.7.1 binary using the official GitHub SHA512-SUMS file
RUN aria2c -x 16 -s 16 https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/SHA512-SUMS.txt \
    && aria2c -x 16 -s 16 https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/Godot_v4.7.1-stable_linux.x86_64.zip \
    && grep " Godot_v4.7.1-stable_linux.x86_64.zip$" SHA512-SUMS.txt | sha512sum --check --status \
    && unzip Godot_v4.7.1-stable_linux.x86_64.zip \
    && mv Godot_v4.7.1-stable_linux.x86_64 /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm Godot_v4.7.1-stable_linux.x86_64.zip SHA512-SUMS.txt

# Download, verify, and extract export templates using the official GitHub SHA512-SUMS file
RUN aria2c -x 16 -s 16 https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/SHA512-SUMS.txt \
    && aria2c -x 16 -s 16 https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/Godot_v4.7.1-stable_export_templates.tpz \
    && grep " Godot_v4.7.1-stable_export_templates.tpz$" SHA512-SUMS.txt | sha512sum --check --status \
    && mkdir -p "${XDG_DATA_HOME}/godot/export_templates/${GODOT_VERSION}" \
    && unzip Godot_v4.7.1-stable_export_templates.tpz -d /tmp/templates \
    && mv /tmp/templates/templates/* "${XDG_DATA_HOME}/godot/export_templates/${GODOT_VERSION}/" \
    && rm -rf /tmp/templates Godot_v4.7.1-stable_export_templates.tpz SHA512-SUMS.txt \
    && chown -R godotuser:godotuser "${XDG_DATA_HOME}"

# Install GDUnit4 v6.2.0
RUN mkdir -p /project/addons \
    && wget -q https://github.com/godot-gdunit-labs/gdUnit4/archive/refs/tags/v6.2.0.zip \
    && unzip v6.2.0.zip -d /project/addons \
    && mv /project/addons/gdUnit4-6.2.0/addons/gdUnit4 /project/addons/gdUnit4 \
    && rm -rf /project/addons/gdUnit4-6.2.0 v6.2.0.zip \
    && chown -R godotuser:godotuser /project

# Install GUT v9.7.1
RUN mkdir -p /project/addons \
    && wget -q https://github.com/bitwes/Gut/archive/refs/tags/v9.7.1.zip \
    && unzip v9.7.1.zip -d /project/addons \
    && mv /project/addons/Gut-9.7.1/addons/gut /project/addons/gut \
    && rm -rf /project/addons/Gut-9.7.1 v9.7.1.zip \
    && chown -R godotuser:godotuser /project

# Set a shared folder for the browser so both root and godotuser can use it
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

# Copy the project requirements into the container
COPY requirements.txt /tmp/requirements.txt

# Install all locked Python packages and download the browser just ONCE as root
RUN pip install -r /tmp/requirements.txt \
    && playwright install --with-deps chromium \
    && chmod -R 755 /ms-playwright

# Switch to your non-root user
USER godotuser

# Set working directory
WORKDIR /project

# Default command
CMD ["/bin/bash"]