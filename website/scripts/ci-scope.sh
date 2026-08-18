#!/usr/bin/env sh
set -u

full_regression() {
  printf '%s\n' 'full=true'
  exit 0
}

is_commit_id() {
  candidate=$1
  length=${#candidate}
  if [ "$length" -ne 40 ] && [ "$length" -ne 64 ]; then
    return 1
  fi
  case "$candidate" in
    *[!0-9a-f]*) return 1 ;;
    *[!0]*) return 0 ;;
    *) return 1 ;;
  esac
}

[ "$#" -eq 2 ] || full_regression
base_sha=$1
head_sha=$2

is_commit_id "$base_sha" || full_regression
is_commit_id "$head_sha" || full_regression
git cat-file -e "$base_sha^{commit}" 2>/dev/null || full_regression
git cat-file -e "$head_sha^{commit}" 2>/dev/null || full_regression

if git diff --quiet --no-renames "$base_sha" "$head_sha" -- \
  ':(top)website' ':(top,exclude)website/docs/**' ':(top).github/workflows/pages.yml'
then
  printf '%s\n' 'full=false'
else
  full_regression
fi
