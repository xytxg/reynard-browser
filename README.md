# Reynard Browser · Chinese Localization Fork

**A community-maintained Simplified Chinese localization fork of [Reynard Browser](https://github.com/minh-ton/reynard-browser), a Gecko-based web browser for iOS 13+.**

[简体中文](README.zh-CN.md) · [Upstream](https://github.com/minh-ton/reynard-browser) · [Builds & CI](https://github.com/xytxg/reynard-browser/actions) · [Changes & upstream sync](docs/UPSTREAM_SYNC.md)

> [!IMPORTANT]
> This is an **independent community fork**, not an official build or product from the upstream author, Mozilla, Apple, or OpenAI. The browser is experimental. Upstream's original code and development are credited to [Minh Ton](https://github.com/minh-ton). No security audit or successful release is implied by this README.

## What this fork does

- Maintains and reviews **Simplified Chinese (zh-Hans)** strings for the browser UI and privacy/settings views.
- Tracks upstream Gecko/iOS browser improvements rather than replacing the native engine with WebKit.
- Adds repository-level localization validation and a separate build-and-test workflow.
- Documents upstream attribution, the source baseline, compatibility limitations, and how to report localization/security issues.

**Current localization baseline:** 471 general UI keys and 41 settings keys have a nonempty Simplified Chinese translation in the synchronized source. These numbers describe catalog coverage, **not** a guarantee that every screen has been tested on hardware.

## Status and versions

The branch `main` is the public project baseline. Upstream updates, new translations and build changes are reviewed in a dedicated work branch before merging to `main`.

The current upstream snapshot is based on commit [`6e84bfca`](https://github.com/minh-ton/reynard-browser/commit/6e84bfca9c16b2204dc64c93d2089b5410039897) (2026-10-21). See [sync notes](docs/UPSTREAM_SYNC.md) for exact parent commits and changes.

**Download warning:** The upstream [Releases](https://github.com/minh-ton/reynard-browser/releases) are published by the original maintainer and **are not Chinese-fork releases**. Check [this fork's releases](https://github.com/xytxg/reynard-browser/releases) for verified fork-specific builds. If that page has no applicable files, there is no downloadable fork IPA to claim. Test artifacts, if any, are in [Actions](https://github.com/xytxg/reynard-browser/actions).

## Installation

Reynard supports several installation methods, subject to actual device/iOS compatibility:

| Method | Package | Notes |
| --- | --- | --- |
| AltStore / SideStore | Standard `.ipa` | Preserve required app extensions; signing/sideloading is needed |
| TrollStore | `.tipa` | Only on TrollStore-compatible OS versions and devices |
| Jailbroken devices | Jailbroken `.ipa` | Requires a compatible jailbreak and signing environment |

The fork's CI initially targets **standard IPA and TrollStore TIPA** only. It does not promise a signed or install-ready app and does not currently generate a jailbroken build. Read [build and installation notes](docs/BUILD.md).

## Build locally

A macOS development environment with a compatible Xcode release, Python, Rust, Gecko build dependencies and `ldid` is required. This is a resource-intensive native Gecko build, not an ordinary small Xcode app.

```sh
git clone --recursive https://github.com/xytxg/reynard-browser.git
cd reynard-browser
./tools/development/update-gecko.sh
./tools/development/apply-patches.sh
./tools/development/build-gecko.sh
./tools/development/build-idevice.sh
./tools/release/build-app.sh --no-signing
./tools/release/create-ipa.sh
```

Refer to [detailed requirements and limitations](docs/BUILD.md) before using these commands. A successful build must be confirmed by its own CI run; do not assume the sequence works on every macOS/Xcode combination.

## Contributing and security

Issues with translations, placeholders, download management, iOS compatibility, and privacy settings are welcome. See [Contributing](CONTRIBUTING.md) and [Security Policy](SECURITY.md). The maintainer plans to use code review, static checks and automated tests to validate changes; those tools are **not a substitute for an independent security audit**.

## Credits and licensing

- **Original browser and Gecko integration:** [minh-ton/reynard-browser](https://github.com/minh-ton/reynard-browser) by Minh Ton and upstream contributors.
- **Localization fork and its additional maintenance:** [xytxg/reynard-browser](https://github.com/xytxg/reynard-browser).
- Firefox / Mozilla components and relevant upstream libraries retain their respective attribution.

The repository keeps the original [GNU GPL v3.0 license](LICENSE). Gecko-derived changes in `patches/` retain the terms described in [LICENSE.firefox](LICENSE.firefox). This fork does not claim ownership of the original project.
