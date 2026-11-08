#!/usr/bin/env bash
# =============================================================================
# mobilebasic - mobile-debug MCP launcher (self-provisioning)
#
# WHY THIS EXISTS
#   The LobeHub cloud sandbox is EPHEMERAL and PER-TOPIC. When the
#   mobile-debug MCP server is launched by the platform, it starts in a fresh
#   sandbox with no JDK, no Android SDK and no adb. Probed live, it then
#   reports:
#       status: blocked, adbAvailable: false, "ADB not available"
#       get_debugger_capabilities -> DEBUGGER_UNSUPPORTED / DEVICE_UNAVAILABLE
#
#   That is not a missing device - it is a missing TOOLCHAIN. The fix is to
#   provision the toolchain *before* the MCP server starts, in the same
#   sandbox, and hand it a correct PATH via environment.
#
#   Verified behaviour (same sandbox, after provisioning):
#       adbAvailable: true, resolvedPath: /usr/bin/adb, envValid: true
#       android.status: partially_ready  (only because no device is attached)
#
# USAGE
#   bash scripts/mcp-mobile-debug.sh          # provision, then run the MCP
#   MCP_BOOTSTRAP_ONLY=1 bash ...            # provision only (for CI)
#
# The MCP server itself is stdio JSON-RPC; this wrapper must forward stdin
# and stdout verbatim.
# =============================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROVISION="${REPO_ROOT}/scripts/provision-toolchain.sh"
BOOTSTRAP_LOG="${MCP_BOOTSTRAP_LOG:-/tmp/mobilebasic-mcp-bootstrap.log}"

log() { printf '\033[36m[mcp-bootstrap]\033[0m %s\n' "$*" >>"$BOOTSTRAP_LOG" 2>/dev/null || true; }

# ---------------------------------------------------------------------------
# 1. Locate the provisioning script (repo copy first, then the shared copy).
# ---------------------------------------------------------------------------
PROVISION_SCRIPT=""
for cand in "$PROVISION" "/tmp/mobilebasic/scripts/provision-toolchain.sh"; do
  if [ -f "$cand" ]; then PROVISION_SCRIPT="$cand"; break; fi
done

# ---------------------------------------------------------------------------
# 2. Fast path: if the toolchain is already present, skip the (slow) install.
#    The MCP server is launched on every tool call, so this must be cheap.
# ---------------------------------------------------------------------------
have_toolchain() {
  [ -x /usr/bin/adb ] || return 1
  [ -d "${ANDROID_HOME:-/opt/android-sdk}/platforms/android-34" ] || return 1
  [ -x /opt/mobile-shims/aapt2 ] || return 1
  return 0
}

if have_toolchain; then
  log "toolchain already present - skipping provision"
else
  log "toolchain missing - provisioning (this happens once per sandbox)"
  if [ -n "$PROVISION_SCRIPT" ]; then
    bash "$PROVISION_SCRIPT" >>"$BOOTSTRAP_LOG" 2>&1 || log "provision script exited non-zero"
  else
    log "no provisioning script found - continuing with degraded toolchain"
  fi
fi

# ---------------------------------------------------------------------------
# 3. Export the environment the MCP server needs.
#    NOTE: /usr/local/bin is on the default PATH; the MCP server resolved adb
#    from PATH, so the shims MUST land somewhere on that default PATH. We
#    also symlink the shims into /usr/local/bin for maximum discoverability.
# ---------------------------------------------------------------------------
ENVFILE=/tmp/mobilebasic.env
if [ -f "$ENVFILE" ]; then
  set -a; . "$ENVFILE"; set +a
fi

mkdir -p /usr/local/bin
for t in aapt aapt2 zipalign dexdump d8 apksigner; do
  [ -x "/opt/mobile-shims/$t" ] && ln -sf "/opt/mobile-shims/$t" "/usr/local/bin/$t" 2>/dev/null || true
done
[ -x /usr/bin/adb ] && ln -sf /usr/bin/adb /usr/local/bin/adb 2>/dev/null || true

export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-arm64}"
export ANDROID_HOME="${ANDROID_HOME:-/opt/android-sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export GRADLE_HOME="${GRADLE_HOME:-/opt/gradle-8.7}"
export ADB_PATH=/usr/bin/adb
export PATH="/opt/gradle-8.7/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/34.0.0:/opt/mobile-shims:$PATH"

log "env ready: JAVA_HOME=$JAVA_HOME ANDROID_HOME=$ANDROID_HOME"

if [ "${MCP_BOOTSTRAP_ONLY:-0}" = "1" ]; then
  log "MCP_BOOTSTRAP_ONLY=1 - not starting the server"
  exit 0
fi

# ---------------------------------------------------------------------------
# 4. Run the MCP server, forwarding stdio untouched.
# ---------------------------------------------------------------------------
log "starting mobile-debug-mcp server"
exec npx --yes mobile-debug-mcp server "$@"
