#!/usr/bin/env sh
set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
SITE_DIR=$(CDPATH= cd -- "$TEST_DIR/../.." && pwd -P)
fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/jekyll-obsidian-clean.XXXXXX")
external_root=$(mktemp -d "${TMPDIR:-/tmp}/jekyll-obsidian-clean-external.XXXXXX")

cleanup() {
  case "$fixture_root" in
    "${TMPDIR:-/tmp}"/jekyll-obsidian-clean.*) rm -rf -- "$fixture_root" ;;
  esac
  case "$external_root" in
    "${TMPDIR:-/tmp}"/jekyll-obsidian-clean-external.*) rm -rf -- "$external_root" ;;
  esac
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

fail() {
  printf '%s\n' "Clean integration contract failed: $1" >&2
  exit 1
}

mkdir -p "$fixture_root/bin"
cp "$SITE_DIR/bin/clean" "$fixture_root/bin/clean"
chmod +x "$fixture_root/bin/clean"

mkdir -p "$fixture_root/_site" "$external_root/cache"
printf '%s\n' "keep" > "$external_root/cache/sentinel.txt"
ln -s "$external_root/cache" "$fixture_root/.jekyll-cache"
if "$fixture_root/bin/clean" >/dev/null 2>&1; then
  fail "a symbolic-link cache target was accepted."
fi
[ -d "$fixture_root/_site" ] || fail "preflight failure removed another build target."
[ -f "$external_root/cache/sentinel.txt" ] || fail "preflight failure touched the link destination."
rm -f -- "$fixture_root/.jekyll-cache"

for relative_path in \
  .jekyll-cache \
  .jekyll-obsidian-cache \
  .sass-cache \
  coverage \
  playwright-report \
  blob-report \
  test-results \
  .vitest \
  .nyc_output \
  tmp \
  log \
  _site \
  _site-browser-minimal; do
  mkdir -p "$fixture_root/$relative_path/nested"
done
printf '%s\n' "metadata" > "$fixture_root/.jekyll-metadata"

for preserved_path in node_modules vendor .bundle docs "_site-unsafe name"; do
  mkdir -p "$fixture_root/$preserved_path"
  printf '%s\n' "keep" > "$fixture_root/$preserved_path/sentinel.txt"
done

output=$("$fixture_root/bin/clean")
[ "$output" = "Removed 14 build output paths." ] || fail "the clean summary was unexpected: $output"

for removed_path in \
  .jekyll-cache \
  .jekyll-obsidian-cache \
  .sass-cache \
  coverage \
  playwright-report \
  blob-report \
  test-results \
  .vitest \
  .nyc_output \
  tmp \
  log \
  _site \
  _site-browser-minimal \
  .jekyll-metadata; do
  [ ! -e "$fixture_root/$removed_path" ] || fail "$removed_path was not removed."
done

for preserved_path in node_modules vendor .bundle docs "_site-unsafe name"; do
  [ -f "$fixture_root/$preserved_path/sentinel.txt" ] || fail "$preserved_path was removed."
done

output=$("$fixture_root/bin/clean")
[ "$output" = "Build output is already clean." ] || fail "the clean command was not idempotent."

printf '%s\n' "Clean integration contract passed."
