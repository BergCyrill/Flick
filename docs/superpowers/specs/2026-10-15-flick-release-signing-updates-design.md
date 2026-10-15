# Flick releases, signing and updates — design

- **Date:** 2026-10-15
- **Status:** draft, awaiting review
- **Builds on:** [Flick v1](2026-10-14-flick-v1-design.md)

## Goal

Flick is now used by people other than its author, and four things are missing:

1. **A version number** users can see and report.
2. **Releases** that happen on their own: every merge to `main` that changes behaviour publishes a
   DMG on GitHub Releases.
3. **Updates** from inside Flick, so users don't watch the releases page.
4. **A stable signature**, so macOS keeps the Accessibility permission across rebuilds and
   updates. Today `task bundle` signs ad-hoc; the permission is tied to the binary's hash, and
   every build has to be added again in *Privacy & Security → Accessibility*.

## Decisions

| Question | Decision |
|---|---|
| Who installs the DMG | Others too, not only the author |
| Apple Developer Program | No. A self-signed certificate now; Developer ID later is a configuration change |
| When to release | Every merge to `main` with a `feat`, `fix` or breaking commit |
| Tooling | Nix dev shell + `task`, git-cliff for versions and notes, Sparkle 2 for updates |
| Bundle ID | Renamed now, from `local.personal.flick` to `io.github.bergcyrill.flick` |
| Key backup | The author's password manager; nothing secret in the repo, not even encrypted |
| ADRs | None for this feature |

### Why not GPG or SSH keys from the hardware token

`codesign` signs only with an X.509 identity from a keychain. GPG and SSH keys can't be used. A
PIV certificate on the token would work locally, but CI can't reach the token, so every release
would need the author's machine — which contradicts automatic releases.

## Delivery

One spec, three PRs, each on its own branch from `main`:

| PR | Branch | Contents |
|---|---|---|
| 1 | `feature/no-ref/code-signing` | This spec, the signing spike, the certificate script, bundle ID rename and settings migration, signed `task bundle`, version stamping and display |
| 2 | `feature/no-ref/release-pipeline` | `task dmg`, `task release`, git-cliff config, `ci.yml`, `release.yml` |
| 3 | `feature/no-ref/sparkle-updates` | Sparkle dependency and embedding, updater adapter, menu and settings entries, appcast in `task release` |

PR 2 is the first to publish anything: its merge releases **v0.1.0** without an updater. PR 3's
merge releases the first version that can update itself. Users of v0.1.0 install that one by
hand once.

## Signing and keys

### The certificate

- **Self-signed**, common name *Flick Code Signing*, RSA 2048, valid 10 years, extended key
  usage *code signing*.
- Created by the author with `scripts/make-signing-cert.sh`, which:
  - generates the key and certificate with `openssl`;
  - writes a password-protected `.p12` outside the repo;
  - imports it into the login keychain;
  - creates the Sparkle EdDSA key pair (PR 3 adds this step);
  - prints what to store where: the `.p12` (base64), its password and the Sparkle private key
    go into the password manager **and** the GitHub secrets below; the Sparkle public key goes
    into `support/Info.plist`.
- `.gitignore` gains `*.p12`, `*.cer`, `*.pem` and `*.key` before anything is staged.

### Designated requirement

The default one stays: `identifier "io.github.bergcyrill.flick" and certificate leaf = H"…"`.
macOS ties the Accessibility permission to it, so the permission survives rebuilds and updates
as long as the bundle ID and certificate stay the same. It is not loosened to match on the
certificate's name only: anyone can create a certificate with that name.

### Signing in `task bundle`

- If *Flick Code Signing* is in the keychain, sign with it; otherwise sign ad-hoc and print a
  warning that Accessibility will have to be granted again.
- Nested code is signed from the inside out (PR 3: Sparkle's helpers, then the framework), the
  app last. No `--deep`.
- No hardened runtime and no notarization for now. Moving to Developer ID later means a new
  identity name, hardened runtime and a notarization step; the designated requirement changes
  then, and users grant Accessibility once more.

### Signing in CI

1. Fail at once if a secret is missing.
2. Create a temporary keychain with a random password, import the `.p12`, allow `codesign` to
   use the key (`security set-key-partition-list`).
3. Sign by the certificate's SHA-1 hash.
4. Delete the keychain in an `always()` step.

Whether `codesign` accepts a certificate nobody trusts is not known yet; the spike below
settles it. Fallback: trust it for code signing on the runner with
`sudo security add-trusted-cert -p codeSign`.

### Secrets

| GitHub secret | Contents |
|---|---|
| `SIGNING_CERT_P12` | the `.p12`, base64 |
| `SIGNING_CERT_PASSWORD` | its password |
| `SPARKLE_ED_PRIVATE_KEY` | the Sparkle private key (PR 3) |

### What it costs users

- **First install:** macOS blocks the app once; the user clicks *Open Anyway* in
  *Privacy & Security* and grants Accessibility. The README walks through it.
- **Updates through Sparkle:** no prompt and no new grant (see *Updates*).
- **If the certificate is lost:** every user grants Accessibility again after the next update.
- **If the Sparkle private key is lost:** installed copies can no longer update; users download
  the new DMG by hand once.

### Bundle ID rename

- `CFBundleIdentifier` and the logger subsystems in `EventTap` and `WindowMover` become
  `io.github.bergcyrill.flick`. The test suite's temporary defaults domain follows.
- UserDefaults are per bundle ID, so settings would reset. `SettingsMigration` (FlickCore)
  copies them from the old domain on launch:
  - only the keys `FlickSettings` knows;
  - only when the new domain has none of them, so it never overwrites;
  - once, remembered with a flag in the new domain.
- macOS sees a new app: Accessibility and *Launch at login* need to be turned on once more. The
  README's upgrade note says so.

## Version and releases

### Version numbers

- **Source of truth:** git tags `vX.Y.Z`. No version file in the repo; CI never pushes to
  `main`.
- **Next version:** `git-cliff --bumped-version` over the commits since the last tag. `fix` →
  patch, `feat` → minor, breaking → minor while below 1.0, major from 1.0. Merges with only
  `docs`, `chore`, `ci`, `test`, `refactor`, `style` or `build` commits don't release.
- **First release:** v0.1.0, the version `Info.plist` already carries.
- **Build number:** `git rev-list --count HEAD`. It only grows on `main`; Sparkle compares it.
- **Stamping:** `support/Info.plist` keeps placeholders; `task bundle` writes
  `CFBundleShortVersionString` and `CFBundleVersion` with `plutil`. Local builds get
  `<last tag>-dev` (`0.0.0-dev` before the first tag).
- **Visible in the app:** a disabled *Flick 0.2.0* line at the top of the menu-bar menu, and
  *Version 0.2.0 (57)* at the bottom of the settings window.

### Task targets

| Target | Does |
|---|---|
| `bundle` | as today, plus version stamping and signing |
| `dmg` | `build/Flick-<version>.dmg` with the app and an *Applications* link, via `hdiutil`, then `hdiutil verify` |
| `release-notes` | Markdown notes since the last tag, via git-cliff |
| `release` | everything below; `DRY=1` runs it locally without tagging or uploading |

`task release`:

1. Compute the next version; if there is none, say so and exit successfully.
2. `task test`, `task lint`.
3. Signed bundle, then the checks under *Testing*.
4. DMG, release notes, appcast (PR 3).
5. Unless `DRY=1`: delete a leftover draft release for this tag, create a **draft** release with
   the DMG (and, from PR 3 on, `appcast.xml`), then publish it. Publishing creates the tag, so a failed run never
   leaves a public release without its files or a tag without a release.

### GitHub Actions

- **`ci.yml`** on pull requests: `task test`, `task lint`, an unsigned `task build`. With every
  merge releasing, this is what keeps a broken PR from shipping.
- **`release.yml`** on push to `main`: `nix develop -c task release`.
  - `concurrency: release`, not cancelling, so two quick merges release one after the other.
  - `permissions: contents: write` and nothing else.
  - Full history checkout (`fetch-depth: 0`) for tags and the build number.
- **Runner:** the macOS image whose Xcode matches the SDK used locally (the dev shell takes
  Swift from Xcode, see `flake.nix`). Which image is pinned in PR 2, after the spike.
- **Third-party actions:** only `actions/checkout` and a Nix installer, both pinned to commit
  SHAs. Secrets reach only our own `task` steps.

## Updates

### Dependency and bundle

- Sparkle 2 via SwiftPM, for the `Flick` target only. `FlickCore` and the tests don't link it.
- Sparkle's command-line tools (`generate_keys`, `sign_update`) come from its release tarball as
  a non-flake input in `flake.nix`, the same version as `Package.resolved`.
- `task bundle` copies `Sparkle.framework` to `Contents/Frameworks` and adds the rpath
  `@executable_path/../Frameworks` with `install_name_tool`.

### In the app

- New adapter `Sources/Flick/Updater.swift` around `SPUStandardUpdaterController`.
- Menu-bar menu: *Check for Updates…*, disabled while a check runs.
- Settings window: *Check for updates automatically*, bound to Sparkle's own setting.
  `FlickSettings` doesn't change.
- `Info.plist`:
  - `SUFeedURL` = `https://github.com/BergCyrill/Flick/releases/latest/download/appcast.xml`
  - `SUPublicEDKey`, printed by the setup script
  - `SUEnableAutomaticChecks` = `YES`, so Sparkle doesn't ask on the second launch; default
    interval of 24 h; no system profiling — a check is one GET request to GitHub.
- **Gentle reminders:** a scheduled check that finds an update doesn't pop up a window over
  whatever the user is doing. The menu gains *Update to 0.3.0…* at the top; choosing it opens
  Sparkle's install dialog.
- Updates are not downloaded or installed without the user confirming.

### Appcast

- `task release` writes `appcast.xml` with one item, the new release: `sparkle:version` (build
  number), `sparkle:shortVersionString`, `sparkle:minimumSystemVersion` 14.0, the versioned DMG
  URL as enclosure, and its EdDSA signature from `sign_update`.
- The item's description is the release notes as HTML, from a second git-cliff template.
- In CI the private key goes from the secret to `sign_update` through a file in `$RUNNER_TEMP`,
  deleted afterwards. With `DRY=1` and no key, the appcast is written unsigned and marked so.

### What an update does

Sparkle checks the EdDSA signature, checks that the new app is signed by the same certificate as
the running one, replaces the app and relaunches it. The designated requirement is unchanged,
so Accessibility stays granted; Sparkle doesn't quarantine the update, so there's no *Open
Anyway*.

## Not in scope

- Developer ID signing, hardened runtime, notarization.
- Delta updates, beta channels, silent automatic installs.
- Homebrew cask.
- Releasing from branches other than `main`, or by hand.

## Error handling

- **Missing certificate locally:** ad-hoc signature and a warning.
- **Missing secret in CI:** the job fails before building, naming the secret.
- **Any failure before publishing:** nothing is published, no tag exists, a re-run starts over.
- **Failure while publishing:** only a draft exists; the re-run deletes it and starts over.
- **Update check fails:** silent for scheduled checks (offline, or 404 before the first release
  with an appcast); Sparkle's error dialog for *Check for Updates…*.

## Testing

### Spike (first task of PR 1)

1. **Locally:** create the certificate, sign a build, check `codesign -dr -` shows the bundle ID
   and `certificate leaf`. Grant Accessibility, rebuild, relaunch: the permission is still there.
2. **In CI:** a throwaway workflow on the branch imports the `.p12` into a temporary keychain,
   signs by hash and runs `codesign --verify --strict`. If that fails, try the trust fallback.
3. If both fail, stop and rethink before building on it.

### Unit tests (FlickCore, test first)

`SettingsMigration` against a key-value store protocol with a fake:

- copies the settings when the new domain is empty;
- never overwrites a value already in the new domain;
- runs only once;
- does nothing when the old domain is empty.

### Checks in `task release` (fail before publishing)

- `Info.plist` carries the computed version, and the build number is higher than the last
  release's.
- `codesign --verify --strict --deep` passes; the designated requirement names the bundle ID
  and a certificate leaf.
- `hdiutil verify` passes on the DMG.
- The appcast signature verifies against the `SUPublicEDKey` in the built `Info.plist`, which
  catches a private key that doesn't match the public one.

### Manual checklist (README)

- First install from the DMG: *Open Anyway* once, grant Accessibility, settings from the old
  bundle ID are there, turn *Launch at login* on again.
- Rebuild with `task run`: Accessibility stays granted.
- *Check for Updates…* when up to date says so.
- Update from the previous release: no Gatekeeper prompt, Accessibility still granted. Needs
  two releases with Sparkle, so it's checked after the first release following PR 3, not
  before merging.
