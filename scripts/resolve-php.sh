#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib.sh"

request=${1:-}

[[ $request =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || fail "usage: resolve-php.sh <branch|version>, got: '$request'"

json=$(mktemp)
trap 'rm -f "$json"' EXIT

download "https://www.php.net/releases/?json&version=${request}" "$json"

version=$(jq -r '.version // empty' "$json")
[[ -n $version ]] || fail "php.net has no release for $request"
validate_version "$version"

if [[ $request =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && $request != "$version" ]]; then
  fail "php.net resolved $request to $version"
fi

sha256=$(jq -r --arg file "php-${version}.tar.xz" '[.source[]? | select(.filename == $file) | .sha256] | first // empty' "$json")
validate_sha256 "$sha256"

echo "version=$version"
echo "sha256=$sha256"
