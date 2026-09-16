#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/../config/build.env"

ACTIONLINT_VERSION=$(sed -n 's/^ *ACTIONLINT_VERSION: //p' "$ROOT_DIR/.github/workflows/ci.yml")
[[ -n $ACTIONLINT_VERSION ]] || fail "ACTIONLINT_VERSION not found in .github/workflows/ci.yml"

json=$(mktemp)
trap 'rm -f "$json"' EXIT

latest_github_release() {
  gh api "repos/$1/releases/latest" --jq .tag_name | sed 's/^v//'
}

latest_composer() {
  download "https://getcomposer.org/versions" "$json"
  jq -r '.stable[0].version' "$json"
}

latest_xdebug() {
  download "https://pecl.php.net/rest/r/xdebug/stable.txt" "$json"
  tr -d '[:space:]' <"$json"
}

is_newer() {
  [[ $1 != "$2" && $(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1) == "$2" ]]
}

outdated=0

report_tool() {
  local name=$1 pinned=$2 latest=$3 file=$4
  [[ $latest =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?([A-Za-z0-9.-]*)$ ]] || fail "unexpected latest version for $name: [$latest]"
  if is_newer "$pinned" "$latest"; then
    outdated=1
    echo "| $name | $pinned | **$latest** | \`$file\` |"
  else
    echo "| $name | $pinned | $latest | \`$file\` |"
  fi
}

echo "| Tool | Pinned | Latest | File |"
echo "| --- | --- | --- | --- |"
report_tool static-php-cli "$SPC_VERSION" "$(latest_github_release crazywhalecc/static-php-cli)" config/build.env
report_tool Composer "$COMPOSER_VERSION" "$(latest_composer)" config/build.env
report_tool Xdebug "$XDEBUG_VERSION" "$(latest_xdebug)" config/build.env
report_tool actionlint "$ACTIONLINT_VERSION" "$(latest_github_release rhysd/actionlint)" .github/workflows/ci.yml

exit "$outdated"
