#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

app_name="Sweep"
build_universal=false
install_app=false
open_app=false

for argument in "$@"; do
    case "$argument" in
        --universal) build_universal=true ;;
        --install) install_app=true ;;
        --open) open_app=true ;;
        -h|--help)
            echo "Usage: scripts/build-app.sh [--universal] [--install] [--open]"
            exit 0
            ;;
        *)
            echo "Unknown option: $argument" >&2
            exit 2
            ;;
    esac
done

swift_build_arguments=(-c release --product "$app_name")
if [[ "$build_universal" == true ]]; then
    swift_build_arguments+=(--arch arm64 --arch x86_64)
fi

echo "==> Building $app_name (release)"
swift build "${swift_build_arguments[@]}"
binary_dir="$(swift build "${swift_build_arguments[@]}" --show-bin-path)"

if [[ ! -f Resources/AppIcon.icns ]]; then
    echo "==> Generating app icon"
    "$script_dir/make-icon.sh"
fi

app_bundle="$repo_root/build/$app_name.app"
contents_dir="$app_bundle/Contents"

echo "==> Assembling $app_bundle"
rm -rf "$app_bundle"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$binary_dir/$app_name" "$contents_dir/MacOS/$app_name"
cp Resources/Info.plist "$contents_dir/Info.plist"
cp Resources/AppIcon.icns "$contents_dir/Resources/AppIcon.icns"
printf 'APPL????' > "$contents_dir/PkgInfo"

shopt -s nullglob
for resource_bundle in "$binary_dir"/*.bundle; do
    ditto "$resource_bundle" "$contents_dir/Resources/$(basename "$resource_bundle")"
done
shopt -u nullglob

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - --options runtime --timestamp=none "$app_bundle"

echo "$app_bundle"

if [[ "$install_app" == true ]]; then
    installed_app="$HOME/Applications/$app_name.app"
    mkdir -p "$HOME/Applications"
    rm -rf "$installed_app"
    ditto "$app_bundle" "$installed_app"
    echo "Installed to $installed_app"
    app_bundle="$installed_app"
fi

if [[ "$open_app" == true ]]; then
    open "$app_bundle"
fi
