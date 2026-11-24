# Releasing Herdr Core Bar

A release ships three assets on a GitHub release `v<version>`:

| Asset | Purpose |
| --- | --- |
| `HerdrCoreBar-<version>.zip` | Notarized, stapled app; the Sparkle update archive |
| `HerdrCoreBar-<version>.dmg` | Signed, notarized, stapled disk image for manual and Homebrew installs |
| `appcast.xml` | Sparkle feed with the EdDSA signature, served from `releases/latest/download/appcast.xml` |

`scripts/release.sh` does the whole job: preconditions, universal release build, notarization, DMG,
appcast, tag, GitHub release, and the Homebrew cask in `olohmann/homebrew-tap`. The same script runs
locally and in `.github/workflows/release.yml`.

## One-time setup

The feed and download URLs only work for users once **`olohmann/herdr-core-bar` is public**.

Resolve the package once so the Sparkle tools exist:

```sh
swift package resolve
SPARKLE_BIN=.build/artifacts/sparkle/Sparkle/bin
```

### 1. Developer ID certificate

Install the "Developer ID Application: Oliver Lohmann (QCRM9T8GD4)" certificate with its private key in the
login keychain (Xcode → Settings → Accounts → Manage Certificates). Check it:

```sh
security find-identity -v -p codesigning | grep QCRM9T8GD4
```

### 2. Notarization credentials (local)

Store a keychain profile named `notarytool` (prompts for an app-specific password from account.apple.com):

```sh
xcrun notarytool store-credentials notarytool --apple-id <apple-id> --team-id QCRM9T8GD4
```

Alternatively export `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY_PATH` (see step 5); they take precedence.

### 3. Sparkle signing key

```sh
"$SPARKLE_BIN/generate_keys" --account herdr-core-bar
```

This stores the private key in the login keychain and prints the public key. Replace
`__SPARKLE_PUBLIC_ED_KEY__` in `Resources/Info.plist` (`SUPublicEDKey`) with it and commit.
`release.sh` refuses to publish when the app's key does not match the signing key.

Back up the private key and give it to CI:

```sh
"$SPARKLE_BIN/generate_keys" --account herdr-core-bar -x sparkle-private.key
gh secret set SPARKLE_PRIVATE_KEY < sparkle-private.key
# Store sparkle-private.key in your password manager, then delete it.
rm sparkle-private.key
```

Losing this key means existing installs can never auto-update again.

### 4. Developer ID certificate for CI

In Keychain Access → My Certificates, export the Developer ID identity (certificate and key) as
`developer-id.p12` with a strong password, then:

```sh
base64 -i developer-id.p12 | gh secret set DEVELOPER_ID_P12_BASE64
gh secret set DEVELOPER_ID_P12_PASSWORD   # paste the export password
rm developer-id.p12
```

### 5. App Store Connect API key for CI

App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys → generate a key
with the Developer role. Download `AuthKey_<KEY_ID>.p8` (only possible once) and note the Issuer ID.

```sh
base64 -i AuthKey_<KEY_ID>.p8 | gh secret set ASC_KEY_P8_BASE64
gh secret set ASC_KEY_ID --body <KEY_ID>
gh secret set ASC_ISSUER_ID --body <ISSUER_ID>
```

### 6. Homebrew tap

```sh
gh repo create olohmann/homebrew-tap --public --description "Homebrew tap"
```

`scripts/update-cask.sh` adds `Casks/herdr-core-bar.rb` from `packaging/homebrew/herdr-core-bar.rb` on the
first release. For CI, create a fine-grained token with **Contents: read and write** on
`olohmann/homebrew-tap` only:

```sh
gh secret set TAP_TOKEN
```

Locally the script uses your `gh` login. If the tap does not exist, the cask step prints a hint and is skipped.

### Secrets summary

| Secret | Used for |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD` | Code signing identity, imported into a temporary keychain |
| `ASC_KEY_P8_BASE64`, `ASC_KEY_ID`, `ASC_ISSUER_ID` | `notarytool` authentication |
| `SPARKLE_PRIVATE_KEY` | EdDSA signature in the appcast (piped to `sign_update`, never written to disk) |
| `TAP_TOKEN` | Pushing the cask to `olohmann/homebrew-tap` |

`GH_TOKEN` is the workflow's own token (`contents: write`).

## Cutting a release

1. In `CHANGELOG.md`, move the `Unreleased` entries into `## [X.Y.Z] - YYYY-MM-DD` and update the link
   references. That section becomes the release notes.
2. Set `CFBundleShortVersionString` in `Resources/Info.plist` to `X.Y.Z` (CI's dry run uses it).
3. Commit, push to `main`, and wait for CI to pass.
4. Release either way:

**From CI (preferred).** Push a tag; the Release workflow builds, notarizes, and publishes:

```sh
git tag -a vX.Y.Z -m "Herdr Core Bar X.Y.Z"
git push origin vX.Y.Z
```

Or run it by hand: `gh workflow run release.yml -f version=X.Y.Z [-f draft=true]` (from `main` it tags `HEAD`).

**Locally.**

```sh
scripts/release.sh X.Y.Z            # full release
scripts/release.sh X.Y.Z --draft    # draft release; run update-cask.sh after publishing it
scripts/release.sh X.Y.Z --skip-publish   # build, notarize, and package only
scripts/release.sh X.Y.Z --dry-run  # no credentials needed; ad-hoc signing, throwaway Sparkle key
```

A local release pushes the tag, which also starts the Release workflow; it sees the published release and
exits without doing anything.

Outputs land in `dist/X.Y.Z/`. The build number (`CFBundleVersion`, `sparkle:version`) defaults to the commit
count of `HEAD`; override with `--build N`, but it must always increase. Versions with a suffix (`1.2.0-beta.1`)
become GitHub prereleases, which `releases/latest` and the cask ignore.

Useful environment overrides: `IDENTITY`, `TEAM_ID`, `NOTARY_PROFILE`, `SPARKLE_ACCOUNT`, `DMG_LAYOUT=1`
(arrange the DMG window through Finder; needs a GUI session).

`scripts/test-release.sh` runs the dry run and checks every output (CI runs it on each push).

## Verifying a release

```sh
gh release view vX.Y.Z
curl -sL https://github.com/olohmann/herdr-core-bar/releases/latest/download/appcast.xml | xmllint --format -

gh release download vX.Y.Z --pattern '*.dmg'
xcrun stapler validate HerdrCoreBar-X.Y.Z.dmg
spctl -a -vv -t open --context context:primary-signature HerdrCoreBar-X.Y.Z.dmg
# after installing:
spctl -a -vv "/Applications/Herdr Core Bar.app"   # expect: source=Notarized Developer ID

brew update && brew install --cask olohmann/tap/herdr-core-bar
```

To test Sparkle, install the previous version and choose Check for Updates… from the menu.

## Rollback

- **Before users update:** delete the release and its tag. `releases/latest` falls back to the previous
  release, so the feed reverts automatically.

  ```sh
  gh release delete vX.Y.Z --cleanup-tag --yes
  git tag -d vX.Y.Z
  ```

  Then revert the cask commit in `olohmann/homebrew-tap` (`git revert <sha> && git push`).
- **After users updated:** Sparkle does not downgrade. Ship a fix as a new version with a higher build number.
  Never reuse a version or build number.
- **Failed run:** fix the cause and rerun the same command. A leftover draft release is reused and its assets
  are replaced; `dist/X.Y.Z` is rebuilt from scratch.
