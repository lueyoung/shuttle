#!/usr/bin/env python3
import pathlib
import subprocess


ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "Shuttle"
# Compiled with ARC, like the Xcode project.
ARC_SOURCES = ["AppDelegate.m", "TerminalManager.m", "AboutWindowController.m"]
# The Xcode project builds this file with -fno-objc-arc.
MRC_SOURCES = ["LaunchAtLoginController.m"]
FRAMEWORKS = ["Cocoa", "ServiceManagement", "CoreServices"]


def run_checked(command):
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError("command failed: {}\n{}".format(" ".join(command), result.stderr))


def build_harness(harness_source, output_dir):
    """Compile an Objective-C test harness with the app sources and return the binary path."""
    output_dir = pathlib.Path(output_dir)
    clang = ["xcrun", "--sdk", "macosx", "clang", "-I", str(SOURCE_DIR)]

    objects = []
    for name in MRC_SOURCES:
        object_path = output_dir / (pathlib.Path(name).stem + ".o")
        run_checked(clang + ["-fno-objc-arc", "-c", str(SOURCE_DIR / name), "-o", str(object_path)])
        objects.append(str(object_path))

    binary = output_dir / pathlib.Path(harness_source).stem
    sources = [str(harness_source)] + [str(SOURCE_DIR / name) for name in ARC_SOURCES]
    frameworks = [arg for framework in FRAMEWORKS for arg in ("-framework", framework)]
    run_checked(clang + ["-fobjc-arc"] + sources + objects + frameworks + ["-o", str(binary)])
    return binary
