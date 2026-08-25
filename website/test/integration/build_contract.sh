#!/usr/bin/env sh
set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
SITE_DIR=$(CDPATH= cd -- "$TEST_DIR/../.." && pwd -P)
temporary_roots=""

cleanup() {
  for root in $temporary_roots; do
    case "$root" in
      "${TMPDIR:-/tmp}"/jekyll-obsidian-build.*) rm -rf -- "$root" ;;
    esac
  done
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

fail() {
  printf '%s\n' "Build integration contract failed: $1" >&2
  exit 1
}

new_host() {
  new_host_path=$(mktemp -d "${TMPDIR:-/tmp}/jekyll-obsidian-build.XXXXXX")
  temporary_roots="$temporary_roots $new_host_path"
  mkdir -p \
    "$new_host_path/.github" \
    "$new_host_path/docs/_plugins" \
    "$new_host_path/website/bin" \
    "$new_host_path/website/scripts" \
    "$new_host_path/fake-bin"
  cp "$SITE_DIR/bin/build" "$new_host_path/website/bin/build"
  cp "$SITE_DIR/_config.yml" "$new_host_path/website/_config.yml"
  cp "$SITE_DIR/scripts/example-config.yml" "$new_host_path/website/scripts/example-config.yml"
  : > "$new_host_path/website/Gemfile"
  cat > "$new_host_path/fake-bin/bundle" <<'SH'
#!/usr/bin/env sh
set -eu
previous=""
config=""
if [ -n "${CAPTURE_BUNDLE_ARGS:-}" ]; then
  printf '%s\n' "$@" > "$CAPTURE_BUNDLE_ARGS"
fi
for argument in "$@"; do
  if [ "$previous" = "--config" ]; then
    config=$argument
  fi
  previous=$argument
done
[ -n "$config" ]
overlay=${config##*,}
cp "$overlay" "$CAPTURE_OVERLAY"
printf '%s' "$config" > "$CAPTURE_CONFIG_PATHS"
[ -z "${FAKE_BUNDLE_PROGRESS:-}" ] || printf '%s\n' "$FAKE_BUNDLE_PROGRESS"
[ -z "${FAKE_BUNDLE_WARNING:-}" ] || printf '%s\n' "$FAKE_BUNDLE_WARNING" >&2
[ -z "${FAKE_BUNDLE_ERROR:-}" ] || {
  printf '%s\n' "$FAKE_BUNDLE_ERROR" >&2
  exit 1
}
SH
  chmod +x "$new_host_path/fake-bin/bundle"
}

new_host
locked_host=$new_host_path
cat > "$locked_host/.github/jekyll-obsidian.yml" <<'YAML'
source: ../docs
plugins_dir: ../docs/_plugins
layouts_dir: ../docs/_layouts
includes_dir: ../docs/_includes
data_dir: ../docs/_data
collections_dir: ../docs/collections
cache_dir: ../host-cache
safe: true

website:
  source: docs
  theme: docs
YAML
CAPTURE_OVERLAY="$locked_host/overlay.yml" \
CAPTURE_CONFIG_PATHS="$locked_host/config-paths.txt" \
PATH="$locked_host/fake-bin:$PATH" \
JEKYLL_ENV=development \
  sh "$locked_host/website/bin/build" --destination _site-contract --skip-assets

grep -Fqx "source: \"$locked_host/website\"" "$locked_host/overlay.yml" || fail "the final overlay did not pin the Jekyll source."
grep -Fqx 'safe: false' "$locked_host/overlay.yml" || fail "the final overlay did not keep custom plugins enabled."
grep -Fqx 'plugins_dir: "_plugins"' "$locked_host/overlay.yml" || fail "the final overlay did not pin plugins_dir."
grep -Fqx 'layouts_dir: "_layouts"' "$locked_host/overlay.yml" || fail "the final overlay did not pin layouts_dir."
grep -Fqx 'includes_dir: "_includes"' "$locked_host/overlay.yml" || fail "the final overlay did not pin includes_dir."
grep -Fqx 'data_dir: "_data"' "$locked_host/overlay.yml" || fail "the final overlay did not pin data_dir."
grep -Fqx 'collections_dir: ""' "$locked_host/overlay.yml" || fail "the final overlay did not pin collections_dir."
grep -Fqx "cache_dir: \"$locked_host/website/.jekyll-cache\"" "$locked_host/overlay.yml" || fail "the final overlay did not pin cache_dir."

new_host
example_host=$new_host_path
cat > "$example_host/.github/jekyll-obsidian.yml" <<'YAML'
title: Host customization must not enter template tests
website:
  source: docs
  theme: docs
  content:
    default_type: page
    directories:
      post: []
      doc: []
  features:
    graph: false
    search: false
YAML
if ! CAPTURE_OVERLAY="$example_host/overlay.yml" \
  CAPTURE_CONFIG_PATHS="$example_host/config-paths.txt" \
  PATH="$example_host/fake-bin:$PATH" \
  JEKYLL_ENV=development \
    sh "$example_host/website/bin/build" --example --theme docs --destination _site-example --skip-assets; then
  fail "the build command did not provide an isolated bundled-example mode."
fi
if grep -Fq '.github/jekyll-obsidian.yml' "$example_host/config-paths.txt"; then
  fail "the bundled-example build still loaded host overrides."
fi
grep -Fq '/website/scripts/example-config.yml' "$example_host/config-paths.txt" || fail "the bundled-example build omitted its project-only configuration."
grep -Fqx '  source: "website/docs"' "$example_host/overlay.yml" || fail "the bundled-example build did not select website/docs."

new_host
quiet_host=$new_host_path
cat > "$quiet_host/fake-bin/npm" <<'SH'
#!/usr/bin/env sh
set -eu
printf '%s\n' "$@" > "$CAPTURE_NPM_ARGS"
quiet=0
for argument in "$@"; do
  [ "$argument" = "--quiet" ] && quiet=1
done
[ "$quiet" -eq 1 ] || printf '%s\n' "Asset progress" >&2
printf '%s\n' "Asset warning" >&2
SH
chmod +x "$quiet_host/fake-bin/npm"
if ! CAPTURE_OVERLAY="$quiet_host/overlay.yml" \
  CAPTURE_CONFIG_PATHS="$quiet_host/config-paths.txt" \
  CAPTURE_BUNDLE_ARGS="$quiet_host/bundle-args.txt" \
  CAPTURE_NPM_ARGS="$quiet_host/npm-args.txt" \
  FAKE_BUNDLE_PROGRESS="Jekyll progress" \
  FAKE_BUNDLE_WARNING="Jekyll warning" \
  PATH="$quiet_host/fake-bin:$PATH" \
  JEKYLL_ENV=development \
    sh "$quiet_host/website/bin/build" --quiet --destination _site-quiet \
      > "$quiet_host/stdout.txt" 2> "$quiet_host/stderr.txt"; then
  fail "--quiet did not complete a development build."
fi
[ ! -s "$quiet_host/stdout.txt" ] || fail "--quiet emitted success progress."
grep -Fqx "Asset warning" "$quiet_host/stderr.txt" || fail "--quiet swallowed an asset warning."
grep -Fqx "Jekyll warning" "$quiet_host/stderr.txt" || fail "--quiet swallowed a warning."
if grep -Fqx "Asset progress" "$quiet_host/stderr.txt"; then
  fail "--quiet emitted asset success progress."
fi
if grep -Fqx -- "--quiet" "$quiet_host/bundle-args.txt"; then
  fail "--quiet was forwarded to Jekyll and would suppress warnings."
fi
grep -Fqx -- "--quiet" "$quiet_host/npm-args.txt" || fail "--quiet did not silence the asset compiler."

if CAPTURE_OVERLAY="$quiet_host/error-overlay.yml" \
  CAPTURE_CONFIG_PATHS="$quiet_host/error-config-paths.txt" \
  FAKE_BUNDLE_ERROR="Jekyll compile failure with trace" \
  PATH="$quiet_host/fake-bin:$PATH" \
  JEKYLL_ENV=development \
    sh "$quiet_host/website/bin/build" --quiet --skip-assets --destination _site-quiet-error \
      > "$quiet_host/error-stdout.txt" 2> "$quiet_host/error-stderr.txt"; then
  fail "--quiet hid a failed Jekyll build."
fi
[ ! -s "$quiet_host/error-stdout.txt" ] || fail "a failed quiet build emitted success progress."
grep -Fqx "Jekyll compile failure with trace" "$quiet_host/error-stderr.txt" || \
  fail "--quiet swallowed a Jekyll compile error or trace."

printf '%s\n' "Build integration contract passed."
