#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import io
import json
import os
import re
import sys
from pathlib import Path, PurePosixPath

if sys.stdout.encoding != "utf-8":
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
if sys.stderr.encoding != "utf-8":
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

SKIP_DIRS = {
    ".godot",
    ".git",
    ".hg",
    ".svn",
    ".vscode",
    "__pycache__",
    "node_modules",
    "tmp",
}

SOURCE_EXTS = {".gd", ".tscn", ".tres"}
ASSET_EXTS = {
    ".png",
    ".jpg",
    ".jpeg",
    ".webp",
    ".svg",
    ".ogg",
    ".wav",
    ".mp3",
    ".ttf",
    ".otf",
    ".glb",
    ".gltf",
    ".dae",
    ".aseprite",
}

RES_RE = re.compile(r"res://[^\"'\s\]\)\},]+")
SECTION_RE = re.compile(r"^\s*\[([^\]]+)\]\s*$")
NODE_ATTR_RE = re.compile(r'(\w+)="([^"]*)"')


def read_text(path):
    try:
        return path.read_text(encoding="utf-8-sig", errors="replace")
    except OSError:
        return ""


def rel(path, root):
    try:
        return str(path.relative_to(root)).replace("\\", "/")
    except ValueError:
        return str(path)


def parse_project_godot(path):
    sections = {}
    current = None
    text = read_text(path)
    for line in text.splitlines():
        match = SECTION_RE.match(line)
        if match:
            current = match.group(1)
            sections.setdefault(current, {})
            continue
        stripped = line.strip()
        if not stripped or stripped.startswith(";") or stripped.startswith("#") or "=" not in stripped:
            continue
        if current is None:
            current = ""
            sections.setdefault(current, {})
        key, value = stripped.split("=", 1)
        sections[current][key.strip()] = value.strip()
    return sections


def strip_variant_string(value):
    value = value.strip()
    if value.startswith('"') and value.endswith('"') and len(value) >= 2:
        return value[1:-1]
    return value


def extract_quoted_values(value):
    return re.findall(r'"([^"]*)"', value)


def extract_res_paths(text):
    refs = set()
    for match in RES_RE.finditer(text):
        ref = match.group(0).rstrip(".,;:")
        refs.add(ref)
    return sorted(refs)


def resolve_res_path(root, ref):
    if not ref.startswith("res://"):
        return None
    suffix = ref[len("res://") :]
    if not suffix:
        return root
    posix = PurePosixPath(suffix)
    return root.joinpath(*posix.parts)


def scan_files(root):
    files = []
    counts = {
        "scripts": 0,
        "scenes": 0,
        "text_resources": 0,
        "assets": 0,
        "import_sidecars": 0,
        "other": 0,
    }
    for current, dirs, filenames in os.walk(str(root)):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.endswith(".tmp")]
        for filename in filenames:
            path = Path(current) / filename
            suffix = path.suffix.lower()
            if filename == "project.godot":
                files.append(path)
                continue
            if suffix == ".import":
                counts["import_sidecars"] += 1
                continue
            if suffix == ".gd":
                counts["scripts"] += 1
                files.append(path)
            elif suffix == ".tscn":
                counts["scenes"] += 1
                files.append(path)
            elif suffix == ".tres":
                counts["text_resources"] += 1
                files.append(path)
            elif suffix in ASSET_EXTS:
                counts["assets"] += 1
            else:
                counts["other"] += 1
    return files, counts


def parse_scene(path, root):
    text = read_text(path)
    root_node = None
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped.startswith("[node "):
            continue
        attrs = dict(NODE_ATTR_RE.findall(stripped))
        if "parent" not in attrs:
            root_node = {
                "name": attrs.get("name", ""),
                "type": attrs.get("type", ""),
                "instance": attrs.get("instance", ""),
            }
            break
    return {
        "path": rel(path, root),
        "root_node": root_node,
    }


def build_probe(root, max_items):
    root = root.resolve()
    project_file = root / "project.godot"
    files, counts = scan_files(root)
    sections = parse_project_godot(project_file) if project_file.exists() else {}

    app = sections.get("application", {})
    main_scene = strip_variant_string(app.get("run/main_scene", ""))
    features = extract_quoted_values(app.get("config/features", ""))
    autoloads = {}
    for name, raw_value in sections.get("autoload", {}).items():
        refs = extract_res_paths(raw_value)
        autoloads[name] = {
            "raw": raw_value,
            "path": refs[0] if refs else strip_variant_string(raw_value).lstrip("*"),
        }

    input_actions = sorted(strip_variant_string(key) for key in sections.get("input", {}).keys())
    scenes = [parse_scene(path, root) for path in files if path.suffix.lower() == ".tscn"]

    missing = []
    seen_missing = set()
    for path in files:
        if path.name != "project.godot" and path.suffix.lower() not in SOURCE_EXTS:
            continue
        text = read_text(path)
        for ref in extract_res_paths(text):
            target = resolve_res_path(root, ref)
            if target is None or target.exists():
                continue
            key = (rel(path, root), ref)
            if key in seen_missing:
                continue
            seen_missing.add(key)
            missing.append(
                {
                    "source": rel(path, root),
                    "reference": ref,
                    "resolved_path": str(target),
                }
            )

    return {
        "project_root": str(root),
        "project_file": str(project_file) if project_file.exists() else None,
        "godot_version_hints": features,
        "main_scene": main_scene,
        "autoloads": autoloads,
        "input_actions": input_actions,
        "counts": counts,
        "scenes": scenes[:max_items],
        "scene_count_reported": min(len(scenes), max_items),
        "scene_count_total": len(scenes),
        "missing_res_references": missing[:max_items],
        "missing_res_reference_count_total": len(missing),
        "excluded_dirs": sorted(SKIP_DIRS),
    }


def print_text(report):
    print("Godot project probe")
    print("Root: " + report["project_root"])
    print("project.godot: " + (report["project_file"] or "not found"))
    print("Version hints: " + (", ".join(report["godot_version_hints"]) or "none"))
    print("Main scene: " + (report["main_scene"] or "not set"))
    print("Excluded dirs: " + ", ".join(report["excluded_dirs"]))
    print()
    print("Counts:")
    for key in sorted(report["counts"].keys()):
        print("  " + key + ": " + str(report["counts"][key]))
    print()
    print("Autoloads:")
    if report["autoloads"]:
        for name, info in report["autoloads"].items():
            print("  " + name + ": " + info.get("path", ""))
    else:
        print("  none")
    print()
    print("Input actions:")
    if report["input_actions"]:
        for action in report["input_actions"]:
            print("  - " + action)
    else:
        print("  none")
    print()
    print("Scenes:")
    if report["scenes"]:
        for scene in report["scenes"]:
            node = scene.get("root_node") or {}
            label = node.get("type") or "unknown"
            name = node.get("name") or "unnamed"
            print("  - " + scene["path"] + " root=" + label + "(" + name + ")")
    else:
        print("  none")
    print()
    print("Missing res:// references:")
    if report["missing_res_references"]:
        for item in report["missing_res_references"]:
            print("  - " + item["source"] + " -> " + item["reference"])
        total = report["missing_res_reference_count_total"]
        shown = len(report["missing_res_references"])
        if total > shown:
            print("  ... " + str(total - shown) + " more")
    else:
        print("  none")


def main():
    parser = argparse.ArgumentParser(description="Read-only Godot project inventory and reference check.")
    parser.add_argument("project_root", nargs="?", default=".", help="Path to a Godot project root.")
    parser.add_argument("--json", action="store_true", help="Emit JSON.")
    parser.add_argument("--max-items", type=int, default=50, help="Maximum scenes or missing refs to print.")
    args = parser.parse_args()

    root = Path(args.project_root)
    report = build_probe(root, max(1, args.max_items))
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print_text(report)


if __name__ == "__main__":
    main()
