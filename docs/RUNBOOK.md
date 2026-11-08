# mobilebasic - Runbook

## 1. Bootstrap the toolchain (REQUIRED FIRST)

The cloud sandbox is ephemeral and per-topic. Nothing survives a new topic.
Always run:

```bash
bash scripts/provision-toolchain.sh      # idempotent
source /tmp/mobilebasic.env              # exports JAVA_HOME / ANDROID_HOME / PATH
```

`--check` verifies without changing anything.

## 2. Build

```bash
source /tmp/mobilebasic.env
cd <repo>
gradle --no-daemon assembleDebug
# -> app/build/outputs/apk/debug/app-debug.apk
```

Verified working on Debian 12 / aarch64. Two host-specific settings make it work:

| Setting | Why |
|---|---|
| `android.aapt2FromMavenOverride=/opt/mobile-shims/aapt2` | AGP otherwise downloads and execs its own x86_64 `aapt2`; this host is aarch64, so it must be run under qemu-user-static. Without this the build dies with `AAPT2 Daemon startup failed`. |
| qemu shims for `aapt`/`aapt2`/`zipalign`/`dexdump` | These build-tools are x86_64 ELF binaries. `d8`/`apksigner` are JVM scripts and need no shim. |

## 3. Run on a device

There is **no local emulator** - Google does not publish an `emulator` package
for aarch64 hosts (`sdkmanager: "Dependant package with key emulator not found"`).
Use a physical device or a remote device farm:

```bash
adb connect <host:port>       # remote device farm
adb devices
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

## 4. mobile-debug MCP

Launch through the bootstrap wrapper so the toolchain exists before the server starts:

```bash
bash scripts/mcp-mobile-debug.sh
```

`scripts/mcp-mobile-debug.sh` is what the LobeHub connector runs. It provisions
if needed, exports the env, then execs `npx --yes mobile-debug-mcp server`.

Verified end state of `get_system_status`:
`adbAvailable: true`, `envValid: true`, `android.status: partially_ready`
(ready except no device attached).

## 5. Reading the source spec

The `mobilebasic` Google Doc is private. Once Google access is granted, read it
with either:

```bash
gws docs documents get --params '{"documentId":"1hDsK-yPLVLSPiolR7LAaA25MMyxI6-6fb2YdBFx8hjQ"}'
```

or the `google-docs` MCP connector (`docs_get_text`).

House pattern for Google access (see `s_agency_os/docs/SHARED_SHEET_SOURCE.md`):
a **service account** with Viewer permission on the shared drive, then
`GOOGLE_APPLICATION_CREDENTIALS` pointing at the service account JSON.
