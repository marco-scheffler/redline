# macOS 27 / Xcode 27 compatibility review

Reviewed on 2026-10-07 against `main` at
`c6d5b6098879d9422e3c6ec9978e22cb3b97f46d`.

## Result and evidence limits

No specific macOS 27 migration requirement was identified in the reviewed source
and Apple documentation. This is a static assessment, not a successful SDK build
or runtime qualification. The available environment is Linux x86_64, without
`xcodebuild`, `xcrun`, `xcodegen` or Swift. Project regeneration, compilation,
linking, Metal shader compilation and execution were not performed.

The latest published release remains v1.0.0 (2026-06-18). Its binary was not
executed or inspected for SDK metadata; this review does not qualify that binary
on macOS 27 or establish that it was built with Xcode 27.

## Static findings

| Area | Calls / configuration checked | Assessment |
| --- | --- | --- |
| Build configuration | `project.yml` and committed `project.pbxproj`: macOS 14.0, Swift 5.0, `SDKROOT = macosx`; no external packages | No SDK-26 pin. Apple's Xcode 27 matrix supports macOS 12–27 deployment and Swift 5 language mode. Keep the macOS 14 minimum and Swift 5 mode; raising either is unnecessary for this review. |
| Metal | `MTLCreateSystemDefaultDevice`, command queue, `makeDefaultLibrary`, `stress` compute pipeline, shared buffer, encoder dispatch and completion wait | Established Metal compute path; no Metal 4 migration identified. `Shaders.metal` is in the committed Sources build phase. A matching Metal Toolchain component must be installed; default library generation/loading remains unverified. |
| Dispatch / shader | `min(pipeline.maxTotalThreadsPerThreadgroup, 256)`, rounded-up group count, buffer-indexed floating-point kernel | The group size respects the reported pipeline limit. The kernel has no bounds guard: validation must confirm that the chosen group size divides the element count for each selectable buffer size on the tested GPU. Apple's macOS 27 texture-sampler fixes do not concern this buffer-only kernel. |
| CPU monitoring | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`, tick deltas, `vm_deallocate` | Return code is checked, counters use wrapping subtraction, and the returned array is deallocated using its reported count. No replacement API identified; returned array layout/count and sampling behavior need runtime validation. |
| Memory monitoring | `host_statistics64(HOST_VM_INFO64)`, `vm_statistics64_data_t`, `vm_kernel_page_size` | The request count derives from the imported structure size, not a fixed byte count; failure is checked. Active + wired + compressed memory is an estimate, not necessarily Activity Monitor's exact accounting. Validate values on macOS 27. |
| System info / swap | `sysctlbyname`: `machdep.cpu.brand_string`, `hw.logicalcpu`, `hw.physicalcpu`, `hw.perflevel0.logicalcpu`, `hw.perflevel1.logicalcpu`, `hw.memsize`, `hw.model`, `vm.swapusage` | Calls check failure; static info has fallbacks or optional values. Availability and the meaning of performance-level keys remain machine-dependent. No network-routing sysctls are used. Failed monitor reads leave the previous value unchanged, so a zero or unchanged gauge alone does not prove success. |
| Disk I/O | Temporary file; `open`, `fcntl(F_NOCACHE)`, `write`, `read`, `lseek`, `fsync`, `close`, `unlink` | Documented Darwin/POSIX path; no macOS 27-specific replacement identified. `F_NOCACHE` requests filesystem cache bypass, not hardware-cache flushing. Existing unchecked `fcntl`, seek and sync results prevent static certification of cache bypass or successful I/O. Verify syscall results and cleanup on macOS 27. |

The disk error-handling limitations and shader dispatch assumption are present
in the reviewed baseline; no evidence establishes a new macOS 27 regression.
This patch changes documentation only. It does not add speculative API swaps,
entitlements, build-setting changes or an unrelated engine rewrite.

## Pending validation on an Apple Silicon Mac

Use macOS 27 and the selected Xcode 27 installation. Install XcodeGen and the
Metal Toolchain component for that Xcode first. Record the exact OS, Xcode,
SDK, XcodeGen and GPU versions with the results.

```bash
sw_vers
xcodebuild -version
xcrun --sdk macosx --show-sdk-version
xcrun --find metal
xcodegen --version
xcodegen generate
git diff -- Redline.xcodeproj
xcodebuild -project Redline.xcodeproj -scheme Redline \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath DerivedData/macos27-debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Redline.xcodeproj -scheme Redline \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath DerivedData/macos27-release CODE_SIGNING_ALLOWED=NO build
```

Review any generated-project diff before keeping it; generation alone is not
proof of compatibility. Check the build logs for Swift, Darwin/Mach and Metal
errors or deprecations, and verify that the app contains `default.metallib`.

On macOS 27, run the built app and check:

- GPU start/stop and every selectable buffer size with Metal API and Shader
  Validation enabled; confirm successful command-buffer completion, no
  out-of-bounds accesses and a responding UI.
- CPU, memory and swap sampling at idle and under controlled load; inspect the
  Mach/sysctl results and returned sizes, not only the displayed gauges. Zero
  swap is valid when the OS has not allocated swap.
- All four disk modes at a small file size; inspect `F_NOCACHE`, seek, read/write
  and sync results, confirm finite throughput and temporary-file removal after
  the worker finishes. Check start/stop, Stop All and quitting during load.
- Launch the Xcode-27-built app on macOS 14 as a separate back-deployment check
  before extending the compatibility claim for a future distributed build.

The existing v1.0.0 download needs its own macOS 27 smoke test if the README is
to claim compatibility for that release. Record build and runtime results before
changing the status above. No release is part of this review.

## Apple references

- [Xcode SDK and system requirements](https://developer.apple.com/xcode/system-requirements/)
- [Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes)
- [macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)
- [Installing additional Xcode components](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)
- [Metal libraries](https://developer.apple.com/documentation/metal/metal-libraries)
- [Compute pipeline threadgroup limit](https://developer.apple.com/documentation/metal/mtlcomputepipelinestate/maxtotalthreadsperthreadgroup)
- [host_processor_info](https://developer.apple.com/documentation/kernel/1502854-host_processor_info)
- [host_statistics64](https://developer.apple.com/documentation/kernel/1502863-host_statistics64)
- [Determining system capabilities with sysctlbyname](https://developer.apple.com/documentation/kernel/1387446-sysctlbyname/determining_system_capabilities)
- [fcntl manual (archived)](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/fcntl.2.html)
- [fsync manual (archived)](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/fsync.2.html)

Archived manuals establish API intent; they do not substitute for checking the
macOS 27 SDK headers and actual syscall results.
