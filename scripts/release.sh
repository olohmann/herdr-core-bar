#!/usr/bin/env bash
# Build, notarize, and publish a Herdr Core Bar release.
#
# Usage: scripts/release.sh <version> [options]
#
#   --dry-run            Build, package, and sign the appcast with a throwaway key.
#                        Ad-hoc signing; no notarization, tagging, or publishing.
#   --skip-publish       Do everything except tagging, the GitHub release, and the cask.
#   --draft              Create the GitHub release as a draft (cask update is skipped).
#   --notes FILE         Release notes file (default: the CHANGELOG.md section).
#   --build N            Bundle build number (default: git commit count).
#   --scratch-path P     SwiftPM scratch path (default: .build).
#
# Environment (see docs/releasing.md):
#   IDENTITY, TEAM_ID                      code signing identity and team
#   NOTARY_PROFILE                         notarytool keychain profile (default: notarytool)
#   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH App Store Connect API key (overrides the profile)
#   SPARKLE_PRIVATE_KEY                    EdDSA private key (default: keychain account herdr-core-bar)
#   TAP_TOKEN, GH_TOKEN                    GitHub tokens for the tap and the release
#   DMG_LAYOUT=1                           arrange the DMG window through Finder
set -euo pipefail

readonly APP_NAME="Herdr Core Bar"
readonly ARCHIVE_BASE="HerdrCoreBar"
readonly RELEASE_REPO="${RELEASE_REPO:-olohmann/herdr-core-bar}"
readonly SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-herdr-core-bar}"
readonly PUBLIC_KEY_PLACEHOLDER="__SPARKLE_PUBLIC_ED_KEY__"
IDENTITY="${IDENTITY:-Developer ID Application: Oliver Lohmann (QCRM9T8GD4)}"
TEAM_ID="${TEAM_ID:-QCRM9T8GD4}"
NOTARY_PROFILE="${NOTARY_PROFILE:-notarytool}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

usage() {
    sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

step_no=0
step() {
    step_no=$((step_no + 1))
    printf '\n\033[1m[%d/7] %s\033[0m\n' "$step_no" "$*" >&2
}
log() { printf '==> %s\n' "$*" >&2; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

dry_run=0
publish=1
draft=0
notes_file=""
build_number=""
scratch=".build"
positional=()
while (($#)); do
    case "$1" in
        --dry-run) dry_run=1 ;;
        --skip-publish) publish=0 ;;
        --draft) draft=1 ;;
        --notes | --build | --scratch-path)
            (($# >= 2)) || die "$1 needs a value"
            case "$1" in
                --notes) notes_file="$2" ;;
                --build) build_number="$2" ;;
                --scratch-path) scratch="$2" ;;
            esac
            shift
            ;;
        -h | --help) usage 0 ;;
        -*) die "unknown option: $1" ;;
        *) positional+=("$1") ;;
    esac
    shift
done
((${#positional[@]} == 1)) || usage 1
version="${positional[0]#v}"
((dry_run)) && publish=0

tag="v$version"
out_dir="$repo_root/dist/$version"
work_dir="$repo_root/dist/.work-$version"
zip="$out_dir/$ARCHIVE_BASE-$version.zip"
dmg="$out_dir/$ARCHIVE_BASE-$version.dmg"
appcast="$out_dir/appcast.xml"
cask_out="$out_dir/herdr-core-bar.rb"
release_url="https://github.com/$RELEASE_REPO/releases/tag/$tag"
download_base="https://github.com/$RELEASE_REPO/releases/download/$tag"
prerelease=0
[[ "$version" == *-* ]] && prerelease=1

cleanup() { rm -rf "$work_dir"; }
trap cleanup EXIT

need() {
    local tool
    for tool in "$@"; do
        command -v "$tool" >/dev/null || die "required tool not found: $tool"
    done
}

# Ed25519 helper on CryptoKit: keygen | public (seed on stdin) | verify <pub> <sig> <file>.
ed25519() {
    local source="$work_dir/ed25519.swift"
    [[ -f "$source" ]] || write_ed25519_source "$source"
    swift "$source" "$@"
}

write_ed25519_source() {
    cat >"$1" <<'SWIFT'
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "keygen":
    let key = Curve25519.Signing.PrivateKey()
    print(key.rawRepresentation.base64EncodedString())
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "public":
    let text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    guard let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        fail("private key is not base64")
    }
    switch raw.count {
    case 32:
        guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else { fail("invalid key") }
        print(key.publicKey.rawRepresentation.base64EncodedString())
    case 96:
        print(raw.suffix(32).base64EncodedString())
    default:
        fail("unexpected private key length \(raw.count)")
    }
case "verify" where args.count == 4:
    guard let pub = Data(base64Encoded: args[1]), let sig = Data(base64Encoded: args[2]),
        let key = try? Curve25519.Signing.PublicKey(rawRepresentation: pub),
        let data = FileManager.default.contents(atPath: args[3])
    else { fail("verify: unreadable input") }
    exit(key.isValidSignature(sig, for: data) ? 0 : 1)
default:
    fail("usage: keygen | public | verify <pub> <sig> <file>")
}
SWIFT
}

plist_value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true; }

# --------------------------------------------------------------------------
step "Preconditions"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || die "not a semantic version: $version"
((dry_run)) && log "DRY RUN: ad-hoc signing, throwaway Sparkle key, nothing leaves this machine"

need git ditto hdiutil codesign shasum plutil xmllint swift awk
[[ -x scripts/build.sh ]] || die "scripts/build.sh is missing or not executable"
[[ -x scripts/verify-bundle.sh ]] || die "scripts/verify-bundle.sh is missing or not executable"
if ((!dry_run)); then
    need gh
    xcrun --find notarytool >/dev/null 2>&1 || die "xcrun notarytool not found (install Xcode)"
    xcrun --find stapler >/dev/null 2>&1 || die "xcrun stapler not found (install Xcode)"
fi

if [[ -n "$(git status --porcelain)" ]]; then
    ((dry_run)) || die "working tree is not clean; commit or stash first"
    warn "working tree is not clean (ignored for --dry-run)"
fi

in_ci_on_tag=0
if [[ "${GITHUB_ACTIONS:-}" == true && "${GITHUB_REF_TYPE:-}" == tag && "${GITHUB_REF_NAME:-}" == "$tag" ]]; then
    in_ci_on_tag=1
fi
tag_exists=0
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    tag_exists=1
    if [[ "$(git rev-list -n 1 "$tag")" != "$(git rev-parse HEAD)" ]]; then
        msg="tag $tag exists but does not point at HEAD; check out $tag to rebuild it"
        if ((dry_run)); then warn "$msg"; else die "$msg"; fi
    fi
fi

release_state="none"
if ((!dry_run)); then
    if is_draft="$(gh release view "$tag" --repo "$RELEASE_REPO" --json isDraft --jq .isDraft 2>/dev/null)"; then
        if [[ "$is_draft" == true ]]; then
            release_state="draft"
            log "Draft release $tag exists; its assets will be replaced"
        else
            release_state="published"
            if [[ "${GITHUB_ACTIONS:-}" == true ]]; then
                log "Release $tag is already published; nothing to do"
                exit 0
            fi
            ((publish)) && die "release $tag is already published"
            warn "release $tag is already published"
        fi
    fi
fi

notes="$work_dir/notes.md"
rm -rf "$work_dir"
mkdir -p "$work_dir"
chmod 700 "$work_dir"
if [[ -n "$notes_file" ]]; then
    [[ -s "$notes_file" ]] || die "notes file is empty or missing: $notes_file"
    cp "$notes_file" "$notes"
else
    awk -v heading="## [$version]" '
        index($0, heading) == 1 { found = 1; next }
        found && /^## \[/ { exit }
        found && /^\[[^]]+\]: / { next }
        found { print }
    ' CHANGELOG.md | awk 'NF { blank_run = 0; seen = 1 } !NF { blank_run++ } seen && blank_run <= 1' >"$notes"
    if [[ ! -s "$notes" ]] || ! grep -q '[^[:space:]]' "$notes"; then
        ((dry_run)) || die "CHANGELOG.md has no '## [$version]' section (or pass --notes FILE)"
        warn "CHANGELOG.md has no '## [$version]' section; using placeholder notes"
        printf 'Dry run of %s %s.\n' "$APP_NAME" "$version" >"$notes"
    fi
fi
log "Release notes: $(wc -l <"$notes" | tr -d ' ') lines"

if [[ -z "$build_number" ]]; then
    build_number="$(git rev-list --count HEAD)"
fi
[[ "$build_number" =~ ^[0-9]+$ ]] || die "build number must be an integer: $build_number"

log "Resolving packages (scratch path: $scratch)"
swift package resolve --scratch-path "$scratch" >&2
sparkle_bin="$scratch/artifacts/sparkle/Sparkle/bin"
sign_update="$sparkle_bin/sign_update"
[[ -x "$sign_update" ]] || die "Sparkle sign_update not found in $sparkle_bin"
[[ -x "$sparkle_bin/generate_appcast" ]] || die "Sparkle generate_appcast not found in $sparkle_bin"

notary_args=()
if ((dry_run)); then
    sign_identity="-"
    keypair="$(ed25519 keygen)" || die "could not create a throwaway Ed25519 key"
    throwaway_key="$work_dir/sparkle-throwaway.key"
    (umask 077 && printf '%s\n' "${keypair%%$'\n'*}" >"$throwaway_key")
    expected_public_key="${keypair##*$'\n'}"
    log "Generated throwaway Sparkle key (public: $expected_public_key)"
else
    sign_identity="$IDENTITY"
    [[ "$(security find-identity -v -p codesigning)" == *"\"$IDENTITY\""* ]] ||
        die "signing identity not found in keychain: $IDENTITY"
    if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_PATH:-}" ]]; then
        [[ -r "$ASC_KEY_PATH" ]] || die "ASC_KEY_PATH is not readable: $ASC_KEY_PATH"
        notary_args=(--key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
        log "Notarizing with App Store Connect API key $ASC_KEY_ID"
    else
        notary_args=(--keychain-profile "$NOTARY_PROFILE")
        log "Notarizing with keychain profile '$NOTARY_PROFILE'"
    fi
    xcrun notarytool history "${notary_args[@]}" >/dev/null ||
        die "notarytool credentials do not work (see docs/releasing.md)"
    if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
        expected_public_key="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | ed25519 public)" ||
            die "SPARKLE_PRIVATE_KEY is not a valid Sparkle EdDSA key"
        log "Sparkle key from SPARKLE_PRIVATE_KEY"
    else
        expected_public_key="$("$sparkle_bin/generate_keys" --account "$SPARKLE_ACCOUNT" -p 2>/dev/null | tail -n 1)" ||
            die "no Sparkle key in keychain account '$SPARKLE_ACCOUNT' (see docs/releasing.md)"
        log "Sparkle key from keychain account '$SPARKLE_ACCOUNT'"
    fi
    [[ -n "$expected_public_key" ]] || die "could not determine the Sparkle public key"
fi

sparkle_sign() {
    if ((dry_run)); then
        "$sign_update" -p --ed-key-file "$throwaway_key" "$1"
    elif [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
        printf '%s' "$SPARKLE_PRIVATE_KEY" | "$sign_update" -p --ed-key-file - "$1"
    else
        "$sign_update" -p --account "$SPARKLE_ACCOUNT" "$1"
    fi
}

notarize() {
    local file=$1
    if ((dry_run)); then
        log "[dry-run] skip: xcrun notarytool submit $(basename "$file") --wait"
        return
    fi
    local result rc=0 id status
    result="$work_dir/notary-$(basename "$file").json"
    log "Submitting $(basename "$file") for notarization (this can take a few minutes)"
    xcrun notarytool submit "$file" "${notary_args[@]}" --wait --output-format json >"$result" || rc=$?
    id="$(plutil -extract id raw -o - "$result" 2>/dev/null || true)"
    status="$(plutil -extract status raw -o - "$result" 2>/dev/null || true)"
    log "Notarization ${id:-?}: ${status:-unknown}"
    if [[ "$status" != Accepted ]]; then
        cat "$result" >&2 || true
        if [[ -n "$id" ]]; then
            log "Notary log:"
            xcrun notarytool log "$id" "${notary_args[@]}" >&2 || true
        fi
        die "notarization failed for $(basename "$file") (status: ${status:-unknown}, exit $rc)"
    fi
}

staple() {
    if ((dry_run)); then
        log "[dry-run] skip: xcrun stapler staple $(basename "$1")"
        return
    fi
    xcrun stapler staple -q "$1"
    xcrun stapler validate -q "$1"
    log "Stapled $(basename "$1")"
}

gatekeeper_check() {
    ((dry_run)) && return
    if [[ "$(spctl --status 2>/dev/null || true)" == *enabled* ]]; then
        spctl "$@" || die "Gatekeeper rejected ${*: -1}"
    else
        warn "Gatekeeper assessments are disabled here; skipped spctl ${*: -1}"
    fi
}

log "Version $version (build $build_number), tag $tag"
log "Signing identity: $sign_identity"

# --------------------------------------------------------------------------
step "Build"

rm -rf "$out_dir"
mkdir -p "$out_dir"
build_output="$(
    scripts/build.sh --config release --version "$version" --build "$build_number" \
        --sign "$sign_identity" --output "$out_dir" --scratch-path "$scratch" | tee /dev/stderr
)"
app="$(printf '%s\n' "$build_output" | tail -n 1)"
[[ -d "$app" ]] || app="$out_dir/$APP_NAME.app"
[[ -d "$app" ]] || die "build did not produce $out_dir/$APP_NAME.app"

if ((dry_run)); then
    scripts/verify-bundle.sh "$app"
else
    scripts/verify-bundle.sh "$app" --signed
    signature_info=$'\n'"$(codesign -dvv "$app" 2>&1)"$'\n'
    [[ "$signature_info" == *$'\n'"TeamIdentifier=$TEAM_ID"$'\n'* ]] || die "app is not signed by team $TEAM_ID"
fi

info="$app/Contents/Info.plist"
[[ "$(plist_value "$info" CFBundleShortVersionString)" == "$version" ]] ||
    die "app CFBundleShortVersionString is not $version"
bundle_version="$(plist_value "$info" CFBundleVersion)"
[[ -n "$bundle_version" ]] || die "app has no CFBundleVersion"
min_os="$(plist_value "$info" LSMinimumSystemVersion)"
min_os="${min_os:-27.0}"
app_public_key="$(plist_value "$info" SUPublicEDKey)"
if [[ "$app_public_key" != "$expected_public_key" ]]; then
    if ((dry_run)); then
        warn "app SUPublicEDKey (${app_public_key:-missing}) differs from the throwaway key (expected in a dry run)"
    elif [[ "$app_public_key" == "$PUBLIC_KEY_PLACEHOLDER" || -z "$app_public_key" ]]; then
        die "app SUPublicEDKey is not set; put the Sparkle public key into Resources/Info.plist"
    else
        die "app SUPublicEDKey does not match the Sparkle signing key; updates would be rejected"
    fi
fi
log "Built $app (build $bundle_version)"

# --------------------------------------------------------------------------
step "Notarize app"

notarize_zip="$work_dir/$ARCHIVE_BASE-$version-notarize.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$notarize_zip"
notarize "$notarize_zip"
staple "$app"
gatekeeper_check --assess --type execute -vv "$app"
((dry_run)) || scripts/verify-bundle.sh "$app" --distribution
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
log "Update archive: $zip"

# --------------------------------------------------------------------------
step "Disk image"

dmg_args=()
[[ "${DMG_LAYOUT:-0}" == 1 ]] && dmg_args+=(--layout)
scripts/make-dmg.sh "$app" "$dmg" "$APP_NAME" ${dmg_args[@]+"${dmg_args[@]}"} >/dev/null
if ((dry_run)); then
    codesign --force --sign - "$dmg"
else
    codesign --force --sign "$sign_identity" --timestamp "$dmg"
fi
codesign --verify --strict "$dmg"
notarize "$dmg"
staple "$dmg"
gatekeeper_check --assess --type open --context context:primary-signature -vv "$dmg"
log "Disk image: $dmg"

# --------------------------------------------------------------------------
step "Sparkle appcast"

zip_length="$(stat -f %z "$zip")"
signature="$(sparkle_sign "$zip")" || die "sign_update failed"
[[ -n "$signature" ]] || die "sign_update returned no signature"
ed25519 verify "$expected_public_key" "$signature" "$zip" || die "EdDSA signature does not verify"
log "EdDSA signature verified against $expected_public_key"

previous_items=""
if ((!dry_run)); then
    latest_tag="$(gh release view --repo "$RELEASE_REPO" --json tagName --jq .tagName 2>/dev/null || true)"
    if [[ -n "$latest_tag" && "$latest_tag" != "$tag" ]] &&
        gh release download "$latest_tag" --repo "$RELEASE_REPO" --pattern appcast.xml \
            --dir "$work_dir/previous" >/dev/null 2>&1; then
        previous_items="$(awk -v skip="<sparkle:shortVersionString>$version</sparkle:shortVersionString>" '
            /<item>/ { buf = ""; inside = 1 }
            inside { buf = buf $0 "\n" }
            /<\/item>/ && inside { inside = 0; if (index(buf, skip) == 0 && n < 9) { printf "%s", buf; n++ } }
        ' "$work_dir/previous/appcast.xml")"
        log "Carried over $(grep -c '<item>' <<<"$previous_items" || true) item(s) from $latest_tag"
    fi
fi

pub_date="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
{
    cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>$APP_NAME</title>
        <link>https://github.com/$RELEASE_REPO</link>
        <description>Updates for $APP_NAME</description>
        <language>en</language>
        <item>
            <title>Version $version</title>
            <pubDate>$pub_date</pubDate>
            <sparkle:version>$bundle_version</sparkle:version>
            <sparkle:shortVersionString>$version</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$min_os</sparkle:minimumSystemVersion>
            <sparkle:releaseNotesLink>$release_url</sparkle:releaseNotesLink>
            <enclosure url="$download_base/$(basename "$zip")" length="$zip_length" type="application/octet-stream" sparkle:edSignature="$signature"/>
        </item>
EOF
    [[ -n "$previous_items" ]] && printf '%s\n' "$previous_items"
    cat <<EOF
    </channel>
</rss>
EOF
} >"$appcast"
xmllint --noout "$appcast" || die "generated appcast is not well-formed XML"
log "Appcast: $appcast"

# --------------------------------------------------------------------------
step "Publish"

zip_sha="$(shasum -a 256 "$zip" | awk '{ print $1 }')"
dmg_sha="$(shasum -a 256 "$dmg" | awk '{ print $1 }')"
scripts/update-cask.sh "$version" "$dmg_sha" --render "$cask_out"

if ((!publish)); then
    log "[skip] git tag -a $tag && git push origin $tag"
    log "[skip] gh release create $tag --title \"$APP_NAME $version\" <zip> <dmg> appcast.xml"
    log "[skip] scripts/update-cask.sh $version $dmg_sha"
else
    if ((in_ci_on_tag)); then
        log "Running on tag $tag in CI; not re-tagging"
    else
        if ((!tag_exists)); then
            tagger=()
            if [[ -z "$(git config user.email || true)" ]]; then
                tagger=(-c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com")
            fi
            git ${tagger[@]+"${tagger[@]}"} tag -a "$tag" -m "$APP_NAME $version"
            log "Created tag $tag"
        fi
        if git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
            log "Tag $tag already on origin"
        else
            git push --quiet origin "refs/tags/$tag"
            log "Pushed tag $tag"
        fi
    fi

    assets=("$zip" "$dmg" "$appcast")
    if [[ "$release_state" == draft ]]; then
        gh release upload "$tag" "${assets[@]}" --repo "$RELEASE_REPO" --clobber
        gh release edit "$tag" --repo "$RELEASE_REPO" --title "$APP_NAME $version" --notes-file "$notes"
        if ((!draft)); then
            gh release edit "$tag" --repo "$RELEASE_REPO" --draft=false >/dev/null
        fi
        log "Updated release $tag"
    else
        release_flags=(--verify-tag)
        ((draft)) && release_flags+=(--draft)
        ((prerelease)) && release_flags+=(--prerelease)
        gh release create "$tag" "${assets[@]}" --repo "$RELEASE_REPO" \
            --title "$APP_NAME $version" --notes-file "$notes" "${release_flags[@]}" >/dev/null
        log "Created release $tag"
    fi

    if ((draft || prerelease)); then
        log "Skipping the cask for a draft or prerelease; after publishing run:"
        log "  scripts/update-cask.sh $version $dmg_sha"
    else
        scripts/update-cask.sh "$version" "$dmg_sha"
    fi
fi

# --------------------------------------------------------------------------
step "Summary"

summary="$(
    cat <<EOF
$APP_NAME $version (build $bundle_version)$( ((dry_run)) && printf ' [dry run]')

App:      $app
Zip:      $zip
          sha256 $zip_sha
DMG:      $dmg
          sha256 $dmg_sha
Appcast:  $appcast
Cask:     $cask_out

Release:  $release_url
Download: $download_base/$(basename "$dmg")
Feed:     https://github.com/$RELEASE_REPO/releases/latest/download/appcast.xml
EOF
)"
printf '%s\n' "$summary" >&2
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    fence='```'
    printf '%s\n%s\n%s\n' "$fence" "$summary" "$fence" >>"$GITHUB_STEP_SUMMARY"
fi
