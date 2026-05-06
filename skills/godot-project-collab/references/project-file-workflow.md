# Project File Workflow

## Safe External Edits

Usually safe when the change is focused and backed by docs or existing project patterns:

- `.gd` scripts;
- simple `project.godot` settings such as app name, main scene, autoloads, and InputMap entries;
- small `.tscn` scene text edits when node paths, resource IDs, and external resources are understood;
- simple `.tres` resources when the resource type and properties are verified.

After editing externally, tell the user to focus or reopen Godot, refresh the FileSystem dock if needed, and watch the Output panel for parse/import errors.

## Prefer Godot Editor

Use the editor when the task is visual, import-driven, or resource-graph-heavy:

- import settings for textures, audio, fonts, models, and animations;
- collision shapes or layout adjusted by visual handles;
- TileSet editing, animation tracks, theme editing, complex materials;
- resources with generated UIDs or many subresources unless the format is already clear.

## Avoid Hand Editing

Do not manually edit as a primary approach:

- `.godot/`;
- generated import artifacts and binary cache files;
- unknown binary `.res` resources;
- generated files under temporary audit or cache directories;
- `.import` files except for read-only diagnosis.

## Edit Sequence

1. Run `scripts/godot_project_probe.py <project-root>`.
2. Identify the exact source files and the `res://` paths involved.
3. Check official docs when a file format, class, property, or CLI flag is version-sensitive.
4. Make the smallest external edit only if the file class is safe.
5. Validate by reading the changed files and, when available, running a Godot CLI parse/run check.

## Common Risks

- Missing `res://` references after moving files.
- Resource ID collisions inside `.tscn`/`.tres` files.
- Confusing Godot 3.x APIs with Godot 4.x APIs.
- Editing generated import state instead of source assets or project settings.
- Scanning temporary folders and mistaking cached third-party files for project source.
