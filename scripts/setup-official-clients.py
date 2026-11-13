#!/usr/bin/env python3
"""Restore pinned official clients and apply the Vibegram patches."""

import argparse
import json
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parent.parent


def git(directory, *args, check=True, capture=False):
    return subprocess.run(
        ["git", "-C", str(directory), *args],
        check=check,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
        text=True,
    )


def restore(platform, source, dependencies):
    directory = ROOT / platform
    if not (directory / ".git").exists():
        if directory.exists() and any(directory.iterdir()):
            raise RuntimeError(f"Refusing to overwrite nonempty directory: {directory}")
        subprocess.run(
            ["git", "clone", "--filter=blob:none", "--no-checkout", source["url"], str(directory)],
            check=True,
        )
        git(directory, "checkout", "--detach", source["revision"])

    revision = git(directory, "rev-parse", "HEAD", capture=True).stdout.strip()
    if revision != source["revision"]:
        raise RuntimeError(
            f"{platform}: expected {source['revision']}, found {revision}; "
            "stopping to preserve the existing checkout"
        )

    for key in ("patch", "build_patch"):
        if key not in source:
            continue
        patch = str(ROOT / source[key])
        if git(directory, "apply", "--reverse", "--check", patch, check=False, capture=True).returncode == 0:
            print(f"{platform}: {Path(patch).name} already applied", flush=True)
        else:
            git(directory, "apply", "--check", patch)
            git(directory, "apply", patch)
            print(f"{platform}: {Path(patch).name} applied", flush=True)

    if dependencies:
        git(
            directory,
            "-c", "url.https://github.com/.insteadOf=git@github.com:",
            "-c", "url.https://gitlab.com/.insteadOf=git@gitlab.com:",
            "submodule", "update", "--init", "--recursive", "--jobs", "4",
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=["macOS", "iOS", "all"], default="all")
    parser.add_argument("--dependencies", action="store_true", help="Also restore native build submodules")
    args = parser.parse_args()
    sources = json.loads((ROOT / "scripts/official-clients.json").read_text())
    for platform, source in sources.items():
        if args.platform in ("all", platform):
            restore(platform, source, args.dependencies)


if __name__ == "__main__":
    main()
