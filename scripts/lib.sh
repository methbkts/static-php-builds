#!/usr/bin/env bash

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly ROOT_DIR

readonly PLATFORMS="linux-x86_64 linux-aarch64"

fail() {
  echo "error: $*" >&2
  exit 1
}

download() {
  curl --fail --silent --show-error --location \
    --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --connect-timeout 30 --max-time 900 \
    --retry 3 --retry-delay 5 \
    --output "$2" "$1"
}

sha256_of() {
  sha256sum "$1" | cut -d ' ' -f 1
}

verify_sha256() {
  local actual
  actual=$(sha256_of "$1")

  [[ $actual == "$2" ]] || fail "checksum mismatch for $1: expected $2, got $actual"
}

validate_version() {
  [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+((alpha|beta|RC)[0-9]+)?$ ]] || fail "invalid PHP version: $1"
}

is_prerelease() {
  [[ $1 =~ (alpha|beta|RC)[0-9]+$ ]]
}

validate_source_url() {
  local version=$1 url=$2

  if is_prerelease "$version"; then
    [[ $url =~ ^https://downloads\.php\.net/~[a-z0-9_-]+/php-${version//./\\.}\.tar\.xz$ ]] || fail "unexpected source URL for PHP $version: $url"
  else
    [[ $url == "https://www.php.net/distributions/php-${version}.tar.xz" ]] || fail "unexpected source URL for PHP $version: $url"
  fi
}

verify_php_signature() {
  local version=$1 tarball=$2 signature=$3
  local branch=${version%.*}
  local allowed
  allowed=$(awk -v branch="$branch" '$1 == branch { print $2 }' "$ROOT_DIR/config/php-release-keys.txt")
  [[ -n $allowed ]] || fail "no release manager key for PHP $branch in config/php-release-keys.txt"

  local home status signer
  home=$(mktemp -d)
  chmod 0700 "$home"
  gpg --homedir "$home" --batch --quiet --import "$ROOT_DIR/config/php-release-keys.asc"
  status=$(gpg --homedir "$home" --batch --status-fd 1 --verify "$signature" "$tarball" 2>/dev/null || true)
  rm -rf "$home"

  grep -q '^\[GNUPG:\] REVKEYSIG ' <<<"$status" && fail "$tarball is signed by a revoked key"
  signer=$(sed -n 's/^\[GNUPG:\] VALIDSIG .* \([0-9A-F]\{40\}\)$/\1/p' <<<"$status")
  [[ -n $signer ]] || fail "invalid signature for $tarball: $status"
  grep -qxF "$signer" <<<"$allowed" || fail "$tarball is signed by $signer, which is not a release manager key for PHP $branch"
  echo "$signer"
}

validate_sha256() {
  [[ $1 =~ ^[0-9a-f]{64}$ ]] || fail "invalid SHA-256 digest: $1"
}

validate_platform() {
  local platform
  for platform in $PLATFORMS; do
    [[ $1 == "$platform" ]] && return 0
  done
  fail "unsupported platform: $1 (expected one of: $PLATFORMS)"
}

release_state() {
  local answer
  if answer=$(gh release view "$1" --repo "$GITHUB_REPOSITORY" --json isDraft --jq .isDraft 2>&1); then
    case $answer in
    true) echo draft ;;
    false) echo published ;;
    *) fail "unexpected answer from [gh release view $1]: [$answer]" ;;
    esac
  elif [[ $answer == *"release not found"* ]]; then
    echo absent
  else
    fail "cannot read release [$1]: [$answer]"
  fi
}

extensions_csv() {
  local branch=${1%.*}
  local excluded
  excluded=$(awk -v branch="$branch" '$1 == branch { print $2 }' "$ROOT_DIR/config/extensions-excluded.txt")
  grep -Ev '^[[:space:]]*(#|$)' "$ROOT_DIR/config/extensions.txt" | grep -vxF -e "$excluded" | paste -sd , -
}
