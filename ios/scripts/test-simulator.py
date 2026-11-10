#!/usr/bin/env python3
# Hermetic regression tests for simulator ownership and failure cleanup.
# Uses fake simctl/simbox commands; never contacts CoreSimulator.
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

HELPER = Path(__file__).with_name('simulator.sh').resolve()


class SimulatorTests(unittest.TestCase):
    def run_case(self, booted=False, pooled=False, failure=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            log = root / 'commands'
            fake = root / 'xcrun'
            fake.write_text('''#!/bin/bash
printf '%s\\n' "$*" >> "$COMMAND_LOG"
if [[ $* == 'simctl list devices available --json' ]]; then
  echo '{"devices":{"runtime":[{"name":"Test Phone","udid":"test-device"}]}}'
elif [[ $* == 'simctl list devices booted --json' ]]; then
  if [[ $BOOTED == 1 ]]; then
    echo '{"devices":{"runtime":[{"udid":"test-device"}]}}'
  else
    echo '{"devices":{}}'
  fi
fi
''')
            fake.chmod(0o755)
            if pooled:
                simbox = root / 'simbox'
                simbox.write_text('''#!/bin/bash
printf '%s\\n' "$*" >> "$COMMAND_LOG"
if [[ $1 == lease ]]; then echo 'test-lease test-device'; fi
''')
                simbox.chmod(0o755)
            env = dict(os.environ, PATH=f'{root}:/usr/bin:/bin',
                       COMMAND_LOG=str(log), BOOTED=str(int(booted)))
            result = subprocess.run(
                ['/bin/bash', '-c', 'set -euo pipefail; source "$1"; '
                 'simulator_acquire "Test Phone"; exit "$2"',
                 'test', str(HELPER), '7' if failure else '0'], env=env, check=False)
            self.assertEqual(result.returncode, 7 if failure else 0)
            return log.read_text()

    def test_fallback_releases_device_after_success(self):
        commands = self.run_case()
        self.assertIn('simctl boot test-device\n', commands)
        self.assertIn('simctl shutdown test-device\n', commands)

    def test_fallback_releases_device_after_failure(self):
        self.assertIn('simctl shutdown test-device\n', self.run_case(failure=True))

    def test_fallback_preserves_already_booted_device(self):
        commands = self.run_case(booted=True)
        self.assertNotIn('simctl boot test-device\n', commands)
        self.assertNotIn('simctl shutdown test-device\n', commands)

    def test_pool_lease_is_released_after_failure(self):
        commands = self.run_case(pooled=True, failure=True)
        self.assertIn('lease --type Test Phone\n', commands)
        self.assertIn('release test-lease\n', commands)
        self.assertNotIn('simctl', commands)


if __name__ == '__main__':
    unittest.main()
