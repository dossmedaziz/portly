#!/usr/bin/env python3
"""Rasterize assets/icons/*.svg into the PNG sizes Portly ships.

Uses rsvg-convert when installed, otherwise GdkPixbuf's SVG loader
(part of a stock GNOME install).

    python3 tool/export_icons.py
"""
import shutil
import subprocess
from pathlib import Path

ICONS = Path(__file__).resolve().parent.parent / "assets" / "icons"

TARGETS = [
    ("portly_tray.svg", 22, "portly_tray_22.png"),
    ("portly_tray.svg", 32, "portly_tray_32.png"),
    ("portly.svg", 128, "portly_128.png"),
    ("portly.svg", 256, "portly_256.png"),
    ("portly.svg", 512, "portly_512.png"),
]


def render(svg: Path, size: int, png: Path) -> None:
    if shutil.which("rsvg-convert"):
        subprocess.run(
            ["rsvg-convert", "-w", str(size), "-h", str(size), "-o", str(png), str(svg)],
            check=True,
        )
        return
    import gi

    gi.require_version("GdkPixbuf", "2.0")
    from gi.repository import GdkPixbuf

    pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(str(svg), size, size, True)
    pixbuf.savev(str(png), "png", [], [])


def main() -> None:
    for source, size, name in TARGETS:
        render(ICONS / source, size, ICONS / name)
        print(f"{name}: {size}x{size}")


if __name__ == "__main__":
    main()
