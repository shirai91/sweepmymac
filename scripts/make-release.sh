#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

version="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
zip_path="build/Sweep-$version.zip"
dmg_path="build/Sweep-$version.dmg"
signature_path="$zip_path.sig"
public_key="$(plutil -extract SweepUpdatePublicKey raw Resources/Info.plist)"
signing_tool="$script_dir/update-signing.swift"

echo "==> Checking the update signing key"
if [[ "$(swift "$signing_tool" public-key)" != "$public_key" ]]; then
    echo "The Keychain signing key does not match SweepUpdatePublicKey in Resources/Info.plist." >&2
    exit 1
fi

"$script_dir/build-app.sh" --universal
"$script_dir/make-dmg.sh"
mv -f build/Sweep.dmg "$dmg_path"
rm -f "$zip_path"
ditto -c -k --keepParent build/Sweep.app "$zip_path"

echo "==> Signing $zip_path"
rm -f "$signature_path"
swift "$signing_tool" sign "$zip_path"
swift "$signing_tool" verify "$zip_path" "$public_key"

echo "==> Release files for v$version"
echo "$repo_root/$zip_path"
echo "$repo_root/$signature_path"
echo "$repo_root/$dmg_path"
echo
echo "Publish with:"
echo "  gh release create v$version $zip_path $signature_path $dmg_path --title \"Sweep $version\" --notes-file <notes.md>"
