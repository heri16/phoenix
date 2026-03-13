#!/usr/bin/env python3
"""Convert TOML config to JSON for Jekyll _data. Requires Python 3.11+."""
import json
import sys
import tomllib
from pathlib import Path


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input.toml> <output.json>", file=sys.stderr)
        sys.exit(1)

    toml_path = Path(sys.argv[1])
    json_path = Path(sys.argv[2])

    with toml_path.open("rb") as f:
        data = tomllib.load(f)

    json_path.parent.mkdir(parents=True, exist_ok=True)

    with json_path.open("w") as f:
        json.dump(data, f, indent=2)

    print(f"Converted {toml_path} -> {json_path}")


if __name__ == "__main__":
    main()
