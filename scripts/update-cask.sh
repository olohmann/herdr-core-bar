#!/usr/bin/env bash
# Point the Homebrew cask at a released version.
#
# Usage: scripts/update-cask.sh <version> <dmg-sha256> [--render FILE] [--tap OWNER/REPO]
#
# Default: clone the tap (TAP_TOKEN if set, else the current gh login), update
# Casks/herdr-core-bar.rb, commit, and push. --render only writes the updated
# cask from packaging/homebrew to FILE and touches nothing remote.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
template="$repo_root/packaging/homebrew/herdr-core-bar.rb"
cask_path="Casks/herdr-core-bar.rb"
tap_repo="${TAP_REPO:-olohmann/homebrew-tap}"

usage() {
    sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

log() { printf '==> %s\n' "$*" >&2; }
die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

render=""
positional=()
while (($#)); do
    case "$1" in
        --render)
            (($# >= 2)) || die "--render needs a file"
            render="$2"
            shift
            ;;
        --tap)
            (($# >= 2)) || die "--tap needs OWNER/REPO"
            tap_repo="$2"
            shift
            ;;
        -h | --help) usage 0 ;;
        -*) die "unknown option: $1" ;;
        *) positional+=("$1") ;;
    esac
    shift
done
((${#positional[@]} == 2)) || usage 1

version="${positional[0]}"
sha="${positional[1]}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || die "not a semantic version: $version"
[[ "$sha" =~ ^[0-9a-f]{64}$ ]] || die "not a sha256 hex digest: $sha"

# Rewrites the first `version` and `sha256` stanzas in place.
update_file() {
    local file=$1
    grep -Eq '^  version "' "$file" || die "no version stanza in $file"
    grep -Eq '^  sha256 ' "$file" || die "no sha256 stanza in $file"
    sed -E -i '' \
        -e "1,/^  version \"/ s/^  version \".*\"/  version \"$version\"/" \
        -e "1,/^  sha256 / s/^  sha256 .*/  sha256 \"$sha\"/" \
        "$file"
    if command -v ruby >/dev/null; then
        ruby -c "$file" >/dev/null || die "updated cask is not valid Ruby: $file"
    fi
}

if [[ -n "$render" ]]; then
    mkdir -p "$(dirname "$render")"
    cp "$template" "$render"
    update_file "$render"
    log "Rendered cask for $version: $render"
    exit 0
fi

command -v gh >/dev/null || die "gh not found"
if [[ -n "${TAP_TOKEN:-}" ]]; then
    export GH_TOKEN="$TAP_TOKEN"
fi

if ! gh repo view "$tap_repo" --json name >/dev/null 2>&1; then
    cat >&2 <<EOF
warning: tap repository $tap_repo is missing or not accessible; skipping the cask update.
         Create it once with: gh repo create $tap_repo --public --description "Homebrew tap"
         then run: scripts/update-cask.sh $version $sha
EOF
    exit 0
fi

work="$repo_root/dist/.tap-$$"
# shellcheck disable=SC2329 # invoked by the EXIT trap
cleanup() { rm -rf "$work"; }
trap cleanup EXIT
rm -rf "$work"

# gh supplies credentials for clone; pass the same helper explicitly for push.
git_auth=(-c credential.helper= -c 'credential.helper=!gh auth git-credential')

log "Cloning $tap_repo"
gh repo clone "$tap_repo" "$work" -- --quiet --depth 1

target="$work/$cask_path"
if [[ ! -f "$target" ]]; then
    log "Adding $cask_path from template"
    mkdir -p "$(dirname "$target")"
    cp "$template" "$target"
fi
update_file "$target"

cd "$work"
if git diff --quiet -- "$cask_path" && git ls-files --error-unmatch "$cask_path" >/dev/null 2>&1; then
    log "Cask already at $version; nothing to push"
    exit 0
fi

author=()
if [[ -z "$(git config user.email || true)" ]]; then
    author=(-c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com")
fi

git add -- "$cask_path"
git ${author[@]+"${author[@]}"} commit --quiet -m "herdr-core-bar $version"
branch="$(git rev-parse --abbrev-ref HEAD)"
for attempt in 1 2 3; do
    if git "${git_auth[@]}" push --quiet origin "HEAD:$branch"; then
        log "Pushed herdr-core-bar $version to $tap_repo ($branch)"
        exit 0
    fi
    log "Push rejected (attempt $attempt); rebasing on origin/$branch"
    git "${git_auth[@]}" pull --quiet --rebase origin "$branch"
done
die "could not push to $tap_repo"
