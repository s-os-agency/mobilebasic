# mobilebasic

> mobilebasic - mobile app project setup, configuration and orchestration.
> Android/iOS toolchain bootstrap, device runtime, and agent pipeline.

Android scaffold + reproducible toolchain bootstrap for the **mobilebasic** project.

> The previously cited private Google Doc
> (`1hDsK-yPLVLSPiolR7LAaA25MMyxI6-6fb2YdBFx8hjQ`) was accessible on 11 November 2026,
> but its current content does not match this mobile scaffold. Do not treat it as
> the confirmed project specification. Continue scaffold and toolchain work from
> the checked-in source and `docs/RUNBOOK.md`; use a matching specification for
> product-specific requirements.

## Quick start

```bash
bash scripts/provision-toolchain.sh   # idempotent toolchain bootstrap
source /tmp/mobilebasic.env
gradle --no-daemon assembleDebug      # -> app/build/outputs/apk/debug/app-debug.apk
```

## What is here

| Path | Purpose |
|---|---|
| `scripts/provision-toolchain.sh` | Idempotent bootstrap: JDK 17, Android SDK 34, build-tools, qemu shims, Gradle 8.7, `gws`. `--check` for a read-only verify. |
| `scripts/mcp-mobile-debug.sh` | Launches the mobile-debug MCP server *after* provisioning, so the server finds adb/SDK. Used by the LobeHub connector. |
| `app/` | Minimal Android app (AGP 8.5.0, minSdk 24, targetSdk 34, Java 17). No third-party SDKs, no network, no analytics. |
| `docs/RUNBOOK.md` | Build, device and MCP operating instructions. |

## Host constraints (verified, not assumed)

- **aarch64 host.** Google's Android build-tools are x86_64-only. `aapt`,
  `aapt2`, `zipalign`, `dexdump` run under `qemu-user-static` via shims in
  `/opt/mobile-shims`. `d8`/`apksigner` are JVM scripts and need no shim.
- **AGP aapt2 override is mandatory.** `android.aapt2FromMavenOverride` points
  AGP at the emulated binary; otherwise AGP execs its own x86_64 `aapt2` and
  the build fails with `AAPT2 Daemon startup failed`.
- **No local emulator.** Google publishes no `emulator` package for aarch64.
  On-device execution needs a physical device over adb or a remote device farm.
- **The sandbox is ephemeral and per-topic.** Installs do not survive a new
  topic - the toolchain is reconstructed by `provision-toolchain.sh`, never
  installed by hand.
- **`adb` must be on the default PATH.** The MCP server resolves adb from
  `PATH`; `/usr/local/bin` is on it, so the wrapper symlinks the shims there.

## Verified

- `assembleDebug` -> BUILD SUCCESSFUL, valid signed 5.3 MB APK
  (`classes.dex`, `AndroidManifest.xml`, `resources.arsc`, zip integrity OK).
- mobile-debug MCP `get_system_status` -> `adbAvailable: true`,
  `envValid: true`, `android.status: partially_ready` (no device attached).
