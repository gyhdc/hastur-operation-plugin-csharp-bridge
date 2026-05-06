# Official Docs Policy

Default target version: Godot 4.6.

## Lookup Order

1. Start with the Chinese docs for orientation:
   - `https://docs.godotengine.org/zh-cn/4.x/`
   - Search pattern: `site:docs.godotengine.org/zh-cn/4.x <keyword>`
2. For version-sensitive facts, cross-check the English 4.6 docs:
   - `https://docs.godotengine.org/en/4.6/`
   - Search pattern: `site:docs.godotengine.org/en/4.6 <keyword>`
3. If Chinese and English docs differ, treat English 4.6 as the final version authority and mention the mismatch.

## Always Verify

Verify official docs before giving or editing:

- class APIs, method names, property names, signals, annotations;
- GDScript syntax that may differ from Godot 3.x;
- `.tscn`, `.tres`, `project.godot`, UID, import, or resource format details;
- InputMap event encoding, autoload config, export presets, CLI flags;
- TileMap/TileMapLayer, physics bodies, animation, Control layout, rendering, or multiplayer APIs.

## Useful Known Pages

- Features: `https://docs.godotengine.org/zh-cn/4.x/about/list_of_features.html`
- InputMap: `https://docs.godotengine.org/zh-cn/4.x/classes/class_inputmap.html`
- TSCN/TRES text format: `https://docs.godotengine.org/zh-cn/4.x/engine_details/file_formats/tscn.html`
- GDScript basics: `https://docs.godotengine.org/zh-cn/4.x/tutorials/scripting/gdscript/gdscript_basics.html`
- Signals: `https://docs.godotengine.org/zh-cn/4.x/getting_started/step_by_step/signals.html`
- Autoloads: `https://docs.godotengine.org/zh-cn/4.x/tutorials/scripting/singletons_autoload.html`
- Exporting: `https://docs.godotengine.org/zh-cn/4.x/tutorials/export/exporting_projects.html`
- Command line: `https://docs.godotengine.org/zh-cn/4.x/tutorials/editor/command_line_tutorial.html`

Use `scripts/godot_doc_lookup.py <keyword>` when a direct page is not obvious.
