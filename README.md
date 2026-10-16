# Sweep

Sweep is a fast disk junk cleaner for macOS 15 and later. It scans your disk, finds caches, logs, leftovers and other junk, and lets you remove them safely.

## Build and run

Needs Xcode 16 or later (Swift 6 toolchain).

```sh
make app       # build build/Sweep.app (ad-hoc signed)
make run       # build and open the app
make install   # build and copy to ~/Applications/Sweep.app
make dmg       # build build/Sweep.dmg
make test      # run the tests
make icon      # regenerate Resources/AppIcon.icns
```

`scripts/build-app.sh --universal` builds an arm64 + x86_64 app.

## Full Disk Access

To scan everything, Sweep needs Full Disk Access:

System Settings → Privacy & Security → Full Disk Access → add Sweep.

Builds are ad-hoc signed, so macOS sees each rebuild as a new app. Remove and add Sweep again after each rebuild.

## Benchmark CLI

```sh
swift run -c release sweep-cli
```
