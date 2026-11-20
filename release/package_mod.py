"""Builds the Workshop zip for the Story Mode mod (#193).

    python release/package_mod.py [--out <dir>]

Packs mods-unpacked/cejdan-StoryMode/ into
<out>/cejdan-StoryMode.zip (default out: ../release_builds, outside
the repo), with the layout the mod loader expects
(mods-unpacked/cejdan-StoryMode/...). The version (manifest.json) is printed, not put in the name.

It packs ONLY what is committed on main, read with `git archive`: the working
tree, uncommitted edits and the checked-out branch are ignored. It fetches
first and refuses to build unless local main matches origin/main.

Only files with an allowed extension go in; dev/ (the playtest harness and dev
cheats) and editor/OS junk never do. Anything else found is listed and fails
the build, so a new file type is a decision, not an accident.
"""
import argparse
import json
import io
import os
import subprocess
import sys
import tarfile
import zipfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD_ID = "cejdan-StoryMode"

ALLOWED = {".gd", ".tscn", ".tres", ".gdshader", ".gdshaderinc", ".png", ".ogg", ".wav", ".json", ".yaml", ".gdignore", ".ttf"}
SKIP_DIRS = {"dev", ".godot", ".git", "__pycache__", ".import"}
SKIP_FILES = {"Thumbs.db", ".DS_Store", "desktop.ini"}
SKIP_EXT = {".import", ".tmp", ".bak", ".orig", ".log", ".uid", ".md", ".ps1", ".bat", ".py"}


REF = "main"


def git(*args):
    return subprocess.run(["git", "-C", REPO] + list(args), check=True, capture_output=True).stdout


def main_files():
    """{path relative to the mod: bytes} for every file of the mod on main."""
    git("fetch", "-q", "origin", REF)
    local = git("rev-parse", REF).strip()
    remote = git("rev-parse", "origin/" + REF).strip()
    if local != remote:
        sys.exit("Local %s (%s) is not origin/%s (%s): pull or push first." % (REF, local[:7].decode(), REF, remote[:7].decode()))
    tar = tarfile.open(fileobj=io.BytesIO(git("archive", "--format=tar", REF, "mods-unpacked/" + MOD_ID)))
    out = {}
    for m in tar.getmembers():
        if m.isfile():
            out[m.name[len("mods-unpacked/" + MOD_ID) + 1:]] = tar.extractfile(m).read()
    return out, local[:7].decode()


def collect(files):
    keep, unknown, skipped = [], [], set()
    for rel in sorted(files):
        parts = rel.split("/")
        f = parts[-1]
        ext = os.path.splitext(f)[1].lower() or f
        if any(d in SKIP_DIRS for d in parts[:-1]):
            skipped.add(next(d for d in parts[:-1] if d in SKIP_DIRS) + "/")
        elif f in SKIP_FILES or ext in SKIP_EXT:
            skipped.add(rel)
        elif ext in ALLOWED:
            keep.append(rel)
        else:
            unknown.append(rel)
    return keep, unknown, sorted(skipped)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(os.path.dirname(REPO), "release_builds"))
    a = ap.parse_args()
    files, commit = main_files()
    manifest = json.loads(files["manifest.json"])
    version = manifest["version_number"]
    keep, unknown, skipped = collect(files)
    if unknown:
        print("Unknown file types (add them to ALLOWED or SKIP_EXT):")
        for u in unknown:
            print("  " + u)
        sys.exit(1)
    for rel in keep:
        if rel.split("/")[0] == "dev":
            sys.exit("dev/ file slipped in: " + rel)
    os.makedirs(a.out, exist_ok=True)
    out = os.path.join(a.out, MOD_ID + ".zip")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for rel in keep:
            z.writestr("mods-unpacked/%s/%s" % (MOD_ID, rel), files[rel])
    print("Built %s from main @ %s, version %s (%d files, %.1f KB)" % (out, commit, version, len(keep), os.path.getsize(out) / 1024))
    print("Left out: " + ", ".join(skipped))


if __name__ == "__main__":
    main()
