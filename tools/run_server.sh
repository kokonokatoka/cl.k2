#!/usr/bin/env bash
set -e

GODOT_BIN="${GODOT:-godot}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

PORT="${1:-8910}"
SEED="${2:-42}"
MAX_PLAYERS="${3:-16}"

echo "Starting cl.k2 Dedicated Server on port $PORT (seed: $SEED, max-players: $MAX_PLAYERS)..."
"$GODOT_BIN" --headless --path "$PROJECT_ROOT" -- --server --port="$PORT" --seed="$SEED" --max-players="$MAX_PLAYERS" "${@:4}"
