# Design: Native SwiftUI rewrite of MacBook Stress Test

**Date:** 2026-06-17
**Status:** Approved

## Overview

Rewrite the existing Python/Tkinter stress-test tool as a native macOS app in
SwiftUI + AppKit, so it looks and feels like a genuine part of macOS (system
font, SF Symbols, native controls, vibrancy). The app keeps full feature parity
with the current version: CPU, GPU, memory and disk stress tests plus a live
system monitor with a per-core grid and an activity log.

The native version replaces the Python implementation in the same repository.
The Python version remains available in git history.

## Goals

- Native macOS look and feel — indistinguishable from a system app.
- Feature parity with the current tool (no regressions in capability).
- Single self-contained `.app` bundle — no Python, no virtualenv, no runtime deps.
- No third-party Swift packages; pure SwiftUI + Metal + Mach/sysctl.

## Non-Goals

- Menu-bar / popover form factor (a standard window app was chosen).
- Code signing / notarization / App Store distribution (personal/local use).
- iOS or cross-platform support.

## Platform & Targets

- **Language/UI:** Swift 6, SwiftUI (with AppKit interop where needed).
- **Architecture:** Apple Silicon (arm64). Universal (arm64 + x86_64) is a
  trivial build-setting change if ever needed.
- **Deployment target:** macOS 14.0 — runs on macOS 14 through 26.
- **Built with:** macOS 26 SDK (Xcode 26), so the app adopts the current system
  design language automatically.
- **No App Sandbox** — the tool needs unrestricted disk I/O and host statistics.

## Architecture

Cleanly separated, independently testable units.

### Stress engines

A common protocol and four independent engines, each owning its own threads and
a cooperative stop flag, publishing live metrics:

```
protocol StressEngine: Observable {
    var isRunning: Bool { get }
    func start(config: …)
    func stop()
}
```

- **CPUStressEngine** — spawns N worker threads (`Thread`, QoS `.userInitiated`).
  Workload modes: Float / Integer / Mixed. Optional auto-stop duration
  (30 s / 1 min / 5 min / 30 min / unlimited).
- **GPUStressEngine** — Metal compute. Reuses the existing stress kernel (ported
  from the project's current embedded Swift/Metal source) and runs it in a loop
  directly in-process (no subprocess). Reports iterations/sec. Configurable
  buffer size (64–1024 MB).
- **MemoryStressEngine** — allocates the requested amount of RAM in chunks and
  continuously touches pages to keep them resident. Reports allocated MB.
- **DiskStressEngine** — sequential/random read and write to a temp file using
  `F_NOCACHE` + `fsync`. Reports MB/s. Configurable size and mode.

### System monitor

`SystemMonitor` replaces `psutil` with native APIs, sampled ~1 Hz:

- **Per-core + overall CPU %** via `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`,
  computed from tick deltas between samples.
- **Memory** via `host_statistics64(HOST_VM_INFO64)` + `sysctl hw.memsize`.
- **Swap** via `sysctl vm.swapusage`.

### System info

`SystemInfo` reads `sysctl` (CPU brand, `hw.perflevelN.logicalcpu` for P/E core
counts, `hw.model`, `hw.memsize`) and `ProcessInfo` (OS version).

### UI layer

SwiftUI views driven by `@Observable` view models bound to the engines:

- Header: title + system info (CPU / cores / RAM / macOS) as chips.
- One card per resource (CPU, GPU, Memory, Disk), each with a tinted rounded
  SF Symbol tile, native controls (`Slider`, segmented `Picker`, `Toggle`),
  Start/Stop, and live readouts.
- System monitor card: overall CPU/Memory/Swap gauges + per-core utilisation grid.
- Activity log as a native `List`.
- Bottom bar: Run All / Stop All.

## Visual Design

- Window background uses a vibrancy material (`NSVisualEffectView` bridged into
  SwiftUI).
- Section identity via SF Symbols in tinted rounded-square tiles
  (`cpu`, `cpu.fill`, `memorychip`, `internaldrive`, `gauge.with.dots.needle`),
  lighting up in their accent colour while the corresponding test runs.
- Native `Slider` / segmented `Picker` / `Gauge` / `ProgressView` throughout.
- System font (SF Pro) and standard control metrics — no custom-drawn widgets.

## Project & Build

- A lean, hand-maintained **Xcode project** (`.xcodeproj`) using a file-system
  synchronized group, so contributors just open it and Run — no code generator
  or package manager step required. (Fallback: XcodeGen `project.yml` if the
  hand-maintained project proves fragile.)
- Build/verify headlessly with `xcodebuild` to confirm a clean compile.
- Source layout under the repo root:
  - `MacBookStressTest.xcodeproj`
  - `MacBookStressTest/` — `App`, `Engines`, `Monitor`, `System`, `Views`,
    `Resources` (incl. the Metal shader), `Info.plist`, entitlements.

## Repository Migration

- Remove `stress_test.py`, `setup.sh`, `requirements.txt` (kept in history).
- Add the Xcode project and Swift sources.
- Replace `.gitignore` with Swift/Xcode rules (DerivedData, `*.xcuserstate`, etc.).
- Update `README.md` for the native app (requirements: macOS 14+, Xcode to build).

## Testing & Verification

- `xcodebuild` clean-compile check on every milestone.
- Manual launch to confirm the UI renders and controls behave.
- Engines are hardware-stressing and time-dependent; verification is primarily
  "runs, reports plausible live metrics, starts/stops cleanly", not unit assertions
  on throughput.

## Risks & Mitigations

- **Mach API porting (monitor):** most non-trivial part. Mitigation: implement and
  validate the monitor first against known values (Activity Monitor) before wiring
  the rest.
- **Hand-written `.xcodeproj`:** mitigation: verify with `xcodebuild`; fall back to
  XcodeGen if needed.
- **Metal differences across GPUs:** kernel is generic compute; validated on the
  development machine's Apple Silicon GPU.
