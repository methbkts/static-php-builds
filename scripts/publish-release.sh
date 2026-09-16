#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/../config/build.env"

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GITHUB_SHA:?GITHUB_SHA is required}"

version=${1:-}
dist=${2:-}

validate_version "$version"
[[ -d $dist ]] || fail "usage: publish-release.sh <version> <dist-dir>"

cd "$dist"

expected=()
for platform in $PLATFORMS; do
  expected+=("php-${version}-${platform}.tar.gz")
  [[ -f "php-${version}-${platform}.tar.gz" ]] || fail "missing php-${version}-${platform}.tar.gz"
done

actual_count=$(find . -maxdepth 1 -type f | wc -l | tr -d ' ')
((actual_count == ${#expected[@]})) || fail "expected ${#expected[@]} files in $dist, found $actual_count"

sha256sum "${expected[@]}" >SHA256SUMS

state=$(release_state "$version")

if [[ $state == published ]]; then
  echo "PHP $version is already published, nothing to do"
  exit 0
fi

if [[ $state == draft ]]; then
  gh release delete "$version" --repo "$GITHUB_REPOSITORY" --yes
fi

latest=false

if ! is_prerelease "$version"; then
  highest=$({ gh release list --repo "$GITHUB_REPOSITORY" --exclude-drafts --limit 1000 --json tagName --jq '.[].tagName'; echo "$version"; } | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1)
  [[ $highest == "$version" ]] && latest=true
fi

notes=$(
  cat <<EOF
PHP ${version} for Linux (x86_64, aarch64; glibc ${GLIBC_VERSION}+).

Includes Composer ${COMPOSER_VERSION} and Xdebug (off by default; enable with \`XDEBUG_MODE\`). Built with static-php-cli ${SPC_VERSION} from the official php.net source (SHA-256 verified). The checksum of every other source that went into the build is in \`share/sources.txt\`.

Extensions: $(extensions_csv | sed 's/,/, /g')

Verify a download:

\`\`\`
gh attestation verify php-${version}-linux-x86_64.tar.gz --repo ${GITHUB_REPOSITORY}
\`\`\`
EOF
)

gh release create "$version" \
  --repo "$GITHUB_REPOSITORY" \
  --target "$GITHUB_SHA" \
  --title "PHP $version" \
  --notes "$notes" \
  --latest="$latest" \
  --draft \
  "${expected[@]}" SHA256SUMS

gh release edit "$version" --repo "$GITHUB_REPOSITORY" --draft=false

echo "Published PHP $version"
