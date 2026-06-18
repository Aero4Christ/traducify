#!/bin/bash
# Create a stable self-signed code-signing identity named "Traducify Self-Signed"
# in the login keychain. build-app.sh signs with it so the macOS Screen & System
# Audio Recording grant survives rebuilds (ad-hoc signing changes the cdhash every
# build, which is what forces the permission re-grant loop). Run once per machine.
set -euo pipefail

NAME="Traducify Self-Signed"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "Identity '$NAME' already present. Nothing to do."
  exit 0
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
EOF

openssl req -x509 -new -newkey rsa:2048 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 -config "$TMP/cert.cnf"
openssl pkcs12 -export -out "$TMP/id.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -passout pass:tmp

# -T /usr/bin/codesign pre-authorizes codesign so signing does not prompt.
security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db -P tmp -T /usr/bin/codesign

echo "Created '$NAME'. Verify: codesign --sign \"$NAME\" some-binary"
