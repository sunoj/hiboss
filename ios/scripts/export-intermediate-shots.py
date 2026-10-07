#!/usr/bin/env python3
# Exports named intermediate-state XCTest screenshots as bounded-size PNG evidence.
# Usage: export-intermediate-shots.py <xcresult> <output-directory>.
# Dependencies: xcresulttool, sips and the Python standard library.

import json
from pathlib import Path
import subprocess
import sys
import tempfile


def export(bundle: str, destination: str) -> None:
    output = Path(destination)
    output.mkdir(parents=True, exist_ok=True)
    count = 0
    with tempfile.TemporaryDirectory(prefix="intermediate-shots-") as temporary:
        raw = Path(temporary)
        subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", bundle,
                        "--output-path", temporary], check=True, stdout=subprocess.DEVNULL)
        manifest = json.loads((raw / "manifest.json").read_text())
        for test in manifest:
            for attachment in test.get("attachments", []):
                name = attachment.get("suggestedHumanReadableName", attachment["exportedFileName"])
                name = name.split("_0_")[0].removesuffix(".png")
                if not name.startswith(("en-", "zh-")):
                    continue
                source = raw / attachment["exportedFileName"]
                subprocess.run(["sips", "-Z", "1100", str(source), "--out", str(output / (name + ".png"))],
                               check=True, stdout=subprocess.DEVNULL)
                count += 1
    print(f"Exported {count} named screenshots to {output}")


if __name__ == "__main__":
    export(sys.argv[1], sys.argv[2])
