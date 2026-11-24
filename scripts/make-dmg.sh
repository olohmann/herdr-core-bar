#!/usr/bin/env bash
# Build a drag-to-install disk image with hdiutil only.
#
# Usage: scripts/make-dmg.sh <app> <out.dmg> <volume-name> [--layout] [--format ULFO|UDZO]
#
# --layout arranges the Finder window through AppleScript. It needs a GUI session
# with Finder automation permission, so it is opt-in and failures only warn.
set -euo pipefail

usage() {
    sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

log() { printf '==> %s\n' "$*" >&2; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

layout=0
format="${DMG_FORMAT:-ULFO}"
positional=()
while (($#)); do
    case "$1" in
        --layout) layout=1 ;;
        --format)
            (($# >= 2)) || die "--format needs a value"
            format="$2"
            shift
            ;;
        -h | --help) usage 0 ;;
        -*) die "unknown option: $1" ;;
        *) positional+=("$1") ;;
    esac
    shift
done
((${#positional[@]} == 3)) || usage 1

app="${positional[0]%/}"
out="${positional[1]}"
volname="${positional[2]}"

[[ -d "$app" ]] || die "app bundle not found: $app"
[[ "$out" == *.dmg ]] || die "output must end in .dmg: $out"
case "$format" in
    ULFO | UDZO) ;;
    *) die "unsupported format: $format (use ULFO or UDZO)" ;;
esac
command -v hdiutil >/dev/null || die "hdiutil not found"

app_name="$(basename "$app")"
out_dir="$(cd "$(dirname "$out")" && pwd)"
out="$out_dir/$(basename "$out")"
work="${out%.dmg}.dmgwork"
mountpoint=""

cleanup() {
    if [[ -n "$mountpoint" && -d "$mountpoint" ]]; then
        hdiutil detach "$mountpoint" -quiet -force >/dev/null 2>&1 || true
    fi
    rm -rf "$work"
}
trap cleanup EXIT

rm -rf "$work" "$out"
mkdir -p "$work/root"

log "Staging $app_name"
ditto "$app" "$work/root/$app_name"
ln -s /Applications "$work/root/Applications"

apply_layout() {
    local dev_mount=$1
    local disk_name
    disk_name="$(basename "$dev_mount")"
    osascript - "$disk_name" "$app_name" <<'APPLESCRIPT'
on run argv
    set diskName to item 1 of argv
    set appName to item 2 of argv
    tell application "Finder"
        tell disk diskName
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set the bounds of container window to {200, 120, 740, 460}
            set viewOptions to the icon view options of container window
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to 112
            set text size of viewOptions to 13
            set position of item appName of container window to {140, 160}
            set position of item "Applications" of container window to {400, 160}
            update without registering applications
            delay 1
            close
        end tell
    end tell
end run
APPLESCRIPT
}

if ((layout)); then
    log "Creating writable image for window layout"
    rw="$work/rw.dmg"
    hdiutil create -quiet -volname "$volname" -srcfolder "$work/root" -fs HFS+ -format UDRW -ov "$rw"
    mountpoint="$(hdiutil attach "$rw" -readwrite -noverify -noautoopen |
        awk -F'\t' '/\/Volumes\// { print $NF; exit }')"
    [[ -n "$mountpoint" ]] || die "could not mount $rw"
    if apply_layout "$mountpoint"; then
        log "Applied Finder layout"
    else
        warn "Finder layout failed; continuing with the default window"
    fi
    sync
    hdiutil detach "$mountpoint" -quiet || hdiutil detach "$mountpoint" -quiet -force
    mountpoint=""
    log "Compressing ($format)"
    hdiutil convert -quiet "$rw" -format "$format" -o "$out"
else
    log "Creating $format image"
    hdiutil create -quiet -volname "$volname" -srcfolder "$work/root" -fs HFS+ -format "$format" -ov "$out"
fi

hdiutil verify -quiet "$out"
log "Disk image ready: $out"
printf '%s\n' "$out"
