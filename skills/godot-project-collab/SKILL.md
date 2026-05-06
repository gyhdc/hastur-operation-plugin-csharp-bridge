---
name: godot-project-collab
description: "Use when helping with Godot 4.6 projects, GDScript, C#/.NET scripts, project.godot, .tscn/.tres files, InputMap, autoloads, scene trees, resources, signals, Godot CLI, editor sync, or project diagnosis. Prefer the lightest reliable path; check official docs only for version-sensitive or uncertain APIs."
---

# Godot Project Collab

## Purpose

Use this skill to collaborate on Godot 4.6 projects accurately without over-processing. The skill is a workflow and inspection aid, not a scene generator: choose the lightest reliable path, then propose or implement the smallest correct change.

For Godot C#/.NET work, prefer local `.cs` file edits plus a real build check. When the enhanced Hastur C# Bridge is available, use `csharp-build` for compilation and `csharp-command` for runtime/editor observation; do not assume arbitrary C# snippets can be evaled like GDScript.

## Effort Ladder

Use the lowest level that can answer correctly:

1. Direct answer: use for small, stable Godot concepts and routine GDScript advice that do not depend on this project's files or on recently changed APIs. Do not run probes or open docs just to restate known basics.
2. Targeted local read: use when the answer depends on one known file or error location. Read that file directly instead of scanning the whole project.
3. Project probe: run `scripts/godot_project_probe.py <project-root>` only when project state matters and the relevant files are not already known, such as missing resources, main scene/autoload/InputMap questions, or scene/script inventory.
4. Official docs check: use `references/official-docs.md` and official Godot docs only when the topic is version-sensitive, uncertain, or easy to confuse with Godot 3.x/other 4.x versions. Prefer Chinese `zh-cn/4.x` for orientation, then English `en/4.6` for final API/file-format checks.

## Action Classification

When proposing or making a change, classify it when useful as:

   - external text edit: safe for focused `.gd`, `project.godot`, simple `.tscn/.tres` edits;
   - Godot editor edit: safer for import settings, visual scene layout, complex resources;
   - Godot CLI or EditorScript: safer for generated resources or validation.

Explain assumptions and cite official pages only when docs were actually checked.

## Tools

- `scripts/godot_project_probe.py`: optional read-only project inventory. It excludes `.godot/`, `.git/`, `.vscode/`, `tmp/`, import sidecars, and common cache folders. It reports main scene, autoloads, InputMap actions, source counts, scene root nodes, and missing `res://` references.
- `scripts/godot_doc_lookup.py`: optional read-only URL/query helper for Godot docs. Use it when the exact official page is not obvious.

## References

- Load `references/official-docs.md` only when an answer needs documentation lookup or version confirmation.
- Load `references/project-file-workflow.md` before risky edits to `project.godot`, `.tscn`, `.tres`, import metadata, or generated/editor-owned files.
- Load `references/common-patterns.md` only when a reusable Godot 4.6 pattern would prevent ad-hoc advice.

## Guardrails

- Assume Godot 4.6 unless the project or user says otherwise.
- Do not rely on memory when Godot 3.x and 4.x differ, when a minor-version API may have changed, or when unsure.
- Do not check docs or run project probes for every small question; use engineering judgment to avoid unnecessary workflow cost.
- Do not hand-edit `.godot/`, generated import artifacts, unknown binary resources, or complex editor-generated resource graphs.
- Treat `.import` files as read-only diagnostic context, not primary edit targets.
- Keep changes project-native and small. Prefer existing project structure and naming over introducing new architecture.
- For ordinary text reads, use the environment's safe text reader when available.
