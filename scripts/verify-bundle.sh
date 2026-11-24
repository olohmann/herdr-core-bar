#!/usr/bin/env bash
# Verifies an assembled "Herdr Core Bar.app". Exits nonzero if any check fails.
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

usage() {
    cat <<EOF
Usage: scripts/verify-bundle.sh <path/to/Herdr Core Bar.app> [--signed | --distribution] [--require-universal]

  --signed             Also require Developer ID signing (team $TEAM_ID), hardened runtime and a
                       secure timestamp on the app and every Sparkle component (before notarization).
  --distribution       --signed, plus Gatekeeper acceptance and a stapled notarization ticket.
  --require-universal  Fail unless the executable contains both arm64 and x86_64.
EOF
}

app=""
signed=0
distribution=0
require_universal=0
while (($#)); do
    case "$1" in
    --signed) signed=1; shift ;;
    --distribution) signed=1; distribution=1; shift ;;
    --require-universal) require_universal=1; shift ;;
    -h | --help) usage; exit 0 ;;
    -*) die "unknown option: $1 (see --help)" ;;
    *)
        [[ -z "$app" ]] || die "only one app path may be given"
        app="${1%/}"
        shift
        ;;
    esac
done
[[ -n "$app" ]] || { usage >&2; exit 2; }
[[ -d "$app" ]] || die "not a directory: $app"

failures=0
fail() {
    printf '%s FAIL%s %s\n' "$_c_red" "$_c_reset" "$*" >&2
    failures=$((failures + 1))
}
check() { # check <description> <command...>
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then ok "$desc"; else fail "$desc"; fi
}

plist="$app/Contents/Info.plist"
fw="$app/Contents/Frameworks/Sparkle.framework"

log "Info.plist"
if [[ ! -f "$plist" ]]; then
    fail "missing $plist"
else
    expect_key() { # expect_key <key> <expected>
        local actual
        actual="$(plist_get "$plist" ":$1" || true)"
        if [[ "$actual" == "$2" ]]; then ok "$1 = $actual"; else fail "$1 is '$actual', expected '$2'"; fi
    }
    expect_key CFBundleIdentifier "$APP_BUNDLE_ID"
    expect_key CFBundleExecutable "$APP_EXECUTABLE"
    expect_key CFBundlePackageType APPL
    expect_key LSMinimumSystemVersion 27.0
    expect_key LSUIElement true
    expect_key CFBundleIconName AppIcon

    short_version="$(plist_get "$plist" :CFBundleShortVersionString || true)"
    bundle_version="$(plist_get "$plist" :CFBundleVersion || true)"
    if [[ "$short_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        ok "CFBundleShortVersionString = $short_version"
    else
        fail "CFBundleShortVersionString '$short_version' is not X.Y.Z"
    fi
    if [[ "$bundle_version" =~ ^[1-9][0-9]*$ ]]; then
        ok "CFBundleVersion = $bundle_version"
    else
        fail "CFBundleVersion '$bundle_version' is not a positive integer"
    fi

    feed="$(plist_get "$plist" :SUFeedURL || true)"
    if [[ "$feed" == https://* ]]; then ok "SUFeedURL = $feed"; else fail "SUFeedURL '$feed' is not an https URL"; fi

    ed_key="$(plist_get "$plist" :SUPublicEDKey || true)"
    ed_key_len="$(printf '%s' "$ed_key" | base64 -D 2>/dev/null | wc -c | tr -d ' ')"
    if [[ -z "$ed_key" || "$ed_key" == *__* ]]; then
        fail "SUPublicEDKey is missing or still a placeholder"
    elif [[ "$ed_key_len" != 32 ]]; then
        fail "SUPublicEDKey does not decode to a 32-byte Ed25519 key"
    else
        ok "SUPublicEDKey = $ed_key"
    fi
fi

log "Contents"
exe="$app/Contents/MacOS/$APP_EXECUTABLE"
if [[ -x "$exe" ]]; then
    archs="$(lipo -archs "$exe" 2>/dev/null || echo unknown)"
    ok "executable $APP_EXECUTABLE (archs: $archs)"
    if ((require_universal)); then
        if [[ " $archs " == *" arm64 "* && " $archs " == *" x86_64 "* ]]; then
            ok "universal binary"
        else
            fail "executable is not universal (archs: $archs)"
        fi
    fi
    if otool -l "$exe" | grep -A2 LC_RPATH | grep -q '@executable_path/../Frameworks'; then
        ok "rpath contains @executable_path/../Frameworks"
    else
        fail "rpath lacks @executable_path/../Frameworks"
    fi
    if otool -L "$exe" | grep -q '@rpath/Sparkle.framework'; then
        ok "links @rpath/Sparkle.framework"
    else
        fail "executable does not link @rpath/Sparkle.framework"
    fi
else
    fail "missing executable $exe"
fi
check "Resources/Assets.car present" test -f "$app/Contents/Resources/Assets.car"
check "Resources/AppIcon.icns present" test -f "$app/Contents/Resources/AppIcon.icns"

sparkle_parts=(
    "$fw/Versions/B/XPCServices/Installer.xpc"
    "$fw/Versions/B/XPCServices/Downloader.xpc"
    "$fw/Versions/B/Autoupdate"
    "$fw/Versions/B/Updater.app"
    "$fw"
)
check "Sparkle.framework present" test -x "$fw/Versions/B/Sparkle"
for part in "${sparkle_parts[@]:0:4}"; do
    check "Sparkle component ${part#"$fw/Versions/B/"}" test -e "$part"
done
sparkle_version="$(plist_get "$fw/Resources/Info.plist" :CFBundleShortVersionString || true)"
[[ -n "$sparkle_version" ]] && ok "Sparkle version $sparkle_version"

log "Code signature"
if codesign --verify --deep --strict --verbose=2 "$app" >/dev/null 2>&1; then
    ok "codesign --verify --deep --strict"
else
    fail "codesign --verify --deep --strict:"
    codesign --verify --deep --strict --verbose=2 "$app" 2>&1 | sed 's/^/      /' >&2 || true
fi

if ((signed)); then
    log "Developer ID signature"
    for item in "${sparkle_parts[@]}" "$app"; do
        name="${item#"$app/"}"
        [[ "$item" == "$app" ]] && name="$(basename "$app")"
        details="$(codesign -dvv "$item" 2>&1 || true)"
        if grep -q '^Authority=Developer ID Application: .*('"$TEAM_ID"')$' <<<"$details" &&
            grep -q "^TeamIdentifier=$TEAM_ID\$" <<<"$details"; then
            ok "$name: Developer ID, team $TEAM_ID"
        else
            fail "$name: not signed with Developer ID Application for team $TEAM_ID"
        fi
        if grep -Eq '^CodeDirectory .*flags=0x[0-9a-f]*\([^)]*runtime' <<<"$details"; then
            ok "$name: hardened runtime"
        else
            fail "$name: hardened runtime flag missing"
        fi
        if grep -q '^Timestamp=' <<<"$details"; then
            ok "$name: secure timestamp"
        else
            fail "$name: no secure timestamp"
        fi
    done
fi

if ((distribution)); then
    log "Distribution"
    if spctl_out="$(spctl -a -t exec -vv "$app" 2>&1)"; then
        ok "spctl: $(tr '\n' ' ' <<<"$spctl_out")"
    else
        fail "spctl rejected the app:"
        printf '      %s\n' "${spctl_out//$'\n'/$'\n'      }" >&2
    fi
    if xcrun stapler validate "$app" >/dev/null 2>&1; then
        ok "stapler validate"
    else
        fail "no valid stapled notarization ticket (xcrun stapler validate)"
    fi
fi

if ((failures)); then
    die "$failures check(s) failed for $app"
fi
log "All checks passed for $app"
