#!/usr/bin/env python3
# Captures state-only startup OSLog lines from a deterministic simulator demo launch.
# Exports a command taking a built .app directory and an output log path.
# Dependencies: Python stdlib and xcrun simctl; uses only iPhone 18 Pro Max.

import os
from pathlib import Path
import subprocess
import sys

SIMULATOR = "iPhone 18 Pro Max"
PREDICATE = 'subsystem == "ai.hiboss.app" AND category == "startup"'
DELAYS = {
    "HIBOSS_DEMO": "1",
    "HIBOSS_DEMO_EMPTY": "1",
    "HIBOSS_DEMO_STABLE_DEADLINES": "1",
    "HIBOSS_DEMO_HISTORY_DELAY_MS": "1200",
    "HIBOSS_DEMO_REQUESTS_DELAY_MS": "1200",
    "HIBOSS_DEMO_REQUESTS_READY_DELAY_MS": "300",
    "HIBOSS_DEMO_PANELS_DELAY_MS": "1200",
    "HIBOSS_DEMO_QUESTIONNAIRES_DELAY_MS": "1200",
}


def measure(app: str, output: str) -> None:
    subprocess.run(["xcrun", "simctl", "install", SIMULATOR, app], check=True)
    env = os.environ.copy()
    env.update({"SIMCTL_CHILD_" + key: value for key, value in DELAYS.items()})
    with Path(output).open("w") as log:
        capture = subprocess.Popen([
            "xcrun", "simctl", "spawn", SIMULATOR, "log", "stream", "--style", "compact",
            "--level", "debug", "--predicate", PREDICATE,
        ], stdout=log, stderr=subprocess.STDOUT)
        try:
            subprocess.run([
                "xcrun", "simctl", "launch", "--terminate-running-process", SIMULATOR,
                "ai.hiboss.app", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            ], env=env, check=True)
            try:
                capture.wait(timeout=8)
            except subprocess.TimeoutExpired:
                capture.terminate()
                capture.wait(timeout=5)
        finally:
            if capture.poll() is None:
                capture.terminate()
                capture.wait(timeout=5)
            subprocess.run(["xcrun", "simctl", "terminate", SIMULATOR, "ai.hiboss.app"], check=True)


if __name__ == "__main__":
    measure(sys.argv[1], sys.argv[2])
