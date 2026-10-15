# Releasing Flick

## How a release happens

Every merge to `main` that brings a `feat`, `fix` or breaking commit publishes a release.
`.github/workflows/release.yml` runs `task release`, which:

1. decides from the commits since the last tag whether there is anything to release, and the
   version (git-cliff, `cliff.toml`): `fix` → patch, `feat` → minor, breaking → minor below 1.0
   and major from 1.0;
2. tests, lints, builds and signs the app, and packages `Flick-<version>.dmg`;
3. checks the version, the signature and the designated requirement against the pinned
   certificate;
4. writes `appcast.xml` for the in-app updater, signs it with the update key and checks that
   signature against the app's public key;
5. publishes both files with the release notes on GitHub Releases.

A failed run leaves at most a draft release, and running it again is safe.

```sh
task release-notes      # what the next release would say (empty: nothing to release)
task release DRY=1      # the whole release locally, without publishing
```

GitHub can take a few minutes after publishing before `releases/latest` points to the new
release, so *Check for Updates…* right after a merge may still say "up to date".

## The two keys

Both are created once, kept in the password manager and in GitHub secrets, and never committed.

**Signing certificate**, *Flick Code Signing*: self-signed. macOS ties the Accessibility
permission to Flick's bundle ID and this certificate, so the permission survives rebuilds and
updates.

```sh
scripts/make-signing-cert.sh    # imports it into the login keychain, writes ~/flick-signing
```

It prints the next steps: keep the `.p12` and its password in the password manager, set the
GitHub secrets `SIGNING_CERT_P12` and `SIGNING_CERT_PASSWORD`, delete `~/flick-signing`. To sign
on another Mac, double-click the `.p12` from the password manager.

**Update key**: EdDSA, signs the appcast so installed copies only accept updates from you.

```sh
scripts/make-update-key.sh      # login keychain, ~/flick-update-key, prints the public key
```

Keep the private key in the password manager and the `SPARKLE_ED_PRIVATE_KEY` secret; the
public key is `SUPublicEDKey` in `support/Info.plist`. On another Mac, import it with
`generate_keys --account io.github.bergcyrill.flick -f <file>`.

## If a key is lost or replaced

- **A new signing certificate** changes the designated requirement: every user has to grant
  Accessibility again after the next update, and `scripts/release.sh` pins the old one, so the
  release fails until `cert_leaf` there is changed on purpose.
- **A lost update key** means installed copies can't verify updates any more. A new key needs a
  new `SUPublicEDKey`, and every user has to install that version by hand once. A release whose
  key doesn't match the app's public key fails before anything is published.
