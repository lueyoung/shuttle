#!/bin/sh
# Creates a self-signed code signing certificate in the login keychain. Builds signed
# with it keep the same designated requirement across rebuilds, so macOS keeps
# Shuttle's Automation permission instead of asking again after every reinstall.
# The certificate is not marked as trusted; codesign does not need that.
set -eu

NAME="${SHUTTLE_CODE_SIGN_IDENTITY:-Shuttle Local Signing}"

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "\"$NAME\" already exists in your keychain."
  exit 0
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

cat > "$WORK_DIR/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# The system LibreSSL writes PKCS#12 files that `security import` can read.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -config "$WORK_DIR/cert.cnf" -keyout "$WORK_DIR/key.pem" -out "$WORK_DIR/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -name "$NAME" -passout pass:shuttle \
  -inkey "$WORK_DIR/key.pem" -in "$WORK_DIR/cert.pem" -out "$WORK_DIR/identity.p12"

# -T lets codesign use the key; macOS may still ask once, answer Always Allow.
security import "$WORK_DIR/identity.p12" -P shuttle -T /usr/bin/codesign
echo "Created \"$NAME\" in your login keychain."
