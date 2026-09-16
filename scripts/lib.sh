#!/usr/bin/env bash

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly ROOT_DIR

readonly PLATFORMS="linux-x86_64 linux-aarch64 macos-aarch64"

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
  if command -v sha256sum >/dev/null; then
    sha256sum "$1" | cut -d ' ' -f 1
  else
    shasum -a 256 "$1" | cut -d ' ' -f 1
  fi
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
  grep -Ev '^[[:space:]]*(#|$)' "$ROOT_DIR/config/extensions.txt" | paste -sd , -
}
