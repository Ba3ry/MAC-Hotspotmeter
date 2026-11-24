#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="$project_dir/dist"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/hotspotmeter-build.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

resources="$project_dir/Resources"
app_name="HotspotMeter.app"
app="$scratch/$app_name"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
/usr/bin/plutil -lint "$resources/Info.plist"
cp "$resources/Info.plist" "$app/Contents/Info.plist"
cp "$resources/HotspotMeter.icns" "$app/Contents/Resources/"
xcrun swiftc -O -target arm64-apple-macos14.0 -module-cache-path "$scratch/module-cache" \
    "$project_dir"/Sources/*.swift -o "$app/Contents/MacOS/HotspotMeter"

/usr/bin/codesign --sign - "$app"
/usr/bin/codesign --verify --strict "$app"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$resources/Info.plist")"
archive="HotspotMeter-${version}-arm64.zip"
/usr/bin/ditto -c -k --norsrc --keepParent "$app" "$scratch/$archive"

mkdir -p "$output_dir"
rm -rf "$output_dir/$app_name"
/usr/bin/ditto --norsrc "$app" "$output_dir/$app_name"
mv -f "$scratch/$archive" "$output_dir/$archive"
printf '%s\n' "$output_dir/$app_name" "$output_dir/$archive"
