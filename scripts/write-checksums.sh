#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib.sh"

version=${1:-}
dist=${2:-}

validate_version "$version"
[[ -d $dist ]] || fail "usage: write-checksums.sh <version> <dist-dir>"

cd "$dist"

expected=()
for platform in $PLATFORMS; do
  expected+=("php-${version}-${platform}.tar.gz")
  [[ -f "php-${version}-${platform}.tar.gz" ]] || fail "missing php-${version}-${platform}.tar.gz"
done

actual_count=$(find . -maxdepth 1 -type f ! -name SHA256SUMS | wc -l | tr -d ' ')
((actual_count == ${#expected[@]})) || fail "expected ${#expected[@]} tarballs in $dist, found $actual_count files"

sha256sum "${expected[@]}" >SHA256SUMS
cat SHA256SUMS
