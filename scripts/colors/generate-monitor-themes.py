#!/usr/bin/env python3

import json
import os
import subprocess
import sys
from pathlib import Path


config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
state_home = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state"))
config_path = config_home / "illogical-impulse" / "config.json"
output_dir = state_home / "quickshell" / "user" / "generated"


def generated_palette(path, mode, scheme):
    command = ["matugen", "image", path, "--mode", mode, "--type", scheme,
               "--source-color-index", "0", "--json", "hex", "--dry-run"]
    return json.loads(subprocess.run(command, check=True, text=True, capture_output=True).stdout)


def average_hex(values):
    channels = [tuple(int(value[offset:offset + 2], 16) for offset in (1, 3, 5)) for value in values]
    return "#{:02x}{:02x}{:02x}".format(*(round(sum(color[index] for color in channels) / len(channels)) for index in range(3)))


def main():
    try:
        config = json.loads(config_path.read_text())
        background = config["background"]
        if background.get("wallpaperMode") != "perMonitor":
            return 0

        entries = [entry for entry in background.get("monitorWallpapers", []) if entry.get("name") and entry.get("path")]
        if len({entry["path"] for entry in entries}) < 2:
            return 0

        mode = "dark" if subprocess.run(["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"], text=True, capture_output=True).stdout.strip("\n'") == "prefer-dark" else "light"
        scheme = config.get("appearance", {}).get("palette", {}).get("type", "scheme-tonal-spot")
        if scheme == "auto":
            scheme = "scheme-tonal-spot"

        palettes = {entry["name"]: generated_palette(entry["path"], mode, scheme) for entry in entries}
        all_palettes = list(palettes.values())
        blended = json.loads(json.dumps(all_palettes[0]))
        for role in blended["colors"]:
            for variant in blended["colors"][role]:
                blended["colors"][role][variant]["color"] = average_hex([palette["colors"][role][variant]["color"] for palette in all_palettes])

        output_dir.mkdir(parents=True, exist_ok=True)
        monitor_colors = {name: {role: value["default"]["color"] for role, value in palette["colors"].items()} for name, palette in palettes.items()}
        (output_dir / "monitor-colors.json").write_text(json.dumps(monitor_colors, indent=2) + "\n")
        blended_path = output_dir / "blended-matugen.json"
        blended_path.write_text(json.dumps(blended) + "\n")
        subprocess.run(["matugen", "json", str(blended_path)], check=True)
    except (OSError, KeyError, ValueError, subprocess.CalledProcessError) as error:
        print(f"[monitor-themes] {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
