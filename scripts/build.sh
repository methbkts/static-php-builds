#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/../config/build.env"

version=${1:-}
php_sha256=${2:-}
platform=${3:-}
source_url=${4:-}

validate_version "$version"
validate_sha256 "$php_sha256"
validate_platform "$platform"
validate_source_url "$version" "$source_url"

umask 022

work="$ROOT_DIR/.build/$platform"
dist="$ROOT_DIR/dist"

rm -rf "$work"
mkdir -p "$work" "$dist"
cd "$work"

case "$platform" in
linux-x86_64)
  spc_asset=spc-linux-x86_64.tar.gz
  spc_sha256=$SPC_SHA256_LINUX_X86_64
  export SPC_TARGET="x86_64-linux-gnu.${GLIBC_VERSION}"
  ;;
linux-aarch64)
  spc_asset=spc-linux-aarch64.tar.gz
  spc_sha256=$SPC_SHA256_LINUX_AARCH64
  export SPC_TARGET="aarch64-linux-gnu.${GLIBC_VERSION}"
  ;;
esac

record_sources() {
  local path name
  for path in "$work"/downloads/*; do
    name=$(basename "$path")
    if [[ -d $path/.git ]]; then
      echo "git:$(git -C "$path" rev-parse HEAD)  $name"
    elif [[ -f $path ]]; then
      echo "sha256:$(sha256_of "$path")  $name"
    else
      fail "unexpected download [$path]"
    fi
  done
}

echo "::group::Download static-php-cli $SPC_VERSION"
download "https://github.com/crazywhalecc/static-php-cli/releases/download/${SPC_VERSION}/${spc_asset}" "$work/spc.tar.gz"
verify_sha256 "$work/spc.tar.gz" "$spc_sha256"
tar -xzf "$work/spc.tar.gz" -C "$work" spc
chmod 0755 "$work/spc"
"$work/spc" --version
echo "::endgroup::"

extensions=$(extensions_csv)
branch=${version%.*}

if [[ $branch == 8.6 ]]; then
  export SPC_MICRO_PATCHES=disable_huge_page_84
fi

echo "::group::Install build tools"
"$work/spc" doctor --auto-fix
echo "::endgroup::"

echo "::group::Download sources"
"$work/spc" download \
  --with-php="$branch" \
  --for-extensions="${extensions},xdebug" \
  --custom-url="php-src:${source_url}" \
  --retry=3 \
  --debug

php_source="$work/downloads/php-${version}.tar.xz"
[[ -f $php_source ]] || fail "PHP source not found at $php_source"
verify_sha256 "$php_source" "$php_sha256"
sources=$(record_sources)
echo "$sources"
echo "::endgroup::"

if [[ $branch == 8.3 ]]; then
  echo "::group::Patch PHP $version"
  "$work/spc" extract php-src
  patch -p1 -d "$work/source/php-src" <"$ROOT_DIR/patches/php-8.3-avx512-cache.patch"
  echo "::endgroup::"
fi

echo "::group::Build PHP $version"
"$work/spc" build "$extensions" \
  --build-cli \
  --build-shared=xdebug \
  --with-suggested-libs \
  --debug
echo "::endgroup::"

echo "::group::Package"
stage="$work/stage"
mkdir -p "$stage/bin" "$stage/libexec" "$stage/lib/php/extensions" "$stage/etc/php/conf.d" "$stage/share"

install -m 0755 "$work/buildroot/bin/php" "$stage/libexec/php"
install -m 0755 "$work/buildroot/modules/xdebug.so" "$stage/lib/php/extensions/xdebug.so"
install -m 0755 "$ROOT_DIR/stubs/php" "$stage/bin/php"
install -m 0755 "$ROOT_DIR/stubs/composer" "$stage/bin/composer"
install -m 0644 "$ROOT_DIR/stubs/xdebug.ini" "$stage/etc/php/conf.d/xdebug.ini"

download "https://getcomposer.org/download/${COMPOSER_VERSION}/composer.phar" "$work/composer.phar"
verify_sha256 "$work/composer.phar" "$COMPOSER_SHA256"
install -m 0644 "$work/composer.phar" "$stage/libexec/composer.phar"

cp -R "$work/buildroot/license" "$stage/share/licenses"

echo "$sources" >"$stage/share/sources.txt"

cat >"$stage/share/build-info.txt" <<EOF
PHP ${version} (${platform})
PHP source SHA-256: ${php_sha256}
static-php-cli: ${SPC_VERSION}
Target: ${SPC_TARGET}
Composer: ${COMPOSER_VERSION}
Extensions: ${extensions}
Shared extensions: xdebug
Sources: share/sources.txt
EOF

tarball="$dist/php-${version}-${platform}.tar.gz"
tar -czf "$tarball" -C "$stage" bin etc lib libexec share
echo "::endgroup::"

echo "Built $tarball ($(sha256_of "$tarball"))"
