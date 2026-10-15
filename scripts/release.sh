#!/usr/bin/env bash
# Builds, checks and publishes a release of Flick on GitHub. Run it through `task release`;
# with DRY=1 it stops before anything leaves this machine. See README → Releases.
set -euo pipefail

# The certificate every release is signed with. Another one would change the designated
# requirement and cost every user a new Accessibility grant, so it fails the release instead.
readonly cert_leaf=1f4706c915a7c15904d0f2201d53e9324f321f81
readonly bundle_id=io.github.bergcyrill.flick
readonly app=build/Flick.app
readonly notes_file=build/release-notes.md
dry=${DRY:-}

fail() {
  echo "error: $*" >&2
  exit 1
}

# In CI the update key can only come from the secret; without it a dry run would pass with an
# unsigned appcast and hide the missing secret until the real release.
if [[ -n ${CI:-} ]]; then
  : "${SPARKLE_ED_PRIVATE_KEY:?is not set — add the GitHub secret, see README → Code signing}"
fi

notes=$(git-cliff --unreleased --strip all 2>/dev/null)
if [[ -z ${notes//[[:space:]]/} ]]; then
  echo "Nothing to release: no feat, fix or breaking commits since the last tag."
  exit 0
fi

tag=$(git-cliff --bumped-version 2>/dev/null)
version=${tag#v}
build=$(git rev-list --count HEAD)
last_tag=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)
if [[ -n $last_tag ]]; then
  [[ $tag != "$last_tag" ]] || fail "next version $tag equals the last tag"
  last_build=$(git rev-list --count "$last_tag")
  ((build > last_build)) || fail "build $build is not above $last_tag's build $last_build"
fi
echo "Releasing Flick $version (build $build)${dry:+, dry run}"

task test
task lint
task dmg VERSION="$version" BUILD="$build"
dmg=build/Flick-$version.dmg

plist=$app/Contents/Info.plist
[[ $(plutil -extract CFBundleShortVersionString raw "$plist") == "$version" ]] ||
  fail "Info.plist does not carry version $version"
[[ $(plutil -extract CFBundleVersion raw "$plist") == "$build" ]] ||
  fail "Info.plist does not carry build $build"
codesign --verify --strict --deep "$app"
requirement=$(codesign --display --requirements - "$app" 2>&1)
expected="designated => identifier \"$bundle_id\" and certificate leaf = H\"$cert_leaf\""
[[ $requirement == *"$expected"* ]] ||
  fail "unexpected designated requirement (wrong or missing certificate?): $requirement"

printf '%s\n' "$notes" >"$notes_file"
git-cliff --unreleased --strip all --body "$(cat support/release-notes.html.tera)" \
  2>/dev/null >build/release-notes.html
scripts/make-appcast.sh "$app" "$dmg" \
  "https://github.com/BergCyrill/Flick/releases/download/$tag/Flick-$version.dmg" \
  build/release-notes.html build/appcast.xml

if [[ -n $dry ]]; then
  echo "Dry run: would publish $tag with $dmg, build/appcast.xml and these notes:"
  cat "$notes_file"
  exit 0
fi

# A draft left by a failed run is replaced; a published release is never touched.
state=$(gh release list --limit 100 --json tagName,isDraft \
  --jq ".[] | select(.tagName == \"$tag\") | .isDraft")
case $state in
  true) gh release delete "$tag" --yes ;;
  false) fail "$tag is already published" ;;
esac
gh release create "$tag" --draft --title "Flick $version" --notes-file "$notes_file" \
  --target "$(git rev-parse HEAD)" "$dmg" build/appcast.xml
gh release edit "$tag" --draft=false --latest
echo "Published Flick $version."
