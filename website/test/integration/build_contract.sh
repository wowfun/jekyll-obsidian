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
    "$new_host_path/fake-bin"
  cp "$SITE_DIR/bin/build" "$new_host_path/website/bin/build"
  cp "$SITE_DIR/_config.yml" "$new_host_path/website/_config.yml"
  : > "$new_host_path/website/Gemfile"
  cat > "$new_host_path/fake-bin/bundle" <<'SH'
#!/usr/bin/env sh
set -eu
previous=""
config=""
for argument in "$@"; do
  if [ "$previous" = "--config" ]; then
    config=$argument
    break
  fi
  previous=$argument
done
[ -n "$config" ]
overlay=${config##*,}
cp "$overlay" "$CAPTURE_OVERLAY"
printf '%s' "$config" > "$CAPTURE_CONFIG_PATHS"
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
grep -Fqx '  source: "website/docs"' "$example_host/overlay.yml" || fail "the bundled-example build did not select website/docs."

printf '%s\n' "Build integration contract passed."
