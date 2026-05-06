---
name: godot-remote-executor
description: "Use when the task requires Hastur broker-server control of a running Godot editor or game runtime, including GDScript execution, live scene inspection, runtime state queries, and enhanced C# bridge commands/build checks. Use godot-project-collab for static project help."
---

# Godot Remote Executor

Use this skill to operate a Godot 4.x editor or live game through the Hastur broker. The enhanced `_CS` plugin supports:

- `gdscript`: arbitrary GDScript snippets/classes in editor or game executors.
- `csharp-build`: .NET build checks only, not arbitrary C# eval.
- `csharp-command`: safe structured commands for editor/runtime inspection and actions. These work on C#, GDScript, and scriptless nodes.

Prefer `godot-project-collab` for static project/file work. Use this skill when live editor/game state matters.

Critical boundary: if broker executors are connected, `godot` in PATH and a local Godot executable path are not prerequisites. Use the broker API as the primary control path. Resolve the Godot executable only for CLI/headless fallback, offline project checks, or when the broker/editor executor is unavailable.

## Efficient Default Route

For Godot .NET demo work, optimize for low token use and reliable feedback:

Hard preference for C# demo logic: if the project is C# enabled and the task is a simulation, game mechanic, physics/math-heavy demo, stateful tool, or anything requiring debug snapshots/build verification, implement the primary logic in C# by default. Use GDScript only for editor snippets, tiny glue, or when the project is clearly GDScript-first. If choosing GDScript in a C# enabled project, state the reason before editing.

1. Query `/api/executors` once. Note `id`, `project_path`, `editor_version`, supported languages, and `type` (`editor` or `game`).
2. Build C# with `csharp-build`.
3. Use `build_open_inspect compact:true` once for orientation, not as a repeated acceptance check.
4. Start the game with `start_game_and_wait_hint`, then poll `/api/executors/runtime-status?project_path=...` until `game_connected:true`.
5. Inspect runtime with `runtime_status`, `debug_snapshot`, `get_property`, and focused `find_nodes`.
6. Expand only when needed: add `path`, small `max_depth`, `compact:true`, and `child_limit` around 5-10.

Do not detour into Godot CLI discovery just because `godot` is not in PATH. That is a fallback path, not the broker workflow.

Recommended orientation call:

```json
{"language":"csharp-command","command":"build_open_inspect","args":{"compact":true,"build_args":{"mode":"dotnet","configuration":"Debug"},"scene_path":"res://scenes/Main.tscn","inspect_args":{"compact":true,"max_depth":2,"child_limit":8}},"project_path":"<project-path>","type":"editor"}
```

Recommended repeated runtime check:

```json
{"language":"csharp-command","command":"debug_snapshot","args":{"scope":"runtime","path":"/root/Main"},"project_path":"<project-path>","type":"game"}
```

## Broker Requests

Broker defaults:

- Base URL: `http://localhost:5302`
- Auth: `Authorization: Bearer <token>`
- Execute endpoint: `POST /api/execute`
- Discovery endpoint: `GET /api/executors`
- Runtime poll endpoint: `GET /api/executors/runtime-status?project_path=<url-encoded-project-path>`

Inputs needed from the user/session: auth token, optional base URL, and either a target project path/name or the connected executor list.

Use this sequence:

1. Discover executors:

```bash
curl -s -H "Authorization: Bearer <token>" http://localhost:5302/api/executors
```

2. Pick the editor executor for editor/build commands and the game executor for live runtime commands. For multi-step workflows, prefer `project_path` + `type` because executor IDs change after reloads. Use `executor_id` only for a fresh one-off exact target.

3. Execute a command:

```bash
curl -s -X POST -H "Authorization: Bearer <token>" -H "Content-Type: application/json" -d '<json-body>' http://localhost:5302/api/execute
```

Target exactly one executor by `executor_id`, `project_path`, or `project_name`. Add `"type":"editor"` or `"type":"game"` when both are connected.

Executor targeting rules:

- Use editor executors for build/open/save/select/start/stop/editor scene inspection.
- Use game executors for live runtime tree/properties/FPS/debug methods.
- `type` alone is not enough for `POST /api/execute`; include `executor_id`, `project_path`, or `project_name`.
- Executor IDs can change after reloads. Refresh `/api/executors` instead of reusing stale IDs.

Prefer direct fields in `<json-body>`:

```json
{"language":"csharp-build","args":{"mode":"dotnet","configuration":"Debug"},"project_path":"<project-path>","type":"editor"}
{"language":"csharp-command","command":"find_nodes","args":{"scope":"edited","path":".","class_filter":"Button","limit":20,"compact":true},"project_path":"<project-path>","type":"editor"}
{"language":"csharp-command","command":"debug_snapshot","args":{"scope":"runtime","path":"/root/Main"},"project_path":"<project-path>","type":"game"}
```

Older `code` JSON payloads remain compatible, but direct fields are shorter and avoid nested JSON escaping.

Read every response before continuing:

- Outer HTTP JSON: require `"success":true`; otherwise inspect `error`.
- Execution data: require `compile_success:true` and `run_success:true`; otherwise use `compile_error`/`run_error`.
- Results live in `data.outputs` as `[key,value]` pairs. Values are strings; parse JSON values yourself when a command returns JSON text.
- For chunked C# command output, concatenate `<key>_chunk_001...` only when the `<key>` summary says `chunked:true`.

For game startup, do not assume `start_game` means the game executor is connected. The agent-side one-step route is: call `start_game_and_wait_hint`, poll `runtime-status` until `game_connected:true`, then target `project_path` + `type:"game"`.

When no broker executor is connected, this skill cannot control Godot. Then use `godot-project-collab` for static work, or locate/run Godot CLI only as a separate fallback.

## C# Bridge Commands

Use `command_help` once if unsure what the connected plugin supports. Common commands:

- Project/build: `project_info`, `self_check`, `csharp-build`, `reload_project_scripts`, `build_open_inspect`.
- Game executor: `game_executor_status`, `ensure_game_executor`, `start_game_and_wait_hint`, `start_game`, `stop_game`, `runtime_status`.
- Scene inspection: `get_edited_scene`, `scene_tree`, `list_nodes`, `find_nodes`, `inspect_node`.
- Properties/actions: `get_property`, `set_property`, `get_signals`, `get_groups`, `select_node`, `click_button`.
- Debug hooks: `debug_snapshot`, `call_debug_method`.

Focused inspection args:

- `scope`: `edited` or `runtime`.
- `path`: node path; prefer explicit paths after discovery.
- `compact`: use `true` for discovery.
- `max_depth`, `child_limit`, `limit`: keep small first.
- `name_filter`, `class_filter`, `script_filter`, `text_filter`: prefer filters over large trees.
- `include_script`, `include_internal`, `chunk`, `max_output_chunks`: enable only when needed.

High-frequency acceptance should be focused:

- Prefer `debug_snapshot` for C# gameplay state. It calls `DebugSnapshot()` by default and returns the fixed `debug_snapshot` output key.
- Prefer `get_property` or `inspect_node` with explicit `properties`; `inspect_node compact:true` intentionally omits default properties unless `include_default_properties:true`.
- Treat `build_open_inspect`, broad `inspect_node`, and full `scene_tree` as low-frequency orientation tools. Even compact output can be large; use focused commands first, or allow chunked output.
- If a JSON output summary says `chunked:true`, concatenate chunks. If a summary says `truncated:true`, rerun with `chunk:true` or narrower args.

`set_property` accepts JSON primitives and typed dictionaries such as `{"type":"Vector2","x":12,"y":34}`. It is not C# eval.

`debug_snapshot` is the cheapest repeated runtime check. `call_debug_method` is intentionally restricted to safe method names such as `Debug*`, `Hastur*`, `Get*`, and `Capture*`. For C# gameplay debugging, add small explicit methods like:

```csharp
public Godot.Collections.Dictionary DebugSnapshot() => new() {
    ["state"] = _state,
    ["count"] = _items.Count
};
```

## Game Executor Setup

When runtime inspection is needed but no `type:"game"` executor is connected:

1. Run `game_executor_status` on the editor executor.
2. If missing, run `ensure_game_executor` only with explicit project-change intent: `{"allow_project_change":true}`.
3. If `autoload/GameExecutor` points elsewhere, do not overwrite it. Report the conflict.
4. Start with `start_game_and_wait_hint` or `start_game`, optionally with `scene_path`.
5. Poll `runtime-status` until `game_connected:true`.
6. After `stop_game`, poll until `game_connected:false` before claiming the runtime stopped.

`start_game_and_wait_hint` starts the scene/main scene and returns the polling hint. It does not query the broker or store auth tokens in Godot.

If `game_executor_status` reports an autoload conflict, do not overwrite the user's autoload. Report the exact configured path and wait for instruction.

## Raw GDScript Fallback

Use raw `gdscript` only when safe `csharp-command` does not cover the need.

Snippet mode has no `extends`; it is wrapped in a `RefCounted`. Do not call `get_tree()` directly. Use:

```gdscript
var tree = Engine.get_main_loop() as SceneTree
var scene = tree.current_scene
executeContext.output("scene", str(scene.name if scene != null else ""))
```

Full class mode includes `extends` and must define:

```gdscript
func execute(executeContext):
    executeContext.output("key", "value")
```

`executeContext.output(key, value)` accepts strings and values may be truncated by the plugin setting, commonly around 800 characters. Return focused values or JSON summaries. Enhanced C# commands may emit chunk outputs; concatenate chunks only when the summary says `chunked:true`.

Raw game snippets are higher risk than `csharp-command`: a runtime error can pause the game debugger and cause 504 timeouts. Keep snippets short, prefer read-only probes, and stop/restart/resume the game if later game executor calls hang.

## Failure Handling

- Always check `compile_success`, `run_success`, `compile_error`, `run_error`, and `outputs`.
- 404 means the target executor did not match; refresh `/api/executors`.
- 504 can mean the game is paused by the debugger or the code hung. Prefer `csharp-command` over raw game snippets; if raw snippet errors freeze the game, resume/stop/restart from the editor before retrying.
- Godot APIs often return integer `Error` codes instead of throwing. Check for `OK` (`0`) on save/load/filesystem calls and report the code.
- For Godot APIs, read only the needed reference file under `references/godot-docs/classes/class_<lowercaseclassname>.rst.txt`.
- For GDScript syntax uncertainty, read only the relevant file under `references/gdscript-syntax/`.
- If C# build fails, fix compile errors before runtime inspection. Game executor state can be stale when scripts did not build.

## Current Practical Guidance

- For agent-led C# demo development, the best loop is: local C# edits -> `csharp-build` -> one-time compact `build_open_inspect` when structure changed -> `start_game_and_wait_hint` -> poll runtime-status -> `runtime_status` -> `debug_snapshot`.
- Keep debug data explicit in game scripts. It is cheaper and more reliable than walking the whole runtime tree.
- Use full `scene_tree` only for unknown structure, and only with `path`, small `max_depth`, compact mode, low `child_limit`, and chunk handling.
- Do not assume arbitrary C# runtime eval exists. Build C#, then inspect through commands or explicit debug methods.
- Prefer editor/game executor separation: editor for build/open/save/select/start/stop; game for live scene state, properties, and debug method calls.
