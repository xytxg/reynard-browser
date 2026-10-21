# Building and installing this Reynard fork

## Requirements

A macOS host with **Xcode 26.6** (matching the reviewed upstream workflow), Python 3, Rust/Cargo with `aarch64-apple-ios` target, Homebrew, LLVM/LLD, `cbindgen`, and `ldid`. You also need adequate free disk space, a working internet connection to download Firefox/Gecko sources, and substantial build time. Xcode is required for the iOS app; Linux cannot compile the full IPA.

```bash
xcodebuild -version
python3 --version
rustc --version
rustup target add aarch64-apple-ios
brew install python@3.12 llvm lld cbindgen ldid
```

These commands describe prerequisites; they do not guarantee that tool versions or build environment are compatible without testing.

## Local source build

```bash
git clone --recursive https://github.com/xytxg/reynard-browser.git
cd reynard-browser
git submodule sync --recursive
git submodule update --init --recursive support/idevice
git submodule update --init --depth 1 engine/firefox
./tools/development/update-gecko.sh
./tools/development/apply-patches.sh
./tools/development/build-gecko.sh --auto-clobber
./tools/development/build-idevice.sh
./tools/release/build-app.sh --no-signing
./tools/release/create-ipa.sh
./tools/release/create-ipa.sh --trollstore
```

The standard IPA is `dist/Reynard.ipa`; the TrollStore build is `dist/Reynard-TrollStore.tipa`. The build can consume hours and may fail when Apple's or Mozilla's toolchains change. Preserve the complete Xcode/Gecko logs for troubleshooting.

## GitHub Actions build

Use [Reynard Fork CI](https://github.com/xytxg/reynard-browser/actions/workflows/fork-ci.yml) on an updated branch. The workflow first checks the Simplified Chinese catalogs, then calls the fork-enabled reusable workflow to compile Gecko and the iOS app on a macOS runner. A failure or a skipped build means **no verified IPA** was produced.

- CI produces a standard IPA and TrollStore TIPA as artifacts when successful.
- Fork CI does **not** currently produce a jailbroken IPA.
- Preview publication requires a successful build and is marked as **prerelease**.
- Do not assume success based on the presence of a workflow file or a passing localization-only job.

## Installation and safety

Unsigned/ad-hoc binaries are not App Store packages. You need a supported signing/sideloading mechanism. Preserve app extensions (especially when using AltStore/SideStore) and verify that TrollStore is actually compatible before installing a `.tipa`. Do not attempt to install a jailbroken build on a non-jailbroken device. Reinstalling experimental browsers may affect saved application data; back up important items.

Any preview release is experimental and may have unresolved crashes or regressions. Its tag and GitHub Actions run should identify the exact source commit; testing on real devices is a separate requirement.
