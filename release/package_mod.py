"""Builds the Workshop zip for the Story Mode mod (#193).

    python release/package_mod.py [--out <dir>]

Packs mods-unpacked/cejdan-StoryMode/ into
<out>/cejdan-StoryMode.zip (default out: ../release_builds, outside
the repo), with the layout the mod loader expects
(mods-unpacked/cejdan-StoryMode/...). The version (manifest.json) is printed, not put in the name.

Only files with an allowed extension go in; dev/ (the playtest harness and dev
cheats) and editor/OS junk never do. Anything else found is listed and fails
the build, so a new file type is a decision, not an accident.
"""
import argparse
import json
import os
import sys
import zipfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD_ID = "cejdan-StoryMode"
MOD_DIR = os.path.join(REPO, "mods-unpacked", MOD_ID)

ALLOWED = {".gd", ".tscn", ".tres", ".gdshader", ".gdshaderinc", ".png", ".ogg", ".wav", ".json", ".yaml", ".gdignore", ".ttf"}
SKIP_DIRS = {"dev", ".godot", ".git", "__pycache__", ".import"}
SKIP_FILES = {"Thumbs.db", ".DS_Store", "desktop.ini"}
SKIP_EXT = {".import", ".tmp", ".bak", ".orig", ".log", ".uid", ".md", ".ps1", ".bat", ".py"}


def collect():
    keep, unknown, skipped = [], [], []
    for root, dirs, files in os.walk(MOD_DIR):
        rel_root = os.path.relpath(root, MOD_DIR)
        for d in list(dirs):
            if d in SKIP_DIRS:
                dirs.remove(d)
                skipped.append(os.path.join(rel_root, d) + "/")
        for f in files:
            rel = os.path.normpath(os.path.join(rel_root, f))
            ext = os.path.splitext(f)[1].lower() or f
            if f in SKIP_FILES or ext in SKIP_EXT:
                skipped.append(rel)
            elif ext in ALLOWED:
                keep.append(rel)
            else:
                unknown.append(rel)
    return sorted(keep), unknown, skipped


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(os.path.dirname(REPO), "release_builds"))
    a = ap.parse_args()
    with open(os.path.join(MOD_DIR, "manifest.json"), encoding="utf-8") as fh:
        manifest = json.load(fh)
    version = manifest["version_number"]
    keep, unknown, skipped = collect()
    if unknown:
        print("Unknown file types (add them to ALLOWED or SKIP_EXT):")
        for u in unknown:
            print("  " + u)
        sys.exit(1)
    for rel in keep:
        if rel.split(os.sep)[0] == "dev":
            sys.exit("dev/ file slipped in: " + rel)
    os.makedirs(a.out, exist_ok=True)
    out = os.path.join(a.out, MOD_ID + ".zip")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for rel in keep:
            z.write(os.path.join(MOD_DIR, rel), "mods-unpacked/%s/%s" % (MOD_ID, rel.replace(os.sep, "/")))
    print("Built %s, version %s (%d files, %.1f KB)" % (out, version, len(keep), os.path.getsize(out) / 1024))
    print("Left out: " + ", ".join(skipped))


if __name__ == "__main__":
    main()
