# Local CI/CD Container Health Validation

This document outlines the procedure for locally building the SkyLockAssault
CI/CD pipeline Docker image and verifying its `HEALTHCHECK` configuration.
The health check mechanism validates that the Godot binary is correctly
installed and executable, satisfying Trivy security scanning requirements
(Rule ID: DS-0026).

## Prerequisites

* Docker Engine installed and running.
* Terminal access in the repository root (directory containing the `Dockerfile`).

## 1. Build the Docker Image

Build the image using the standardized pipeline tag. This step will execute
the `Dockerfile`, installing system dependencies, Python packages, Playwright
browsers, and Godot export templates.

```bash
docker build -t sky-lock-assault-pipeline:latest .


```

## 2. Execute the Container

Start the container in detached mode (`-d`) with an interactive terminal
(`-it`). The interactive flag is required to keep the container running in
the background, as the default command is `/bin/bash`.

```bash
docker run -d -it --name sky-lock-health-test sky-lock-assault-pipeline:latest


```

## 3. Monitor Health Status

The `Dockerfile` is configured with a 5-second start period before the
health check (`/usr/local/bin/godot --version`) initiates. Monitor the
container's status transitions using the process list.

```bash
docker ps


```

**Expected Status Progression:**

1. `Up X seconds (health: starting)` - Container is running; waiting for the start
period.
2. `Up X seconds (healthy)` - The Godot version command returned an exit code
of `0`.

## 4. Troubleshooting (If Unhealthy)

If the status transitions to `(unhealthy)`, the Godot binary may be
missing, lack executable permissions, or have missing system dependencies.
Retrieve the exact error output from the health check logs using the
Docker inspect command:

```bash
docker inspect --format "{{json .State.Health }}" sky-lock-health-test


```

*Review the `Output` field within the returned JSON to diagnose the specific error.*

## 5. Clean Up

Once the `(healthy)` state is verified, stop and remove the test container
to free up system resources.

```bash
docker rm -f sky-lock-health-test


```
