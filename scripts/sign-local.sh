#!/bin/sh
# Re-signs a built Shuttle.app with the local signing identity when it exists.
# Ad-hoc signatures change on every build, so macOS asks again for Shuttle's
# Automation permission; a fixed identity keeps it. Without the identity (as in CI)
# the ad-hoc signature from Xcode is kept.
set -eu

APP="$1"
NAME="${SHUTTLE_CODE_SIGN_IDENTITY:-Shuttle Local Signing}"

if ! security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "No \"$NAME\" certificate, keeping the ad-hoc signature (see scripts/create-signing-identity.sh)."
  exit 0
fi

# Keep the entitlements Xcode signed the app with.
ENTITLEMENTS="$(mktemp)"
trap 'rm -f "$ENTITLEMENTS"' EXIT
codesign -d --entitlements - --xml "$APP" > "$ENTITLEMENTS" 2>/dev/null

if [ -s "$ENTITLEMENTS" ]; then
  codesign --force --sign "$NAME" --entitlements "$ENTITLEMENTS" --timestamp=none "$APP"
else
  codesign --force --sign "$NAME" --timestamp=none "$APP"
fi
codesign --verify --strict "$APP"
echo "Signed $APP with \"$NAME\"."
