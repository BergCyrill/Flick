#!/usr/bin/env bash
# Creates the self-signed "Flick Code Signing" certificate, imports it into the login keychain
# and writes the pieces that go into the password manager and the GitHub secrets. Run it once,
# ever: a second certificate changes Flick's designated requirement, and every user would have
# to grant Accessibility again. See README → Code signing.
set -euo pipefail

name="Flick Code Signing"
out=${1:-"$HOME/flick-signing"}

# Read the whole listing first: a reader that stops at the first match can make `security` fail
# with SIGPIPE, and under pipefail the check would then let a second certificate through.
identities=$(security find-identity -p codesigning)
if grep -qF "\"$name\"" <<<"$identities"; then
  echo "error: \"$name\" is already in the keychain; Flick needs that one, not a new one." >&2
  echo "On another Mac, import the .p12 from the password manager instead." >&2
  exit 1
fi
if [[ -e $out ]]; then
  echo "error: $out exists; move it away first." >&2
  exit 1
fi

umask 077
mkdir "$out"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat >"$work/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$work/cert.cnf" \
  -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null

P12_PASSWORD=$(openssl rand -base64 24)
export P12_PASSWORD
# 3DES and SHA-1 keep the file readable by every macOS `security` version.
openssl pkcs12 -export -name "$name" -inkey "$work/key.pem" -in "$work/cert.pem" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
  -passout env:P12_PASSWORD -out "$out/flick-code-signing.p12"

security import "$out/flick-code-signing.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -P "$P12_PASSWORD" -T /usr/bin/codesign
# One line, no wrapping: the same with macOS and GNU tools.
openssl base64 -A -in "$out/flick-code-signing.p12" -out "$out/SIGNING_CERT_P12.txt"
printf '%s' "$P12_PASSWORD" >"$out/SIGNING_CERT_PASSWORD.txt"

cat <<EOF

"$name" is in your login keychain. Next:

1. Password manager: store $out/flick-code-signing.p12
   and its password from $out/SIGNING_CERT_PASSWORD.txt.
2. GitHub secrets:
     gh secret set SIGNING_CERT_P12 < "$out/SIGNING_CERT_P12.txt"
     gh secret set SIGNING_CERT_PASSWORD < "$out/SIGNING_CERT_PASSWORD.txt"
3. Delete the folder: rm -rf "$out"
EOF
