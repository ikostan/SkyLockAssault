# Use Ubuntu 24.04 as base (matches GitHub Actions runner)
FROM ubuntu:24.04

# Install base dependencies
RUN apt-get update && apt-get install -y \
    python3 python3-pip wget unzip curl git zip libxml2-utils netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Set up Python and pip
RUN pip3 install --upgrade pip setuptools wheel

# Install GDToolkit for GDScript lint/format (gdtoolkit==4.* for Godot 4.x)
RUN pip3 install gdtoolkit==4.*

# Install yamllint
RUN pip3 install yamllint

# Install markdownlint-cli2 (for Markdown linting)
RUN pip3 install markdownlint-cli2

# Download Godot v4.5 binary and export templates
RUN wget https://github.com/godotengine/godot/releases/download/4.5-stable/Godot_v4.5-stable_linux.x86_64.zip \
    && unzip Godot_v4.5-stable_linux.x86_64.zip \
    && mv Godot_v4.5-stable_linux.x86_64 /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm Godot_v4.5-stable_linux.x86_64.zip

RUN wget https://github.com/godotengine/godot/releases/download/4.5-stable/Godot_v4.5-stable_export_templates.tpz \
    && mkdir -p ~/.local/share/godot/export_templates/4.5.stable/ \
    && unzip Godot_v4.5-stable_export_templates.tpz -d ~/.local/share/godot/export_templates/4.5.stable/ \
    && rm Godot_v4.5-stable_export_templates.tpz

# Install GDUnit4 v6
RUN mkdir -p /project/addons \
    && wget https://github.com/MikeSchulze/gdUnit4/archive/refs/tags/v6.0.0.zip \
    && unzip v6.0.0.zip -d /project/addons \
    && mv /project/addons/gdUnit4-6.0.0/addons/gdUnit4 /project/addons/gdUnit4 \
    && rm -rf /project/addons/gdUnit4-6.0.0 v6.0.0.zip

# Install Playwright and dependencies for browser tests
RUN pip3 install playwright pytest-playwright pytest-asyncio \
    && playwright install-deps \
    && playwright install

# Set working directory
WORKDIR /project

# Default command (overridden when running the script)
CMD ["/bin/bash"]
