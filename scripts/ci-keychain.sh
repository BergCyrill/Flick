#!/usr/bin/env bash
# CI only: puts the signing certificate from the GitHub secrets into a temporary keychain
# (`import`) and removes that keychain again (`delete`). See .github/workflows.
set -euo pipefail

keychain="${RUNNER_TEMP:?RUNNER_TEMP is not set (CI only)}/signing.keychain-db"

case ${1:-} in
  import)
    : "${SIGNING_CERT_P12:?is not set — add the GitHub secret, see README → Code signing}"
    : "${SIGNING_CERT_PASSWORD:?is not set — add the GitHub secret, see README → Code signing}"
    p12=$RUNNER_TEMP/signing.p12
    trap 'rm -f "$p12"' EXIT
    password=$(openssl rand -hex 16)
    security create-keychain -p "$password" "$keychain"
    security set-keychain-settings -lut 3600 "$keychain"
    security unlock-keychain -p "$password" "$keychain"
    printf '%s' "$SIGNING_CERT_P12" | base64 --decode >"$p12"
    security import "$p12" -k "$keychain" -P "$SIGNING_CERT_PASSWORD" -T /usr/bin/codesign
    security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$keychain" >/dev/null
    searchlist=$(security list-keychains -d user | tr -d '"')
    # shellcheck disable=SC2086 # one keychain path per word
    security list-keychains -d user -s "$keychain" $searchlist
    ;;
  delete)
    security delete-keychain "$keychain" 2>/dev/null || true
    ;;
  *)
    echo "usage: $0 import|delete" >&2
    exit 2
    ;;
esac
