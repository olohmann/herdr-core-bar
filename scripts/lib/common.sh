# shellcheck shell=bash
# Shared helpers for scripts/*.sh. Source it; do not execute it.

# shellcheck disable=SC2034
APP_NAME="Herdr Core Bar"
# shellcheck disable=SC2034
APP_EXECUTABLE="HerdrCoreBar"
# shellcheck disable=SC2034
APP_BUNDLE_ID="com.olohmann.herdr-core-bar"
# shellcheck disable=SC2034
TEAM_ID="QCRM9T8GD4"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ -t 2 ]]; then
    _c_bold=$'\033[1m' _c_red=$'\033[31m' _c_yellow=$'\033[33m' _c_green=$'\033[32m' _c_reset=$'\033[0m'
else
    _c_bold="" _c_red="" _c_yellow="" _c_green="" _c_reset=""
fi

log() { printf '%s==>%s %s\n' "$_c_bold" "$_c_reset" "$*" >&2; }
warn() { printf '%swarning:%s %s\n' "$_c_yellow" "$_c_reset" "$*" >&2; }
ok() { printf '%s  ok%s %s\n' "$_c_green" "$_c_reset" "$*" >&2; }
die() {
    printf '%serror:%s %s\n' "$_c_red" "$_c_reset" "$*" >&2
    exit 1
}

require_cmd() {
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || die "required command not found: $cmd"
    done
}

# plist_get <plist> <key-path>   e.g. plist_get Info.plist :CFBundleVersion
plist_get() {
    /usr/libexec/PlistBuddy -c "Print $2" "$1" 2>/dev/null
}

# plist_set <plist> <key-path> <type> <value>   adds the key if it is missing
plist_set() {
    /usr/libexec/PlistBuddy -c "Set $2 $4" "$1" 2>/dev/null ||
        /usr/libexec/PlistBuddy -c "Add $2 $3 $4" "$1"
}
