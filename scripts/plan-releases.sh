#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib.sh"

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

requested=${1:-}

if [[ -n $requested ]]; then
  requests=("$requested")
else
  mapfile -t requests < <(grep -Ev '^[[:space:]]*(#|$)' "$ROOT_DIR/config/php-branches.txt")
fi

releases=()

for request in "${requests[@]}"; do
  resolved=$("$ROOT_DIR/scripts/resolve-php.sh" "$request")
  version=$(sed -n 's/^version=//p' <<<"$resolved")
  sha256=$(sed -n 's/^sha256=//p' <<<"$resolved")

  validate_version "$version"
  validate_sha256 "$sha256"

  state=$(release_state "$version")

  if [[ -z $requested && $state == published ]]; then
    echo "PHP $version is already released, skipping" >&2
    continue
  fi

  echo "PHP $version will be built" >&2
  releases+=("$(jq -cn --arg version "$version" --arg sha256 "$sha256" '{version: $version, sha256: $sha256}')")
done

if ((${#releases[@]} == 0)); then
  echo "releases=[]"
else
  echo "releases=$(printf '%s\n' "${releases[@]}" | jq -cs .)"
fi
