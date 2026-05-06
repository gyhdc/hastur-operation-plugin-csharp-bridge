# Common Godot 4.6 Patterns

## Project Orientation

- Start from `project.godot`, then identify `application/run/main_scene`.
- Inspect `[autoload]` before proposing global state or event buses.
- Inspect `[input]` before adding movement, action, or UI controls.
- Treat `res://` as project-root-relative, not filesystem-root-relative.

## Input

- Prefer named actions in InputMap over hard-coded keys in gameplay code.
- Add actions in `project.godot` only after confirming the Godot 4.6 InputEvent encoding or matching existing project style.
- In scripts, use `Input.is_action_pressed`, `Input.is_action_just_pressed`, or `_input(event)` depending on whether the behavior is continuous or event-based.

## Autoloads

- Use autoloads for global services, save managers, scene routers, or event buses.
- Keep gameplay node logic local unless multiple scenes need the same state or signal hub.
- Verify autoload paths and names in `[autoload]`; a bad path can break project startup.

## Signals

- Prefer signals for cross-node events when direct parent/child ownership is weak.
- Connect in the editor for stable scene-local links; connect in code for dynamic instances.
- For dynamic connections, check instance validity and avoid duplicate connections.

## Scenes and Resources

- Use `PackedScene.instantiate()` for runtime scene creation.
- Load project resources through `preload("res://...")` when the dependency is static; use `load()` for dynamic paths.
- Keep reusable gameplay objects as scenes and reusable data as resources.

## CLI and Diagnostics

- Godot CLI can help open, run, export, or validate a project, but flags should be checked against official docs for the installed version.
- Parse Output panel errors literally: missing scripts, bad `res://` paths, and class/property mismatches usually point to the exact file.
- When no Godot binary path is known, do not invent one; inspect the user's environment or ask.
