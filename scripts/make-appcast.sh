#!/usr/bin/env bash
# Writes the Sparkle appcast for one release and checks its signature against SUPublicEDKey in
# the app's Info.plist, so a private key that doesn't match fails here and not on every
# installed copy. The key comes from SPARKLE_ED_PRIVATE_KEY (on stdin to sign_update), else the
# login keychain (FLICK_UPDATE_KEY_ACCOUNT picks another account); with DRY set and no key at
# all, the appcast is written unsigned.
# Usage: make-appcast.sh <app> <dmg> <download-url> <notes.html> <out.xml>
set -euo pipefail

app=$1 dmg=$2 url=$3 notes=$4 out=$5
account=${FLICK_UPDATE_KEY_ACCOUNT:-io.github.bergcyrill.flick}

fail() {
  echo "error: $*" >&2
  exit 1
}

plist=$app/Contents/Info.plist
version=$(plutil -extract CFBundleShortVersionString raw "$plist")
build=$(plutil -extract CFBundleVersion raw "$plist")
minimum=$(plutil -extract LSMinimumSystemVersion raw "$plist")
public_key=$(plutil -extract SUPublicEDKey raw "$plist")

unsigned=
if [[ -n ${SPARKLE_ED_PRIVATE_KEY:-} ]]; then
  attributes=$(printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | sign_update --ed-key-file - "$dmg")
elif attributes=$(sign_update --account "$account" "$dmg" 2>/dev/null); then
  :
elif [[ -n ${DRY:-} ]]; then
  echo "warning: no update key (SPARKLE_ED_PRIVATE_KEY or keychain); the appcast is unsigned." >&2
  attributes="length=\"$(wc -c <"$dmg" | tr -d ' ')\""
  unsigned=1
else
  fail "no update key: set SPARKLE_ED_PRIVATE_KEY or import the key into the keychain (docs/releasing.md)"
fi

if [[ -z $unsigned ]]; then
  signature=$(sed -E 's/.*edSignature="([^"]+)".*/\1/' <<<"$attributes")
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  # An Ed25519 public key in DER: the fixed SubjectPublicKeyInfo prefix, then the 32 key bytes.
  {
    printf '\x30\x2a\x30\x05\x06\x03\x2b\x65\x70\x03\x21\x00'
    base64 --decode <<<"$public_key"
  } >"$tmp/key.der"
  base64 --decode <<<"$signature" >"$tmp/signature"
  openssl pkeyutl -verify -pubin -keyform DER -inkey "$tmp/key.der" -rawin -in "$dmg" \
    -sigfile "$tmp/signature" >/dev/null 2>&1 ||
    fail "the update signature doesn't match SUPublicEDKey in $plist; wrong private key?"
fi

cat >"$out" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Flick</title>${unsigned:+
    <!-- unsigned: dry run without an update key -->}
    <item>
      <title>Flick $version</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum</sparkle:minimumSystemVersion>
      <description><![CDATA[
$(cat "$notes")
]]></description>
      <enclosure url="$url" type="application/octet-stream" $attributes/>
    </item>
  </channel>
</rss>
EOF
xmllint --noout "$out"
