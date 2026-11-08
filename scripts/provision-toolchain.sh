#!/usr/bin/env bash
# =============================================================================
# mobilebasic - Android toolchain bootstrap (self-provisioning)
#
# WHY THIS EXISTS
#   The cloud sandbox is EPHEMERAL and PER-TOPIC. A fresh topic starts with
#   no JDK, no Android SDK, no adb. Any hand-installed toolchain evaporates.
#   So the toolchain is not "installed once" - it is RECONSTRUCTED on demand
#   from this repo, which is the durable source of truth.
#
#   This script is idempotent and safe to re-run. It is the bootstrap that
#   every mobile task (and the mobile-debug MCP wrapper) runs first.
#
# USAGE
#   bash scripts/provision-toolchain.sh            # provision (idempotent)
#   bash scripts/provision-toolchain.sh --check    # verify only, change nothing
#   source scripts/provision-toolchain.sh --env    # print exports only
#
# HOST NOTES (verified on Debian 12 / aarch64)
#   * Google's Android platform-tools and build-tools are x86_64-only.
#     The Debian `adb` package IS native arm64, so it is preferred for the
#     adb server; the SDK's x86_64 adb is kept as a fallback via qemu.
#   * build-tools (aapt, aapt2, zipalign, dexdump) are x86_64 ELF binaries ->
#     executed under qemu-user-static with the amd64 multiarch sysroot.
#     d8 / apksigner are JVM shell scripts and need no qemu.
#   * The `emulator` SDK package is NOT published for aarch64 hosts
#     (sdkmanager: "Dependant package with key emulator not found"), so there
#     is NO local emulator. On-device execution requires a physical device
#     over adb, or a remote device farm.
# =============================================================================
set -uo pipefail

ANDROID_SDK="${ANDROID_SDK:-/opt/android-sdk}"
BUILD_TOOLS_VERSION="${BUILD_TOOLS_VERSION:-34.0.0}"
PLATFORM_VERSION="${PLATFORM_VERSION:-android-34}"
GRADLE_VERSION="${GRADLE_VERSION:-8.7}"
GWS_VERSION="${GWS_VERSION:-0.22.5}"
SHIM_DIR="${SHIM_DIR:-/opt/mobile-shims}"
ENVFILE="${ENVFILE:-/tmp/mobilebasic.env}"
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
GRADLE_URL="https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip"

MODE="provision"
for arg in "$@"; do
  case "$arg" in
    --check) MODE="check" ;;
    --env)   MODE="env" ;;
  esac
done

log()  { [ "$MODE" = "env" ] || printf '\033[36m[provision]\033[0m %s\n' "$*"; }
ok()   { [ "$MODE" = "env" ] || printf '\033[32m  ✓\033[0m %s\n' "$*"; }
warn() { [ "$MODE" = "env" ] || printf '\033[33m  !\033[0m %s\n' "$*"; }
die()  { printf '\033[31m  ✗\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Environment emitted for every consumer.
# ---------------------------------------------------------------------------
emit_env() {
  cat <<EOF
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-arm64}"
export ANDROID_HOME="$ANDROID_SDK"
export ANDROID_SDK_ROOT="$ANDROID_SDK"
export ANDROID_HOME="$ANDROID_SDK"
export GRADLE_HOME="/opt/gradle-${GRADLE_VERSION}"
export GRADLE_JAVA_HOME="$JAVA_HOME"
export GRADLE_USER_HOME="/root/.gradle"
export PATH="/opt/gradle-${GRADLE_VERSION}/bin:$ANDROID_SDK/platform-tools:$ANDROID_SDK/build-tools/$BUILD_TOOLS_VERSION:$SHIM_DIR:/usr/local/bin:/usr/bin:/bin:/opt/venv/bin"
export ADB_PATH=/usr/bin/adb
export GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND=file
EOF
}

# ---------------------------------------------------------------------------
# 0. Preflight
# ---------------------------------------------------------------------------
ARCH="$(uname -m)"
export JAVA_HOME="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v java 2>/dev/null || echo /usr/bin/java)")")")}"
export ANDROID_HOME="$ANDROID_SDK"

if [ "$MODE" = "check" ]; then
  log "Preflight"
  java -version >/dev/null 2>&1 && ok "java present" || warn "java MISSING"
  [ -x /usr/bin/adb ] && ok "native adb present" || warn "native adb MISSING"
  [ -x /usr/bin/qemu-x86_64-static ] && ok "qemu present" || warn "qemu MISSING"
  [ -d "$ANDROID_SDK/platforms/$PLATFORM_VERSION" ] && ok "platform $PLATFORM_VERSION" || warn "platform MISSING"
  [ -d "$ANDROID_SDK/build-tools/$BUILD_TOOLS_VERSION" ] && ok "build-tools $BUILD_TOOLS_VERSION" || warn "build-tools MISSING"
  [ -x "$SHIM_DIR/aapt2" ] && ok "shims present" || warn "shims MISSING"
  [ -d "/opt/gradle-${GRADLE_VERSION}" ] && ok "gradle $GRADLE_VERSION" || warn "gradle MISSING"
  command -v gws >/dev/null 2>&1 && ok "gws present" || warn "gws MISSING"
  emit_env
  exit 0
fi

[ "$(id -u)" = "0" ] || die "run as root (needs apt + /opt writes)"
export DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# 1. System packages: JDK 17, native arm64 adb, qemu, amd64 multiarch
# ---------------------------------------------------------------------------
log "System packages (JDK 17, arm64 adb, qemu-user-static, amd64 multiarch)"
dpkg --add-architecture amd64 2>/dev/null || true
apt-get update -qq >/dev/null 2>&1 || true
apt-get install -y -qq \
  openjdk-17-jdk-headless adb qemu-user-static binfmt-support \
  libc6:amd64 unzip zip curl ca-certificates \
  >/tmp/mobilebasic-apt.log 2>&1 || {
    warn "apt install failed - see /tmp/mobilebasic-apt.log"
    tail -15 /tmp/mobilebasic-apt.log >&2
  }
ok "system packages handled"

# ---------------------------------------------------------------------------
# 2. Android SDK
# ---------------------------------------------------------------------------
log "Android SDK -> $ANDROID_SDK"
SDKMANAGER="$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager"
if [ ! -x "$SDKMANAGER" ]; then
  mkdir -p "$ANDROID_SDK/cmdline-tools"
  log "downloading cmdline-tools"
  curl -sL -o /tmp/cmdline-tools.zip "$CMDLINE_TOOLS_URL" \
    && unzip -q -o /tmp/cmdline-tools.zip -d "$ANDROID_SDK/cmdline-tools" \
    && rm -rf "$ANDROID_SDK/cmdline-tools/latest" \
    && mv "$ANDROID_SDK/cmdline-tools/cmdline-tools" "$ANDROID_SDK/cmdline-tools/latest" \
    && rm -f /tmp/cmdline-tools.zip \
    && ok "cmdline-tools installed" \
    || warn "cmdline-tools download failed"
else
  ok "cmdline-tools already present"
fi

export PATH="$ANDROID_SDK/cmdline-tools/latest/bin:$ANDROID_SDK/platform-tools:$ANDROID_SDK/build-tools/$BUILD_TOOLS_VERSION:$SHIM_DIR:$PATH"
yes 2>/dev/null | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true

# NOTE: `emulator` is intentionally NOT installed - it has no aarch64 build.
if "$SDKMANAGER" --list_installed 2>/dev/null | grep -q "build-tools;$BUILD_TOOLS_VERSION"; then
  ok "build-tools $BUILD_TOOLS_VERSION already installed"
else
  "$SDKMANAGER" "platform-tools" "platforms;$PLATFORM_VERSION" "build-tools;$BUILD_TOOLS_VERSION" \
    2>&1 | tr '\r' '\n' | grep -vE '^\[|Unzipping|Downloading|^$' | tail -3
  ok "SDK packages installed"
fi
warn "emulator unavailable on aarch64 (no Google build) - use a physical device via adb"

# ---------------------------------------------------------------------------
# 3. qemu + JVM shims for build-tools
#    The MCP server resolves build tools from PATH. Without shims it either
#    fails on exec format error or silently uses the wrong binaries.
# ---------------------------------------------------------------------------
log "build-tools shims -> $SHIM_DIR"
mkdir -p "$SHIM_DIR"
BT="$ANDROID_SDK/build-tools/$BUILD_TOOLS_VERSION"
for t in aapt aapt2 zipalign dexdump; do
  [ -f "$BT/$t" ] || continue
  cat > "$SHIM_DIR/$t" <<SHIM
#!/bin/sh
# Google build-tools are x86_64; this host is aarch64.
exec /usr/bin/qemu-x86_64-static -L /usr/x86_64-linux-gnu $BT/$t "\$@"
SHIM
  chmod +x "$SHIM_DIR/$t"
done
# d8 / apksigner are JVM scripts: exec the original so it resolves its own jar.
for t in d8 apksigner; do
  [ -f "$BT/$t" ] || continue
  cat > "$SHIM_DIR/$t" <<SHIM
#!/bin/sh
exec $BT/$t "\$@"
SHIM
  chmod +x "$SHIM_DIR/$t"
done
ok "shims written: $(ls "$SHIM_DIR" | tr '\n' ' ')"

# ---------------------------------------------------------------------------
# 4. Gradle (the MCP reports gradleValid=false without it)
# ---------------------------------------------------------------------------
log "Gradle $GRADLE_VERSION"
if [ ! -x "/opt/gradle-${GRADLE_VERSION}/bin/gradle" ]; then
  curl -sL -o /tmp/gradle.zip "$GRADLE_URL" \
    && unzip -q -o /tmp/gradle.zip -d /opt \
    && rm -f /tmp/gradle.zip \
    && ok "gradle installed" \
    || warn "gradle download failed"
else
  ok "gradle already present"
fi

# ---------------------------------------------------------------------------
# 5. Google Workspace CLI + Cloud SDK (needed for the doc OAuth path)
# ---------------------------------------------------------------------------
log "Google Workspace CLI + Cloud SDK"
if ! command -v gws >/dev/null 2>&1; then
  npm install -g "@googleworkspace/cli@${GWS_VERSION}" >/dev/null 2>&1 \
    && ok "gws $GWS_VERSION installed" || warn "gws install failed"
else
  ok "gws already present"
fi
GCLOUD_BIN=/tmp/google-cloud-sdk/bin/gcloud
if [ ! -x "$GCLOUD_BIN" ] && ! command -v gcloud >/dev/null 2>&1; then
  ( cd /tmp && curl -sL -o gcloud.tar.gz \
      https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz \
      && tar -xzf gcloud.tar.gz ) \
    && ok "gcloud installed at /tmp/google-cloud-sdk" || warn "gcloud install failed"
else
  ok "gcloud already present"
fi

# ---------------------------------------------------------------------------
# 6. Emit environment + verify
# ---------------------------------------------------------------------------
emit_env > "$ENVFILE"
ok "environment written to $ENVFILE"

log "Verification"
java -version 2>&1 | head -1
/usr/bin/adb version 2>&1 | head -1
[ -x "$SHIM_DIR/aapt2" ] && "$SHIM_DIR/aapt2" version 2>&1 | head -1
[ -x "/opt/gradle-${GRADLE_VERSION}/bin/gradle" ] && "/opt/gradle-${GRADLE_VERSION}/bin/gradle" --version 2>&1 | grep -i "^Gradle" | head -1
command -v gws >/dev/null 2>&1 && gws --version 2>&1 | head -1
[ -x "$GCLOUD_BIN" ] && "$GCLOUD_BIN" --version 2>&1 | head -1
echo "--- device state ---"
/usr/bin/adb devices 2>&1 | head -5

if [ "$MODE" = "env" ]; then
  emit_env
else
  cat "$ENVFILE"
  echo
  echo "To use in this shell:  source $ENVFILE"
fi
