#!/bin/zsh
# Build v2s for daily local use, sign it with a stable identity, install it, and launch it.
#
# Why this exists: the Xcode project signs Debug builds ad hoc (CODE_SIGN_IDENTITY = "-").
# macOS identifies an ad-hoc app by its code hash, which changes on every rebuild, so the
# "Screen & System Audio Recording" grant silently stops applying and Core Audio taps return
# pure silence without any error. Signing with an Apple Development certificate gives TCC a
# stable identity (bundle ID + team), so the grant survives rebuilds.
#
# Launching through `open` (not by running the binary from a shell or Xcode) also matters:
# otherwise TCC attributes the capture to the parent process (Terminal/Xcode) instead of v2s.
#
# Usage: scripts/run-local.sh [--config Debug|Release] [--dest ~/Applications]
set -euo pipefail

CONFIG="Release"
DEST="$HOME/Applications"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG="$2"; shift 2 ;;
    --dest) DEST="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 64 ;;
  esac
done

ROOT="${0:A:h:h}"
IDENTITY="${V2S_SIGN_IDENTITY:-Apple Development}"

# The team ID is the certificate's OU, not the code in parentheses in its common name.
TEAM="${V2S_TEAM_ID:-$(security find-certificate -c "$IDENTITY" -p 2>/dev/null \
  | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU=\([A-Z0-9]*\).*/\1/p')}"
if [[ -z "$TEAM" ]]; then
  echo "No '$IDENTITY' certificate found. Sign in to Xcode > Settings > Accounts, or set V2S_SIGN_IDENTITY / V2S_TEAM_ID." >&2
  exit 1
fi

DERIVED="$ROOT/.build/local-xcode"
echo "==> Building v2s ($CONFIG, team $TEAM)"
xcodebuild build \
  -project "$ROOT/v2s.xcodeproj" \
  -scheme v2s \
  -configuration "$CONFIG" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM" \
  COREML_CODEGEN_LANGUAGE=Swift \
  | grep -E "error:|warning: .*signing|\*\* BUILD" || true

APP="$DERIVED/Build/Products/$CONFIG/v2s.app"
codesign --verify --deep --strict "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Authority=Apple Development|TeamIdentifier" || {
  echo "Build is not signed with $IDENTITY" >&2
  exit 1
}

echo "==> Installing to $DEST"
pkill -x v2s 2>/dev/null && sleep 1 || true
mkdir -p "$DEST"
rm -rf "$DEST/v2s.app"
ditto "$APP" "$DEST/v2s.app"

echo "==> Launching"
open "$DEST/v2s.app"
cat <<'EOF'

If subtitles show "No audio — check permission", open
System Settings > Privacy & Security > Screen & System Audio Recording,
enable v2s under "System Audio Recording Only", then quit and reopen v2s.

Note: turn off "Check for Updates Automatically" in v2s Settings for this local build.
Otherwise Sparkle replaces it with the next upstream release, which is signed differently
and does not contain your local changes.
EOF
