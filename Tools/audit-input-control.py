#!/usr/bin/env python3
"""Verify the explicit product constraint: never synthesize input or move cursors."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
forbidden = (
    "CGEvent", "CGWarpMouseCursorPosition", "CGDisplayMoveCursorToPoint",
    "CGAssociateMouseAndMouseCursorPosition", "CGPostMouseEvent",
    "IOHIDPostEvent", "postToPid", "AXUIElementPerformAction",
)
for path in (root / "Sources").rglob("*"):
    if path.suffix in {".swift", ".m", ".h"}:
        source = path.read_text()
        for name in forbidden:
            if name in source:
                raise SystemExit(f"Input-control API found: {path}:{name}")
if len(sys.argv) > 1:
    symbols = subprocess.check_output(["nm", "-u", sys.argv[1]], text=True)
    for name in forbidden:
        if name in symbols:
            raise SystemExit(f"Input-control symbol found in executable: {name}")
print("No synthesized input or cursor-control APIs found.")
