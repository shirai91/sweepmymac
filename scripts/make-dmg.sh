#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

app_bundle="build/Sweep.app"
dmg_path="build/Sweep.dmg"

if [[ ! -d "$app_bundle" ]]; then
    "$script_dir/build-app.sh"
fi

staging_dir="$(mktemp -d)"
trap 'rm -rf "$staging_dir"' EXIT

ditto "$app_bundle" "$staging_dir/Sweep.app"
ln -s /Applications "$staging_dir/Applications"

rm -f "$dmg_path"
hdiutil create -volname "Sweep" -srcfolder "$staging_dir" -ov -format UDZO "$dmg_path"
echo "$repo_root/$dmg_path"
