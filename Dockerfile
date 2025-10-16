# Use Ubuntu 24.04 as base (matches GitHub Actions runner)
FROM ubuntu:24.04

# Install base dependencies (added nodejs, npm, libglib2.0-bin, kio, gvfs)
RUN apt-get update && apt-get install -y \
    python3 python3-pip wget unzip curl git zip libxml2-utils netcat-openbsd python3-venv nodejs npm \
    libglib2.0-bin kio gvfs \
    && rm -rf /var/lib/apt/lists/*

# Create and activate virtual environment for Python tools
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Upgrade pip, setuptools, and wheel in venv
RUN pip install --upgrade pip setuptools wheel

# Install GDToolkit for GDScript lint/format (gdtoolkit==4.* for Godot 4.x)
RUN pip install gdtoolkit==4.*

# Install yamllint
RUN pip install yamllint

# Install markdownlint-cli2 via npm (Node.js tool)
RUN npm install -g markdownlint-cli2

# Download Godot v4.5 binary and export templates
RUN wget https://github.com/godotengine/godot/releases/download/4.5-stable/Godot_v4.5-stable_linux.x86_64.zip \
    && unzip Godot_v4.5-stable_linux.x86_64.zip \
    && mv Godot_v4.5-stable_linux.x86_64 /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm Godot_v4.5-stable_linux.x86_64.zip

# Download and extract export templates, ensuring correct naming
RUN wget https://github.com/godotengine/godot/releases/download/4.5-stable/Godot_v4.5-stable_export_templates.tpz \
    && mkdir -p /root/.local/share/godot/export_templates/4.5.stable \
    && unzip Godot_v4.5-stable_export_templates.tpz -d /tmp/templates \
    && mv /tmp/templates/templates/* /root/.local/share/godot/export_templates/4.5.stable/ \
    && mv /root/.local/share/godot/export_templates/4.5.stable/web_debug.zip /root/.local/share/godot/export_templates/4.5.stable/web_nothreads_debug.zip || true \
    && mv /root/.local/share/godot/export_templates/4.5.stable/web_release.zip /root/.local/share/godot/export_templates/4.5.stable/web_nothreads_release.zip || true \
    && rm -rf /tmp/templates Godot_v4.5-stable_export_templates.tpz

# Install GDUnit4 v6
RUN mkdir -p /project/addons \
    && wget https://github.com/MikeSchulze/gdUnit4/archive/refs/tags/v6.0.0.zip \
    && unzip v6.0.0.zip -d /project/addons \
    && mv /project/addons/gdUnit4-6.0.0/addons/gdUnit4 /project/addons/gdUnit4 \
    && rm -rf /project/addons/gdUnit4-6.0.0 v6.0.0.zip

# Install Playwright and dependencies for browser tests (in venv)
RUN pip install playwright pytest-playwright pytest-asyncio \
    && playwright install-deps \
    && playwright install

# Set working directory
WORKDIR /project

# Default command (overridden when running the script)
CMD ["/bin/bash"]
