#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/hotspotmeter-tests.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

xcrun swiftc -module-cache-path "$scratch/module-cache" \
    "$project_dir/Sources/Traffic.swift" "$project_dir/Tests/TrafficChecks.swift" \
    -o "$scratch/traffic-checks"
"$scratch/traffic-checks" "$scratch"
