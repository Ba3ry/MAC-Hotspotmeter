#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="$project_dir/dist"
app="$output_dir/HotspotMeter.app"
if [[ ! -d "$app" ]]; then
    printf '%s\n' 'Run bash scripts/build.sh before creating a DMG.' >&2
    exit 1
fi
/usr/bin/codesign --verify "$app"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
name="HotspotMeter-${version}-arm64.dmg"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/hotspotmeter-dmg.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

mkdir -p "$scratch/volume"
/usr/bin/ditto --norsrc "$app" "$scratch/volume/HotspotMeter.app"
ln -s /Applications "$scratch/volume/Applications"
/usr/bin/hdiutil create -format UDZO -volname HotspotMeter -srcfolder "$scratch/volume" "$scratch/$name"
/usr/bin/hdiutil verify "$scratch/$name"
mv -f "$scratch/$name" "$output_dir/$name"
printf '%s\n' "$output_dir/$name"
