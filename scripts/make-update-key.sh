#!/usr/bin/env bash
# Creates Flick's EdDSA key pair for Sparkle updates, once: the private key goes into the login
# keychain and into a file for the password manager and the GitHub secret; the public key goes
# into support/Info.plist. Losing the private key means installed copies can't be updated any
# more. See docs/releasing.md.
set -euo pipefail

account=io.github.bergcyrill.flick
out=${1:-"$HOME/flick-update-key"}

# generate_keys comes with the Sparkle package; it's on the dev shell's PATH once resolved.
command -v generate_keys >/dev/null || swift package resolve

if existing=$(generate_keys --account "$account" -p 2>/dev/null); then
  echo "error: the keychain already has an update key for $account (public key $existing)." >&2
  echo "On another Mac, import it from the password manager: generate_keys --account $account -f <file>" >&2
  exit 1
fi
if [[ -e $out ]]; then
  echo "error: $out exists; move it away first." >&2
  exit 1
fi

umask 077
mkdir "$out"
generate_keys --account "$account" >/dev/null
generate_keys --account "$account" -x "$out/SPARKLE_ED_PRIVATE_KEY.txt"
public=$(generate_keys --account "$account" -p)

cat <<EOF

The update key is in your login keychain (account $account). Next:

1. Password manager: store the contents of $out/SPARKLE_ED_PRIVATE_KEY.txt.
2. GitHub secret:
     gh secret set SPARKLE_ED_PRIVATE_KEY < "$out/SPARKLE_ED_PRIVATE_KEY.txt"
3. Delete the folder: rm -rf "$out"

Public key for support/Info.plist (SUPublicEDKey), not secret:
$public
EOF
