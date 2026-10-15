# Flick Release Pipeline Implementation Plan (PR 2 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every merge to `main` with a `feat`, `fix` or breaking commit publishes a signed, versioned `Flick-<version>.dmg` on GitHub Releases, with release notes; pull requests are tested, linted and dry-run released before they can be merged.

**Architecture:** git-cliff (config `cliff.toml`) writes the release notes and computes the next version from Conventional Commits; an empty set of notes means nothing to release. `scripts/release.sh` (run by `task release`) tests, lints, bundles and signs via the existing `task bundle`, packages via a new `task dmg`, checks version, signature and designated requirement (pinned certificate leaf), and — unless `DRY=1` — publishes a draft release and then makes it public. Two workflows run it on `macos-26`: `ci.yml` on pull requests, `release.yml` on pushes to `main`; `scripts/ci-keychain.sh` puts the certificate into a temporary keychain.

**Tech Stack:** bash, git-cliff 2.13, GitHub CLI (`gh`) 2.92, `hdiutil`, `ditto`, `codesign`, `plutil`; Task; Nix flake dev shell; GitHub Actions (`actions/checkout`, `cachix/install-nix-action`); actionlint.

**Spec:** `docs/superpowers/specs/2026-10-15-flick-release-signing-updates-design.md` — the PR 2 row of *Delivery*, *Version and releases*, and the release checks under *Testing*. The spec was amended on this branch (first commit) with what PR 1 and the git-cliff experiments found.

## Global Constraints

- Version rules (verified with git-cliff 2.13.1 in a scratch repo, 2026-10-15): `fix` → patch, `feat` → minor, breaking (`!` or `BREAKING CHANGE:` footer, any type) → minor below 1.0 and major from 1.0. `chore`, `docs`, `ci`, `test`, `refactor`, `style`, `build` and merge commits alone → no release. First release **v0.1.0**.
- **Whether to release** = the unreleased notes are non-empty. `git-cliff --bumped-version` alone is not trustworthy: before the first tag it always prints `v0.1.0`, and with nothing to release it prints the last tag.
- Tags `vX.Y.Z`; release title **`Flick X.Y.Z`**; asset **`Flick-X.Y.Z.dmg`**, volume name **`Flick`**, containing `Flick.app` and an `Applications` link.
- Build number = `git rev-list --count HEAD`; it must be higher than the last tag's.
- Designated requirement of a release build, exactly: `identifier "io.github.bergcyrill.flick" and certificate leaf = H"1f4706c915a7c15904d0f2201d53e9324f321f81"`.
- Publishing: delete a leftover **draft** for the tag, refuse if the tag is already **published**, create a draft with the DMG, then publish it with `--latest`. Publishing creates the tag. Nothing is published with `DRY=1`.
- CI: runner **`macos-26`**. Actions pinned by SHA: `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1` (v7.0.1), `cachix/install-nix-action@448cde739abec1eaf0646249e3d25bb8d9bc7702` (v31.11.2). `persist-credentials: false`. `release.yml`: `permissions: contents: write`, `concurrency: { group: release, cancel-in-progress: false }`, `fetch-depth: 0`. `ci.yml`: `permissions: contents: read`. Secrets only in env of our own script steps.
- Secrets: `SIGNING_CERT_P12`, `SIGNING_CERT_PASSWORD` (exist since PR 1). `GH_TOKEN: ${{ github.token }}` only for the publishing step.
- Shell: `#!/usr/bin/env bash`, `set -euo pipefail`, clean under shellcheck; never pipe `security` into a reader that can stop early (PR 1 review finding) — capture first.
- Commands run in the dev shell: `nix develop -c …`. `task format`, `task test`, `task lint` pass at the end of every task.
- Git: branch `feature/no-ref/release-pipeline` (exists, off `main` at 09c8e9a). **Never run `git commit` yourself**: stage, hand the user `gitcs '<message>'`, wait for "done", check `git log --oneline -1`. Pushing and the PR only when the user asks.

## Review Focus

1. **A merge with only `docs`/`chore`/`ci`/merge commits** must not release and must end green. Pinned by Task 2 Step 6 (scratch clone tagged at HEAD → "Nothing to release", exit 0, no `build/`) and the git-cliff rule check in Task 1 Step 4.
2. **A replaced or missing certificate in CI** must fail the release before anything is published, not ship a build that costs every user a new Accessibility grant. Pinned by Task 2 Step 7 (`FLICK_SIGNING_NAME` pointing nowhere → ad-hoc → designated requirement check fails, exit 1) and `ci-keychain.sh`'s secret checks (Task 3 Step 2).
3. **A run that dies after creating the draft**, re-run: must delete the draft and publish cleanly; a tag that is already published must make the run fail, never overwrite. Pinned by the `gh release list` branch in `release.sh` (Task 2 Step 3) — review it; it can't run before merge.
4. **Pull requests from forks** get no secrets: the signing job must be skipped, the test/lint/build job must still run. Pinned by the `if:` on `release-dry` in `ci.yml` (Task 3 Step 3) — review it.
5. **Two merges in quick succession**: the second run waits for the first (concurrency group) and then releases everything since the new tag; a squash merge with a non-conventional title releases nothing. Pinned by `concurrency` in `release.yml` (Task 3 Step 4) and the README's *Releases* note (Task 3 Step 6).

---

## File structure

| File | Task | Responsibility |
|---|---|---|
| `docs/superpowers/specs/2026-10-15-flick-release-signing-updates-design.md` | 1 | Amended (already edited, uncommitted) |
| `flake.nix` | 1, 3 | Adds `git-cliff`, `gh` (Task 1), `actionlint` (Task 3) |
| `cliff.toml` (new) | 1 | Commit grouping, notes template, bump rules |
| `Taskfile.yml` | 1, 2, 3 | `release-notes`; `dmg`, `release`; `lint` runs actionlint |
| `scripts/release.sh` (new) | 2 | The release: decide, build, check, publish |
| `README.md` | 2, 3 | *Installing*, *Releases*, checklist |
| `scripts/ci-keychain.sh` (new) | 3 | Temporary keychain for the certificate in CI |
| `.github/workflows/ci.yml` (new) | 3 | Pull requests: test, lint, build; dry-run release |
| `.github/workflows/release.yml` (new) | 3 | Pushes to `main`: release |

---

### Task 1: Release notes and version bumps with git-cliff

**Files:**
- Modify: `flake.nix`, `Taskfile.yml`, spec (already edited)
- Create: `cliff.toml`

**Interfaces:**
- Consumes: nothing.
- Produces: `cliff.toml` at the repo root; `git-cliff --unreleased --strip all` prints the notes (empty ⇔ nothing to release); `git-cliff --bumped-version` prints `vX.Y.Z`; `task release-notes`; `git-cliff` and `gh` on the dev shell's `PATH`.

- [ ] **Step 1: Commit the spec amendment**

Stage: `git add docs/superpowers/specs/2026-10-15-flick-release-signing-updates-design.md docs/superpowers/plans/2026-10-15-flick-release-pipeline.md`. Hand over:

```sh
gitcs 'docs: plan the release pipeline and amend the spec with what PR 1 found'
```

- [ ] **Step 2: Add the tools**

`flake.nix` package list gains `git-cliff` and `gh`:

```nix
          packages = with pkgs; [
            go-task
            swiftlint
            pre-commit
            openssl
            shellcheck
            git-cliff
            gh
          ];
```

Run: `nix develop -c sh -c 'git-cliff --version; gh --version | head -1'`
Expected: `git-cliff 2.13.1` and `gh version 2.92.0` (or newer, from the pinned `flake.lock`).

- [ ] **Step 3: Write `cliff.toml`**

```toml
# Release notes and version bumps from Conventional Commits, for `task release`.
# Only feat, fix and breaking commits appear; empty notes mean there is nothing to release.

[changelog]
body = """
{% for group, commits in commits | group_by(attribute="group") %}
### {{ group | striptags | trim | upper_first }}
{% for commit in commits %}- {% if commit.scope %}**{{ commit.scope }}:** {% endif %}{{ commit.message | upper_first }}
{% endfor %}{% endfor %}"""
trim = true

[git]
conventional_commits = true
filter_unconventional = true
protect_breaking_commits = true
commit_parsers = [
  { field = "breaking", pattern = "true", group = "<!-- 0 -->Breaking changes" },
  { message = "^feat", group = "<!-- 1 -->Features" },
  { message = "^fix", group = "<!-- 2 -->Fixes" },
  { message = ".*", skip = true },
]
tag_pattern = "v[0-9]+\\.[0-9]+\\.[0-9]+"

[bump]
features_always_bump_minor = true
breaking_always_bump_major = false
initial_tag = "v0.1.0"
```

`Taskfile.yml`, after `bundle`:

```yaml
  release-notes:
    desc: Print the release notes since the last tag (empty means nothing to release)
    cmds:
      - git-cliff --unreleased --strip all
```

- [ ] **Step 4: Check the rules in a scratch repo**

Write `$WORKSPACE/cliff-rules.sh` (workspace = this plan's `.superpowers/sdd/…` dir) and run it with the repo path:

```bash
#!/usr/bin/env bash
# Checks cliff.toml's release rules on throwaway commits.
set -euo pipefail
repo=$1
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
git init -q
git config user.email t@t; git config user.name t
git config commit.gpgsign false; git config tag.gpgsign false
cp "$repo/cliff.toml" .
fail=0
c() { git commit -q --allow-empty "$@"; }
check() { # name, expected version or "none"
  local notes version
  notes=$(git-cliff --unreleased --strip all 2>/dev/null)
  if [[ -z ${notes//[[:space:]]/} ]]; then version=none; else version=$(git-cliff --bumped-version 2>/dev/null); fi
  if [[ $version == "$2" ]]; then echo "PASS $1 → $version"; else echo "FAIL $1 → $version, expected $2"; fail=1; fi
}
c -m "chore: init";                       check "no tag, chore only" none
c -m "feat: first";                       check "no tag, feat" v0.1.0
git tag v0.1.0;                           check "at the tag" none
c -m "docs: x"; c -m "Merge pull request #9 from a/b"; check "docs + merge" none
c -m "fix(app): y";                       check "fix" v0.1.1
c -m "feat(core): z";                     check "fix + feat" v0.2.0
git tag v0.2.0
c -m "chore: z" -m "BREAKING CHANGE: footer"; check "breaking footer below 1.0" v0.3.0
git tag v1.0.0; c -m "refactor!: big";    check "breaking from 1.0" v2.0.0
exit $fail
```

Run: `nix develop -c "$WORKSPACE/cliff-rules.sh" "$PWD"`
Expected: 8 `PASS` lines, exit 0.

- [ ] **Step 5: Notes for the real history**

Run: `nix develop -c task release-notes` and `nix develop -c git-cliff --bumped-version`
Expected: a *Features* section (e.g. "**app:** Fill and restore by holding the right button and scrolling") and a *Fixes* section, no `chore`/`docs`/`build` entries, no "Merge pull request" lines; then `v0.1.0`.

- [ ] **Step 6: Verify and commit**

Run: `nix develop -c sh -c 'task format && task test && task lint'`
Expected: all pass.

Stage: `git add flake.nix flake.lock cliff.toml Taskfile.yml` (`flake.lock` only if it changed). Hand over:

```sh
gitcs 'build: write release notes and versions with git-cliff'
```

---

### Task 2: DMG and `task release`

**Files:**
- Create: `scripts/release.sh`
- Modify: `Taskfile.yml` (`dmg`, `release`), `README.md`

**Interfaces:**
- Consumes: `cliff.toml` (Task 1); `task bundle VERSION=… BUILD=…` and `scripts/sign-app.sh` (PR 1; honours `FLICK_SIGNING_NAME`).
- Produces: `task dmg` → `build/Flick-<VERSION>.dmg`; `task release` / `task release DRY=1` → `scripts/release.sh`, which needs `GH_TOKEN` (or `gh auth`) only when not dry; writes `build/release-notes.md`. Task 3's workflows call exactly `nix develop -c task release` and `nix develop -c task release DRY=1`.

- [ ] **Step 1: `task dmg`**

`Taskfile.yml`, after `release-notes`:

```yaml
  dmg:
    desc: Package build/Flick.app as build/Flick-<version>.dmg
    deps: [bundle]
    vars:
      STAGE: build/dmg
      DMG: build/Flick-{{.VERSION}}.dmg
    cmds:
      - rm -rf {{.STAGE}} {{.DMG}}
      - mkdir -p {{.STAGE}}
      - ditto {{.APP}} {{.STAGE}}/Flick.app
      - ln -s /Applications {{.STAGE}}/Applications
      - hdiutil create -volname Flick -srcfolder {{.STAGE}} -format UDZO -ov {{.DMG}}
      - hdiutil verify {{.DMG}}
      - rm -rf {{.STAGE}}
```

Run: `nix develop -c task dmg VERSION=9.9.9 BUILD=1`
Expected: ends with `hdiutil: verify: checksum of "build/Flick-9.9.9.dmg" is VALID`.

Then:

```sh
mnt=$(mktemp -d)
hdiutil attach -nobrowse -readonly -mountpoint "$mnt" build/Flick-9.9.9.dmg >/dev/null
ls -l "$mnt"; codesign --verify --strict "$mnt/Flick.app" && echo signature-ok
plutil -extract CFBundleShortVersionString raw "$mnt/Flick.app/Contents/Info.plist"
hdiutil detach "$mnt" >/dev/null; rm build/Flick-9.9.9.dmg
```

Expected: `Applications -> /Applications` and `Flick.app`, `signature-ok`, `9.9.9`.

- [ ] **Step 2: `task release`**

`Taskfile.yml`, after `dmg`:

```yaml
  release:
    desc: Test, build, check and publish a release on GitHub (DRY=1 stops before publishing)
    cmds:
      - DRY={{.DRY}} scripts/release.sh
```

- [ ] **Step 3: Write `scripts/release.sh`**

```bash
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

if [[ -n $dry ]]; then
  echo "Dry run: would publish $tag with $dmg and these notes:"
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
  --target "$(git rev-parse HEAD)" "$dmg"
gh release edit "$tag" --draft=false --latest
echo "Published Flick $version."
```

Run: `chmod +x scripts/release.sh && nix develop -c task lint`
Expected: PASS (shellcheck silent).

- [ ] **Step 4: Dry run on the real repo**

Run: `nix develop -c task release DRY=1 > "$WORKSPACE/dry.log" 2>&1; echo "exit $?"; grep -E "Releasing|Test run with|VALID|Dry run" "$WORKSPACE/dry.log"; tail -15 "$WORKSPACE/dry.log"`
Expected: exit 0; `Releasing Flick 0.1.0 (build <n>), dry run`; the test run line; `… Flick-0.1.0.dmg" is VALID`; `Dry run: would publish v0.1.0 with build/Flick-0.1.0.dmg …` followed by the notes from Task 1 Step 5.

- [ ] **Step 5: README — installing and the checklist**

After the intro image (before *Getting started*), add:

```markdown
## Installing

1. Download `Flick-<version>.dmg` from the
   [latest release](https://github.com/BergCyrill/Flick/releases/latest), open it and drag
   *Flick* onto *Applications*.
2. Open Flick. macOS blocks it the first time because it is signed with Flick's own
   certificate, not one from Apple: open **System Settings → Privacy & Security**, scroll to
   the message about Flick and click **Open Anyway**.
3. Grant Flick **Accessibility** access when it asks.

A new version downloaded this way needs *Open Anyway* once more; the Accessibility permission
stays.
```

Add to *Manual test checklist*:

```markdown
- [ ] Release DMG: opening it shows *Flick* and an *Applications* link; after dragging and *Open Anyway*, the menu shows the release's version.
```

- [ ] **Step 6: Nothing to release**

Run:

```sh
tmp=$(mktemp -d); git clone -q . "$tmp/repo"; cd "$tmp/repo"
git -c tag.gpgsign=false tag v9.9.9
nix develop -c task release DRY=1; echo "exit $?"; ls build 2>&1 | head -1
cd - >/dev/null; rm -rf "$tmp"
```

Expected: `Nothing to release: no feat, fix or breaking commits since the last tag.`, `exit 0`, and `ls` reports no `build` directory.

- [ ] **Step 7: A wrong certificate fails the release**

Run: `FLICK_SIGNING_NAME="No Such Certificate" nix develop -c task release DRY=1 > "$WORKSPACE/wrongcert.log" 2>&1; echo "exit $?"; grep -E "warning:|error:" "$WORKSPACE/wrongcert.log"`
Expected: exit non-zero; the two ad-hoc `warning:` lines from `sign-app.sh`, then `error: unexpected designated requirement (wrong or missing certificate?): … cdhash H"…"`. No `Dry run:` line.

- [ ] **Step 8: Verify and commit**

Run: `nix develop -c sh -c 'task format && task test && task lint' && rm -f build/*.dmg build/release-notes.md`
Expected: all pass.

Stage: `git add Taskfile.yml scripts/release.sh README.md`. Hand over:

```sh
gitcs 'build: package a DMG and publish releases with task release'
```

---

### Task 3: GitHub Actions

**Files:**
- Create: `scripts/ci-keychain.sh`, `.github/workflows/ci.yml`, `.github/workflows/release.yml`
- Modify: `flake.nix` (`actionlint`), `Taskfile.yml` (`lint`), `README.md`

**Interfaces:**
- Consumes: `task test`, `task lint`, `task build`, `task release [DRY=1]` (Task 2); secrets `SIGNING_CERT_P12`, `SIGNING_CERT_PASSWORD`.
- Produces: `scripts/ci-keychain.sh import|delete` (needs `RUNNER_TEMP`; `import` needs both secrets in env); the two workflows. PR 3 will add the Sparkle key to `release.yml`'s release step.

- [ ] **Step 1: actionlint in the dev shell and in lint**

`flake.nix` package list gains `actionlint`. `Taskfile.yml` `lint`:

```yaml
  lint:
    desc: Run swiftlint, swift-format (strict), shellcheck and actionlint
    cmds:
      - swiftlint lint --strict --quiet
      - swift format lint --strict --recursive Sources Tests Package.swift
      - shellcheck scripts/*.sh
      - actionlint
```

- [ ] **Step 2: Write `scripts/ci-keychain.sh`**

```bash
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
```

Run: `chmod +x scripts/ci-keychain.sh && nix develop -c shellcheck scripts/ci-keychain.sh && (unset SIGNING_CERT_P12; RUNNER_TEMP=/nonexistent nix develop -c scripts/ci-keychain.sh import; echo "exit $?")`
Expected: shellcheck silent; then `…SIGNING_CERT_P12: is not set — add the GitHub secret, see README → Code signing` and `exit 1`, before any `security` call (no keychain created).

- [ ] **Step 3: Write `.github/workflows/ci.yml`**

```yaml
name: ci
on:
  pull_request:
permissions:
  contents: read
concurrency:
  group: ci-${{ github.event.pull_request.number }}
  cancel-in-progress: true
jobs:
  check:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: cachix/install-nix-action@448cde739abec1eaf0646249e3d25bb8d9bc7702 # v31.11.2
      - name: Test
        run: nix develop -c task test
      - name: Lint
        run: nix develop -c task lint
      - name: Build
        run: nix develop -c task build

  release-dry:
    # Signs with the real certificate, so only for branches of this repository: forks get no
    # secrets.
    if: github.event.pull_request.head.repo.full_name == github.repository
    runs-on: macos-26
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          fetch-depth: 0
          persist-credentials: false
      - uses: cachix/install-nix-action@448cde739abec1eaf0646249e3d25bb8d9bc7702 # v31.11.2
      - name: Import the signing certificate
        env:
          SIGNING_CERT_P12: ${{ secrets.SIGNING_CERT_P12 }}
          SIGNING_CERT_PASSWORD: ${{ secrets.SIGNING_CERT_PASSWORD }}
        run: nix develop -c scripts/ci-keychain.sh import
      - name: Dry-run the release
        run: nix develop -c task release DRY=1
      - name: Delete the keychain
        if: always()
        run: scripts/ci-keychain.sh delete
```

- [ ] **Step 4: Write `.github/workflows/release.yml`**

```yaml
name: release
on:
  push:
    branches: [main]
permissions:
  contents: write
# One release at a time; a merge during a release waits instead of cancelling it.
concurrency:
  group: release
  cancel-in-progress: false
jobs:
  release:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          fetch-depth: 0
          persist-credentials: false
      - uses: cachix/install-nix-action@448cde739abec1eaf0646249e3d25bb8d9bc7702 # v31.11.2
      - name: Import the signing certificate
        env:
          SIGNING_CERT_P12: ${{ secrets.SIGNING_CERT_P12 }}
          SIGNING_CERT_PASSWORD: ${{ secrets.SIGNING_CERT_PASSWORD }}
        run: nix develop -c scripts/ci-keychain.sh import
      - name: Release
        env:
          GH_TOKEN: ${{ github.token }}
        run: nix develop -c task release
      - name: Delete the keychain
        if: always()
        run: scripts/ci-keychain.sh delete
```

Run: `nix develop -c task lint`
Expected: PASS — actionlint silent for both workflows (it also shellchecks the `run:` blocks).

- [ ] **Step 5: README — releases**

After *Code signing*, add:

````markdown
## Releases

Every merge to `main` that brings a `feat`, `fix` or breaking commit publishes a release:
`.github/workflows/release.yml` runs `task release`, which tests, lints, builds, signs, checks
the signature and publishes `Flick-<version>.dmg` with release notes on GitHub Releases. The
version follows the commits since the last tag (git-cliff, `cliff.toml`): `fix` → patch,
`feat` → minor, breaking → minor below 1.0 and major from 1.0. Merges with only `docs`,
`chore`, `ci`, `build`, `test`, `refactor` or `style` commits release nothing. With squash
merges the PR title is the commit, so it must be a Conventional Commit too.

```sh
task release-notes      # what the next release would say (empty: nothing to release)
task release DRY=1      # the whole release locally, without publishing
```

Pull requests run `task test`, `task lint` and `task build`, and — for branches of this
repository — `task release DRY=1` with the signing certificate (`.github/workflows/ci.yml`).
````

- [ ] **Step 6: Verify and commit**

Run: `nix develop -c sh -c 'task format && task test && task lint'`
Expected: all pass.

Stage: `git add flake.nix flake.lock Taskfile.yml scripts/ci-keychain.sh .github/workflows/ci.yml .github/workflows/release.yml README.md` (`flake.lock` only if it changed). Hand over:

```sh
gitcs 'ci: check pull requests and release every merge to main'
```

---

## After the last task

1. Whole-branch review (Opus subagent) against the spec's PR 2 row and this plan's Review Focus.
2. When the user asks: push and open PR 2. Its own CI is the first real run of `ci.yml`: both jobs must be green (`release-dry` shows `Dry run: would publish v0.1.0 …`). Fix forward on the branch if not.
3. After the user merges: watch `release.yml` (`gh run watch`). Expected: release **v0.1.0** with `Flick-0.1.0.dmg`, marked latest, tag `v0.1.0` on the merge commit. Then the user downloads the DMG in a browser and walks the *Installing* steps (first real *Open Anyway*).
