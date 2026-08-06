#!/usr/bin/env sh
set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
SITE_DIR=$(CDPATH= cd -- "$TEST_DIR/../.." && pwd -P)
temporary_roots=""

cleanup() {
  for root in $temporary_roots; do
    case "$root" in
      "${TMPDIR:-/tmp}"/jekyll-obsidian-integrate.*) rm -rf -- "$root" ;;
    esac
  done
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

fail() {
  printf '%s\n' "POSIX integration contract failed: $1" >&2
  exit 1
}

new_host() {
  new_host_path=$(mktemp -d "${TMPDIR:-/tmp}/jekyll-obsidian-integrate.XXXXXX")
  temporary_roots="$temporary_roots $new_host_path"
  mkdir -p "$new_host_path/website/bin" "$new_host_path/website/scripts/templates" "$new_host_path/docs"
  cp "$SITE_DIR/bin/integrate" "$new_host_path/website/bin/integrate"
  cp "$SITE_DIR/scripts/templates/host-config.yml" "$new_host_path/website/scripts/templates/host-config.yml"
  cp "$SITE_DIR/scripts/templates/pages.yml" "$new_host_path/website/scripts/templates/pages.yml"
  printf '%s\n' '---' 'publish: true' '---' '# Start' > "$new_host_path/docs/Start.md"
}

assert_lf_without_bom() {
  path=$1
  LC_ALL=C awk 'index($0, "\r") { exit 1 }' "$path" || fail "$path contains CRLF line endings."
  first_bytes=$(od -An -tx1 -N3 "$path" | tr -d ' \n')
  [ "$first_bytes" != efbbbf ] || fail "$path contains a UTF-8 BOM."
}

new_host
default_host=$new_host_path
"$default_host/website/bin/integrate" >/dev/null
"$default_host/website/bin/integrate" --check >/dev/null
grep -Fqx "  source: 'docs'" "$default_host/.github/jekyll-obsidian.yml" || fail "default source was not generated."
grep -Fqx "  theme: 'minimal'" "$default_host/.github/jekyll-obsidian.yml" || fail "default theme was not generated."
grep -Fqx 'title: My Project Documentation' "$default_host/.github/jekyll-obsidian.yml" || fail "editable host defaults were not generated."
grep -Fqx '  repository: ""' "$default_host/.github/jekyll-obsidian.yml" || fail "repository auto-detection default was not generated."
grep -Fqx '    publish_by_default: []' "$default_host/.github/jekyll-obsidian.yml" || fail "new hosts must require explicit publication by default."
grep -Fqx '    default_type: doc' "$default_host/.github/jekyll-obsidian.yml" || fail "the default host content was not classified as documentation."
grep -Fqx '      post: []' "$default_host/.github/jekyll-obsidian.yml" || fail "the default host post directories were not reset."
grep -Fqx '      doc: []' "$default_host/.github/jekyll-obsidian.yml" || fail "the default host doc directories were not rooted at website.source."
[ "$(grep -Fxc "      - 'docs/**'" "$default_host/.github/workflows/pages.yml")" -eq 2 ] || fail "content trigger was not generated twice."
grep -Fq "bin/integrate --check" "$default_host/.github/workflows/pages.yml" || fail "workflow does not check integration drift."
grep -Fq -- "--example" "$default_host/.github/workflows/pages.yml" || fail "template regression builds are not isolated."
assert_lf_without_bom "$default_host/.github/jekyll-obsidian.yml"
assert_lf_without_bom "$default_host/.github/workflows/pages.yml"
if [ -n "${INTEGRATION_REFERENCE_DIR:-}" ]; then
  mkdir -p -- "$INTEGRATION_REFERENCE_DIR"
  cp "$default_host/.github/jekyll-obsidian.yml" "$INTEGRATION_REFERENCE_DIR/jekyll-obsidian.yml"
  cp "$default_host/.github/workflows/pages.yml" "$INTEGRATION_REFERENCE_DIR/pages.yml"
fi

before_config=$(cksum "$default_host/.github/jekyll-obsidian.yml")
before_workflow=$(cksum "$default_host/.github/workflows/pages.yml")
"$default_host/website/bin/integrate" >/dev/null
[ "$before_config" = "$(cksum "$default_host/.github/jekyll-obsidian.yml")" ] || fail "idempotent run rewrote host configuration."
[ "$before_workflow" = "$(cksum "$default_host/.github/workflows/pages.yml")" ] || fail "idempotent run rewrote the workflow."

config_tmp=$(mktemp "$default_host/.github/.custom-config.XXXXXX")
awk '
  /^title:/ { print "title: Preserved host title"; next }
  /^  repository:/ { print "  repository: owner/project"; next }
  { print }
' "$default_host/.github/jekyll-obsidian.yml" > "$config_tmp"
mv -- "$config_tmp" "$default_host/.github/jekyll-obsidian.yml"
"$default_host/website/bin/integrate" --theme minimal >/dev/null
grep -Fqx 'title: Preserved host title' "$default_host/.github/jekyll-obsidian.yml" || fail "top-level host configuration was lost."
grep -Fqx '  repository: owner/project' "$default_host/.github/jekyll-obsidian.yml" || fail "website host configuration was lost."
grep -Fqx "  theme: 'minimal'" "$default_host/.github/jekyll-obsidian.yml" || fail "theme was not updated."

new_host
detached_markers_host=$new_host_path
mkdir -p "$detached_markers_host/.github"
printf '%s\n' \
  'website:' \
  '  repository: owner/project' \
  'other:' \
  '  # jekyll-obsidian:managed-start' \
  "  source: 'docs'" \
  "  theme: 'docs'" \
  '  # jekyll-obsidian:managed-end' > "$detached_markers_host/.github/jekyll-obsidian.yml"
detached_before=$(cksum "$detached_markers_host/.github/jekyll-obsidian.yml")
if "$detached_markers_host/website/bin/integrate" >/dev/null 2>&1; then
  fail "managed markers outside the website root were accepted."
fi
[ "$detached_before" = "$(cksum "$detached_markers_host/.github/jekyll-obsidian.yml")" ] || fail "detached managed markers were rewritten."

mkdir -p "$default_host/Documentation/用户 指南"
printf '%s\n' '---' 'publish: true' '---' '# Unicode documentation' > "$default_host/Documentation/用户 指南/index.md"
"$default_host/website/bin/integrate" --source 'Documentation\用户 指南' --theme minimal >/dev/null
grep -Fqx "  source: 'Documentation/用户 指南'" "$default_host/.github/jekyll-obsidian.yml" || fail "Windows-style source was not normalized."
[ "$(grep -Fxc "      - 'Documentation/用户 指南/**'" "$default_host/.github/workflows/pages.yml")" -eq 2 ] || fail "Unicode workflow trigger was not generated."
"$default_host/website/bin/integrate" --check >/dev/null

new_host
legacy_theme_host=$new_host_path
for legacy_theme in blog digital-garden; do
  if "$legacy_theme_host/website/bin/integrate" --theme "$legacy_theme" >/dev/null 2>&1; then
    fail "the removed $legacy_theme theme was accepted."
  fi
done
[ ! -e "$legacy_theme_host/.github" ] || fail "an invalid legacy theme left partial integration files."

special_source="docs'[one]"
mkdir -p "$default_host/$special_source"
printf '%s\n' '---' 'publish: true' '---' '# Literal YAML and glob characters' > "$default_host/$special_source/index.md"
"$default_host/website/bin/integrate" --source "$special_source" >/dev/null
grep -Fqx "  source: 'docs''[one]'" "$default_host/.github/jekyll-obsidian.yml" || fail "YAML-special source characters were not escaped."
[ "$(grep -Fxc "      - 'docs''\[one\]/**'" "$default_host/.github/workflows/pages.yml")" -eq 2 ] || fail "workflow glob characters were not escaped."
"$default_host/website/bin/integrate" --check >/dev/null

new_host
conflict_host=$new_host_path
mkdir -p "$conflict_host/.github/workflows"
printf '%s\n' 'name: Existing workflow' > "$conflict_host/.github/workflows/pages.yml"
if "$conflict_host/website/bin/integrate" >/dev/null 2>&1; then
  fail "an unmanaged workflow was overwritten without consent."
fi
[ ! -e "$conflict_host/.github/jekyll-obsidian.yml" ] || fail "a failed preflight left partial host configuration."
"$conflict_host/website/bin/integrate" --force-workflow >/dev/null
grep -Fqx '# Generated by website/bin/integrate. Re-run that command instead of editing this file.' \
  "$conflict_host/.github/workflows/pages.yml" || fail "--force-workflow did not install the managed workflow."

new_host
unmanaged_config_host=$new_host_path
mkdir -p "$unmanaged_config_host/.github"
printf '%s\n' 'title: Existing configuration' > "$unmanaged_config_host/.github/jekyll-obsidian.yml"
if "$unmanaged_config_host/website/bin/integrate" >"$unmanaged_config_host/output.txt" 2>&1; then
  fail "an unmanaged host configuration was overwritten."
fi
grep -Fq 'jekyll-obsidian:managed-start' "$unmanaged_config_host/output.txt" || fail "the manual merge example was not printed."
[ ! -e "$unmanaged_config_host/.github/workflows" ] || fail "an unmanaged configuration failure created a workflow directory."

new_host
reversed_markers_host=$new_host_path
mkdir -p "$reversed_markers_host/.github"
printf '%s\n' \
  'website:' \
  '  # jekyll-obsidian:managed-end' \
  '  # jekyll-obsidian:managed-start' \
  "  source: 'docs'" \
  "  theme: 'docs'" \
  '  repository: owner/project' > "$reversed_markers_host/.github/jekyll-obsidian.yml"
reversed_before=$(cksum "$reversed_markers_host/.github/jekyll-obsidian.yml")
if "$reversed_markers_host/website/bin/integrate" >/dev/null 2>&1; then
  fail "reversed managed markers were accepted."
fi
[ "$reversed_before" = "$(cksum "$reversed_markers_host/.github/jekyll-obsidian.yml")" ] || fail "a malformed managed block was rewritten."
[ ! -e "$reversed_markers_host/.github/workflows" ] || fail "a malformed managed block created a workflow directory."

new_host
link_host=$new_host_path
mkdir -p "$link_host/real-docs"
printf '%s\n' '---' 'publish: true' '---' '# Linked' > "$link_host/real-docs/index.md"
if ln -s "$link_host/real-docs" "$link_host/linked-docs" 2>/dev/null; then
  if "$link_host/website/bin/integrate" --source linked-docs >/dev/null 2>&1; then
    fail "a symbolic-link content root was accepted."
  fi
fi

if grep -Eq '(^|[^[:alnum:]_])(ruby|node|npm|bundle)([^[:alnum:]_]|$)' "$SITE_DIR/bin/integrate"; then
  fail "the POSIX adapter depends on a local Ruby or Node toolchain."
fi

printf '%s\n' "POSIX host integration contract passed."
