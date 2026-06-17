# MacBook Stress Test

A native macOS app that pushes your Mac's CPU, GPU, memory and disk to their
limits while showing live system load — built with SwiftUI so it looks and
feels like a genuine part of macOS.

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black)
![Swift](https://img.shields.io/badge/Swift-5-orange)

## Features

- **CPU** — multi-core load across all logical cores, with Float / Integer /
  Mixed workloads and an optional auto-stop duration.
- **GPU (Metal)** — a heavy compute kernel saturates the GPU; configurable
  buffer size, live iterations/sec.
- **Memory** — allocates and continuously touches a chosen amount of RAM.
- **Disk I/O** — sequential / random read & write throughput (cache-bypassing).
- **Live system monitor** — overall CPU / memory / swap plus a per-core grid,
  sampled natively via Mach/sysctl, and a timestamped activity log.

## Requirements

- macOS 14 or newer (Apple Silicon).
- Xcode 26+ to build (includes the Metal toolchain component).

## Build & Run

Open the project and run:

```bash
open MacBookStressTest.xcodeproj
# then press Run (⌘R) in Xcode
```

Or build from the command line:

```bash
xcodebuild -scheme MacBookStressTest -configuration Release build
```

The Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen). It is committed so you can
open and run without any extra tooling; regenerate it only if you change the
project layout:

```bash
xcodegen generate
```

## Notes

The app deliberately drives your hardware hard. Keep an eye on temperatures and
use **Stop All** (or quit) to end every running test and release allocated
memory.
