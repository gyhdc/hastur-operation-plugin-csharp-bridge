#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import io
import json
import sys

if sys.stdout.encoding != "utf-8":
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
if sys.stderr.encoding != "utf-8":
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

ZH_BASE = "https://docs.godotengine.org/zh-cn/4.x"
EN_BASE = "https://docs.godotengine.org/en/4.6"

TOPICS = {
    "inputmap": [("InputMap class", "classes/class_inputmap.html")],
    "input": [("Input event tutorial", "tutorials/inputs/inputevent.html")],
    "tscn": [("TSCN scene file format", "engine_details/file_formats/tscn.html")],
    "scene": [
        ("Scenes and nodes", "getting_started/step_by_step/scenes_and_nodes.html"),
        ("PackedScene class", "classes/class_packedscene.html"),
    ],
    "tres": [
        ("TSCN/TRES text resource format", "engine_details/file_formats/tscn.html"),
        ("Resource class", "classes/class_resource.html"),
    ],
    "resource": [("Resource class", "classes/class_resource.html")],
    "gdscript": [("GDScript basics", "tutorials/scripting/gdscript/gdscript_basics.html")],
    "signals": [("Signals", "getting_started/step_by_step/signals.html")],
    "signal": [("Signals", "getting_started/step_by_step/signals.html")],
    "autoload": [("Singletons and autoload", "tutorials/scripting/singletons_autoload.html")],
    "singleton": [("Singletons and autoload", "tutorials/scripting/singletons_autoload.html")],
    "projectsettings": [("ProjectSettings class", "classes/class_projectsettings.html")],
    "project": [("ProjectSettings class", "classes/class_projectsettings.html")],
    "export": [("Exporting projects", "tutorials/export/exporting_projects.html")],
    "cli": [("Command line tutorial", "tutorials/editor/command_line_tutorial.html")],
    "commandline": [("Command line tutorial", "tutorials/editor/command_line_tutorial.html")],
    "tilemaplayer": [("TileMapLayer class", "classes/class_tilemaplayer.html")],
    "tilemap": [("TileMapLayer class", "classes/class_tilemaplayer.html")],
    "node": [("Node class", "classes/class_node.html")],
    "node2d": [("Node2D class", "classes/class_node2d.html")],
    "control": [("Control class", "classes/class_control.html")],
    "characterbody2d": [("CharacterBody2D class", "classes/class_characterbody2d.html")],
    "rigidbody2d": [("RigidBody2D class", "classes/class_rigidbody2d.html")],
    "area2d": [("Area2D class", "classes/class_area2d.html")],
    "animationplayer": [("AnimationPlayer class", "classes/class_animationplayer.html")],
}


def normalize(text):
    return "".join(ch for ch in text.lower() if ch.isalnum())


def topic_matches(query):
    norm = normalize(query)
    matches = []
    for key, pages in TOPICS.items():
        if key in norm or norm in key:
            matches.extend(pages)
    return matches


def build_result(query):
    pages = topic_matches(query)
    direct = []
    seen = set()
    for title, path in pages:
        if path in seen:
            continue
        seen.add(path)
        direct.append(
            {
                "title": title,
                "zh_cn_4x": ZH_BASE + "/" + path,
                "en_46": EN_BASE + "/" + path,
            }
        )
    return {
        "query": query,
        "direct_candidates": direct,
        "site_queries": [
            "site:docs.godotengine.org/zh-cn/4.x " + query,
            "site:docs.godotengine.org/en/4.6 " + query,
        ],
    }


def print_text(results):
    for result in results:
        print("Query: " + result["query"])
        if result["direct_candidates"]:
            print("Direct official candidates:")
            for item in result["direct_candidates"]:
                print("  - " + item["title"])
                print("    zh-cn/4.x: " + item["zh_cn_4x"])
                print("    en/4.6:    " + item["en_46"])
        else:
            print("Direct official candidates: none; use site queries.")
        print("Site queries:")
        for query in result["site_queries"]:
            print("  - " + query)
        print()


def main():
    parser = argparse.ArgumentParser(description="Suggest Godot official documentation URLs and site queries.")
    parser.add_argument("keywords", nargs="+", help="Godot keywords, classes, APIs, or file formats to look up.")
    parser.add_argument("--json", action="store_true", help="Emit JSON.")
    args = parser.parse_args()

    results = [build_result(keyword) for keyword in args.keywords]
    if args.json:
        print(json.dumps(results, ensure_ascii=False, indent=2))
    else:
        print_text(results)


if __name__ == "__main__":
    main()
