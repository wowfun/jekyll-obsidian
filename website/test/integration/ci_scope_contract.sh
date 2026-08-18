#!/usr/bin/env sh
set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
SITE_DIR=$(CDPATH= cd -- "$TEST_DIR/../.." && pwd -P)
CLASSIFIER="$SITE_DIR/scripts/ci-scope.sh"
temporary_roots=""

cleanup() {
  for root in $temporary_roots; do
    case "$root" in
      "${TMPDIR:-/tmp}"/jekyll-obsidian-ci-scope.*) rm -rf -- "$root" ;;
    esac
  done
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

fail() {
  printf '%s\n' "CI scope contract failed: $1" >&2
  exit 1
}

new_repository() {
  repository=$(mktemp -d "${TMPDIR:-/tmp}/jekyll-obsidian-ci-scope.XXXXXX")
  temporary_roots="$temporary_roots $repository"
  git -C "$repository" init -q
  git -C "$repository" config user.name "CI Scope Contract"
  git -C "$repository" config user.email "ci-scope@example.invalid"
  mkdir -p "$repository/content"
  printf '%s\n' '# Initial' > "$repository/content/index.md"
  git -C "$repository" add content/index.md
  git -C "$repository" commit -qm "initial"
  base_sha=$(git -C "$repository" rev-parse HEAD)
}

assert_scope() {
  expected=$1
  base=$2
  head=$3
  label=$4

  if ! actual=$(cd "$repository" && "$CLASSIFIER" "$base" "$head"); then
    fail "$label could not be classified."
  fi
  [ "$actual" = "full=$expected" ] ||
    fail "$label returned '$actual' instead of 'full=$expected'."
}

assert_scope_from_website() {
  expected=$1
  base=$2
  head=$3
  label=$4
  mkdir -p "$repository/website"

  if ! actual=$(cd "$repository/website" && "$CLASSIFIER" "$base" "$head"); then
    fail "$label could not be classified from the workflow directory."
  fi
  [ "$actual" = "full=$expected" ] ||
    fail "$label returned '$actual' instead of 'full=$expected' from the workflow directory."
}

assert_added_path_requires_full() {
  path=$1
  label=$2
  new_repository
  mkdir -p "$repository/${path%/*}"
  printf '%s\n' 'implementation change' > "$repository/$path"
  git -C "$repository" add "$path"
  git -C "$repository" commit -qm "change $label"
  assert_scope true "$base_sha" "$(git -C "$repository" rev-parse HEAD)" "$label"
}

new_repository
printf '%s\n' '# Content update' > "$repository/content/index.md"
git -C "$repository" add content/index.md
git -C "$repository" commit -qm "update content"
assert_scope false "$base_sha" "$(git -C "$repository" rev-parse HEAD)" "content-only change"

mkdir -p "$repository/.github"
printf '%s\n' 'title: Updated host' > "$repository/.github/jekyll-obsidian.yml"
git -C "$repository" add .github/jekyll-obsidian.yml
git -C "$repository" commit -qm "update host configuration"
assert_scope false "$base_sha" "$(git -C "$repository" rev-parse HEAD)" "host configuration change"

mkdir -p "$repository/website/docs"
printf '%s\n' '# Deployment' > "$repository/website/docs/Deployment.md"
git -C "$repository" add website/docs/Deployment.md
git -C "$repository" commit -qm "update source documentation"
assert_scope false "$base_sha" "$(git -C "$repository" rev-parse HEAD)" "website documentation change"
assert_scope_from_website false "$base_sha" "$(git -C "$repository" rev-parse HEAD)" "website documentation change"

assert_added_path_requires_full "website/lib/jekyll_obsidian/compiler.rb" "Ruby implementation change"
assert_added_path_requires_full "website/assets/js/application.js" "frontend implementation change"
assert_added_path_requires_full "website/package-lock.json" "dependency change"
assert_added_path_requires_full "website/test/unit/compiler_test.rb" "test change"
assert_added_path_requires_full "website/scripts/templates/pages.yml" "workflow template change"
assert_added_path_requires_full ".github/workflows/pages.yml" "generated workflow change"
assert_scope_from_website true "$base_sha" "$(git -C "$repository" rev-parse HEAD)" "generated workflow change"

new_repository
printf '%s\n' '# Mixed content' > "$repository/content/index.md"
mkdir -p "$repository/website/lib"
printf '%s\n' 'implementation change' > "$repository/website/lib/compiler.rb"
git -C "$repository" add content/index.md website/lib/compiler.rb
git -C "$repository" commit -qm "mix content and implementation"
assert_scope true "$base_sha" "$(git -C "$repository" rev-parse HEAD)" "mixed change"

new_repository
mkdir -p "$repository/website/lib"
printf '%s\n' 'implementation' > "$repository/website/lib/moved.rb"
git -C "$repository" add website/lib/moved.rb
git -C "$repository" commit -qm "add implementation file"
rename_base=$(git -C "$repository" rev-parse HEAD)
mkdir -p "$repository/website/docs"
git -C "$repository" mv website/lib/moved.rb website/docs/moved.md
git -C "$repository" commit -qm "move implementation into documentation"
assert_scope true "$rename_base" "$(git -C "$repository" rev-parse HEAD)" "implementation-to-content rename"

new_repository
mkdir -p "$repository/website/docs"
printf '%s\n' '# Documentation' > "$repository/website/docs/moved.md"
git -C "$repository" add website/docs/moved.md
git -C "$repository" commit -qm "add documentation file"
rename_base=$(git -C "$repository" rev-parse HEAD)
mkdir -p "$repository/website/lib"
git -C "$repository" mv website/docs/moved.md website/lib/moved.rb
git -C "$repository" commit -qm "move documentation into implementation"
assert_scope true "$rename_base" "$(git -C "$repository" rev-parse HEAD)" "content-to-implementation rename"

new_repository
head_sha=$(git -C "$repository" rev-parse HEAD)
assert_scope true "1111111111111111111111111111111111111111" "$head_sha" "unknown base commit"
assert_scope true "0000000000000000000000000000000000000000" "$head_sha" "initial push"
assert_scope true "not-a-commit" "$head_sha" "invalid base SHA"
assert_scope true "" "$head_sha" "manual dispatch"

printf '%s\n' "CI scope contract passed."
