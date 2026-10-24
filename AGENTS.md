# Godot MCP Project Guidelines

This project has the `godot-mcp` server attached (386 tools).

## Tool Usage Principles
- Call `search_tools` with a keyword first if searching for a specific tool (e.g. `search_tools("scene")`, `search_tools("script")`).
- On `EDITOR_NOT_REACHABLE` or `RUNTIME_NOT_REACHABLE`, call `get_status` to check connections instead of retrying blindly.
- Prefer file tools (`read_scene`, `write_script`, `create_resource`, etc.) for direct file modifications—they work even when the Godot editor is closed.
- Every `editor_*` change is registered on the undo stack (`editor_undo`).
- When running playtests or debugging, use the runtime tools to inspect nodes and errors.

## Project Structure
- `scenes/`: Main scenes (`main.tscn`, `player.tscn`)
- `scripts/`: GDScripts (`main.gd`, `player.gd`, `network_manager.gd`)
- `server/`: Node.js WebSocket relay server for multiplayer testing
- `addons/godot-mcp/`: Godot Editor MCP companion plugin
- `.github/workflows/deploy.yml`: GitHub Actions workflow for automatic Web export & GitHub Pages deployment
