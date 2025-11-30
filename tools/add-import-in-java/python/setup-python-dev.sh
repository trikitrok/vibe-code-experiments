#!/usr/bin/env bash
# setup-python-dev.sh — create a Python virtual environment under ./dev/python and install dev-only deps
#
# This script installs Python tooling locally under the project ./dev/python directory, without touching the system Python.
# It creates ./dev/python/.venv and installs the packages listed in ./dev/python/requirements-dev.txt (pytest, click, etc.).
#
# Usage:
#   dev/python/setup-python-dev.sh
#
# After running it, you can execute pytest via the wrapper:
#   dev/python/pytest -q dev/python
# or activate the venv manually:
#   source dev/python/.venv/bin/activate
#   pytest -q dev/python
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../.." && pwd)
PY_DEV_DIR="$ROOT_DIR/dev/python"
VENV_DIR="$PY_DEV_DIR/.venv"
REQ_FILE="$PY_DEV_DIR/requirements-dev.txt"

info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
fatal() { echo "[FATAL] $*" >&2; exit 1; }

# Find Python
PYTHON_BIN="${PYTHON_BIN:-}"
if [[ -z "$PYTHON_BIN" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN=python3
  elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN=python
  else
    fatal "Python not found. Please install Python 3.x and retry."
  fi
fi

# Create venv if missing
if [[ ! -d "$VENV_DIR" ]]; then
  info "Creating virtual environment at $VENV_DIR"
  "$PYTHON_BIN" -m venv "$VENV_DIR" || fatal "Failed to create virtual environment"
else
  info "Using existing virtual environment at $VENV_DIR"
fi

PIP_BIN="$VENV_DIR/bin/pip"
PYTEST_BIN="$VENV_DIR/bin/pytest"

# Ensure pip is present
if [[ ! -x "$PIP_BIN" ]]; then
  fatal "pip not found in virtualenv ($PIP_BIN). Python venv may be incomplete."
fi

info "Upgrading pip/setuptools/wheel inside the venv"
"$PIP_BIN" install --upgrade pip setuptools wheel || warn "Could not upgrade pip/setuptools/wheel (continuing)"

# Install requirements
if [[ -f "$REQ_FILE" ]]; then
  info "Installing dev requirements from $REQ_FILE"
  "$PIP_BIN" install -r "$REQ_FILE"
else
  warn "Requirements file not found at $REQ_FILE — installing minimal packages"
  "$PIP_BIN" install "click>=8.0.0" "pytest>=7.0.0"
fi

if [[ -x "$PYTEST_BIN" ]]; then
  info "Setup complete. Pytest available at: $PYTEST_BIN"
  "$PYTEST_BIN" --version || true
else
  warn "Pytest not found after installation. Please check the above logs."
fi
