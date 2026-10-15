# Flick Code Signing Implementation Plan (PR 1 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sign every build with a stable self-signed certificate so macOS keeps Flick's Accessibility permission across rebuilds, move to the bundle ID `io.github.bergcyrill.flick` without losing settings, and stamp and show a version number.

**Architecture:** A maintainer script creates the certificate once (login keychain, password manager, GitHub secrets). `scripts/sign-app.sh` signs the bundle with it, falling back to ad-hoc. `task bundle` stamps the version from git tags into `Info.plist`. `FlickCore` gains `SettingsMigration`, which copies settings from the old defaults domain once; `main.swift` runs it before anything reads settings. The app shows its version in the menu and the settings window.

**Tech Stack:** Swift 6 (Xcode toolchain), SwiftPM, swift-testing, AppKit, SwiftUI; bash, `openssl`, `security`, `codesign`, `plutil`; Nix flake dev shell (go-task, swiftlint, pre-commit, openssl, shellcheck); Task as task runner; GitHub Actions (spike only).

**Spec:** `docs/superpowers/specs/2026-10-15-flick-release-signing-updates-design.md` — this plan covers the PR 1 row of *Delivery*. PRs 2 and 3 get their own plans once the CI spike (Task 2) has reported.

## Global Constraints

- Bundle ID **`io.github.bergcyrill.flick`**; the old one, **`local.personal.flick`**, appears only in `SettingsMigration.oldDomain`.
- Certificate: common name **`Flick Code Signing`**, RSA 2048, valid **3650** days, `extendedKeyUsage = critical, codeSigning`. Created once by the maintainer; never a second one.
- GitHub secrets: **`SIGNING_CERT_P12`** (the `.p12`, base64), **`SIGNING_CERT_PASSWORD`**. (`SPARKLE_ED_PRIVATE_KEY` comes with PR 3.)
- Nothing secret in the repo, not even encrypted. `.gitignore` gets `*.p12`, `*.cer`, `*.pem`, `*.key` **before** any script is staged.
- The default designated requirement stays (`identifier "io.github.bergcyrill.flick" and certificate leaf = H"…"`). Never pass `-r`/`--requirements` to `codesign`. No `--deep` when signing. No hardened runtime, no notarization.
- Version: `CFBundleShortVersionString` = `<last tag without v>-dev` locally, `0.0.0-dev` before the first tag; `CFBundleVersion` = `git rev-list --count HEAD`. Both overridable: `task bundle VERSION=0.2.0 BUILD=57` (CLI vars override the Taskfile's — checked with the dev shell's `task`). No version file in the repo.
- Visible version: menu line **`Flick <version>`** (first item, disabled); settings window footer **`Version <version> (<build>)`**.
- `FlickCore` imports nothing but `Foundation`. Tests use swift-testing (`import Testing`, `@Test`, `#expect`); new suites go in new files; temporary defaults domains are named `io.github.bergcyrill.flick.tests.<UUID>` and removed afterwards.
- Shell scripts: `#!/usr/bin/env bash`, `set -euo pipefail`, clean under `shellcheck`.
- Commands run inside the dev shell: prefix with `nix develop -c` (direnv is blocked in this checkout). `task format`, `task test`, `task lint` and `task build` must pass at the end of every task.
- Git: branch `feature/no-ref/code-signing` (exists; holds the spec commit f662cd2). **Never run `git commit` yourself.** At each commit step, stage the listed files, hand the user the `gitcs '<message>'` command (signing alias, needs a hardware token) and wait for "done"; then check `git log --oneline -1`. Conventional Commits. Pushing and opening the PR only when the user asks.
- Already verified on this Mac (scratch keychain, 2026-10-15): a self-signed, untrusted certificate imported from a 3DES/SHA1 `.p12` signs with `codesign --sign <SHA-1>` and `--sign "<name>"`, passes `codesign --verify --strict`, and yields `designated => identifier "…" and certificate leaf = H"<sha1>"`. `security find-identity -p codesigning` (without `-v`) lists it as `CSSMERR_TP_NOT_TRUSTED`; with `-v` it is not listed.

## Review Focus

1. **Running the certificate script a second time** must not create a second certificate: a new one changes the designated requirement and every user re-grants Accessibility. Pinned by the refusal check in `make-signing-cert.sh` and Task 1 Step 6.
2. **A user who already changed settings under the new bundle ID** must not have them overwritten by old values. Pinned by `neverOverwritesSettingsInTheNewDomain` and `runsOnlyOnce` (Task 3).
3. **Unrelated keys in the old domain** (status item positions, window frames, macOS bookkeeping) must stay behind. Pinned by `leavesOtherKeysBehind` (Task 3).
4. **A build on a machine without the certificate** (a contributor, CI's PR job) must still produce a runnable, verified app and say why Accessibility will ask again. Pinned by Task 4 Step 6 (`FLICK_SIGNING_NAME=…` forces the fallback).
5. **A checkout without tags** (today, and shallow CI clones) must still stamp a valid version. Pinned by Task 4 Step 5 (`0.0.0-dev`).

---

## File structure

| File | Task | Responsibility |
|---|---|---|
| `.gitignore` | 1 | Keeps key material out of the repo |
| `flake.nix` | 1 | Adds `openssl` and `shellcheck` to the dev shell |
| `Taskfile.yml` | 1, 4 | `lint` runs shellcheck; `bundle` stamps the version and signs via `sign-app.sh` |
| `.pre-commit-config.yaml` | 1 | shellcheck hook |
| `scripts/make-signing-cert.sh` (new) | 1 | Creates the certificate once, prints where each piece goes |
| `README.md` | 1, 3, 4 | *Code signing*, upgrade note, Accessibility paragraph, checklist |
| `.github/workflows/signing-spike.yml` (new, scratch branch only) | 2 | Throwaway: does codesign accept the certificate on a GitHub runner? |
| `Sources/FlickCore/SettingsMigration.swift` (new) | 3 | Copies settings from the old defaults domain once |
| `Sources/FlickCore/FlickSettings.swift` | 3 | Exposes the keys it reads (`storedKeys`) |
| `Sources/Flick/main.swift` | 3 | Runs the migration before the app starts |
| `Sources/Flick/EventTap.swift`, `Sources/Flick/WindowMover.swift` | 3 | Logger subsystem renamed |
| `support/Info.plist` | 3, 4 | New bundle ID; version placeholders |
| `Tests/FlickCoreTests/SettingsMigrationTests.swift` (new) | 3 | The migration |
| `Tests/FlickCoreTests/FlickSettingsTests.swift` | 3 | Test domain prefix renamed |
| `scripts/sign-app.sh` (new) | 4 | Signs with the certificate, or ad-hoc with a warning, then verifies |
| `Sources/Flick/AppVersion.swift` (new) | 4 | Reads the stamped version from the bundle |
| `Sources/Flick/MenuBarApp.swift`, `Sources/Flick/SettingsWindow.swift` | 4 | Show the version |

---

### Task 1: Certificate script and local signing check

**Files:**
- Modify: `.gitignore`, `flake.nix`, `Taskfile.yml` (`lint`), `.pre-commit-config.yaml`, `README.md`
- Create: `scripts/make-signing-cert.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: the identity *Flick Code Signing* in the maintainer's login keychain; GitHub secrets `SIGNING_CERT_P12`, `SIGNING_CERT_PASSWORD`; `openssl` and `shellcheck` on the dev shell's `PATH`; `task lint` checks `scripts/*.sh`.

- [ ] **Step 1: Keep key material out of git**

Append to `.gitignore`, under `# Local secrets`:

```gitignore
# Local secrets
.env
.env.*
*.p12
*.cer
*.pem
*.key
```

Run: `git check-ignore -v x.p12 x.cer x.pem x.key`
Expected: four lines, each naming `.gitignore`.

- [ ] **Step 2: Add openssl and shellcheck to the dev shell and lint**

In `flake.nix`, extend the package list:

```nix
          packages = with pkgs; [
            go-task
            swiftlint
            pre-commit
            openssl
            shellcheck
          ];
```

In `Taskfile.yml`, `lint` becomes:

```yaml
  lint:
    desc: Run swiftlint, swift-format (strict) and shellcheck
    cmds:
      - swiftlint lint --strict --quiet
      - swift format lint --strict --recursive Sources Tests Package.swift
      - shellcheck scripts/*.sh
```

In `.pre-commit-config.yaml`, add to the `local` hooks:

```yaml
      - id: shellcheck
        name: shellcheck
        entry: shellcheck
        language: system
        types: [shell]
```

Run: `nix develop -c sh -c 'openssl version; shellcheck --version | head -2'`
Expected: an OpenSSL 3.x version line and a shellcheck version, both from `/nix/store` (`nix develop -c which openssl` shows the path).

- [ ] **Step 3: Write `scripts/make-signing-cert.sh`**

```bash
#!/usr/bin/env bash
# Creates the self-signed "Flick Code Signing" certificate, imports it into the login keychain
# and writes the pieces that go into the password manager and the GitHub secrets. Run it once,
# ever: a second certificate changes Flick's designated requirement, and every user would have
# to grant Accessibility again. See README → Code signing.
set -euo pipefail

name="Flick Code Signing"
out=${1:-"$HOME/flick-signing"}

if security find-identity -p codesigning | grep -qF "\"$name\""; then
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
base64 -i "$out/flick-code-signing.p12" -o "$out/SIGNING_CERT_P12.txt"
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
```

Run: `chmod +x scripts/make-signing-cert.sh && nix develop -c task lint`
Expected: PASS (shellcheck prints nothing).

- [ ] **Step 4: Document it in the README**

Add after *Project layout* (before *Usage*):

````markdown
## Code signing

Builds are signed with a self-signed certificate, *Flick Code Signing*. macOS ties the
Accessibility permission to Flick's bundle ID and this certificate, so the permission survives
rebuilds and updates. The maintainer creates the certificate once:

```sh
scripts/make-signing-cert.sh    # imports it into the login keychain, writes ~/flick-signing
```

It prints the next steps: keep the `.p12` and its password in the password manager, set the
GitHub secrets `SIGNING_CERT_P12` and `SIGNING_CERT_PASSWORD`, delete `~/flick-signing`.
Never create a second certificate: a new one changes the designated requirement, and every
user has to grant Accessibility again. To sign on another Mac, double-click the `.p12` from the
password manager.
````

- [ ] **Step 5: The user creates the certificate**

Hand over to the user (the key must never pass through the agent):

```sh
nix develop -c scripts/make-signing-cert.sh
```

then the three printed steps (password manager, `gh secret set` ×2, `rm -rf ~/flick-signing`). Wait for "done".

Run: `security find-identity -p codesigning | grep "Flick Code Signing"` and `gh secret list`
Expected: one line `… "Flick Code Signing" (CSSMERR_TP_NOT_TRUSTED)`; the secrets list shows `SIGNING_CERT_P12` and `SIGNING_CERT_PASSWORD`.

- [ ] **Step 6: The script refuses a second run**

Run: `nix develop -c scripts/make-signing-cert.sh /tmp/flick-signing-again; echo "exit $?"; ls /tmp/flick-signing-again`
Expected: `error: "Flick Code Signing" is already in the keychain…`, `exit 1`, and `ls` reports no such directory.

- [ ] **Step 7: Local check — the permission survives a re-sign**

Still with the old bundle ID; Task 3 changes it. Run:

```sh
nix develop -c task bundle
codesign --force --sign "Flick Code Signing" build/Flick.app
codesign -dr - build/Flick.app
codesign -dvvv build/Flick.app 2>&1 | grep CDHash
```

Expected: `designated => identifier "local.personal.flick" and certificate leaf = H"…"` and a CDHash.

Hand over to the user: quit Flick, remove *Flick* from *System Settings → Privacy & Security → Accessibility*, `open build/Flick.app`, grant access, check the menu says *Accessibility access granted*. Then run:

```sh
pkill -x Flick
plutil -replace CFBundleVersion -string 2 build/Flick.app/Contents/Info.plist
codesign --force --sign "Flick Code Signing" build/Flick.app
codesign -dvvv build/Flick.app 2>&1 | grep CDHash
open build/Flick.app
```

Expected: a different CDHash, and the menu still says *Accessibility access granted* within a few seconds, without a new prompt. If it asks again, stop: the spec's premise is wrong; report to the user before going on.

- [ ] **Step 8: Verify and commit**

Run: `nix develop -c sh -c 'task format && task test && task lint && task build'`
Expected: all pass.

Stage: `git add .gitignore flake.nix Taskfile.yml .pre-commit-config.yaml scripts/make-signing-cert.sh README.md` (and `flake.lock` only if it changed — it shouldn't). Check `git status --short` shows no `.p12`/`.txt` key files. Hand over:

```sh
gitcs 'build: add a script that creates the code signing certificate'
```

---

### Task 2: CI signing spike (scratch branch, never merged)

**Files:**
- Create (on `chore/no-ref/signing-spike` only): `.github/workflows/signing-spike.yml`

**Interfaces:**
- Consumes: secrets `SIGNING_CERT_P12`, `SIGNING_CERT_PASSWORD` (Task 1).
- Produces: a written result for PR 2's plan — runner label and Xcode/Swift version that build Flick; whether untrusted signing works there or needs the trust fallback; the exact keychain commands that worked. Record it in the ledger (`.superpowers/sdd/2026-10-15-flick-code-signing/progress.md`) and in the PR 1 description.

- [ ] **Step 1: Create the scratch branch**

```sh
git switch -c chore/no-ref/signing-spike feature/no-ref/code-signing
```

- [ ] **Step 2: Write the workflow**

`.github/workflows/signing-spike.yml`:

```yaml
# Throwaway: does codesign accept the self-signed certificate on a GitHub runner?
name: signing spike
on:
  push:
    branches: [chore/no-ref/signing-spike]
permissions:
  contents: read
jobs:
  sign:
    runs-on: macos-26
    env:
      KEYCHAIN: ${{ runner.temp }}/signing.keychain-db
      NAME: Flick Code Signing
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - name: Toolchain
        run: sw_vers; xcodebuild -version; swift --version
      - name: Build
        run: swift build -c release
      - name: Assemble the bundle
        run: |
          mkdir -p build/Flick.app/Contents/MacOS
          cp support/Info.plist build/Flick.app/Contents/Info.plist
          cp "$(swift build -c release --show-bin-path)/Flick" build/Flick.app/Contents/MacOS/Flick
      - name: Import the certificate into a temporary keychain
        env:
          P12: ${{ secrets.SIGNING_CERT_P12 }}
          P12_PASSWORD: ${{ secrets.SIGNING_CERT_PASSWORD }}
        run: |
          test -n "$P12" || { echo "SIGNING_CERT_P12 is not set" >&2; exit 1; }
          test -n "$P12_PASSWORD" || { echo "SIGNING_CERT_PASSWORD is not set" >&2; exit 1; }
          kc_password=$(openssl rand -hex 16)
          security create-keychain -p "$kc_password" "$KEYCHAIN"
          security set-keychain-settings -lut 900 "$KEYCHAIN"
          security unlock-keychain -p "$kc_password" "$KEYCHAIN"
          printf '%s' "$P12" | base64 --decode >"$RUNNER_TEMP/cert.p12"
          security import "$RUNNER_TEMP/cert.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign
          rm "$RUNNER_TEMP/cert.p12"
          security set-key-partition-list -S apple-tool:,apple: -s -k "$kc_password" "$KEYCHAIN" >/dev/null
          # shellcheck disable=SC2046
          security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
          security find-identity -p codesigning
      - name: Sign without trusting the certificate
        id: untrusted
        continue-on-error: true
        run: |
          hash=$(security find-identity -p codesigning | awk -v name="\"$NAME\"" 'index($0, name) { print $2; exit }')
          test -n "$hash"
          codesign --force --sign "$hash" build/Flick.app
          codesign --verify --strict build/Flick.app
          codesign -dr - build/Flick.app
      - name: Fallback - trust it for code signing, then sign
        if: steps.untrusted.outcome == 'failure'
        run: |
          security find-certificate -c "$NAME" -p "$KEYCHAIN" >"$RUNNER_TEMP/cert.pem"
          sudo security add-trusted-cert -d -r trustRoot -p codeSign -k /Library/Keychains/System.keychain "$RUNNER_TEMP/cert.pem"
          hash=$(security find-identity -p codesigning | awk -v name="\"$NAME\"" 'index($0, name) { print $2; exit }')
          codesign --force --sign "$hash" build/Flick.app
          codesign --verify --strict build/Flick.app
          codesign -dr - build/Flick.app
      - name: Delete the keychain
        if: always()
        run: security delete-keychain "$KEYCHAIN" || true
```

- [ ] **Step 3: Commit and push (user)**

Stage: `git add .github/workflows/signing-spike.yml`. Hand over:

```sh
gitcs 'ci: throwaway signing spike'
git push -u origin chore/no-ref/signing-spike
```

- [ ] **Step 4: Watch the run**

Run: `gh run list --branch chore/no-ref/signing-spike --limit 1` then `gh run watch <id> --exit-status` and `gh run view <id> --log`
Expected outcomes and what to do:
- **Run never starts / "No runner matching macos-26":** change `runs-on` to `macos-15`, hand over a `gitcs 'ci: try macos-15'` + `git push`, watch again.
- **Build fails** (Swift too old for the package): record the Xcode version; PR 2 then selects a newer Xcode with `sudo xcode-select -s`; try `/Applications/Xcode_26*.app` in a follow-up commit the same way.
- **`untrusted` succeeds:** record the `designated =>` line. Done.
- **`untrusted` fails, fallback succeeds:** record the error from `untrusted` and that PR 2 needs the trust step.
- **Both fail:** stop and report to the user with the log; do not start PR 2.

- [ ] **Step 5: Record and clean up**

Write the result (runner, `xcodebuild -version`, `swift --version`, which path signed, `designated =>` line) into the ledger. Then hand over to the user:

```sh
git switch feature/no-ref/code-signing
git push origin --delete chore/no-ref/signing-spike
git branch -D chore/no-ref/signing-spike
```

Run: `git branch --all | grep signing-spike`
Expected: nothing.

---

### Task 3: Bundle ID rename with settings migration

**Files:**
- Create: `Sources/FlickCore/SettingsMigration.swift`, `Tests/FlickCoreTests/SettingsMigrationTests.swift`
- Modify: `Sources/FlickCore/FlickSettings.swift`, `Sources/Flick/main.swift`, `Sources/Flick/EventTap.swift:20,136`, `Sources/Flick/WindowMover.swift:8`, `support/Info.plist:8`, `Tests/FlickCoreTests/FlickSettingsTests.swift:9`, `README.md`

**Interfaces:**
- Consumes: `FlickSettings(defaults:)` and its private keys (existing).
- Produces: `FlickSettings.storedKeys: [String]` (internal static); `public enum SettingsMigration` with `public static let oldDomain: String` (`"local.personal.flick"`) and `public static func run(from old: UserDefaults, to new: UserDefaults)`.

The spec's "key-value store protocol with a fake" is a temporary `UserDefaults` suite here, as `FlickSettingsTests` already does: same isolation, no protocol to maintain.

- [ ] **Step 1: Write the failing tests**

`Tests/FlickCoreTests/SettingsMigrationTests.swift`:

```swift
import Foundation
import Testing

@testable import FlickCore

@Suite struct SettingsMigrationTests {
    /// Runs `body` with two private defaults domains, old and new, and removes them afterwards.
    func withDomains(_ body: (_ old: UserDefaults, _ new: UserDefaults) -> Void) {
        let names = [UUID(), UUID()].map { "io.github.bergcyrill.flick.tests.\($0.uuidString)" }
        let old = UserDefaults(suiteName: names[0])!
        let new = UserDefaults(suiteName: names[1])!
        defer {
            old.removePersistentDomain(forName: names[0])
            new.removePersistentDomain(forName: names[1])
        }
        body(old, new)
    }

    @Test func copiesTheSettingsWhenTheNewDomainIsEmpty() {
        withDomains { old, new in
            var settings = FlickSettings()
            settings.livePreview = false
            settings.scrollButton = .right
            settings.save(to: old)
            SettingsMigration.run(from: old, to: new)
            #expect(FlickSettings(defaults: new) == settings)
        }
    }

    @Test func carriesTheOldSwitchOver() {
        withDomains { old, new in
            old.set(false, forKey: "scrollWhileDragging")
            SettingsMigration.run(from: old, to: new)
            #expect(FlickSettings(defaults: new).scrollButton == .off)
        }
    }

    @Test func neverOverwritesSettingsInTheNewDomain() {
        withDomains { old, new in
            old.set(false, forKey: "livePreview")
            old.set(false, forKey: "swipeToSnap")
            new.set(true, forKey: "livePreview")
            SettingsMigration.run(from: old, to: new)
            #expect(new.object(forKey: "livePreview") as? Bool == true)
            #expect(new.object(forKey: "swipeToSnap") == nil)
        }
    }

    @Test func runsOnlyOnce() {
        withDomains { old, new in
            SettingsMigration.run(from: old, to: new)
            old.set(false, forKey: "livePreview")
            SettingsMigration.run(from: old, to: new)
            #expect(new.object(forKey: "livePreview") == nil)
        }
    }

    @Test func copiesNothingWhenTheOldDomainIsEmpty() {
        withDomains { old, new in
            SettingsMigration.run(from: old, to: new)
            #expect(FlickSettings.storedKeys.allSatisfy { new.object(forKey: $0) == nil })
        }
    }

    @Test func leavesOtherKeysBehind() {
        withDomains { old, new in
            old.set(false, forKey: "livePreview")
            old.set(true, forKey: "NSStatusItem Visible Item-0")
            SettingsMigration.run(from: old, to: new)
            #expect(new.object(forKey: "livePreview") as? Bool == false)
            #expect(new.object(forKey: "NSStatusItem Visible Item-0") == nil)
        }
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `nix develop -c swift test --filter SettingsMigrationTests`
Expected: compile error — `cannot find 'SettingsMigration' in scope` and `type 'FlickSettings' has no member 'storedKeys'`.

- [ ] **Step 3: Implement**

In `Sources/FlickCore/FlickSettings.swift`, after `oldScrollKey`:

```swift
    /// Every key `init(defaults:)` reads.
    static var storedKeys: [String] { keys.map(\.0) + [scrollButtonKey, oldScrollKey] }
```

`Sources/FlickCore/SettingsMigration.swift`:

```swift
import Foundation

/// Carries the settings over from Flick's first bundle ID: UserDefaults are kept per bundle ID,
/// so without this the move to `io.github.bergcyrill.flick` would reset them.
public enum SettingsMigration {
    /// The bundle ID, and with it the defaults domain, before releases existed.
    public static let oldDomain = "local.personal.flick"
    static let doneKey = "settingsMigratedFromOldDomain"

    /// Copies the settings from `old` to `new`, once. Does nothing when `new` already holds a
    /// setting: the user has changed something since, and that wins.
    public static func run(from old: UserDefaults, to new: UserDefaults) {
        guard !new.bool(forKey: doneKey) else { return }
        new.set(true, forKey: doneKey)
        let keys = FlickSettings.storedKeys
        guard !keys.contains(where: { new.object(forKey: $0) != nil }) else { return }
        for key in keys {
            if let value = old.object(forKey: key) {
                new.set(value, forKey: key)
            }
        }
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `nix develop -c swift test --filter SettingsMigrationTests`
Expected: 6 tests pass.

- [ ] **Step 5: Rename the bundle ID and run the migration at launch**

- `support/Info.plist` line 8: `<string>io.github.bergcyrill.flick</string>`.
- `Sources/Flick/EventTap.swift` lines 20 and 136, `Sources/Flick/WindowMover.swift` line 8: `subsystem: "io.github.bergcyrill.flick"`.
- `Tests/FlickCoreTests/FlickSettingsTests.swift` line 9: `"io.github.bergcyrill.flick.tests.\(UUID().uuidString)"`.
- `Sources/Flick/main.swift` becomes:

```swift
import AppKit
import FlickCore

// Before anything reads the settings: carry them over from the old bundle ID, once.
if let old = UserDefaults(suiteName: SettingsMigration.oldDomain) {
    SettingsMigration.run(from: old, to: .standard)
}

let app = NSApplication.shared
let delegate = MenuBarApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

Run: `grep -rn "local.personal.flick" Sources Tests support README.md Taskfile.yml`
Expected: only `Sources/FlickCore/SettingsMigration.swift`.

- [ ] **Step 6: README upgrade note and checklist**

After the Accessibility paragraph in *Getting started*, add:

```markdown
**Upgrading from a build before the bundle ID change** (`local.personal.flick` →
`io.github.bergcyrill.flick`): settings carry over on first launch, but macOS sees a new app.
Remove the old *Flick* from *Accessibility*, grant the new one, and turn *Launch at login* on
again in Flick's settings.
```

Add to *Manual test checklist*:

```markdown
- [ ] First launch after the bundle ID change: settings changed before it are still set.
```

- [ ] **Step 7: Manual check (user)**

Hand over: before installing, set a non-default value with the old build still around (e.g. `defaults write local.personal.flick livePreview -bool false`), then `nix develop -c task run`, grant Accessibility to the new entry, open *Settings…*: *Show live preview* is off. Afterwards `defaults read io.github.bergcyrill.flick` shows `settingsMigratedFromOldDomain = 1`.

- [ ] **Step 8: Verify and commit**

Run: `nix develop -c sh -c 'task format && task test && task lint && task build'`
Expected: all pass.

Stage: `git add Sources/FlickCore/SettingsMigration.swift Sources/FlickCore/FlickSettings.swift Tests/FlickCoreTests/SettingsMigrationTests.swift Tests/FlickCoreTests/FlickSettingsTests.swift Sources/Flick/main.swift Sources/Flick/EventTap.swift Sources/Flick/WindowMover.swift support/Info.plist README.md`. Hand over:

```sh
gitcs 'feat(app): move to bundle ID io.github.bergcyrill.flick and carry settings over'
```

---

### Task 4: Signed bundle with version stamping, version in the app

**Files:**
- Create: `scripts/sign-app.sh`, `Sources/Flick/AppVersion.swift`
- Modify: `Taskfile.yml` (`vars`, `bundle`), `support/Info.plist` (version placeholders), `Sources/Flick/MenuBarApp.swift`, `Sources/Flick/SettingsWindow.swift`, `README.md`

**Interfaces:**
- Consumes: the *Flick Code Signing* identity (Task 1); bundle ID (Task 3).
- Produces (PR 2 relies on these): `scripts/sign-app.sh <app>` — signs with the first identity named `$FLICK_SIGNING_NAME` (default `Flick Code Signing`) from the keychain search list, else ad-hoc with a warning on stderr; always ends with `codesign --verify --strict`. `task bundle VERSION=<x.y.z> BUILD=<n>` overrides the stamped version. `AppVersion.short`, `AppVersion.build: String`.

- [ ] **Step 1: Write `scripts/sign-app.sh`**

```bash
#!/usr/bin/env bash
# Signs an app bundle with the "Flick Code Signing" certificate from the keychain, so macOS
# keeps Flick's Accessibility permission across builds. Without the certificate it signs
# ad-hoc and says so. FLICK_SIGNING_NAME picks another certificate name.
set -euo pipefail

app=$1
name=${FLICK_SIGNING_NAME:-Flick Code Signing}

# By hash: codesign rejects a name that matches more than one certificate. Without -v, so the
# self-signed (untrusted) certificate is listed too.
hash=$(security find-identity -p codesigning | awk -v name="\"$name\"" 'index($0, name) { print $2; exit }')

if [[ -n $hash ]]; then
  codesign --force --sign "$hash" "$app"
else
  echo "warning: no \"$name\" certificate in the keychain; signing ad-hoc." >&2
  echo "warning: macOS will ask for Accessibility again after this build (README → Code signing)." >&2
  codesign --force --sign - "$app"
fi
codesign --verify --strict "$app"
```

Run: `chmod +x scripts/sign-app.sh && nix develop -c shellcheck scripts/sign-app.sh`
Expected: no output.

- [ ] **Step 2: Stamp the version and sign in `task bundle`**

`support/Info.plist`: `CFBundleShortVersionString` → `0.0.0`, `CFBundleVersion` → `0` (always overwritten by `task bundle`).

`Taskfile.yml`, `vars` and `bundle`:

```yaml
vars:
  APP: build/Flick.app
  # `task release` passes the real version; local builds are "<last tag>-dev".
  VERSION:
    sh: tag=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || echo v0.0.0); echo "${tag#v}-dev"
  BUILD:
    sh: git rev-list --count HEAD
```

```yaml
  bundle:
    desc: Assemble build/Flick.app, stamp its version and sign it
    deps: [build]
    cmds:
      - rm -rf {{.APP}}
      - mkdir -p {{.APP}}/Contents/MacOS
      - cp support/Info.plist {{.APP}}/Contents/Info.plist
      - plutil -replace CFBundleShortVersionString -string "{{.VERSION}}" {{.APP}}/Contents/Info.plist
      - plutil -replace CFBundleVersion -string "{{.BUILD}}" {{.APP}}/Contents/Info.plist
      - cp "$(swift build -c release --show-bin-path)/Flick" {{.APP}}/Contents/MacOS/Flick
      - scripts/sign-app.sh {{.APP}}
```

- [ ] **Step 3: Read the version in the app**

`Sources/Flick/AppVersion.swift`:

```swift
import Foundation

/// The version `task bundle` stamped into Info.plist.
enum AppVersion {
    static let short = info("CFBundleShortVersionString")
    static let build = info("CFBundleVersion")

    private static func info(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "?"
    }
}
```

`Sources/Flick/MenuBarApp.swift`, in `buildMenu()` right after `menu.autoenablesItems = false`:

```swift
        let versionLine = NSMenuItem(title: "Flick \(AppVersion.short)", action: nil, keyEquivalent: "")
        versionLine.isEnabled = false
        menu.addItem(versionLine)
        menu.addItem(.separator())
```

`Sources/Flick/SettingsWindow.swift`, the last `Section` becomes:

```swift
            Section {
                Text("Fullscreen windows are always left alone. Changes apply from the next gesture.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Version \(AppVersion.short) (\(AppVersion.build))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
```

and the frame height goes from 560 to 590: `.frame(width: 480, height: 590)`.

- [ ] **Step 4: README**

Replace the Accessibility paragraph in *Getting started* (the one ending "…run `task run` again and re-enable it.") with:

```markdown
On first launch Flick asks for Accessibility access. Enable it under **System Settings →
Privacy & Security → Accessibility**; Flick picks it up within a few seconds. `task bundle`
signs with the *Flick Code Signing* certificate when the keychain has it (see *Code signing*),
so the permission survives rebuilds. Without it the build is signed ad-hoc and says so; after
each rebuild remove Flick from that list, run `task run` again and re-enable it.
```

Add to *Manual test checklist*:

```markdown
- [ ] Rebuild after a code change (`task run`): Accessibility stays granted, no prompt.
- [ ] The menu's first line shows *Flick &lt;version&gt;*; the settings window's footer shows *Version &lt;version&gt; (&lt;build&gt;)* without scrolling.
```

- [ ] **Step 5: Check stamping and signature**

Run:

```sh
nix develop -c task bundle
plutil -extract CFBundleShortVersionString raw build/Flick.app/Contents/Info.plist
plutil -extract CFBundleVersion raw build/Flick.app/Contents/Info.plist
codesign -dr - build/Flick.app
nix develop -c task bundle VERSION=1.2.3 BUILD=99
plutil -extract CFBundleShortVersionString raw build/Flick.app/Contents/Info.plist
```

Expected: `0.0.0-dev` (no tags yet), the output of `git rev-list --count HEAD`, `designated => identifier "io.github.bergcyrill.flick" and certificate leaf = H"…"`, then `1.2.3`.

- [ ] **Step 6: Check the ad-hoc fallback**

Run: `FLICK_SIGNING_NAME="No Such Certificate" scripts/sign-app.sh build/Flick.app; echo "exit $?"; codesign -dr - build/Flick.app`
Expected: the two `warning:` lines, `exit 0`, and a designated requirement with `cdhash H"…"` instead of `certificate leaf`.

- [ ] **Step 7: Manual check (user)**

Hand over: `nix develop -c task run`; menu shows *Flick 0.0.0-dev* first; *Settings…* shows *Version 0.0.0-dev (<n>)* at the bottom without scrolling (if it scrolls, raise the height in 10 pt steps and say so). Then change any comment in `Sources/Flick/MenuBarApp.swift`, `task run` again, revert the comment: Accessibility still granted, no prompt.

- [ ] **Step 8: Verify and commit**

Run: `nix develop -c sh -c 'task format && task test && task lint && task bundle'`
Expected: all pass, and `task bundle` prints no `warning:`.

Two commits. First stage `git add scripts/sign-app.sh Taskfile.yml support/Info.plist` and hand over:

```sh
gitcs 'build: sign the bundle with the Flick certificate and stamp its version'
```

Then `git add Sources/Flick/AppVersion.swift Sources/Flick/MenuBarApp.swift Sources/Flick/SettingsWindow.swift README.md` and:

```sh
gitcs 'feat(app): show the version in the menu and the settings window'
```

---

## After the last task

Whole-branch review (Opus subagent) against the spec's PR 1 row and this plan's Review Focus. Then, when the user asks: push `feature/no-ref/code-signing` and open PR 1. The description explains why (Accessibility re-grants after every build; versions users can report), lists the spike result from Task 2, and the one-time cost for existing users (new Accessibility entry, *Launch at login* again).
