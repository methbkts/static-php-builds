#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/../config/build.env"

build_env="$ROOT_DIR/config/build.env"
ci_yml="$ROOT_DIR/.github/workflows/ci.yml"
sources_lock="$ROOT_DIR/config/sources.lock"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

changed=0

is_newer() {
  [[ $1 != "$2" && $(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1) == "$2" ]]
}

set_value() {
  local file=$1 key=$2 value=$3
  awk -v key="$key" -v value="$value" '
    index($0, key "=") == 1 { print key "=" value; next }
    $0 ~ "^ *" key ": " { sub(/: .*/, ": " value); print; next }
    { print }
  ' "$file" >"$tmp/edit"
  cat "$tmp/edit" >"$file"
}

set_mirror() {
  local name=$1 sha256=$2 url=$3
  awk -v name="$name" -v line="  \"$name $sha256 $url\"" '
    index($0, "  \"" name " ") == 1 { print line; next }
    { print }
  ' "$build_env" >"$tmp/edit"
  cat "$tmp/edit" >"$build_env"
}

set_lock() {
  local package=$1 sha256=$2 file=$3
  awk -v package="$package" -v line="sha256:$sha256  $file" '
    $2 ~ "^" package "-[0-9]" { print line; next }
    { print }
  ' "$sources_lock" | sort -k2,2 >"$tmp/edit"
  cat "$tmp/edit" >"$sources_lock"
}

hash_of_url() {
  download "$1" "$tmp/download"
  sha256_of "$tmp/download"
}

same_or_fail() {
  [[ $1 == "$2" ]] || fail "$3: the two origins give different checksums: $1 and $2"
}

updated() {
  echo "$1: $2 -> $3"
  changed=1
}

current() {
  echo "$1: $2 is current"
}

update_spc() {
  local latest x86_64 aarch64
  latest=$(gh api repos/crazywhalecc/static-php-cli/releases/latest --jq .tag_name)
  if ! is_newer "$SPC_VERSION" "$latest"; then
    current static-php-cli "$SPC_VERSION"
    return
  fi
  x86_64=$(hash_of_url "https://github.com/crazywhalecc/static-php-cli/releases/download/${latest}/spc-linux-x86_64.tar.gz")
  aarch64=$(hash_of_url "https://github.com/crazywhalecc/static-php-cli/releases/download/${latest}/spc-linux-aarch64.tar.gz")
  set_value "$build_env" SPC_VERSION "$latest"
  set_value "$build_env" SPC_SHA256_LINUX_X86_64 "$x86_64"
  set_value "$build_env" SPC_SHA256_LINUX_AARCH64 "$aarch64"
  updated static-php-cli "$SPC_VERSION" "$latest"
}

update_composer() {
  local latest sha256 published
  download "https://getcomposer.org/versions" "$tmp/composer.json"
  latest=$(jq -r '.stable[0].version' "$tmp/composer.json")
  if ! is_newer "$COMPOSER_VERSION" "$latest"; then
    current Composer "$COMPOSER_VERSION"
    return
  fi
  sha256=$(hash_of_url "https://getcomposer.org/download/${latest}/composer.phar")
  download "https://getcomposer.org/download/${latest}/composer.phar.sha256sum" "$tmp/composer.sha256sum"
  published=$(cut -d ' ' -f 1 "$tmp/composer.sha256sum")
  same_or_fail "$sha256" "$published" Composer
  set_value "$build_env" COMPOSER_VERSION "$latest"
  set_value "$build_env" COMPOSER_SHA256 "$sha256"
  updated Composer "$COMPOSER_VERSION" "$latest"
}

update_xdebug() {
  local latest sha256 pecl
  download "https://pecl.php.net/rest/r/xdebug/stable.txt" "$tmp/xdebug.txt"
  latest=$(tr -d '[:space:]' <"$tmp/xdebug.txt")
  if ! is_newer "$XDEBUG_VERSION" "$latest"; then
    current Xdebug "$XDEBUG_VERSION"
    return
  fi
  sha256=$(hash_of_url "https://xdebug.org/files/xdebug-${latest}.tgz")
  pecl=$(hash_of_url "https://pecl.php.net/get/xdebug-${latest}.tgz")
  same_or_fail "$sha256" "$pecl" Xdebug
  set_value "$build_env" XDEBUG_VERSION "$latest"
  set_value "$build_env" XDEBUG_SHA256 "$sha256"
  set_lock xdebug "$sha256" "xdebug-${latest}.tgz"
  updated Xdebug "$XDEBUG_VERSION" "$latest"
}

update_actionlint() {
  local pinned latest sha256 published
  pinned=$(sed -n 's/^ *ACTIONLINT_VERSION: //p' "$ci_yml")
  latest=$(gh api repos/rhysd/actionlint/releases/latest --jq .tag_name | sed 's/^v//')
  if ! is_newer "$pinned" "$latest"; then
    current actionlint "$pinned"
    return
  fi
  sha256=$(hash_of_url "https://github.com/rhysd/actionlint/releases/download/v${latest}/actionlint_${latest}_linux_amd64.tar.gz")
  download "https://github.com/rhysd/actionlint/releases/download/v${latest}/actionlint_${latest}_checksums.txt" "$tmp/actionlint.txt"
  published=$(grep " actionlint_${latest}_linux_amd64.tar.gz\$" "$tmp/actionlint.txt" | cut -d ' ' -f 1)
  same_or_fail "$sha256" "$published" actionlint
  set_value "$ci_yml" ACTIONLINT_VERSION "$latest"
  set_value "$ci_yml" ACTIONLINT_SHA256 "$sha256"
  updated actionlint "$pinned" "$latest"
}

primary_url_of_mirror() {
  local directory=$1 package=$2 file=$3
  case $directory in
  */gnu/*) echo "https://ftp.gnu.org/gnu/${package}/${file}" ;;
  */nongnu/*) echo "https://download-mirror.savannah.gnu.org/releases/${package}/${file}" ;;
  *) fail "no primary origin known for mirror directory $directory" ;;
  esac
}

update_mirror() {
  local name=$1 url=$3
  local directory=${url%/*} file=${url##*/}
  local package=${file%%-[0-9]*} extension=${file##*.tar.}
  local pinned=${file#"${package}-"}
  pinned=${pinned%.tar.*}

  local latest_file latest sha256 primary
  download "${directory}/" "$tmp/listing.html"
  latest_file=$(grep -oE "${package}-[0-9]+(\.[0-9]+)*\.tar\.${extension}" "$tmp/listing.html" | sort -uV | tail -n 1)
  [[ -n $latest_file ]] || fail "$name: no ${package}-*.tar.${extension} in ${directory}/"
  latest=${latest_file#"${package}-"}
  latest=${latest%.tar.*}
  if ! is_newer "$pinned" "$latest"; then
    current "$name" "$pinned"
    return
  fi
  sha256=$(hash_of_url "${directory}/${latest_file}")
  primary=$(hash_of_url "$(primary_url_of_mirror "$directory" "$package" "$latest_file")")
  same_or_fail "$sha256" "$primary" "$name"
  set_mirror "$name" "$sha256" "${directory}/${latest_file}"
  set_lock "$package" "$sha256" "$latest_file"
  updated "$name" "$pinned" "$latest"
}

update_spc
update_composer
update_xdebug
update_actionlint
for mirror in "${SPC_SOURCE_MIRRORS[@]}"; do
  read -r mirror_name mirror_sha256 mirror_url <<<"$mirror"
  update_mirror "$mirror_name" "$mirror_sha256" "$mirror_url"
done

if ((changed)); then
  echo
  echo "Review the diff, then run the Release workflow with publish off. When the lock check fails, copy the lines from the sources.drift artifact into config/sources.lock."
fi
