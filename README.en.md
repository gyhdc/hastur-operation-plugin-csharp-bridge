[中文文档](README.md)

# Hastur Operation Plugin C# Bridge

A Godot editor plugin and broker server that let coding agents control Godot through HTTP. This fork keeps the original GDScript remote execution workflow and adds a practical C#/.NET development loop: build diagnostics, editor inspection, runtime inspection, safe property access, button clicks, and explicit debug snapshots.

This project is based on the idea and architecture of [rayxuln/hastur-operation-plugin](https://github.com/rayxuln/hastur-operation-plugin), then extends it for Godot .NET projects where arbitrary C# eval is not the right tool. The C# path is intentionally command based: write C# files normally, build them normally, then inspect the editor or running game through structured commands.

## What Problem Does This Solve?

Coding agents are good at file edits and shell commands, but Godot is a GUI editor with scene state, editor-only APIs, running-game state, and project resources that are hard to inspect from a terminal.

The original Hastur plugin gives agents a GDScript "shell" into the editor. This C# Bridge version keeps that and adds the missing pieces for Godot .NET work:

- Run legacy `gdscript` snippets in the editor or game runtime.
- Run `csharp-build` for `dotnet build` or Godot solution builds with structured errors, warnings, diagnostics, and raw output.
- Run `csharp-command` for safe editor/runtime actions such as opening scenes, inspecting nodes, reading/writing simple properties, clicking buttons, and calling explicit debug methods.
- Separate editor executors from game executors so an agent can inspect both the edited scene and the live running scene.
- Use `debug_snapshot` / `DebugSnapshot()` as a cheap, repeatable way to observe C# gameplay state without injecting C# source at runtime.

## How It Works

The core architecture is still a small relay:

```text
+----------------+        HTTP        +----------------+        TCP        +----------------------+
| Coding Agent   |  <-------------->  | Broker Server  |  <------------>  | Godot Editor Plugin  |
| Codex/Claude   |                    | Node/Express   |                  | HasturOperationGD_CS |
+----------------+                    +----------------+                  +----------------------+
                                                                                     |
                                                                                     | optional debug run
                                                                                     v
                                                                            +----------------------+
                                                                            | GameExecutor runtime |
                                                                            | type: "game"         |
                                                                            +----------------------+
```

1. The coding agent sends HTTP requests to the broker with a Bearer token.
2. The broker authenticates, selects the matching Godot executor, and forwards the request over TCP.
3. The editor plugin executes GDScript, C# bridge commands, or C# build requests and returns structured output.
4. When `GameExecutor` is installed as an autoload and the game is running in debug mode, the broker also sees a `type:"game"` executor for live runtime inspection.

## Project Structure

```text
hastur-operation-plugin-csharp-bridge/
|-- addons/
|   `-- hasturoperationgd_CS/          # Godot plugin folder to copy into a target project
|       |-- plugin.cfg                 # Plugin manifest
|       |-- hasturoperationgd.gd       # EditorPlugin entry point
|       |-- executor_router.gd         # Routes gdscript/csharp-command/csharp-build requests
|       |-- gdscript_executor.gd       # Legacy GDScript snippet/class execution
|       |-- csharp_command_executor.gd # Safe C# bridge command surface
|       |-- csharp_build_executor.gd   # dotnet/Godot solution build diagnostics
|       |-- csharp_diagnostics.gd      # C# project/runtime detection helpers
|       |-- game_executor.gd           # Optional runtime autoload for type:"game"
|       |-- broker_client.gd           # TCP client used by editor and game executors
|       `-- executor_dock.gd           # Editor dock connection/status UI
|-- broker-server/                     # Node.js HTTP/TCP relay server
|-- skills/                            # Agent skills for Godot/Hastur workflows
|-- openspec/                          # Behavior specs for broker/plugin APIs
|-- tests/                             # Godot headless plugin tests
`-- README.md / README.en.md
```

## Requirements

- Godot 4.x with .NET support for C# projects. The current plugin has been developed against Godot 4.6.x Mono.
- Node.js 18+ for the broker server.
- A coding agent that can send HTTP requests and follow a project skill, such as Codex or Claude.

GDScript-only projects can still use the legacy `gdscript` path. C# bridge languages are advertised only when the plugin detects a C# project and C# runtime support.

## Getting Started

### 1. Start the Broker Server

```bash
cd broker-server
npm install
npm run dev
```

Defaults:

- HTTP API: `http://localhost:5302`
- TCP relay: `localhost:5301`
- Auth: if no token is supplied, the broker prints a generated `auth-token <token>` line to stdout.

You can also provide a fixed token and ports:

```bash
npx tsx src/index.ts --http-port 5302 --tcp-port 5301 --auth-token your-secret-token
```

PowerShell example:

```powershell
$env:HASTUR_AUTH_TOKEN="your-secret-token"
npm run dev
```

### 2. Install the Godot Plugin

Copy `addons/hasturoperationgd_CS/` into your Godot project's `addons/` directory, then enable **HasturOperationGD C# Bridge** in **Project > Project Settings > Plugins**.

The editor plugin connects to the broker TCP port from **Project Settings > Hastur Operation GD**. Defaults are `localhost` and `5301`. The editor dock shows the connection state.

### 3. Give the Agent the Token

Provide the broker base URL and token to your agent:

- Base URL: `http://localhost:5302`
- Auth header: `Authorization: Bearer <token>`

List connected executors:

```bash
curl -s -H "Authorization: Bearer <token>" http://localhost:5302/api/executors
```

For multi-step work, prefer targeting by `project_path` plus `type` instead of a stale executor ID:

```json
{
  "project_path": "E:/Godot/projects/my-game",
  "type": "editor",
  "language": "csharp-command",
  "command": "self_check",
  "args": {}
}
```

## Recommended C# Agent Workflow

Use normal C# files as the source of truth. Do not expect arbitrary C# snippets to be evaled like GDScript.

1. Discover executors with `GET /api/executors`.
2. Build the project with `csharp-build`.
3. Use `build_open_inspect` once when scene structure changes.
4. If runtime state is needed, run `game_executor_status` on the editor executor.
5. If the runtime autoload is missing and the user explicitly allows a project change, run `ensure_game_executor` with `allow_project_change:true`.
6. Start the game with `start_game_and_wait_hint` or `start_game`.
7. Poll `GET /api/executors/runtime-status?project_path=<url-encoded-project-path>` until `game_connected:true`.
8. Send `csharp-command` to `type:"game"` for `runtime_status`, `debug_snapshot`, focused `find_nodes`, `get_property`, `inspect_node`, or `call_debug_method`.

Typical build request:

```json
{
  "project_path": "E:/Godot/projects/my-game",
  "type": "editor",
  "language": "csharp-build",
  "args": {
    "mode": "dotnet",
    "configuration": "Debug"
  }
}
```

Typical editor orientation request:

```json
{
  "project_path": "E:/Godot/projects/my-game",
  "type": "editor",
  "language": "csharp-command",
  "command": "build_open_inspect",
  "args": {
    "compact": true,
    "build_args": { "mode": "dotnet", "configuration": "Debug" },
    "scene_path": "res://scenes/Main.tscn",
    "inspect_args": { "compact": true, "max_depth": 2, "child_limit": 8 }
  }
}
```

Typical runtime snapshot request:

```json
{
  "project_path": "E:/Godot/projects/my-game",
  "type": "game",
  "language": "csharp-command",
  "command": "debug_snapshot",
  "args": {
    "scope": "runtime",
    "path": "/root/Main/Player"
  }
}
```

In your C# node, expose small explicit debug hooks:

```csharp
public Godot.Collections.Dictionary DebugSnapshot() => new()
{
    ["state"] = _state,
    ["position"] = GlobalPosition,
    ["health"] = _health
};
```

`debug_snapshot` calls `DebugSnapshot()` by default. `call_debug_method` is restricted to safe method prefixes such as `Debug`, `Hastur`, `Get`, and `Capture`.

## API Reference

All endpoints except `GET /api/health` require Bearer token authentication.

### `GET /api/health`

Health check. No auth required.

### `GET /api/executors`

Lists connected editor and game executors. Each executor includes project metadata, supported languages, connection state, and `type` (`"editor"` or `"game"`).

### `GET /api/executors/runtime-status?project_path=<path>`

Read-only same-project runtime check. It returns:

- `editor_connected`
- `game_connected`
- `editor_executors`
- `game_executors`
- `recommended_next_request`

Use this after starting a game to wait for a same-project `type:"game"` executor before inspecting runtime nodes.

### `GET /api/diagnostics`

Returns broker diagnostics: ports, token source, connected executor count, advertised languages, executor details, and recent executor events. It does not return the full auth token; copy the token from the broker console output.

### `POST /api/execute`

Executes one request on a selected executor.

Common request fields:

| Field | Type | Notes |
| --- | --- | --- |
| `executor_id` | string | Exact executor target. |
| `project_name` | string | Fuzzy project name target. |
| `project_path` | string | Fuzzy/normalized project path target. |
| `type` | `"editor"` or `"game"` | Optional but recommended when both are connected. |
| `language` | string | Defaults to `gdscript`. Use `csharp-command` or `csharp-build` for the bridge. |
| `code` | string | GDScript code or legacy bridge JSON payload. |
| `command` | string | Direct `csharp-command` command name. |
| `args` | object | Direct `csharp-command` or `csharp-build` args. |

Provide exactly one target selector: `executor_id`, `project_name`, or `project_path`. `type` filters that target.

GDScript example:

```json
{
  "project_name": "my-game",
  "type": "editor",
  "code": "executeContext.output(\"hello\", \"from gdscript\")"
}
```

Direct `csharp-command` example:

```json
{
  "project_path": "E:/Godot/projects/my-game",
  "type": "editor",
  "language": "csharp-command",
  "command": "find_nodes",
  "args": {
    "scope": "edited",
    "path": ".",
    "class_filter": "Button",
    "limit": 20,
    "compact": true
  }
}
```

Legacy wrapped `code` payloads remain supported:

```json
{
  "project_name": "my-game",
  "language": "csharp-command",
  "code": "{\"command\":\"project_info\",\"args\":{}}"
}
```

Response shape:

```json
{
  "success": true,
  "data": {
    "request_id": "uuid",
    "compile_success": true,
    "compile_error": "",
    "run_success": true,
    "run_error": "",
    "outputs": [["key", "value"]]
  }
}
```

Values in `outputs` are strings. JSON command results should be parsed by the caller. Large command outputs may be chunked as `<key>_chunk_001`, `<key>_chunk_002`, and so on.

## C# Bridge Commands

Run `command_help` against the connected plugin for the exact command list. Current common commands include:

- Project/build: `project_info`, `self_check`, `reload_project_scripts`, `build_open_inspect`, plus `csharp-build`.
- Game executor setup: `game_executor_status`, `ensure_game_executor`, `start_game_and_wait_hint`, `start_game`, `stop_game`, `runtime_status`.
- Scene inspection: `get_edited_scene`, `scene_tree`, `list_nodes`, `find_nodes`, `inspect_node`.
- Properties/actions: `get_property`, `set_property`, `get_signals`, `get_groups`, `select_node`, `click_button`.
- Debug hooks: `debug_snapshot`, `call_debug_method`.

Focused inspection arguments:

- `scope`: `edited` or `runtime`
- `path`: node path
- `compact`: concise output
- `max_depth`, `child_limit`, `limit`
- `name_filter`, `class_filter`, `script_filter`, `text_filter`
- `include_script`, `include_internal`, `chunk`, `max_output_chunks`

`set_property` accepts JSON primitives and explicit typed dictionaries such as:

```json
{ "type": "Vector2", "x": 12, "y": 34 }
```

```json
{ "type": "Color", "r": 1, "g": 1, "b": 1, "a": 1 }
```

## GDScript Compatibility

If `language` is omitted, requests run as `gdscript`.

Snippet mode is wrapped in a `RefCounted` helper. Use `Engine.get_main_loop()` to reach the scene tree:

```gdscript
var tree = Engine.get_main_loop() as SceneTree
var scene = tree.edited_scene_root
executeContext.output("scene_name", scene.name if scene != null else "")
```

Full class mode is still supported when the code contains `extends` and defines `func execute(executeContext):`.

## Safety Notes

This tool can execute code inside your Godot editor and debug game process. Treat the broker token as a password.

- Keep the broker bound to localhost unless you fully understand the risk.
- Do not expose the broker to the public internet.
- Use `csharp-command` for routine C# project inspection instead of raw runtime GDScript probes.
- `GameExecutor` connects only in debug builds and frees itself in non-debug builds.
- `ensure_game_executor` adds the autoload only when explicitly called with `allow_project_change:true`; it does not overwrite a conflicting existing `GameExecutor` autoload.
- The C# bridge does not provide arbitrary C# eval or runtime source injection.

## Testing

Broker tests:

```bash
cd broker-server
npm test
npm run build
```

Godot plugin smoke test:

```bash
Godot_v4.6.2-stable_mono_win64_console.exe --headless --path . --script res://tests/test_csharp_bridge.gd
```

## License

MIT
