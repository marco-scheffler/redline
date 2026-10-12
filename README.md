<div align="center">

<img src="docs/icon.png" width="128" height="128" alt="Redline" />

# Redline

**Push your Mac to the redline.**

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform: macOS 14+](https://img.shields.io/badge/Platform-macOS%2014%2B-blue.svg)](#requirements)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-required-black.svg)](#requirements)
[![Latest Release](https://img.shields.io/github/v/release/marco-scheffler/redline)](https://github.com/marco-scheffler/redline/releases/latest)

A native macOS app that drives your CPU, GPU, memory and disk to their limits —
with a live system monitor — all in one window that looks like part of macOS.

</div>

---

## Why?

Sometimes you need to *know* how your Mac behaves under load — checking thermals,
validating a fresh machine, burning in new hardware, or just seeing how far it goes.
Most stress tools are either command-line gymnastics or cross-platform apps that
feel foreign on a Mac.

Redline is the alternative: **one native SwiftUI window** that saturates every
subsystem on demand and shows you exactly what's happening, in real time.

## Highlights

- 🧮 **CPU** — multi-core load across every logical core, with Float / Integer /
  Mixed workloads and an optional auto-stop timer
- 🎮 **GPU (Metal)** — a heavy compute kernel saturates the GPU; configurable
  buffer size, live iterations/sec
- 🧠 **Memory** — allocates and continuously touches a chosen amount of RAM
- 💽 **Disk I/O** — sequential / random read & write throughput (cache-bypassing)
- 📊 **Live system monitor** — overall CPU / memory / swap plus a per-core grid,
  sampled natively via Mach/sysctl, with a timestamped activity log
- 🎨 **Looks like a Mac app should** — SF Symbols, vibrancy, native controls, and a
  single Start/Stop toggle per test

## Install

### Option A — Download (recommended)

1. Grab the latest **Redline-x.y.z.zip** from
   [Releases](https://github.com/marco-scheffler/redline/releases/latest).
2. Unzip and drag `Redline.app` into `/Applications`, then open it.

Releases from 1.2.0 on are signed with a Developer ID and notarized by Apple. Older
releases are unsigned: on first launch right-click the app → **Open**, then confirm
once to let Gatekeeper through.

### Option B — Build from source

```bash
git clone https://github.com/marco-scheffler/redline.git
cd redline
open Redline.xcodeproj    # then press Run (⌘R)
```

The Xcode project is committed, so it opens and runs without any extra tooling.
It is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen); regenerate it only if you change
the project layout (`xcodegen generate`).

## How to use

1. Pick the resource you want to hammer (CPU, GPU, Memory, Disk) and tune its options.
2. Press **Start** on that card — the icon lights up and the live monitor reacts.
3. Press it again to **Stop**, or use **Run All Tests** / **Stop All** at the bottom.

Watch the per-core grid and the CPU / memory / swap gauges to see the impact as it happens.

## Requirements

- macOS 14 (Sonoma) or later (deployment minimum)
- Apple Silicon
- Xcode 26+ to build from source, with the Metal Toolchain component installed
  (download it separately in Xcode → Settings → Components if needed)

**macOS 27 / Xcode 27:** builds cleanly with Xcode 27 and runs on macOS 27, including
the v1.0.0 and v1.1.0 releases. Running an Xcode 27 build on macOS 14 is not yet
verified. See the [compatibility review](docs/macos-27-compatibility.md) for details.

## Development

Run the tests with ⌘U in Xcode, or from the command line:

```bash
xcodebuild test -project Redline.xcodeproj -scheme Redline \
  -destination 'platform=macOS,arch=arm64'
```

This runs two suites:

- **RedlineTests** exercises the stress engines and the monitor on the real hardware
  (about 15 seconds).
- **RedlineUITests** clicks through the window and takes over the mouse and keyboard
  for about a minute. To skip it, add `-only-testing:RedlineTests`.

CI builds and runs both suites on every push to `main` and on every pull request.

To publish a release, push a version tag:

```bash
git tag -a v1.2.0 -m "Redline 1.2.0"
git push origin v1.2.0
```

The release workflow runs the tests, builds the app with the version taken from the
tag, signs it with the Developer ID certificate, notarizes it with Apple and publishes
`Redline-1.2.0.zip` as a GitHub release. Running the workflow manually (Actions →
Release → Run workflow) does the same without publishing, and attaches the zip to the
run instead.

Signing needs these repository secrets:

| Secret | Content |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Developer ID Application certificate with private key, as base64-encoded `.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | Password of that `.p12` |
| `NOTARY_KEY_P8_BASE64` | App Store Connect API key (`AuthKey_….p8`), base64-encoded |
| `NOTARY_KEY_ID` | Key ID of that API key |
| `NOTARY_ISSUER_ID` | Issuer ID shown above the API key list in App Store Connect |

## Notes

Redline deliberately drives your hardware hard, which raises temperatures and fan
speed. Keep an eye on thermals and use **Stop All** (or quit) to end every running
test and release allocated memory.

## License

[MIT](LICENSE) © 2026 marco-scheffler

---

<div align="center">

Built with SwiftUI, Metal and Mach — no third-party dependencies.

</div>
