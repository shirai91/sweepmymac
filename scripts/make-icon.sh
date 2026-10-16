#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

iconset_dir="$work_dir/AppIcon.iconset"
swift "$script_dir/make-icon.swift" "$iconset_dir"
mkdir -p "$repo_root/Resources"
iconutil -c icns "$iconset_dir" -o "$repo_root/Resources/AppIcon.icns"
echo "$repo_root/Resources/AppIcon.icns"
