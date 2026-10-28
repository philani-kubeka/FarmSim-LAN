#!/usr/bin/env python3
"""Static checks for the FarmSim project.

Catches the class of mistake that only shows up at runtime in Godot: a scene
pointing at a script that was renamed, an autoload path that no longer exists,
a `load_steps` count that does not match the resources in the file, or a
malformed data file.

Run it from the project root:

    python tools/validate_project.py

Exit code 0 means every check passed.
"""

from __future__ import annotations

import json
import os
import re
import sys

SKIP_DIRS = {".godot", ".git", "test_out", "__pycache__"}

# Paths that are created at runtime and are correctly absent from a clean tree.
RUNTIME_PATHS = {
    "res://test_out",
    "res://test_out/test_results.json",
    "res://test_out/sample_session.json",
    "res://data/sessions",
}

# Screens the session controller already knows about but that a later
# development stage still has to build. Reported as notices, not failures, so
# that a genuine broken reference is never lost in the noise.
PLANNED_PATHS: set[str] = set()


def res_to_fs(root: str, res_path: str) -> str:
    return os.path.join(root, res_path[len("res://"):])


def walk(root: str):
    for dirpath, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            yield os.path.join(dirpath, name)


# Variable types whose methods return Variant to the GDScript analyser, so that
# `var x := thatvar.method()` cannot infer a type and fails to compile. gdparse
# and every other syntax-only tool miss this; Godot only reports it at load
# time, and the symptom is a scene with no script (a blank window).
OPAQUE_TYPES = {
    "Node", "Node2D", "Node3D", "CanvasItem", "CanvasLayer", "Control",
    "Object", "RefCounted", "Resource", "Variant", "CharacterBody2D",
}

DECL_RE = re.compile(r"^\s*(?:@\w+\s+)?var\s+(\w+)\s*:\s*([A-Za-z_][\w]*)", re.M)
INFER_RE = re.compile(r"^\s*var\s+(\w+)\s*:=\s*(\w+)\.\w+\s*\(", re.M)
# `var x := thing.method() as Type` is fine: the cast supplies the type.
CAST_RE = re.compile(r"\)\s*as\s+[A-Za-z_][\w]*\s*$")


def check_type_inference(text: str, rel: str) -> list[str]:
    """Flags `var x := <opaque>.method()`, which Godot refuses to compile."""
    opaque = {
        name for name, declared in DECL_RE.findall(text) if declared in OPAQUE_TYPES
    }
    problems: list[str] = []
    if not opaque:
        return problems
    for line_number, line in enumerate(text.splitlines(), start=1):
        match = INFER_RE.match(line)
        if match and match.group(2) in opaque and not CAST_RE.search(line.rstrip()):
            problems.append(
                f"{rel}:{line_number}: `var {match.group(1)} := {match.group(2)}."
                f"...()` cannot infer a type ({match.group(2)} is opaque to the "
                f"analyser). Annotate it explicitly, e.g. `var {match.group(1)}: int = ...`"
            )
    return problems


def check(root: str) -> list[str]:
    problems: list[str] = []

    notices: list[str] = []

    def missing(res_path: str) -> bool:
        if res_path in RUNTIME_PATHS:
            return False
        if res_path in PLANNED_PATHS:
            notices.append(res_path)
            return False
        if "%" in res_path or "{" in res_path:
            return False
        return not os.path.exists(res_to_fs(root, res_path))

    for full in walk(root):
        rel = os.path.relpath(full, root)

        if full.endswith((".tscn", ".tres")):
            text = open(full, encoding="utf-8").read()
            for match in re.finditer(r'\[ext_resource[^\]]*path="([^"]+)"', text):
                path = match.group(1)
                if path.startswith("res://") and missing(path):
                    problems.append(f"{rel}: ext_resource points at a missing file: {path}")

            header = re.search(r"\[gd_(?:scene|resource)[^\]]*load_steps=(\d+)", text)
            n_ext = len(re.findall(r"^\[ext_resource", text, re.M))
            n_sub = len(re.findall(r"^\[sub_resource", text, re.M))
            if header and int(header.group(1)) != n_ext + n_sub + 1:
                problems.append(
                    f"{rel}: load_steps={header.group(1)} but the file declares "
                    f"{n_ext} ext_resource and {n_sub} sub_resource entries "
                    f"(expected {n_ext + n_sub + 1})"
                )

        elif full.endswith(".gd"):
            text = open(full, encoding="utf-8").read()
            problems.extend(check_type_inference(text, rel))
            for match in re.finditer(r'"(res://[^"]+)"', text):
                path = match.group(1)
                if missing(path):
                    problems.append(f"{rel}: refers to a missing resource: {path}")

        elif full.endswith(".json") and os.sep + "data" + os.sep in full:
            try:
                json.load(open(full, encoding="utf-8"))
            except Exception as exc:  # noqa: BLE001 - report whatever json says
                problems.append(f"{rel}: invalid JSON: {exc}")

    project_file = os.path.join(root, "project.godot")
    if not os.path.exists(project_file):
        problems.append("project.godot is missing")
        return problems

    project_text = open(project_file, encoding="utf-8").read()
    autoload_section = re.search(r"\[autoload\](.*?)(\n\[|\Z)", project_text, re.S)
    if autoload_section:
        for match in re.finditer(r'^(\w+)="\*?(res://[^"]+)"', autoload_section.group(1), re.M):
            name, path = match.groups()
            if missing(path):
                problems.append(f"project.godot: autoload {name} points at a missing file: {path}")

    main_scene = re.search(r'run/main_scene="(res://[^"]+)"', project_text)
    if not main_scene:
        problems.append("project.godot: no main scene is configured")
    elif missing(main_scene.group(1)):
        problems.append(f"project.godot: main scene is missing: {main_scene.group(1)}")

    if notices:
        for path in sorted(set(notices)):
            print(f"  note: {path} is scheduled for a later development stage")

    return problems


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    problems = check(root)
    if problems:
        print(f"{len(problems)} problem(s) found:")
        for problem in problems:
            print(f"  - {problem}")
        return 1
    print("Static reference check: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
