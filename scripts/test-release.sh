#!/usr/bin/env bash
# End-to-end check of the release pipeline without credentials.
#
# Usage: scripts/test-release.sh [--scratch-path P]
#
# Runs `scripts/release.sh <current version> --dry-run` and asserts that the app,
# update zip, DMG, appcast, and cask come out well-formed.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

readonly APP_NAME="Herdr Core Bar"
readonly ARCHIVE_BASE="HerdrCoreBar"

log() { printf '==> %s\n' "$*" >&2; }
failures=0
pass() { printf '  ok    %s\n' "$*" >&2; }
fail() {
    printf '  FAIL  %s\n' "$*" >&2
    failures=$((failures + 1))
}
check() {
    local label=$1
    shift
    if "$@" >/dev/null 2>&1; then pass "$label"; else fail "$label"; fi
}

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
out_dir="$repo_root/dist/$version"
app="$out_dir/$APP_NAME.app"
zip="$out_dir/$ARCHIVE_BASE-$version.zip"
dmg="$out_dir/$ARCHIVE_BASE-$version.dmg"
appcast="$out_dir/appcast.xml"
cask="$out_dir/herdr-core-bar.rb"
scratch_dir="$out_dir/.test"
mountpoint="$scratch_dir/mnt"

cleanup() {
    if [[ -d "$mountpoint" && "$(mount)" == *" on $mountpoint "* ]]; then
        hdiutil detach "$mountpoint" -quiet -force || true
    fi
    rm -rf "$scratch_dir"
}
trap cleanup EXIT

log "Dry-run release of $version"
scripts/release.sh "$version" --dry-run "$@"

log "Checking outputs in $out_dir"
check "app bundle exists" test -d "$app"
check "app signature is valid" codesign --verify --deep --strict "$app"
check "update zip exists" test -s "$zip"
check "DMG exists" test -s "$dmg"
check "DMG signature is valid" codesign --verify --strict "$dmg"
check "DMG checksum verifies" hdiutil verify -quiet "$dmg"
check "appcast is well-formed XML" xmllint --noout "$appcast"
check "cask is valid Ruby" ruby -c "$cask"
check "cask has version $version" grep -q "version \"$version\"" "$cask"
check "cask sha256 matches the DMG" grep -q "sha256 \"$(shasum -a 256 "$dmg" | awk '{ print $1 }')\"" "$cask"

xpath() { xmllint --xpath "$1" "$appcast" 2>/dev/null; }
enclosure='//item[1]/enclosure'
signature="$(xpath "string($enclosure/@*[local-name()='edSignature'])")"
length="$(xpath "string($enclosure/@length)")"
url="$(xpath "string($enclosure/@url)")"
short_version="$(xpath "string(//item[1]/*[local-name()='shortVersionString'])")"
bundle_version="$(xpath "string(//item[1]/*[local-name()='version'])")"
min_os="$(xpath "string(//item[1]/*[local-name()='minimumSystemVersion'])")"

check "appcast has an EdDSA signature" test "$(printf '%s' "$signature" | base64 -d 2>/dev/null | wc -c | tr -d ' ')" = 64
check "appcast length matches the zip" test "$length" = "$(stat -f %z "$zip")"
check "appcast url points at the release zip" test "$url" = \
    "https://github.com/olohmann/herdr-core-bar/releases/download/v$version/$ARCHIVE_BASE-$version.zip"
check "appcast shortVersionString is $version" test "$short_version" = "$version"
check "appcast version matches CFBundleVersion" test "$bundle_version" = \
    "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
check "appcast minimumSystemVersion is set" test -n "$min_os"

mkdir -p "$scratch_dir/unzip" "$mountpoint"
if ditto -x -k "$zip" "$scratch_dir/unzip"; then
    check "zip contains a valid signed app" codesign --verify --deep --strict "$scratch_dir/unzip/$APP_NAME.app"
else
    fail "zip extracts"
fi

if hdiutil attach "$dmg" -readonly -nobrowse -noautoopen -mountpoint "$mountpoint" >/dev/null; then
    pass "DMG mounts read-only"
    check "DMG contains the app" test -d "$mountpoint/$APP_NAME.app"
    check "DMG app signature is valid" codesign --verify --deep --strict "$mountpoint/$APP_NAME.app"
    check "DMG links /Applications" test "$(readlink "$mountpoint/Applications")" = /Applications
    check "DMG volume is read-only" bash -c "! touch '$mountpoint/.write-test'"
    hdiutil detach "$mountpoint" -quiet || hdiutil detach "$mountpoint" -quiet -force
else
    fail "DMG mounts read-only"
fi

if ((failures)); then
    log "$failures check(s) failed"
    exit 1
fi
log "Release dry run passed"
