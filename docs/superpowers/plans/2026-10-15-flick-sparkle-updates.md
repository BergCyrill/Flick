# Flick Sparkle Updates Implementation Plan (PR 3 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Flick updates itself: it checks GitHub once a day, shows a found update as a menu item instead of a window, installs it on request with the Accessibility permission intact, and every release publishes a signed `appcast.xml` next to its DMG.

**Architecture:** Sparkle 2.10.0 via SwiftPM, embedded in `Contents/Frameworks` and signed inside-out with the Flick certificate. `Sources/Flick/Updater.swift` wraps `SPUStandardUpdaterController` and implements Sparkle's gentle reminders; `MenuBarApp` shows *Check for Updates…* and *Update to X…*, the settings window a toggle. `scripts/make-appcast.sh` writes a one-item appcast signed with `sign_update` (key from the secret on stdin, or the keychain) and verifies the signature with `openssl` against the app's `SUPublicEDKey`; `task release` calls it and uploads the appcast. A maintainer script creates the EdDSA key once.

**Tech Stack:** Swift 6 (Xcode toolchain), SwiftPM, Sparkle 2.10.0, AppKit, SwiftUI; bash, `sign_update`/`generate_keys` (Sparkle tarball as a flake input), `openssl`, `install_name_tool`, `codesign`, `xmllint`, git-cliff; GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-15-flick-release-signing-updates-design.md` — *Updates*, the update key, the appcast check under *Testing*, and *Local end-to-end update*. Amended on this branch with what the planning experiments found (committed in Task 1).

## Global Constraints

- Sparkle **2.10.0** everywhere: SwiftPM `exact: "2.10.0"` (Flick target only) and the flake input `https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz` (`flake = false`; verified: Nix fetches it, `bin/sign_update` runs from the store).
- Swift 6: `final class Updater: NSObject, @preconcurrency SPUStandardUserDriverDelegate` — without `@preconcurrency` the conformance is a compile error (verified). `FlickCore` and the tests don't import Sparkle.
- `swift build -c release --show-bin-path` holds `Flick` and `Sparkle.framework`; the binary loads `@rpath/Sparkle.framework/Versions/B/Sparkle` and has only `@loader_path` and toolchain rpaths, so the bundle adds `@executable_path/../Frameworks` (verified).
- Signing order (no `--deep` when signing): `XPCServices/Installer.xpc`, `XPCServices/Downloader.xpc` (with `--preserve-metadata=entitlements`), `Autoupdate`, `Updater.app` (all under `Sparkle.framework/Versions/B`), then `Sparkle.framework`, then the app. Verify with `codesign --verify --strict --deep`. The app's designated requirement stays `identifier "io.github.bergcyrill.flick" and certificate leaf = H"1f4706c915a7c15904d0f2201d53e9324f321f81"`.
- `Info.plist`: `SUFeedURL` = `https://github.com/BergCyrill/Flick/releases/latest/download/appcast.xml`; `SUPublicEDKey` = the key printed in Task 1; `SUEnableAutomaticChecks` = true. No automatic download or install.
- Update key: keychain account **`io.github.bergcyrill.flick`**; GitHub secret **`SPARKLE_ED_PRIVATE_KEY`**; the private key reaches `sign_update` only on stdin (`--ed-key-file -`) or from the keychain, never as a file in CI.
- Appcast: one item; `sparkle:version` = build number, `sparkle:shortVersionString`, `sparkle:minimumSystemVersion` from `LSMinimumSystemVersion` (14.0), description = release notes as HTML, enclosure = `https://github.com/BergCyrill/Flick/releases/download/vX.Y.Z/Flick-X.Y.Z.dmg` with `sign_update`'s `sparkle:edSignature`/`length`. Signature verified with `openssl pkeyutl -verify -rawin` against `SUPublicEDKey` (verified with a throwaway key: accepts the right file, rejects a changed one).
- Copy: menu **Check for Updates…**, **Update to &lt;version&gt;…** (first after the version line, hidden when nothing is pending); settings toggle **Check for updates automatically**, hint **Once a day, from GitHub. Flick asks before installing anything.**
- Shell: `#!/usr/bin/env bash`, `set -euo pipefail`, shellcheck clean; capture `security`/tool output before matching (PR 1 finding).
- Commands in the dev shell: `nix develop -c …`. `task format`, `task test`, `task lint` (and `task bundle` where the app changes) pass at the end of every task.
- Git: branch `feature/no-ref/sparkle-updates` (exists, off `main` at the v0.1.0 merge). **Never run `git commit` yourself**: stage, hand over `gitcs '<message>'`, wait for "done", check `git log --oneline -1`. Push and PR only when the user asks.

## Review Focus

1. **A private key that doesn't match the app's `SUPublicEDKey`** (replaced secret, wrong key pasted) must fail the release before publishing — otherwise every installed copy rejects every update from then on. Pinned by Task 4 Step 6 (throwaway key in `SPARKLE_ED_PRIVATE_KEY` → `make-appcast.sh` fails).
2. **No update key at all**: `DRY=1` still runs to the end with an unsigned, marked appcast; a real release fails. Pinned by Task 4 Step 7.
3. **Signing without the certificate** (ad-hoc fallback) must still give a bundle that passes `codesign --verify --strict --deep` with the embedded framework. Pinned by Task 2 Step 7.
4. **A scheduled check that finds an update** must not open a window; the menu shows *Update to …*, and choosing it (or *Check for Updates…*) opens Sparkle's dialog. Pinned by Task 5 Steps 4–5 (local end-to-end).
5. **Installing an update** must relaunch the new version without *Open Anyway* and with Accessibility still granted; and with the real feed still 404 (v0.1.0 has no appcast), launching must not show an error. Pinned by Task 5 Step 5 and Task 2 Step 8.

---

## File structure

| File | Task | Responsibility |
|---|---|---|
| spec (edited), this plan | 1 | Committed first |
| `flake.nix`, `flake.lock` | 1 | Sparkle tarball input; its `bin` on `PATH` |
| `scripts/make-update-key.sh` (new) | 1 | Creates the update key once |
| `Package.swift`, `Package.resolved` | 2 | Sparkle dependency |
| `Sources/Flick/Updater.swift` (new) | 2, 3 | Wraps Sparkle; gentle reminders |
| `Sources/Flick/MenuBarApp.swift` | 2, 3 | Menu items, menu delegate |
| `support/Info.plist` | 2 | Feed URL, public key, automatic checks |
| `Taskfile.yml` | 2 | `bundle` embeds the framework, adds the rpath |
| `scripts/sign-app.sh` | 2 | Signs nested code first |
| `Sources/Flick/SettingsStore.swift`, `Sources/Flick/SettingsWindow.swift` | 3 | Automatic-check toggle |
| `support/release-notes.html.tera` (new) | 4 | HTML notes template |
| `scripts/make-appcast.sh` (new) | 4 | Writes, signs and verifies the appcast |
| `scripts/release.sh` | 4 | Builds and uploads the appcast |
| `.github/workflows/ci.yml`, `release.yml` | 4 | Pass `SPARKLE_ED_PRIVATE_KEY` |
| `README.md` | 1, 3, 4 | Update key, updates, checklist |

---

### Task 1: Sparkle tools and the update key

**Files:**
- Modify: `flake.nix`, `flake.lock`, `README.md`; commit the spec and this plan
- Create: `scripts/make-update-key.sh`

**Interfaces:**
- Produces: `generate_keys`, `sign_update` on the dev shell's `PATH`; the key in the maintainer's keychain (account `io.github.bergcyrill.flick`); secret `SPARKLE_ED_PRIVATE_KEY`; the public key (base64, 44 chars) recorded in the ledger for Task 2.

- [ ] **Step 1: Commit the spec amendment and this plan**

Stage: `git add docs/superpowers/specs/2026-10-15-flick-release-signing-updates-design.md docs/superpowers/plans/2026-10-15-flick-sparkle-updates.md`. Hand over:

```sh
gitcs 'docs: plan in-app updates and amend the spec with what planning found'
```

- [ ] **Step 2: Sparkle's tools in the dev shell**

`flake.nix`:

```nix
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # Sparkle's command-line tools (sign_update, generate_keys). Keep the version equal to the
    # Sparkle package in Package.swift.
    sparkle = {
      url = "https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, sparkle, ... }:
```

and in the `shellHook`, first line:

```nix
            export PATH="${sparkle}/bin:$PATH"
```

Run: `nix develop -c sh -c 'which sign_update generate_keys; sign_update --help | head -1'`
Expected: both under `/nix/store/…-source/bin/`; `OVERVIEW: Sign or verify an update file using your signing keys.`; `flake.lock` gains a `sparkle` node.

- [ ] **Step 3: Write `scripts/make-update-key.sh`**

First run `nix develop -c generate_keys --account io.github.bergcyrill.flick -p; echo "exit $?"` (a read-only lookup) and note the exit code and message for a missing key; the refusal check below relies on a non-zero exit. If it exits 0 without a key, ledger a ruling and test for a non-empty base64 output instead.

```bash
#!/usr/bin/env bash
# Creates Flick's EdDSA key pair for Sparkle updates, once: the private key goes into the login
# keychain and into a file for the password manager and the GitHub secret; the public key goes
# into support/Info.plist. Losing the private key means installed copies can't be updated any
# more. See README → Code signing.
set -euo pipefail

account=io.github.bergcyrill.flick
out=${1:-"$HOME/flick-update-key"}

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
```

Run: `chmod +x scripts/make-update-key.sh && nix develop -c task lint`
Expected: PASS.

- [ ] **Step 4: README**

At the end of *Code signing*, add:

````markdown
Updates are signed with a separate EdDSA key, created once the same way:

```sh
scripts/make-update-key.sh      # login keychain, ~/flick-update-key, prints the public key
```

Keep the private key in the password manager and the `SPARKLE_ED_PRIVATE_KEY` secret; the
public key is `SUPublicEDKey` in `support/Info.plist`. Losing the private key means installed
copies can't be updated any more.
````

- [ ] **Step 5: The user creates the key**

Hand over: `nix develop -c scripts/make-update-key.sh`, then the printed steps (password manager, `gh secret set`, `rm -rf ~/flick-update-key`). macOS may ask whether `generate_keys` may use the keychain. Wait for "done".

Run: `gh secret list` and `nix develop -c generate_keys --account io.github.bergcyrill.flick -p`
Expected: `SPARKLE_ED_PRIVATE_KEY` listed; a 44-character base64 public key. Record it in the ledger as `Task 1: SUPublicEDKey = <key>`.

- [ ] **Step 6: The script refuses a second run**

Run: `nix develop -c scripts/make-update-key.sh /tmp/flick-update-key-again; echo "exit $?"; ls /tmp/flick-update-key-again`
Expected: `error: the keychain already has an update key …`, `exit 1`, no such directory.

- [ ] **Step 7: Verify and commit**

Run: `nix develop -c sh -c 'task format && task test && task lint'`
Expected: all pass.

Stage: `git add flake.nix flake.lock scripts/make-update-key.sh README.md`. Hand over:

```sh
gitcs 'build: add Sparkle tools and a script that creates the update key'
```

---

### Task 2: Sparkle in the app bundle, *Check for Updates…*

**Files:**
- Create: `Sources/Flick/Updater.swift`
- Modify: `Package.swift`, `Package.resolved`, `Sources/Flick/MenuBarApp.swift`, `support/Info.plist`, `Taskfile.yml` (`bundle`), `scripts/sign-app.sh`

**Interfaces:**
- Consumes: the public key from Task 1's ledger line.
- Produces: `@MainActor final class Updater: NSObject` with `init()`, `var canCheckForUpdates: Bool`, `var automaticallyChecksForUpdates: Bool { get set }`, `func checkForUpdates()`. `MenuBarApp` conforms to `NSMenuDelegate` and refreshes items in `menuNeedsUpdate(_:)`. `sign-app.sh` signs an embedded `Sparkle.framework` if present.

- [ ] **Step 1: Dependency**

`Package.swift`:

```swift
let package = Package(
    name: "Flick",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Keep equal to the Sparkle input in flake.nix.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "FlickCore"),
        .executableTarget(
            name: "Flick", dependencies: ["FlickCore", .product(name: "Sparkle", package: "Sparkle")]),
        .testTarget(name: "FlickCoreTests", dependencies: ["FlickCore"]),
    ]
)
```

- [ ] **Step 2: `Sources/Flick/Updater.swift`**

```swift
import Sparkle

/// Sparkle's updater: checks the appcast on GitHub and installs updates the user accepts.
@MainActor
final class Updater: NSObject {
    private var controller: SPUStandardUpdaterController?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    /// False while a check or an update is in progress.
    var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }

    /// Sparkle keeps this in its own defaults keys.
    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Checks now and shows Sparkle's window: up to date, an error, or the update to install.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
```

- [ ] **Step 3: Menu item**

`Sources/Flick/MenuBarApp.swift`:
- class declaration: `final class MenuBarApp: NSObject, NSApplicationDelegate, NSMenuDelegate {`
- properties, after `private let pauseItem …`:

```swift
    private let checkItem = NSMenuItem(title: "Check for Updates…", action: nil, keyEquivalent: "")
    private let updater = Updater()
```

- in `buildMenu()`, right after `menu.addItem(settingsItem)`:

```swift
        checkItem.target = self
        checkItem.action = #selector(checkForUpdates)
        menu.addItem(checkItem)
```

  and before `item.menu = menu`: `menu.delegate = self`.
- new methods, after `openSettings()`:

```swift
    @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        checkItem.isEnabled = updater.canCheckForUpdates
    }
```

- [ ] **Step 4: `Info.plist`**

Add before `</dict>` (keys sorted with the existing ones), using the public key from the ledger:

```xml
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUFeedURL</key>
    <string>https://github.com/BergCyrill/Flick/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>PUBLIC_KEY_FROM_TASK_1</string>
```

(`PUBLIC_KEY_FROM_TASK_1` is the literal value recorded in the ledger, not a placeholder to keep.)

Run: `plutil -lint support/Info.plist`
Expected: `support/Info.plist: OK`.

- [ ] **Step 5: Embed the framework in `task bundle`**

`Taskfile.yml` `bundle`:

```yaml
  bundle:
    desc: Assemble build/Flick.app, stamp its version and sign it
    deps: [build]
    vars:
      BIN:
        sh: swift build -c release --show-bin-path
    cmds:
      - rm -rf {{.APP}}
      - mkdir -p {{.APP}}/Contents/MacOS {{.APP}}/Contents/Frameworks
      - cp support/Info.plist {{.APP}}/Contents/Info.plist
      - plutil -replace CFBundleShortVersionString -string "{{.VERSION}}" {{.APP}}/Contents/Info.plist
      - plutil -replace CFBundleVersion -string "{{.BUILD}}" {{.APP}}/Contents/Info.plist
      - cp "{{.BIN}}/Flick" {{.APP}}/Contents/MacOS/Flick
      - ditto "{{.BIN}}/Sparkle.framework" {{.APP}}/Contents/Frameworks/Sparkle.framework
      - install_name_tool -add_rpath @executable_path/../Frameworks {{.APP}}/Contents/MacOS/Flick
      - scripts/sign-app.sh {{.APP}}
```

- [ ] **Step 6: Sign nested code in `scripts/sign-app.sh`**

Replace everything from `if [[ -n $hash ]]; then` to the end with:

```bash
if [[ -n $hash ]]; then
  identity=$hash
else
  echo "warning: no \"$name\" certificate in the keychain; signing ad-hoc." >&2
  echo "warning: macOS will ask for Accessibility again after this build (README → Code signing)." >&2
  identity=-
fi

sign() {
  codesign --force --sign "$identity" "$@"
}

# Nested code first, the app last. `--deep` would sign in the wrong order and drop the
# Downloader service's entitlements.
sparkle=$app/Contents/Frameworks/Sparkle.framework
if [[ -d $sparkle ]]; then
  sign "$sparkle/Versions/B/XPCServices/Installer.xpc"
  sign --preserve-metadata=entitlements "$sparkle/Versions/B/XPCServices/Downloader.xpc"
  sign "$sparkle/Versions/B/Autoupdate"
  sign "$sparkle/Versions/B/Updater.app"
  sign "$sparkle"
fi
sign "$app"
codesign --verify --strict --deep "$app"
```

- [ ] **Step 7: Check the bundle**

Run:

```sh
nix develop -c task bundle
codesign -dr - build/Flick.app 2>&1 | grep designated
for p in Versions/B/XPCServices/Installer.xpc Versions/B/XPCServices/Downloader.xpc Versions/B/Autoupdate Versions/B/Updater.app .; do
  codesign -dvv "build/Flick.app/Contents/Frameworks/Sparkle.framework/$p" 2>&1 | grep -m1 Authority || echo "unsigned: $p"
done
otool -l build/Flick.app/Contents/MacOS/Flick | grep -A2 LC_RPATH | grep "@executable_path"
FLICK_SIGNING_NAME="No Such Certificate" scripts/sign-app.sh build/Flick.app; echo "adhoc exit $?"
nix develop -c task bundle
```

Expected: the designated requirement from *Global Constraints*; five `Authority=Flick Code Signing`; `path @executable_path/../Frameworks`; the ad-hoc run prints the two warnings and `adhoc exit 0` (deep verify passes ad-hoc too); the last `task bundle` re-signs with the certificate.

- [ ] **Step 8: Manual check (user)**

Hand over: `nix develop -c task run`.
- No Accessibility prompt; no update alert on launch (the real feed is 404 until the first release with an appcast, and background checks fail silently).
- The menu has *Check for Updates…* after *Settings…*. Choosing it opens Sparkle's window with an error like "An error occurred in retrieving update information" — expected until PR 3's release exists. While the window is open, the item is disabled.

- [ ] **Step 9: Verify and commit**

Run: `nix develop -c sh -c 'task format && task test && task lint && task bundle'`
Expected: all pass, no `warning:` from `sign-app.sh`.

Stage: `git add Package.swift Package.resolved Sources/Flick/Updater.swift Sources/Flick/MenuBarApp.swift support/Info.plist Taskfile.yml scripts/sign-app.sh`. Hand over:

```sh
gitcs 'feat(app): check for updates with Sparkle'
```

---

### Task 3: Scheduled updates in the menu, and the automatic-check toggle

**Files:**
- Modify: `Sources/Flick/Updater.swift`, `Sources/Flick/MenuBarApp.swift`, `Sources/Flick/SettingsStore.swift`, `Sources/Flick/SettingsWindow.swift`, `README.md`

**Interfaces:**
- Consumes: `Updater` (Task 2).
- Produces: `Updater: @preconcurrency SPUStandardUserDriverDelegate` with `private(set) var availableVersion: String?`; `SettingsStore(defaults:updater:)` with `@Published var checksForUpdates: Bool`.

- [ ] **Step 1: Gentle reminders in `Updater`**

Class declaration becomes `final class Updater: NSObject, @preconcurrency SPUStandardUserDriverDelegate {`; the doc comment gains a second line: `/// An update found by a scheduled check waits in the menu (Sparkle's gentle reminders) instead of opening a window over whatever the user is doing.`; `init` passes `userDriverDelegate: self`. Add, after `private var controller`:

```swift
    /// The version a scheduled check found, until the user looks at it or the session ends.
    private(set) var availableVersion: String?
```

and at the end of the class:

```swift
    // MARK: - SPUStandardUserDriverDelegate (called on the main thread)

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        if !handleShowingUpdate {
            availableVersion = update.displayVersionString
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
    }
```

- [ ] **Step 2: *Update to …* in the menu**

`MenuBarApp`:
- property: `private let updateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")`
- in `buildMenu()`, right after `menu.addItem(versionLine)`:

```swift
        updateItem.target = self
        updateItem.action = #selector(checkForUpdates)
        updateItem.isHidden = true
        menu.addItem(updateItem)
```

- `menuNeedsUpdate(_:)` becomes:

```swift
    func menuNeedsUpdate(_ menu: NSMenu) {
        if let version = updater.availableVersion {
            updateItem.title = "Update to \(version)…"
            updateItem.isHidden = false
        } else {
            updateItem.isHidden = true
        }
        checkItem.isEnabled = updater.canCheckForUpdates
    }
```

(Choosing it calls `checkForUpdates()`, which brings the waiting update into Sparkle's dialog.)

- [ ] **Step 3: The toggle**

`SettingsStore`: add after `launchAtLogin`'s block:

```swift
    /// Mirrors Sparkle's own setting.
    @Published var checksForUpdates: Bool {
        didSet { updater?.automaticallyChecksForUpdates = checksForUpdates }
    }
```

a stored `private let updater: Updater?`, and `init(defaults: UserDefaults = .standard, updater: Updater? = nil)` setting `self.updater = updater` and `checksForUpdates = updater?.automaticallyChecksForUpdates ?? false` before `launchAtLogin = …`.

`MenuBarApp`: `private let store = SettingsStore()` becomes `private lazy var store = SettingsStore(updater: updater)` (declared after `updater`).

`SettingsWindow.swift`, in `Section("General")` after the `if store.loginProblem != nil { … }` block:

```swift
                Toggle(isOn: $store.checksForUpdates) {
                    Self.label(
                        "Check for updates automatically",
                        hint: "Once a day, from GitHub. Flick asks before installing anything.")
                }
```

and `.frame(width: 480, height: 590)` → `.frame(width: 480, height: 640)`.

- [ ] **Step 4: README checklist**

Add:

```markdown
- [ ] *Check for updates automatically* off: `defaults read io.github.bergcyrill.flick SUEnableAutomaticChecks` prints 0; on again prints 1. The settings window shows everything without scrolling.
```

- [ ] **Step 5: Verify, manual check, commit**

Run: `nix develop -c sh -c 'task format && task test && task lint && task bundle'`
Expected: all pass.

Hand over: `nix develop -c task run`; the menu shows no *Update to …* item; the settings toggle is on; switching it writes `SUEnableAutomaticChecks` as in the checklist item; nothing scrolls (if it does, raise the height in 10 pt steps and say so). The reminder itself is exercised in Task 5.

Stage: `git add Sources/Flick/Updater.swift Sources/Flick/MenuBarApp.swift Sources/Flick/SettingsStore.swift Sources/Flick/SettingsWindow.swift README.md`. Hand over:

```sh
gitcs 'feat(app): show scheduled updates in the menu and let users turn checks off'
```

---

### Task 4: Signed appcast with every release

**Files:**
- Create: `support/release-notes.html.tera`, `scripts/make-appcast.sh`
- Modify: `scripts/release.sh`, `.github/workflows/ci.yml`, `.github/workflows/release.yml`, `README.md`

**Interfaces:**
- Consumes: `SUPublicEDKey` in the built app (Task 2); `sign_update` (Task 1).
- Produces: `scripts/make-appcast.sh <app> <dmg> <download-url> <notes.html> <out.xml>` — env `SPARKLE_ED_PRIVATE_KEY` (else keychain account `$FLICK_UPDATE_KEY_ACCOUNT`, default `io.github.bergcyrill.flick`, else only with `DRY` set: unsigned); exits 1 if the signature doesn't verify against the app's key. `task release` uploads `build/appcast.xml`. Task 5 calls `make-appcast.sh` with a localhost URL.

- [ ] **Step 1: HTML notes template**

`support/release-notes.html.tera`:

```
{% for group, commits in commits | group_by(attribute="group") %}<h3>{{ group | striptags | trim | upper_first }}</h3>
<ul>
{% for commit in commits %}<li>{% if commit.scope %}<b>{{ commit.scope }}:</b> {% endif %}{{ commit.message | upper_first | escape }}</li>
{% endfor %}</ul>
{% endfor %}
```

Run: `nix develop -c sh -c 'git-cliff --latest --strip all --body "$(cat support/release-notes.html.tera)"' | head -3`
Expected: `<h3>Features</h3>`, `<ul>`, `<li><b>core:</b> Scaffold Swift package, dev shell and global geometry</li>`.

- [ ] **Step 2: `scripts/make-appcast.sh`**

```bash
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
  fail "no update key: set SPARKLE_ED_PRIVATE_KEY or import the key into the keychain (README → Code signing)"
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
```

Run: `chmod +x scripts/make-appcast.sh && nix develop -c shellcheck scripts/make-appcast.sh`
Expected: no output.

- [ ] **Step 3: Use it in `scripts/release.sh`**

- After `printf '%s\n' "$notes" >"$notes_file"`, add:

```bash
git-cliff --unreleased --strip all --body "$(cat support/release-notes.html.tera)" \
  2>/dev/null >build/release-notes.html
scripts/make-appcast.sh "$app" "$dmg" \
  "https://github.com/BergCyrill/Flick/releases/download/$tag/Flick-$version.dmg" \
  build/release-notes.html build/appcast.xml
```

- The dry-run message becomes `echo "Dry run: would publish $tag with $dmg, build/appcast.xml and these notes:"`.
- `gh release create … "$dmg"` becomes `… "$dmg" build/appcast.xml`.

- [ ] **Step 4: CI gets the key**

In `.github/workflows/ci.yml` (step *Dry-run the release*) and `.github/workflows/release.yml` (step *Release*), add to the step's `env` (create `env:` in `ci.yml`):

```yaml
          SPARKLE_ED_PRIVATE_KEY: ${{ secrets.SPARKLE_ED_PRIVATE_KEY }}
```

Run: `nix develop -c task lint`
Expected: PASS (actionlint, shellcheck).

- [ ] **Step 5: Dry run, signed from the keychain**

Run: `nix develop -c task release DRY=1 > "$WORKSPACE/dry.log" 2>&1; echo "exit $?"; grep -E "Releasing|Dry run|warning:|error:" "$WORKSPACE/dry.log"; grep -E "sparkle:version|shortVersion|enclosure" build/appcast.xml`
Expected: exit 0 (macOS may ask once whether `sign_update` may use the keychain item — the user allows it); `Releasing Flick 0.2.0 (build <n>), dry run`; `Dry run: would publish v0.2.0 with build/Flick-0.2.0.dmg, build/appcast.xml …`; no `warning:`; the appcast has `<sparkle:version><n>`, `0.2.0` and an enclosure with `…/download/v0.2.0/Flick-0.2.0.dmg`, `sparkle:edSignature="…"` and `length="…"`.

- [ ] **Step 6: A mismatched key fails**

Run:

```sh
other=$(nix develop -c openssl genpkey -algorithm ed25519 -outform DER 2>/dev/null | tail -c 32 | base64)
SPARKLE_ED_PRIVATE_KEY=$other nix develop -c scripts/make-appcast.sh build/Flick.app build/Flick-0.2.0.dmg https://example.invalid/x.dmg build/release-notes.html "$WORKSPACE/bad.xml"; echo "exit $?"; ls "$WORKSPACE/bad.xml"
```

Expected: `error: the update signature doesn't match SUPublicEDKey in build/Flick.app/Contents/Info.plist; wrong private key?`, `exit 1`, no such file.

- [ ] **Step 7: No key at all**

Run: `FLICK_UPDATE_KEY_ACCOUNT=no-such-account DRY=1 nix develop -c scripts/make-appcast.sh build/Flick.app build/Flick-0.2.0.dmg https://example.invalid/x.dmg build/release-notes.html "$WORKSPACE/unsigned.xml"; echo "exit $?"; grep -c "unsigned: dry run" "$WORKSPACE/unsigned.xml"`, then the same without `DRY=1` (output path `$WORKSPACE/fail.xml`).
Expected: first: the `warning: … unsigned.` line, `exit 0`, `1`. Second: `error: no update key …`, `exit 1`, no `fail.xml`.

- [ ] **Step 8: README**

In *Installing*, replace the final paragraph with:

```markdown
From then on Flick checks for updates once a day and shows *Update to …* in its menu when one
is ready; installing it keeps the Accessibility permission and needs no *Open Anyway*. Flick
0.1.0 has no updater: install the next version by hand once.
```

In *Releases*, after "publishes `Flick-<version>.dmg`", add "and the `appcast.xml` Sparkle reads".

- [ ] **Step 9: Verify and commit**

Run: `nix develop -c sh -c 'task format && task test && task lint' && rm -f build/*.dmg build/appcast.xml build/release-notes.*`
Expected: all pass.

Stage: `git add support/release-notes.html.tera scripts/make-appcast.sh scripts/release.sh .github/workflows/ci.yml .github/workflows/release.yml README.md`. Hand over:

```sh
gitcs 'build: publish a signed appcast with every release'
```

---

### Task 5: Local end-to-end update (no commit)

**Files:** none in the repo; everything under `$WORKSPACE/e2e`.

**Interfaces:**
- Consumes: `task dmg`, `task bundle`, `scripts/make-appcast.sh` (Task 4), the keychain update key (Task 1).

- [ ] **Step 1: The newer version, served from localhost**

```sh
e2e=$WORKSPACE/e2e; rm -rf "$e2e"; mkdir -p "$e2e/feed" "$e2e/old"
nix develop -c task dmg VERSION=0.9.0 BUILD=9000
cp build/Flick-0.9.0.dmg "$e2e/feed/"
nix develop -c sh -c 'git-cliff --latest --strip all --body "$(cat support/release-notes.html.tera)"' 2>/dev/null >"$e2e/feed/notes.html"
nix develop -c scripts/make-appcast.sh build/Flick.app "$e2e/feed/Flick-0.9.0.dmg" http://localhost:8765/Flick-0.9.0.dmg "$e2e/feed/notes.html" "$e2e/feed/appcast.xml"
```

Expected: exit 0, an appcast with `<sparkle:version>9000` and an `edSignature`. Start the server in the background (`run_in_background`): `cd "$e2e/feed" && python3 -m http.server 8765 --bind 127.0.0.1`. `curl -sI http://localhost:8765/appcast.xml | head -1` → `HTTP/1.0 200 OK`.

- [ ] **Step 2: The older version, pointed at that feed**

```sh
nix develop -c task bundle VERSION=0.8.0 BUILD=8000
ditto build/Flick.app "$e2e/old/Flick.app"
pkill -x Flick || true
defaults write io.github.bergcyrill.flick SUFeedURL http://localhost:8765/appcast.xml
defaults write io.github.bergcyrill.flick SULastCheckTime -date "2020-01-01 00:00:00 +0000"
open "$e2e/old/Flick.app"
```

- [ ] **Step 3: User: the old version runs**

Hand over: the menu's first line is *Flick 0.8.0*; Accessibility granted without a prompt (same certificate).

- [ ] **Step 4: User: the scheduled check shows a reminder, not a window**

Wait up to 2 minutes without clicking anything. Expected: no Sparkle window appears; opening the menu shows *Update to 0.9.0…* under the version line. If nothing appears after 2 minutes, ledger it and continue with *Check for Updates…* in Step 5 (the reminder then stays unverified until the first real update).

- [ ] **Step 5: User: install**

Choose *Update to 0.9.0…* (or *Check for Updates…*). Expected: Sparkle's dialog with the HTML notes; *Install Update* → download, Flick quits and relaunches; the menu shows *Flick 0.9.0*; no *Open Anyway*; *Accessibility access granted*. Then `codesign -dr - "$e2e/old/Flick.app"` shows the pinned designated requirement and `plutil -extract CFBundleVersion raw "$e2e/old/Flick.app/Contents/Info.plist"` prints `9000`.

If Sparkle refuses the feed (App Transport Security or an insecure-feed error in its window or in `log show --last 5m --predicate 'process == "Flick"'`), ledger the message: the end-to-end check then moves to after the second release with an updater (spec, *Local end-to-end update*).

- [ ] **Step 6: Clean up**

Stop the server (TaskStop/kill). Then:

```sh
pkill -x Flick || true
defaults delete io.github.bergcyrill.flick SUFeedURL
defaults delete io.github.bergcyrill.flick SULastCheckTime
rm -rf "$e2e" build/Flick-0.9.0.dmg
nix develop -c task run
```

Expected: `defaults read io.github.bergcyrill.flick SUFeedURL` reports that the key doesn't exist; the normal dev build runs, Accessibility granted.

Ledger: `Task 5: e2e <result per Step 4 and 5>`; run `task-done` with `nix develop -c task test`.

---

## After the last task

1. Whole-branch review (Opus subagent) against the spec's *Updates* sections and this plan's Review Focus.
2. When the user asks: push and open PR 3; both CI jobs green (`release-dry` now verifies the appcast signature with the real key).
3. After the merge: `release.yml` publishes **v0.2.0** with `Flick-0.2.0.dmg` and `appcast.xml`; `curl -sL https://github.com/BergCyrill/Flick/releases/latest/download/appcast.xml` returns it. The user installs 0.2.0 by hand once (0.1.0 has no updater); from 0.3.0 on, updates arrive in the app.
