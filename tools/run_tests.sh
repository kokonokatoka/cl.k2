#!/usr/bin/env bash
set -e

GODOT_BIN="${GODOT:-godot}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Running Godot tests in $PROJECT_ROOT using $GODOT_BIN..."
"$GODOT_BIN" --headless --path "$PROJECT_ROOT" -s res://tests/run_tests.gd "$@"
