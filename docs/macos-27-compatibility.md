# macOS 27 / Xcode 27 compatibility

Static review on 2026-10-07 against `c6d5b60`; validated on a Mac on 2026-10-12
against `045b486` plus the fixes in this change.

## Result

Redline builds without errors or warnings with Xcode 27 and runs correctly on
macOS 27. Both published releases (v1.0.0 and v1.1.0, built with the macOS 26.5
SDK) also launch on macOS 27. No macOS 27 migration was required.

Still open: running an Xcode 27 build on macOS 14 (back-deployment), and a manual
click-through of the UI (Run All, pickers and sliders, Stop All). The engines and
the monitor were exercised directly, without the UI.

## Environment

| | |
| --- | --- |
| Mac | Apple M5 Max (Metal 4), 18 cores, 64 GB RAM |
| macOS | 27.0 (26A428) |
| Xcode | 27.0 (27A266a), macOS SDK 27.0 |
| Metal Toolchain | 27.1, `metal` 32023.921 |
| XcodeGen | 2.46.0 |

## Build

- `xcodegen generate` reproduces the committed project without changes.
- Debug and Release builds (`-destination 'platform=macOS,arch=arm64'`,
  `CODE_SIGNING_ALLOWED=NO`) succeed with no errors or warnings in Swift 6
  language mode.
- The app contains `default.metallib`, is arm64 only, and targets macOS 14.0
  with SDK 27.0 (`LC_BUILD_VERSION`).
- CI builds the same sources with Xcode 26.6.

## Runtime checks on macOS 27

| Area | Check | Result |
| --- | --- | --- |
| GPU | Every buffer size (64–1024 MB) with `MTL_DEBUG_LAYER=1` and `MTL_SHADER_VALIDATION=1` | No validation messages; all command buffers complete. Element counts are multiples of 256 for every size, so the unguarded kernel never reads past the buffer. |
| CPU monitor | Idle and with all 18 cores loaded | All 18 cores reported; 99 % overall, ≥ 98 % per core under load. |
| Memory monitor | Compared with `vm_stat` (active + wired + compressor) | 37.4 GB vs 37.9 GB, sampled moments apart. |
| Swap | Compared with `sysctl vm.swapusage` | 16.51 GB vs 16 908.56 MB. Matches. |
| Disk | All four modes, 256 MB | Finite throughput, no errors logged. |
| Disk cleanup | `kill -9` during a 1 GB write | The file has no name in the temp directory while it is open, and nothing is left after the kill. |
| Stop / restart | Rapid stop → start on every engine | No stray workers or stale UI updates; no Swift 6 runtime isolation traps. |
| Releases | v1.0.0 and v1.1.0 launched for 8 s | Both open their window and stay running. |

## Findings from the static review, resolved

The static review flagged unchecked results and silent failures. These are now
handled:

- Disk: per-run temp file created with `mkstemp` and unlinked right away; write,
  read, `F_NOCACHE` and `F_FULLFSYNC` failures are logged and reset the card;
  free space is checked before starting. Write timing uses `F_FULLFSYNC`, because
  `fsync` does not flush the drive's write cache.
- GPU: a failed command buffer or encoder stops the run with a log entry instead
  of looping silently.
- Concurrency: Swift 6 strict checking; each run has its own `Sendable` stop flag.

## Reproducing

```bash
sw_vers && xcodebuild -version && xcrun --sdk macosx --show-sdk-version
xcrun --find metal && xcodegen --version
xcodegen generate && git diff --exit-code -- Redline.xcodeproj
xcodebuild -project Redline.xcodeproj -scheme Redline \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath DerivedData/macos27-release CODE_SIGNING_ALLOWED=NO build
```

For the GPU check, launch the built app with `MTL_DEBUG_LAYER=1` and
`MTL_SHADER_VALIDATION=1` set, run the GPU card at each buffer size, and watch the
console for validation messages.

## Apple references

- [Xcode SDK and system requirements](https://developer.apple.com/xcode/system-requirements/)
- [Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes)
- [macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)
- [Installing additional Xcode components](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)
- [Metal libraries](https://developer.apple.com/documentation/metal/metal-libraries)
- [Compute pipeline threadgroup limit](https://developer.apple.com/documentation/metal/mtlcomputepipelinestate/maxtotalthreadsperthreadgroup)
- [host_processor_info](https://developer.apple.com/documentation/kernel/1502854-host_processor_info)
- [host_statistics64](https://developer.apple.com/documentation/kernel/1502863-host_statistics64)
- [fcntl manual (archived)](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/fcntl.2.html)
