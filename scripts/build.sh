#!/usr/bin/env bash
# Builds HerdrCoreBar with SwiftPM and assembles a signed "Herdr Core Bar.app".
# The only line written to stdout is the absolute path of the finished app; all logs go to stderr.
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

usage() {
    cat <<EOF
Usage: scripts/build.sh [options]

  --config debug|release   Build configuration (default: release)
  --universal              Build arm64 + x86_64 (default: host architecture only)
  --version X.Y.Z          CFBundleShortVersionString (default: from Resources/Info.plist)
  --build N                CFBundleVersion (default: git rev-list --count HEAD)
  --output DIR             Output directory for the .app (default: dist)
  --sign IDENTITY          Code signing identity; "-" signs ad-hoc (default: -)
                           A real identity adds --options runtime --timestamp.
  --open                   Launch the app after building
  --scratch-path P         SwiftPM scratch path (default: .build)
  -h, --help               Show this help
EOF
}

config="release"
universal=0
version=""
build_number=""
output="dist"
identity="-"
open_app=0
scratch=".build"

need_value() {
    [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || die "$1 requires a value (see --help)"
}

while (($#)); do
    case "$1" in
    --config) need_value "$@"; config="$2"; shift 2 ;;
    --universal) universal=1; shift ;;
    --version) need_value "$@"; version="$2"; shift 2 ;;
    --build) need_value "$@"; build_number="$2"; shift 2 ;;
    --output) need_value "$@"; output="$2"; shift 2 ;;
    --sign) [[ $# -ge 2 && -n "$2" ]] || die "--sign requires a value"; identity="$2"; shift 2 ;;
    --open) open_app=1; shift ;;
    --scratch-path) need_value "$@"; scratch="$2"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
    esac
done

case "$config" in
debug | release) ;;
*) die "--config must be debug or release, got '$config'" ;;
esac

require_cmd swift xcrun codesign ditto otool lipo git

# Resolve user-supplied paths against the caller's working directory before changing into the repo.
mkdir -p "$output" "$scratch"
output="$(cd "$output" && pwd)"
scratch="$(cd "$scratch" && pwd)"
cd "$REPO_ROOT"

info_plist_src="$REPO_ROOT/Resources/Info.plist"
icon_src="$REPO_ROOT/Resources/AppIcon.icon"
entitlements="$REPO_ROOT/Resources/HerdrCoreBar.entitlements"

if [[ -z "$version" ]]; then
    version="$(plist_get "$info_plist_src" :CFBundleShortVersionString)" || die "cannot read version from $info_plist_src"
fi
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "--version must look like X.Y.Z, got '$version'"

if [[ -z "$build_number" ]]; then
    build_number="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
fi
[[ "$build_number" =~ ^[1-9][0-9]*$ ]] || die "--build must be a positive integer, got '$build_number'"

swift_args=(-c "$config" --product "$APP_EXECUTABLE" --scratch-path "$scratch")
if ((universal)); then
    swift_args+=(--arch arm64 --arch x86_64)
fi

arch_desc="$(uname -m)"
((universal)) && arch_desc="arm64 + x86_64"
log "Building $APP_EXECUTABLE ($config, $arch_desc) $version ($build_number)"
swift build "${swift_args[@]}" >&2
bin_path="$(swift build "${swift_args[@]}" --show-bin-path)"
binary="$bin_path/$APP_EXECUTABLE"
sparkle_src="$bin_path/Sparkle.framework"
[[ -x "$binary" ]] || die "built executable not found at $binary"
[[ -d "$sparkle_src" ]] || sparkle_src="$bin_path/PackageFrameworks/Sparkle.framework"
[[ -d "$sparkle_src" ]] || die "Sparkle.framework not found in $bin_path"

if ((universal)); then
    for arch in arm64 x86_64; do
        lipo "$binary" -verify_arch "$arch" || die "$binary is missing architecture $arch"
    done
fi
otool -l "$binary" | grep -A2 LC_RPATH | grep -q '@executable_path/../Frameworks' ||
    die "$binary lacks the @executable_path/../Frameworks rpath (see linkerSettings in Package.swift)"

log "Compiling app icon"
icon_out="$scratch/app-icon"
rm -rf "$icon_out"
mkdir -p "$icon_out"
xcrun actool "$icon_src" \
    --compile "$icon_out" \
    --platform macosx \
    --minimum-deployment-target 27.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$icon_out/partial-info.plist" \
    --output-format human-readable-text --errors --warnings >&2
[[ -f "$icon_out/Assets.car" && -f "$icon_out/AppIcon.icns" ]] || die "actool did not produce Assets.car and AppIcon.icns"

app="$output/$APP_NAME.app"
log "Assembling $app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"

ditto "$binary" "$app/Contents/MacOS/$APP_EXECUTABLE"
cp "$info_plist_src" "$app/Contents/Info.plist"
plist_set "$app/Contents/Info.plist" :CFBundleShortVersionString string "$version"
plist_set "$app/Contents/Info.plist" :CFBundleVersion string "$build_number"
printf 'APPL????' >"$app/Contents/PkgInfo"
cp "$icon_out/Assets.car" "$icon_out/AppIcon.icns" "$app/Contents/Resources/"

for bundle in "$bin_path"/*.bundle; do
    [[ -d "$bundle" ]] || continue
    case "$(basename "$bundle")" in *Tests*) continue ;; esac
    ditto "$bundle" "$app/Contents/Resources/$(basename "$bundle")"
done

fw="$app/Contents/Frameworks/Sparkle.framework"
ditto "$sparkle_src" "$fw"
# Like Xcode's "Embed & Sign": headers and module maps are build-time only.
rm -rf "$fw/Headers" "$fw/PrivateHeaders" "$fw/Modules" \
    "$fw/Versions/B/Headers" "$fw/Versions/B/PrivateHeaders" "$fw/Versions/B/Modules"

if [[ -d "$bin_path/$APP_EXECUTABLE.dSYM" ]]; then
    rm -rf "$output/$APP_EXECUTABLE.dSYM"
    ditto "$bin_path/$APP_EXECUTABLE.dSYM" "$output/$APP_EXECUTABLE.dSYM"
fi

xattr -cr "$app"

if [[ "$identity" == "-" ]]; then
    sign_opts=(--timestamp=none)
    log "Signing ad-hoc"
else
    sign_opts=(--options runtime --timestamp)
    log "Signing with '$identity' (hardened runtime, secure timestamp)"
fi

sign() {
    codesign --force --sign "$identity" "${sign_opts[@]}" "$@" >&2
}

# Inside-out, per Sparkle 2 docs; --deep is avoided so Downloader.xpc keeps its own entitlements.
sign "$fw/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$fw/Versions/B/XPCServices/Downloader.xpc"
sign "$fw/Versions/B/Autoupdate"
sign "$fw/Versions/B/Updater.app"
sign "$fw"
if [[ -f "$entitlements" ]]; then
    sign --entitlements "$entitlements" "$app"
else
    sign "$app"
fi

codesign --verify --deep --strict "$app" >&2 || die "code signature verification failed for $app"
log "Built $app"
printf '%s\n' "$app"

if ((open_app)); then
    open "$app"
fi
