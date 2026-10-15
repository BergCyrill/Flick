#!/usr/bin/env bash
# Signs an app bundle with the "Flick Code Signing" certificate from the keychain, so macOS
# keeps Flick's Accessibility permission across builds. Without the certificate it signs
# ad-hoc and says so. FLICK_SIGNING_NAME picks another certificate name.
set -euo pipefail

app=$1
name=${FLICK_SIGNING_NAME:-Flick Code Signing}

# By hash: codesign rejects a name that matches more than one certificate. Without -v, so the
# self-signed (untrusted) certificate is listed too. The listing is read in full first: awk
# stopping at the first match could make `security` fail with SIGPIPE under pipefail.
identities=$(security find-identity -p codesigning)
hash=$(awk -v name="\"$name\"" 'index($0, name) { print $2; exit }' <<<"$identities")

if [[ -n $hash ]]; then
  codesign --force --sign "$hash" "$app"
else
  echo "warning: no \"$name\" certificate in the keychain; signing ad-hoc." >&2
  echo "warning: macOS will ask for Accessibility again after this build (README → Code signing)." >&2
  codesign --force --sign - "$app"
fi
codesign --verify --strict "$app"
