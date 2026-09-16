#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib.sh"

request=${1:-}

[[ $request =~ ^[0-9]+\.[0-9]+(\.[0-9]+((alpha|beta|RC)[0-9]+)?)?$ ]] || fail "usage: resolve-php.sh <branch|version>, got: '$request'"

json=$(mktemp)
trap 'rm -f "$json"' EXIT

version=""
sha256=""
url=""

resolve_stable() {
  download "https://www.php.net/releases/?json&version=${request}" "$json"

  version=$(jq -r '.version // empty' "$json")
  [[ -n $version ]] || return 0

  sha256=$(jq -r --arg file "php-${version}.tar.xz" '[.source[]? | select(.filename == $file) | .sha256] | first // empty' "$json")
  url="https://www.php.net/distributions/php-${version}.tar.xz"
}

resolve_prerelease() {
  download "https://qa.php.net/api.php?type=qa-releases&format=json" "$json"

  local release
  release=$(jq -c --arg request "$request" '[.releases[]? | select(.version == $request or (.version | startswith($request + ".")))] | first // empty' "$json")
  [[ -n $release ]] || return 0

  version=$(jq -r '.version // empty' <<<"$release")
  sha256=$(jq -r '.files.xz.sha256 // empty' <<<"$release")
  url=$(jq -r '.files.xz.path // empty' <<<"$release")
}

if ! is_prerelease "$request"; then
  resolve_stable
fi

if [[ -z $version && ! $request =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  resolve_prerelease
fi

[[ -n $version ]] || fail "php.net has no release for $request"
validate_version "$version"

if [[ $request =~ ^[0-9]+\.[0-9]+\.[0-9]+ && $request != "$version" ]]; then
  fail "php.net resolved $request to $version"
fi

validate_sha256 "$sha256"
validate_source_url "$version" "$url"

echo "version=$version"
echo "sha256=$sha256"
echo "url=$url"
