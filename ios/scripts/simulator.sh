#!/bin/bash
# Simulator ownership helpers for local iOS verification scripts.
# Uses simbox when available; otherwise releases only a device booted here.

simulator_cleanup() {
  if [[ -n ${SIMULATOR_LEASE:-} ]]; then
    simbox release "$SIMULATOR_LEASE"
  elif [[ ${SIMULATOR_BOOTED:-0} == 1 ]]; then
    xcrun simctl shutdown "$SIMULATOR_ID"
  fi
}

simulator_acquire() {
  local device_type=$1 lease
  SIMULATOR_LEASE=
  SIMULATOR_BOOTED=0
  trap simulator_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  if command -v simbox >/dev/null 2>&1; then
    lease=$(simbox lease --type "$device_type")
    read -r SIMULATOR_LEASE SIMULATOR_ID <<< "$lease"
  else
    SIMULATOR_ID=$(xcrun simctl list devices available --json | python3 -c '
import json, sys
name = sys.argv[1]
for devices in json.load(sys.stdin)["devices"].values():
    for device in devices:
        if device["name"] == name:
            print(device["udid"])
            sys.exit(0)
sys.exit("Simulator not found: " + name)
' "$device_type")
    if ! xcrun simctl list devices booted --json | python3 -c '
import json, sys
sys.exit(not any(d["udid"] == sys.argv[1] for devices in
    json.load(sys.stdin)["devices"].values() for d in devices))
' "$SIMULATOR_ID"; then
      xcrun simctl boot "$SIMULATOR_ID"
      SIMULATOR_BOOTED=1
    fi
  fi
}

simulator_command() {
  local device_type=$1
  if command -v simbox >/dev/null 2>&1; then
    SIMULATOR_ID='{udid}'
    SIMULATOR_COMMAND=(simbox run --type "$device_type" --)
  else
    simulator_acquire "$device_type"
    # Consumed by the sourcing test wrapper.
    # shellcheck disable=SC2034
    SIMULATOR_COMMAND=(env)
  fi
}
