# Sweep

Sweep is a fast disk junk cleaner for macOS 15 and later. It scans your disk, finds caches, logs, leftovers and other junk, and lets you remove them safely.

## Build and run

Needs Xcode 16 or later (Swift 6 toolchain).

```sh
make app       # build build/Sweep.app (ad-hoc signed)
make run       # build and open the app
make install   # build and copy to ~/Applications/Sweep.app
make dmg       # build build/Sweep.dmg
make release   # build build/Sweep-<version>.zip and .dmg (universal)
make test      # run the tests
make icon      # regenerate Resources/AppIcon.icns
```

`scripts/build-app.sh --universal` builds an arm64 + x86_64 app.

## Full Disk Access

To scan everything, Sweep needs Full Disk Access:

System Settings → Privacy & Security → Full Disk Access → add Sweep.

Builds are ad-hoc signed, so macOS sees each rebuild as a new app. Remove and add Sweep again after each rebuild.

## Updates

At startup, Sweep checks the latest release on https://github.com/shirai91/sweepmymac/releases. If the release is newer, Sweep downloads the `.zip` asset and asks to install. Before it installs, Sweep checks the SHA-256 digest, the Ed25519 update signature (`.zip.sig`) against `SweepUpdatePublicKey` in `Info.plist`, and the code signature. Use Sweep → Check for Updates… to check by hand.

To ship a version:

1. Set `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
2. Run `make release`.
3. Publish a GitHub release with tag `v<version>`. Attach the `.zip`, the `.zip.sig` (both needed for updates) and the `.dmg`.

Drafts and pre-releases are not offered as updates. A release without a valid `.zip.sig` is never installed.

### Update signing key

The private key is in the login Keychain (service `com.tungpham.sweep.update-signing`). `make release` uses it. Keep a backup: if you lose the key, installed apps cannot accept new updates.

Do not change `SweepUpdatePublicKey` and do not make a new key. Installed apps trust only the current key, so they reject updates signed with any other key. `generate` refuses to replace a key that is already in the Keychain.

```sh
swift scripts/update-signing.swift export-private-key   # print the key, save it in a password manager
swift scripts/update-signing.swift import-private-key   # restore it on a new Mac (paste the key)
```

## Benchmark CLI

```sh
swift run -c release sweep-cli
```
