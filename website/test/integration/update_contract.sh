#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
SITE_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd -P)
SOURCE_ROOT=$(CDPATH= cd -- "$SITE_DIR/.." && pwd -P)
UPDATE=$SITE_DIR/bin/update

fail() {
  printf '%s\n' "update contract failure: $1" >&2
  exit 1
}

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/jekyll-obsidian-update-contract.XXXXXX")
background_pid=""
cleanup() {
  if [ -n "$background_pid" ] && kill -0 "$background_pid" 2>/dev/null; then
    kill "$background_pid" 2>/dev/null || true
    wait "$background_pid" 2>/dev/null || true
  fi
  rm -rf -- "$tmp_root"
}
trap cleanup EXIT HUP INT TERM

help_output=$($UPDATE --help) || fail "--help did not exit successfully."
printf '%s\n' "$help_output" | grep -Fq 'Usage: website/bin/update [--check] [--to X.Y.Z]' || fail "--help omitted the public usage."
printf '%s\n' "$help_output" | grep -Fq -- '--check' || fail "--help omitted --check."
printf '%s\n' "$help_output" | grep -Fq -- '--to X.Y.Z' || fail "--help omitted --to."
if printf '%s\n' "$help_output" | grep -Eqi 'origin|remote|force|adopt|recover|testing'; then
  fail "--help exposed a private transport or recovery control."
fi

set +e
$UPDATE --unknown >"$tmp_root/unknown.out" 2>"$tmp_root/unknown.err"
unknown_status=$?
set -e
[ "$unknown_status" -eq 1 ] || fail "an unknown option did not exit 1."
grep -Fq 'Update error: unknown option: --unknown' "$tmp_root/unknown.err" || fail "an unknown option did not use the stable error prefix."

set +e
$UPDATE --to '' >"$tmp_root/empty-version.out" 2>"$tmp_root/empty-version.err"
empty_version_status=$?
set -e
[ "$empty_version_status" -eq 1 ] || fail "an empty --to value did not exit 1."
grep -Fxq 'Update error: invalid release version: ' "$tmp_root/empty-version.err" || fail "an empty --to value was treated as latest."

set +e
$UPDATE --to '' --to 0.0.10 >"$tmp_root/duplicate-version.out" 2>"$tmp_root/duplicate-version.err"
duplicate_version_status=$?
set -e
[ "$duplicate_version_status" -eq 1 ] || fail "a duplicate --to after an empty value did not exit 1."
grep -Fxq 'Update error: --to may only be specified once.' "$tmp_root/duplicate-version.err" || fail "a duplicate --to after an empty value was not rejected as duplicate."

for invalid_version in 00.1.0 0.01.0 0.1.00 0.1 0.0.9.1 0.0.9-rc.1 0.0.9+build latest; do
  set +e
  $UPDATE --to "$invalid_version" >"$tmp_root/version.out" 2>"$tmp_root/version.err"
  version_status=$?
  set -e
  [ "$version_status" -eq 1 ] || fail "invalid version $invalid_version did not exit 1."
  grep -Fq "Update error: invalid release version: $invalid_version" "$tmp_root/version.err" || fail "invalid version $invalid_version reached release discovery."
done

set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
  $UPDATE --check --to 0.0.9 >"$tmp_root/testing-missing.out" 2>"$tmp_root/testing-missing.err"
testing_missing_status=$?
set -e
[ "$testing_missing_status" -eq 1 ] || fail "testing mode without an origin did not fail closed."
grep -Fxq 'Update error: the internal test transport is missing its origin.' "$tmp_root/testing-missing.err" || fail "missing internal origin rejection was unclear."

set +e
JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN=file:///tmp/not-used \
  $UPDATE --check --to 0.0.9 >"$tmp_root/testing-stray.out" 2>"$tmp_root/testing-stray.err"
testing_stray_status=$?
set -e
[ "$testing_stray_status" -eq 1 ] || fail "a stray internal origin did not fail closed."
grep -Fxq 'Update error: the internal test transport is disabled.' "$tmp_root/testing-stray.err" || fail "stray internal origin rejection was unclear."

set +e
JEKYLL_OBSIDIAN_UPDATE_TEST_FAIL_AT=fail_after_first_file \
  $UPDATE --check --to 0.0.9 >"$tmp_root/testing-failure-stray.out" 2>"$tmp_root/testing-failure-stray.err"
testing_failure_stray_status=$?
set -e
[ "$testing_failure_stray_status" -eq 1 ] || fail "a stray internal failure injection did not fail closed."
grep -Fxq 'Update error: the internal test transport is disabled.' "$tmp_root/testing-failure-stray.err" || fail "stray failure injection rejection was unclear."

empty_remote=$tmp_root/empty.git
git init --bare --quiet "$empty_remote"
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
  JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="file://$empty_remote" \
  $UPDATE --check >"$tmp_root/empty.out" 2>"$tmp_root/empty.err"
empty_status=$?
set -e
[ "$empty_status" -eq 1 ] || fail "an origin without tags did not exit 1."
grep -Fq 'Update error: no annotated stable SemVer release tags were found.' "$tmp_root/empty.err" || fail "an origin without tags did not fail during release discovery."

replace_literal_count() {
  replace_file=$1
  replace_before=$2
  replace_after=$3
  replace_expected=$4
  awk -v before="$replace_before" -v after="$replace_after" -v expected="$replace_expected" '
    {
      if (replaced < expected) {
        position = index($0, before)
        if (position > 0) {
          $0 = substr($0, 1, position - 1) after substr($0, position + length(before))
          replaced++
        }
      }
      print
    }
    END { if (replaced != expected) exit 1 }
  ' "$replace_file" >"$replace_file.next" || {
    rm -f -- "$replace_file.next"
    fail "could not rewrite the fixture version in $replace_file."
  }
  mv -- "$replace_file.next" "$replace_file"
}

set_product_version() {
  product_site=$1
  product_before=$2
  product_after=$3
  replace_literal_count "$product_site/.jekyll-obsidian-release" "version=$product_before" "version=$product_after" 1
  replace_literal_count "$product_site/package.json" "\"version\": \"$product_before\"" "\"version\": \"$product_after\"" 1
  replace_literal_count "$product_site/package-lock.json" "\"version\": \"$product_before\"" "\"version\": \"$product_after\"" 2
  replace_literal_count "$product_site/lib/jekyll_obsidian.rb" "VERSION = \"$product_before\"" "VERSION = \"$product_after\"" 1
}

release_work=$tmp_root/release-work
mkdir -p "$release_work"
git -C "$SOURCE_ROOT" archive --format=tar HEAD website |
  tar -xf - -C "$release_work"
cp -p -- "$SITE_DIR/bin/update" "$release_work/website/bin/update"
cp -p -- "$SITE_DIR/bin/update.cmd" "$release_work/website/bin/update.cmd"
cp -p -- "$SITE_DIR/bin/update.ps1" "$release_work/website/bin/update.ps1"
cp -p -- "$SITE_DIR/bin/integrate" "$release_work/website/bin/integrate"
cp -p -- "$SITE_DIR/.jekyll-obsidian-release" "$release_work/website/.jekyll-obsidian-release"
cp -p -- "$SITE_DIR/package.json" "$release_work/website/package.json"
cp -p -- "$SITE_DIR/package-lock.json" "$release_work/website/package-lock.json"
cp -p -- "$SITE_DIR/lib/jekyll_obsidian.rb" "$release_work/website/lib/jekyll_obsidian.rb"
cp -p -- "$SITE_DIR/scripts/example-config.yml" "$release_work/website/scripts/example-config.yml"
mkdir -p "$release_work/docs"
printf '%s\n' '---' 'publish: true' '---' '# Start' >"$release_work/docs/Start.md"
sh "$release_work/website/bin/integrate" >/dev/null || fail "the fixture host integration could not be generated."
sh "$release_work/website/bin/integrate" --check >/dev/null || fail "the fixture host integration was invalid."
product_version=$(sed -n 's/^version=//p' "$release_work/website/.jekyll-obsidian-release")
[ -n "$product_version" ] || fail "the product release version could not be read."
set_product_version "$release_work/website" "$product_version" '0.0.9'
printf '%s\n' alpha >"$release_work/website/update-fixture.txt"
printf '%s\n' remove-me >"$release_work/website/update-removed-fixture.txt"
printf '%s\n' parent-file >"$release_work/website/parent-transition"
mkdir -p "$release_work/website/nested-ignore"
printf '%s\n' 'state/' >"$release_work/website/nested-ignore/.gitignore"

git -C "$release_work" init --quiet
git -C "$release_work" config user.name 'Update Contract'
git -C "$release_work" config user.email 'update-contract@example.invalid'
git -C "$release_work" add --all
git -C "$release_work" commit --quiet -m 'Fixture 0.0.9'
git -C "$release_work" tag -a v0.0.9 -m 'Fixture 0.0.9'

set_product_version "$release_work/website" '0.0.9' '0.0.10'
printf '%s\n' beta >"$release_work/website/update-fixture.txt"
printf '%s\n' added >"$release_work/website/update-added-fixture.txt"
rm -- "$release_work/website/update-removed-fixture.txt"
printf '%s\n' '# update-contract-generated-workflow' >>"$release_work/website/scripts/templates/pages.yml"
git -C "$release_work" add --all
git -C "$release_work" commit --quiet -m 'Fixture 0.0.10'
git -C "$release_work" tag -a v0.0.10 -m 'Fixture 0.0.10'

release_remote=$tmp_root/releases.git
git clone --quiet --bare "$release_work" "$release_remote"
test_transport="file://$release_remote"

new_current_host() {
  current_host=$tmp_root/host-$1
  git clone --quiet "$release_work" "$current_host"
  git -C "$current_host" config user.name 'Update Contract'
  git -C "$current_host" config user.email 'update-contract@example.invalid'
  git -C "$current_host" checkout --quiet -B host-main 'v0.0.9^{}'
  git -C "$current_host" remote set-url origin https://example.invalid/host.git
  printf '%s\n' "$current_host"
}

new_locked_host() {
  locked_host=$(new_current_host "$1")
  JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
    JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
    "$locked_host/website/bin/update" --to 0.0.9 >/dev/null
  git -C "$locked_host" add .github/jekyll-obsidian.lock
  git -C "$locked_host" commit --quiet -m 'Record fixture provenance'
  printf '%s\n' "$locked_host"
}

run_lock_path() {
  lock_host=$(CDPATH= cd -- "$1" && pwd -P)
  lock_key=$(printf '%s\n' "$lock_host" | git -C "$lock_host" hash-object --stdin)
  printf '/tmp/jekyll-obsidian-update-lock.%s\n' "$lock_key"
}

rewrite_host=$(new_current_host origin-rewrite)
git -C "$rewrite_host" config url."$test_transport".insteadOf https://github.com/wowfun/jekyll-obsidian.git
fake_git_exec=$tmp_root/git-exec
mkdir -p "$fake_git_exec"
ln -s "$(git --exec-path)/git-upload-pack" "$fake_git_exec/git-upload-pack"
printf '%s\n' '#!/usr/bin/env sh' 'exit 97' >"$fake_git_exec/git-remote-https"
chmod +x "$fake_git_exec/git-remote-https"
set +e
(
  cd "$rewrite_host"
  GIT_EXEC_PATH=$fake_git_exec \
    "$rewrite_host/website/bin/update" --check --to 0.0.9
) >"$tmp_root/origin-rewrite.out" 2>"$tmp_root/origin-rewrite.err"
origin_rewrite_status=$?
set -e
[ "$origin_rewrite_status" -eq 1 ] || fail "host url.insteadOf redirected the fixed official release origin."
grep -Fxq 'Update error: could not list official releases.' "$tmp_root/origin-rewrite.err" || fail "fixed-origin rewrite isolation did not reach the official transport."
[ ! -e "$rewrite_host/.jekyll-obsidian-update" ] || fail "fixed-origin rewrite rejection created a transaction."
[ ! -e "$rewrite_host/.jekyll-obsidian-update.lock" ] || fail "fixed-origin rewrite rejection retained its command lock."
[ ! -e "$(run_lock_path "$rewrite_host")" ] || fail "fixed-origin rewrite rejection retained its runtime command lock."

adoption_host=$(new_current_host adoption)
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
  JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$adoption_host/website/bin/update" --check --to 0.0.9 \
  >"$tmp_root/adoption.out" 2>"$tmp_root/adoption.err"
adoption_status=$?
set -e
[ "$adoption_status" -eq 2 ] || fail "an exact legacy snapshot was not reported as adoptable."
grep -Fq 'Provenance can be established for 0.0.9.' "$tmp_root/adoption.out" || fail "adoption check output was not actionable."
[ ! -e "$adoption_host/.github/jekyll-obsidian.lock" ] || fail "--check wrote a provenance lock."
[ -z "$(git -C "$adoption_host" status --porcelain)" ] || fail "--check changed the host worktree."
[ ! -e "$adoption_host/.jekyll-obsidian-update" ] || fail "--check left a transaction directory."

JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
  JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$adoption_host/website/bin/update" --to 0.0.9 \
  >"$tmp_root/adopt.out" 2>"$tmp_root/adopt.err" || fail "an exact legacy snapshot could not establish provenance."
grep -Fq 'Recorded jekyll-obsidian provenance for 0.0.9.' "$tmp_root/adopt.out" || fail "adoption output did not identify the recorded version."
lock_path=$adoption_host/.github/jekyll-obsidian.lock
[ "$(wc -l <"$lock_path" | tr -d ' ')" -eq 7 ] || fail "the provenance lock was not the strict seven-line format."
sed -n '1p' "$lock_path" | grep -Fxq 'format=1' || fail "the lock format field was malformed."
sed -n '2p' "$lock_path" | grep -Fxq 'origin=https://github.com/wowfun/jekyll-obsidian.git' || fail "the lock exposed the test transport."
sed -n '3p' "$lock_path" | grep -Fxq 'version=0.0.9' || fail "the lock version was malformed."
sed -n '4p' "$lock_path" | grep -Fxq 'tag=v0.0.9' || fail "the lock tag was malformed."
[ "$(git -C "$adoption_host" status --porcelain)" = '?? .github/jekyll-obsidian.lock' ] || fail "adoption changed more than the provenance lock."
[ ! -e "$adoption_host/.jekyll-obsidian-update" ] || fail "adoption left a transaction directory."

git -C "$adoption_host" add .github/jekyll-obsidian.lock
git -C "$adoption_host" commit --quiet -m 'Record fixture provenance'
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
  JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$adoption_host/website/bin/update" --check --to 0.0.9 \
  >"$tmp_root/current.out" 2>"$tmp_root/current.err" || fail "a locked current release was not idempotent."
grep -Fq 'jekyll-obsidian 0.0.9 is current.' "$tmp_root/current.out" || fail "the current-version output was unclear."
[ -z "$(git -C "$adoption_host" status --porcelain)" ] || fail "a current-version check changed the host."

set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
  JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$adoption_host/website/bin/update" --check \
  >"$tmp_root/available.out" 2>"$tmp_root/available.err"
available_status=$?
set -e
[ "$available_status" -eq 2 ] || fail "the latest release check did not exit 2."
grep -Fq 'Update available: 0.0.9 -> 0.0.10.' "$tmp_root/available.out" || fail "the available update was not reported."
[ -z "$(git -C "$adoption_host" status --porcelain)" ] || fail "an available update check changed the host."

mkdir -p "$adoption_host/website/node_modules/update-contract"
printf '%s\n' keep >"$adoption_host/website/node_modules/update-contract/local-state.txt"
mkdir -p "$adoption_host/website/nested-ignore/state"
printf '%s\n' nested-keep >"$adoption_host/website/nested-ignore/state/local-state.txt"
printf '%s\n' '# host-owned-prefix' >"$tmp_root/config.next"
cat "$adoption_host/.github/jekyll-obsidian.yml" >>"$tmp_root/config.next"
printf '%s' '# host-owned-tail-without-final-newline' >>"$tmp_root/config.next"
mv -- "$tmp_root/config.next" "$adoption_host/.github/jekyll-obsidian.yml"
cp -p -- "$adoption_host/.github/jekyll-obsidian.yml" "$tmp_root/config.before-update"
printf '%s\n' unrelated >"$adoption_host/host-unrelated.txt"
host_head_before=$(git -C "$adoption_host" rev-parse HEAD)
host_branch_before=$(git -C "$adoption_host" symbolic-ref HEAD)
host_remote_before=$(git -C "$adoption_host" remote get-url origin)
host_index=$(git -C "$adoption_host" rev-parse --git-path index)
touch -t 203001010000 "$adoption_host/website/package.json"
host_index_before=$(cksum "$adoption_host/$host_index")

JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
  JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$adoption_host/website/bin/update" \
  >"$tmp_root/update.out" 2>"$tmp_root/update.err" || fail "the locked snapshot did not update to latest."
grep -Fq 'Updated jekyll-obsidian from 0.0.9 to 0.0.10.' "$tmp_root/update.out" || fail "successful update output omitted the version transition."
[ "$(cat "$adoption_host/website/update-fixture.txt")" = beta ] || fail "a tracked website file was not updated."
[ "$(cat "$adoption_host/website/update-added-fixture.txt")" = added ] || fail "a new tracked website file was not installed."
[ ! -e "$adoption_host/website/update-removed-fixture.txt" ] || fail "a removed tracked website file was retained."
[ "$(cat "$adoption_host/website/node_modules/update-contract/local-state.txt")" = keep ] || fail "ignored local state was not preserved."
[ "$(cat "$adoption_host/website/nested-ignore/state/local-state.txt")" = nested-keep ] || fail "nested ignored local state was not preserved."
[ "$(sed -n '1p' "$adoption_host/.github/jekyll-obsidian.yml")" = '# host-owned-prefix' ] || fail "host configuration outside the managed block changed."
cmp -s "$tmp_root/config.before-update" "$adoption_host/.github/jekyll-obsidian.yml" || fail "host configuration bytes outside an unchanged managed block changed."
grep -Fq '# update-contract-generated-workflow' "$adoption_host/.github/workflows/pages.yml" || fail "the target integrate command did not render the workflow."
grep -Fxq 'version=0.0.10' "$adoption_host/.github/jekyll-obsidian.lock" || fail "the provenance lock was not advanced."
[ "$(git -C "$adoption_host" rev-parse HEAD)" = "$host_head_before" ] || fail "update changed host HEAD."
[ "$(git -C "$adoption_host" symbolic-ref HEAD)" = "$host_branch_before" ] || fail "update changed the host branch."
[ "$(git -C "$adoption_host" remote get-url origin)" = "$host_remote_before" ] || fail "update changed the host remote."
[ "$(cksum "$adoption_host/$host_index")" = "$host_index_before" ] || fail "update changed the host index."
[ ! -e "$adoption_host/.jekyll-obsidian-update" ] || fail "update left a transaction directory."

rollback_host=$(new_locked_host rollback)
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
  JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  JEKYLL_OBSIDIAN_UPDATE_TEST_FAIL_AT=fail_after_first_file \
  "$rollback_host/website/bin/update" >"$tmp_root/rollback.out" 2>"$tmp_root/rollback.err"
rollback_status=$?
set -e
[ "$rollback_status" -eq 1 ] || fail "an injected transaction failure did not exit 1."
grep -Fq 'Update error: injected transaction failure' "$tmp_root/rollback.err" || fail "the injected transaction failure was not reported."
[ "$(cat "$rollback_host/website/update-fixture.txt")" = alpha ] || fail "rollback did not restore an old tracked file."
[ ! -e "$rollback_host/website/update-added-fixture.txt" ] || fail "rollback retained a target-only file."
[ "$(cat "$rollback_host/website/update-removed-fixture.txt")" = remove-me ] || fail "rollback did not restore a removed old file."
grep -Fxq 'version=0.0.9' "$rollback_host/.github/jekyll-obsidian.lock" || fail "rollback did not restore the old lock."
[ -z "$(git -C "$rollback_host" status --porcelain)" ] || fail "rollback did not restore the clean old snapshot."
[ ! -e "$rollback_host/.jekyll-obsidian-update" ] || fail "rollback retained its transaction directory."

concurrent_host=$(new_locked_host concurrent)
(
  cd "$concurrent_host"
  JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
    JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
    JEKYLL_OBSIDIAN_UPDATE_TEST_FAIL_AT=wait_after_claim \
    exec "$concurrent_host/website/bin/update"
) >"$tmp_root/concurrent-winner.out" 2>"$tmp_root/concurrent-winner.err" &
background_pid=$!
concurrent_wait=0
while [ ! -f "$concurrent_host/.jekyll-obsidian-update/preparing" ]; do
  kill -0 "$background_pid" 2>/dev/null || fail "the concurrent winner exited before claiming its transaction."
  concurrent_wait=$((concurrent_wait + 1))
  [ "$concurrent_wait" -lt 30 ] || fail "the concurrent winner did not claim its transaction."
  sleep 1
done
[ -d "$(run_lock_path "$concurrent_host")" ] || fail "the concurrent winner did not retain its external lifecycle lock."
[ ! -e "$concurrent_host/.jekyll-obsidian-update/journal" ] || fail "the concurrent winner passed its requested pause."
[ "$(cat "$concurrent_host/website/update-fixture.txt")" = alpha ] || fail "the paused concurrent winner applied early."
set +e
sha256_cwd=$tmp_root/sha256-caller
git init --quiet --object-format=sha256 "$sha256_cwd"
(
  cd "$sha256_cwd"
  JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
    JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
    "$concurrent_host/website/bin/update"
) >"$tmp_root/concurrent-loser.out" 2>"$tmp_root/concurrent-loser.err"
concurrent_loser_status=$?
set -e
[ "$concurrent_loser_status" -eq 1 ] || fail "a concurrent update command shared the active transaction."
grep -Fxq 'Update error: another jekyll-obsidian update command is running.' "$tmp_root/concurrent-loser.err" || fail "the concurrent loser rejection was unclear."
[ ! -e "$concurrent_host/.jekyll-obsidian-update/journal" ] || fail "the concurrent loser advanced the winner transaction."
[ "$(cat "$concurrent_host/website/update-fixture.txt")" = alpha ] || fail "the concurrent loser changed managed content."
: >"$concurrent_host/.jekyll-obsidian-update/test-continue"
wait "$background_pid" || fail "the concurrent winner did not finish after the loser was rejected."
background_pid=""
[ "$(cat "$concurrent_host/website/update-fixture.txt")" = beta ] || fail "the concurrent winner did not complete its update."
[ ! -e "$concurrent_host/.jekyll-obsidian-update" ] || fail "the concurrent winner retained its transaction."
[ ! -e "$concurrent_host/.jekyll-obsidian-update.lock" ] || fail "the concurrent winner retained its command lock."
[ ! -e "$(run_lock_path "$concurrent_host")" ] || fail "the concurrent winner retained its runtime command lock."

preparing_host=$(new_locked_host preparing-crash)
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
  JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  JEKYLL_OBSIDIAN_UPDATE_TEST_FAIL_AT=crash_preparing \
  "$preparing_host/website/bin/update" >"$tmp_root/preparing-crash.out" 2>"$tmp_root/preparing-crash.err"
preparing_crash_status=$?
set -e
[ "$preparing_crash_status" -ne 0 ] || fail "the preparing crash injection returned success."
[ -f "$preparing_host/.jekyll-obsidian-update/preparing" ] || fail "the preparing crash did not retain its marker."
[ ! -e "$preparing_host/.jekyll-obsidian-update/journal" ] || fail "the preparing crash unexpectedly reached a journal."
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$preparing_host/website/bin/update" --check >"$tmp_root/preparing-check.out" 2>"$tmp_root/preparing-check.err"
preparing_check_status=$?
set -e
[ "$preparing_check_status" -eq 1 ] || fail "--check changed a preparing transaction."
[ -d "$preparing_host/.jekyll-obsidian-update" ] || fail "--check removed a preparing transaction."
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$preparing_host/website/bin/update" --to 0.0.9 >"$tmp_root/preparing-recover.out" 2>"$tmp_root/preparing-recover.err" || fail "a preparing transaction was not safely discarded."
grep -Fq 'Discarded an incomplete jekyll-obsidian preparing transaction.' "$tmp_root/preparing-recover.out" || fail "preparing recovery was not reported."
[ ! -e "$preparing_host/.jekyll-obsidian-update" ] || fail "preparing recovery retained the canonical transaction directory."
[ -z "$(git -C "$preparing_host" status --porcelain)" ] || fail "preparing recovery changed the old snapshot."

prepared_host=$(new_locked_host prepared-crash)
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
  JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  JEKYLL_OBSIDIAN_UPDATE_TEST_FAIL_AT=crash_prepared \
  "$prepared_host/website/bin/update" >"$tmp_root/prepared-crash.out" 2>"$tmp_root/prepared-crash.err"
prepared_crash_status=$?
set -e
[ "$prepared_crash_status" -ne 0 ] || fail "the prepared crash injection returned success."
[ -d "$prepared_host/.jekyll-obsidian-update" ] || fail "the prepared crash did not retain a recovery journal."
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
  JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$prepared_host/website/bin/update" --check >"$tmp_root/prepared-recover.out" 2>"$tmp_root/prepared-recover.err"
prepared_recover_status=$?
set -e
[ "$prepared_recover_status" -eq 1 ] || fail "--check recovered an unfinished transaction instead of staying read-only."
grep -Fq 'Update error: recovery_required: --check cannot recover' "$tmp_root/prepared-recover.err" || fail "read-only recovery refusal was not reported."
[ -d "$prepared_host/.jekyll-obsidian-update" ] || fail "--check removed an unfinished transaction."
printf '%s\n' tampered >"$prepared_host/website/update-fixture.txt"
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$prepared_host/website/bin/update" --to 0.0.9 >"$tmp_root/prepared-tampered.out" 2>"$tmp_root/prepared-tampered.err"
prepared_tampered_status=$?
set -e
[ "$prepared_tampered_status" -eq 1 ] || fail "prepared recovery discarded a host that no longer matched old."
grep -Fq 'prepared transaction no longer matches the complete old snapshot' "$tmp_root/prepared-tampered.err" || fail "prepared mixed-state refusal was unclear."
[ -d "$prepared_host/.jekyll-obsidian-update" ] || fail "prepared mixed-state refusal removed evidence."
printf '%s\n' alpha >"$prepared_host/website/update-fixture.txt"
ln -s missing-target "$prepared_host/website/update-added-fixture.txt"
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$prepared_host/website/bin/update" --to 0.0.9 >"$tmp_root/prepared-link.out" 2>"$tmp_root/prepared-link.err"
prepared_link_status=$?
set -e
[ "$prepared_link_status" -eq 1 ] || fail "prepared recovery treated a dangling target-only link as absent."
[ -L "$prepared_host/website/update-added-fixture.txt" ] || fail "prepared dangling-link refusal removed the link."
[ -d "$prepared_host/.jekyll-obsidian-update" ] || fail "prepared dangling-link refusal removed evidence."
rm -- "$prepared_host/website/update-added-fixture.txt"
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
  JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$prepared_host/website/bin/update" --to 0.0.9 >"$tmp_root/prepared-recover.out" 2>"$tmp_root/prepared-recover.err" || fail "a prepared transaction was not safely discarded."
grep -Fq 'Discarded an unapplied jekyll-obsidian 0.0.9 -> 0.0.10 transaction.' "$tmp_root/prepared-recover.out" || fail "prepared recovery was not reported."
[ ! -e "$prepared_host/.jekyll-obsidian-update" ] || fail "prepared recovery retained the transaction directory."
[ -z "$(git -C "$prepared_host" status --porcelain)" ] || fail "prepared recovery changed the old snapshot."

verified_host=$(new_locked_host verified-crash)
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
  JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  JEKYLL_OBSIDIAN_UPDATE_TEST_FAIL_AT=crash_verified \
  "$verified_host/website/bin/update" >"$tmp_root/verified-crash.out" 2>"$tmp_root/verified-crash.err"
verified_crash_status=$?
set -e
[ "$verified_crash_status" -ne 0 ] || fail "the verified crash injection returned success."
[ -d "$verified_host/.jekyll-obsidian-update" ] || fail "the verified crash did not retain a recovery journal."
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
  JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$verified_host/website/bin/update" >"$tmp_root/verified-recover.out" 2>"$tmp_root/verified-recover.err" || fail "a complete new snapshot was not recovered."
grep -Fq 'Recovered completed jekyll-obsidian update 0.0.9 -> 0.0.10.' "$tmp_root/verified-recover.out" || fail "verified recovery was not reported."
[ "$(cat "$verified_host/website/update-fixture.txt")" = beta ] || fail "verified recovery did not retain the new snapshot."
[ ! -e "$verified_host/.jekyll-obsidian-update" ] || fail "verified recovery retained the transaction directory."

applying_host=$(new_locked_host applying-complete-crash)
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
  JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  JEKYLL_OBSIDIAN_UPDATE_TEST_FAIL_AT=crash_after_last_rename \
  "$applying_host/website/bin/update" >"$tmp_root/applying-crash.out" 2>"$tmp_root/applying-crash.err"
applying_crash_status=$?
set -e
[ "$applying_crash_status" -ne 0 ] || fail "the final-rename crash injection returned success."
grep -Fxq 'state=applying' "$applying_host/.jekyll-obsidian-update/journal" || fail "the final-rename crash did not retain an applying journal."
[ "$(cat "$applying_host/website/update-fixture.txt")" = beta ] || fail "the final-rename crash did not leave the complete new snapshot."
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
  JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$applying_host/website/bin/update" >"$tmp_root/applying-recover.out" 2>"$tmp_root/applying-recover.err" || fail "an all-new applying snapshot did not pass post-update recovery verification."
grep -Fq 'Recovered completed jekyll-obsidian update 0.0.9 -> 0.0.10.' "$tmp_root/applying-recover.out" || fail "all-new applying recovery was not reported."
[ ! -e "$applying_host/.jekyll-obsidian-update" ] || fail "all-new applying recovery retained the transaction."

install_copy_host=$(new_locked_host install-copy-crash)
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
  JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  JEKYLL_OBSIDIAN_UPDATE_TEST_FAIL_AT=crash_after_install_copy \
  "$install_copy_host/website/bin/update" >"$tmp_root/install-copy-crash.out" 2>"$tmp_root/install-copy-crash.err"
install_copy_crash_status=$?
set -e
[ "$install_copy_crash_status" -ne 0 ] || fail "the install-copy crash injection returned success."
[ -d "$install_copy_host/.jekyll-obsidian-update" ] || fail "the install-copy crash did not retain its transaction."
[ -z "$(find "$install_copy_host/website" -name '.jekyll-obsidian-update.*' -type f -print)" ] ||
  fail "the install-copy crash leaked a temporary file outside its transaction."
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
  JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$install_copy_host/website/bin/update" >"$tmp_root/install-copy-recover.out" 2>"$tmp_root/install-copy-recover.err" ||
  {
    sed 's/^/install-copy recovery: /' "$tmp_root/install-copy-recover.err" >&2
    fail "the install-copy crash could not recover without manual cleanup."
  }
[ "$(cat "$install_copy_host/website/update-fixture.txt")" = beta ] || fail "install-copy recovery did not finish the update."
[ ! -e "$install_copy_host/.jekyll-obsidian-update" ] || fail "install-copy recovery retained the transaction."

completed_host=$(new_locked_host completed-rename-crash)
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
  JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  JEKYLL_OBSIDIAN_UPDATE_TEST_FAIL_AT=crash_after_transaction_rename \
  "$completed_host/website/bin/update" >"$tmp_root/completed-crash.out" 2>"$tmp_root/completed-crash.err"
completed_crash_status=$?
set -e
[ "$completed_crash_status" -ne 0 ] || fail "the completed-transaction rename crash injection returned success."
[ -d "$completed_host/.jekyll-obsidian-update.completed" ] || fail "the completed-transaction crash did not leave a discoverable tombstone."
[ ! -e "$completed_host/.jekyll-obsidian-update" ] || fail "the completed-transaction crash retained both transaction names."
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$completed_host/website/bin/update" --check >"$tmp_root/completed-check.out" 2>"$tmp_root/completed-check.err"
completed_check_status=$?
set -e
[ "$completed_check_status" -eq 1 ] || fail "--check cleaned a completed transaction tombstone."
grep -Fq 'Update error: recovery_required:' "$tmp_root/completed-check.err" || fail "completed tombstone read-only refusal was unclear."
[ -d "$completed_host/.jekyll-obsidian-update.completed" ] || fail "--check removed a completed transaction tombstone."
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$completed_host/website/bin/update" >"$tmp_root/completed-recover.out" 2>"$tmp_root/completed-recover.err" || fail "a completed transaction tombstone was not recovered."
grep -Fq 'Recovered completed jekyll-obsidian update 0.0.9 -> 0.0.10.' "$tmp_root/completed-recover.out" || fail "completed transaction tombstone recovery was not reported."
[ ! -e "$completed_host/.jekyll-obsidian-update.completed" ] || fail "completed transaction tombstone recovery retained the tombstone."

mixed_host=$(new_locked_host mixed-crash)
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
  JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  JEKYLL_OBSIDIAN_UPDATE_TEST_FAIL_AT=crash_after_first_file \
  "$mixed_host/website/bin/update" >"$tmp_root/mixed-crash.out" 2>"$tmp_root/mixed-crash.err"
mixed_crash_status=$?
set -e
[ "$mixed_crash_status" -ne 0 ] || fail "the mixed crash injection returned success."
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
  JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$mixed_host/website/bin/update" >"$tmp_root/mixed-recover.out" 2>"$tmp_root/mixed-recover.err"
mixed_recover_status=$?
set -e
[ "$mixed_recover_status" -eq 1 ] || fail "mixed recovery did not stop with exit 1."
grep -Fq 'Update error: recovery_required:' "$tmp_root/mixed-recover.err" || fail "mixed recovery did not report recovery_required."
[ -d "$mixed_host/.jekyll-obsidian-update" ] || fail "mixed recovery did not preserve the transaction evidence."

mode_host=$(new_current_host mode-only)
chmod -x "$mode_host/website/bin/build"
git -C "$mode_host" add website/bin/build
git -C "$mode_host" commit --quiet -m 'Simulate a mode-only Windows checkout difference'
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
  JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$mode_host/website/bin/update" --check --to 0.0.9 >"$tmp_root/mode.out" 2>"$tmp_root/mode.err"
mode_status=$?
set -e
[ "$mode_status" -eq 2 ] || fail "a regular-file mode-only difference blocked exact adoption."
grep -Fq 'Provenance can be established for 0.0.9.' "$tmp_root/mode.out" || fail "mode-only adoption was not reported."

crlf_lock_host=$(new_locked_host crlf-lock)
awk '{ printf "%s\r\n", $0 }' "$crlf_lock_host/.github/jekyll-obsidian.lock" >"$tmp_root/crlf.lock"
mv -- "$tmp_root/crlf.lock" "$crlf_lock_host/.github/jekyll-obsidian.lock"
git -C "$crlf_lock_host" add .github/jekyll-obsidian.lock
git -C "$crlf_lock_host" commit --quiet -m 'Simulate a CRLF host lock checkout'
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$crlf_lock_host/website/bin/update" --check --to 0.0.9 >"$tmp_root/crlf-lock.out" 2>"$tmp_root/crlf-lock.err" || fail "a strict CRLF provenance lock was rejected."
grep -Fq 'jekyll-obsidian 0.0.9 is current.' "$tmp_root/crlf-lock.out" || fail "CRLF lock current output was unclear."
[ -z "$(git -C "$crlf_lock_host" status --porcelain)" ] || fail "CRLF lock check changed the host."

downgrade_host=$tmp_root/host-downgrade
git clone --quiet "$release_work" "$downgrade_host"
git -C "$downgrade_host" checkout --quiet -B host-main 'v0.0.10^{}'
git -C "$downgrade_host" remote set-url origin https://example.invalid/host.git
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
  JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$downgrade_host/website/bin/update" --to 0.0.9 >"$tmp_root/downgrade.out" 2>"$tmp_root/downgrade.err"
downgrade_status=$?
set -e
[ "$downgrade_status" -eq 1 ] || fail "a downgrade did not exit 1."
grep -Fq 'Update error: downgrades are not supported: 0.0.10 -> 0.0.9' "$tmp_root/downgrade.err" || fail "the downgrade rejection was unclear."
[ -z "$(git -C "$downgrade_host" status --porcelain)" ] || fail "downgrade rejection changed the host."

unstaged_host=$(new_locked_host dirty-unstaged)
printf '%s\n' dirty >"$unstaged_host/website/update-fixture.txt"
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$unstaged_host/website/bin/update" >"$tmp_root/dirty-unstaged.out" 2>"$tmp_root/dirty-unstaged.err"
unstaged_status=$?
set -e
[ "$unstaged_status" -eq 1 ] || fail "an unstaged website edit was accepted."
grep -Fq 'website has unstaged changes' "$tmp_root/dirty-unstaged.err" || fail "the unstaged website rejection was unclear."
[ ! -e "$unstaged_host/.jekyll-obsidian-update" ] || fail "unstaged rejection created a transaction."

staged_host=$(new_locked_host dirty-staged)
printf '%s\n' staged >"$staged_host/website/update-fixture.txt"
git -C "$staged_host" add website/update-fixture.txt
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$staged_host/website/bin/update" >"$tmp_root/dirty-staged.out" 2>"$tmp_root/dirty-staged.err"
staged_status=$?
set -e
[ "$staged_status" -eq 1 ] || fail "a staged website edit was accepted."
grep -Fq 'website has staged changes' "$tmp_root/dirty-staged.err" || fail "the staged website rejection was unclear."
[ ! -e "$staged_host/.jekyll-obsidian-update" ] || fail "staged rejection created a transaction."

untracked_host=$(new_locked_host dirty-untracked)
printf '%s\n' untracked >"$untracked_host/website/not-ignored.txt"
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$untracked_host/website/bin/update" >"$tmp_root/dirty-untracked.out" 2>"$tmp_root/dirty-untracked.err"
untracked_status=$?
set -e
[ "$untracked_status" -eq 1 ] || fail "a non-ignored untracked website file was accepted."
grep -Fq 'website has non-ignored untracked files' "$tmp_root/dirty-untracked.err" || fail "the untracked website rejection was unclear."
[ ! -e "$untracked_host/.jekyll-obsidian-update" ] || fail "untracked rejection created a transaction."

committed_host=$(new_locked_host dirty-committed)
printf '%s\n' customized >"$committed_host/website/update-fixture.txt"
git -C "$committed_host" add website/update-fixture.txt
git -C "$committed_host" commit --quiet -m 'Customize the managed snapshot'
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$committed_host/website/bin/update" --to 0.0.9 >"$tmp_root/dirty-committed.out" 2>"$tmp_root/dirty-committed.err"
committed_status=$?
set -e
[ "$committed_status" -eq 1 ] || fail "a committed website customization was accepted."
grep -Fq 'committed website does not match its provenance lock' "$tmp_root/dirty-committed.err" || fail "the committed customization rejection was unclear."
[ ! -e "$committed_host/.jekyll-obsidian-update" ] || fail "committed customization rejection created a transaction."

workflow_host=$(new_locked_host dirty-workflow)
printf '%s\n' '# local workflow edit' >>"$workflow_host/.github/workflows/pages.yml"
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$workflow_host/website/bin/update" >"$tmp_root/dirty-workflow.out" 2>"$tmp_root/dirty-workflow.err"
workflow_status=$?
set -e
[ "$workflow_status" -eq 1 ] || fail "a dirty managed workflow was accepted."
grep -Fq 'managed Pages workflow has unstaged changes' "$tmp_root/dirty-workflow.err" || fail "the dirty workflow rejection was unclear."
[ ! -e "$workflow_host/.jekyll-obsidian-update" ] || fail "dirty workflow rejection created a transaction."

github_link_host=$(new_locked_host github-parent-link)
mv -- "$github_link_host/.github" "$tmp_root/external-github"
ln -s "$tmp_root/external-github" "$github_link_host/.github"
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$github_link_host/website/bin/update" >"$tmp_root/github-link.out" 2>"$tmp_root/github-link.err"
github_link_status=$?
set -e
[ "$github_link_status" -eq 1 ] || fail "a symlinked .github parent was accepted."
grep -Fq '.github must be a regular directory' "$tmp_root/github-link.err" || fail "the symlinked .github rejection was unclear."
[ ! -e "$github_link_host/.jekyll-obsidian-update" ] || fail "symlinked .github rejection created a transaction."

workflows_link_host=$(new_locked_host workflows-parent-link)
mv -- "$workflows_link_host/.github/workflows" "$tmp_root/external-workflows"
ln -s "$tmp_root/external-workflows" "$workflows_link_host/.github/workflows"
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$workflows_link_host/website/bin/update" >"$tmp_root/workflows-link.out" 2>"$tmp_root/workflows-link.err"
workflows_link_status=$?
set -e
[ "$workflows_link_status" -eq 1 ] || fail "a symlinked workflows parent was accepted."
grep -Fq '.github/workflows must be a regular directory' "$tmp_root/workflows-link.err" || fail "the symlinked workflows rejection was unclear."
[ ! -e "$workflows_link_host/.jekyll-obsidian-update" ] || fail "symlinked workflows rejection created a transaction."

config_unstaged_host=$(new_locked_host dirty-config-unstaged)
sed "s/theme: 'minimal'/theme: 'docs'/" "$config_unstaged_host/.github/jekyll-obsidian.yml" >"$tmp_root/config-unstaged.next"
mv -- "$tmp_root/config-unstaged.next" "$config_unstaged_host/.github/jekyll-obsidian.yml"
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$config_unstaged_host/website/bin/update" >"$tmp_root/config-unstaged.out" 2>"$tmp_root/config-unstaged.err"
config_unstaged_status=$?
set -e
[ "$config_unstaged_status" -eq 1 ] || fail "an unstaged managed config edit was accepted."
grep -Fq 'managed host configuration block has unstaged changes' "$tmp_root/config-unstaged.err" || fail "the unstaged managed config rejection was unclear."
[ ! -e "$config_unstaged_host/.jekyll-obsidian-update" ] || fail "unstaged managed config rejection created a transaction."

config_staged_host=$(new_locked_host dirty-config-staged)
sed "s/theme: 'minimal'/theme: 'docs'/" "$config_staged_host/.github/jekyll-obsidian.yml" >"$tmp_root/config-staged.next"
mv -- "$tmp_root/config-staged.next" "$config_staged_host/.github/jekyll-obsidian.yml"
git -C "$config_staged_host" add .github/jekyll-obsidian.yml
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$config_staged_host/website/bin/update" >"$tmp_root/config-staged.out" 2>"$tmp_root/config-staged.err"
config_staged_status=$?
set -e
[ "$config_staged_status" -eq 1 ] || fail "a staged managed config edit was accepted."
grep -Fq 'managed host configuration block has staged changes' "$tmp_root/config-staged.err" || fail "the staged managed config rejection was unclear."
[ ! -e "$config_staged_host/.jekyll-obsidian-update" ] || fail "staged managed config rejection created a transaction."

lock_host=$(new_locked_host dirty-lock)
printf '%s\n' 'tampered=true' >>"$lock_host/.github/jekyll-obsidian.lock"
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="$test_transport" \
  "$lock_host/website/bin/update" >"$tmp_root/dirty-lock.out" 2>"$tmp_root/dirty-lock.err"
lock_status=$?
set -e
[ "$lock_status" -eq 1 ] || fail "a malformed provenance lock was accepted."
grep -Fq 'provenance lock is malformed' "$tmp_root/dirty-lock.err" || fail "the malformed lock rejection was unclear."
[ ! -e "$lock_host/.jekyll-obsidian-update" ] || fail "malformed lock rejection created a transaction."

bump_fixture_version() {
  fixture_root=$1
  fixture_before=$2
  fixture_after=$3
  set_product_version "$fixture_root/website" "$fixture_before" "$fixture_after"
}

missing_work=$tmp_root/missing-work
git clone --quiet "$release_remote" "$missing_work"
git -C "$missing_work" config user.name 'Update Contract'
git -C "$missing_work" config user.email 'update-contract@example.invalid'
git -C "$missing_work" checkout --quiet -B missing-main 'v0.0.10^{}'
bump_fixture_version "$missing_work" 0.0.10 0.1.9
rm -- "$missing_work/website/scripts/example-config.yml"
git -C "$missing_work" add --all
git -C "$missing_work" commit --quiet -m 'Missing required component fixture'
git -C "$missing_work" tag -a v0.1.9 -m 'Missing required component fixture'
missing_remote=$tmp_root/missing-releases.git
git clone --quiet --bare "$missing_work" "$missing_remote"
missing_host=$(new_locked_host missing-component)
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="file://$missing_remote" \
  "$missing_host/website/bin/update" --check --to 0.1.9 >"$tmp_root/missing.out" 2>"$tmp_root/missing.err"
missing_status=$?
set -e
[ "$missing_status" -eq 1 ] || fail "a release missing example-config.yml was accepted."
grep -Fq 'missing required component: website/scripts/example-config.yml' "$tmp_root/missing.err" || fail "the missing required component rejection was unclear."
[ -z "$(git -C "$missing_host" status --porcelain)" ] || fail "missing component rejection changed the host."
[ ! -e "$missing_host/.jekyll-obsidian-update" ] || fail "missing component rejection created a transaction."

for malformed_version in 0.01.0 .0.1; do
  malformed_work=$tmp_root/malformed-work-$malformed_version
  git clone --quiet "$release_remote" "$malformed_work"
  git -C "$malformed_work" config user.name 'Update Contract'
  git -C "$malformed_work" config user.email 'update-contract@example.invalid'
  git -C "$malformed_work" tag -a "v$malformed_version" 'v0.0.10^{}' -m 'Malformed SemVer tag fixture'
  malformed_remote=$tmp_root/malformed-releases-$malformed_version.git
  git clone --quiet --bare "$malformed_work" "$malformed_remote"
  malformed_host=$(new_locked_host "malformed-tag-$malformed_version")
  set +e
  JEKYLL_OBSIDIAN_UPDATE_TESTING=1 JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="file://$malformed_remote" \
    "$malformed_host/website/bin/update" --check --to 0.0.9 >"$tmp_root/malformed-$malformed_version.out" 2>"$tmp_root/malformed-$malformed_version.err"
  malformed_status=$?
  set -e
  [ "$malformed_status" -eq 1 ] || fail "an invalid stable SemVer-shaped release tag was ignored."
  grep -Fq "invalid stable SemVer release tag: v$malformed_version" "$tmp_root/malformed-$malformed_version.err" || fail "the invalid SemVer tag rejection was unclear."
  [ -z "$(git -C "$malformed_host" status --porcelain)" ] || fail "invalid SemVer tag rejection changed the host."
done

boundary_work=$tmp_root/boundary-work
git clone --quiet "$release_remote" "$boundary_work"
git -C "$boundary_work" config user.name 'Update Contract'
git -C "$boundary_work" config user.email 'update-contract@example.invalid'
git -C "$boundary_work" checkout --quiet -B case-main 'v0.0.10^{}'
bump_fixture_version "$boundary_work" 0.0.10 0.1.13
git -C "$boundary_work" mv website/update-fixture.txt website/Update-Fixture.txt
git -C "$boundary_work" add --all
git -C "$boundary_work" commit --quiet -m 'Case-only rename fixture'
git -C "$boundary_work" tag -a v0.1.13 -m 'Case-only rename fixture'

git -C "$boundary_work" checkout --quiet -B parent-main 'v0.0.10^{}'
bump_fixture_version "$boundary_work" 0.0.10 0.1.14
rm -- "$boundary_work/website/parent-transition"
mkdir -p "$boundary_work/website/parent-transition"
printf '%s\n' child >"$boundary_work/website/parent-transition/child.txt"
git -C "$boundary_work" add --all
git -C "$boundary_work" commit --quiet -m 'File-to-directory fixture'
git -C "$boundary_work" tag -a v0.1.14 -m 'File-to-directory fixture'

git -C "$boundary_work" checkout --quiet -B nested-tag-main 'v0.0.10^{}'
bump_fixture_version "$boundary_work" 0.0.10 0.1.15
git -C "$boundary_work" add --all
git -C "$boundary_work" commit --quiet -m 'Nested tag target fixture'
git -C "$boundary_work" tag -a inner-0.1.15 -m 'Nested tag inner object'
git -C "$boundary_work" tag -a v0.1.15 inner-0.1.15 -m 'Nested official tag fixture'

boundary_remote=$tmp_root/boundary-releases.git
git clone --quiet --bare "$boundary_work" "$boundary_remote"
case_rename_host=$(new_locked_host case-rename)
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="file://$boundary_remote" \
  "$case_rename_host/website/bin/update" --check --to 0.1.13 >"$tmp_root/case-rename.out" 2>"$tmp_root/case-rename.err"
case_rename_status=$?
set -e
[ "$case_rename_status" -eq 1 ] || fail "a cross-version case-only path rename was accepted."
grep -Fq 'contains a cross-version case-only path rename' "$tmp_root/case-rename.err" || fail "case-only rename rejection was unclear."
[ ! -e "$case_rename_host/.jekyll-obsidian-update" ] || fail "case-only rename rejection created a transaction."

parent_transition_host=$(new_locked_host parent-transition)
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="file://$boundary_remote" \
  "$parent_transition_host/website/bin/update" --check --to 0.1.14 >"$tmp_root/parent-transition.out" 2>"$tmp_root/parent-transition.err"
parent_transition_status=$?
set -e
[ "$parent_transition_status" -eq 1 ] || fail "a target child beneath an old regular file passed preflight."
grep -Fq 'release path has a non-directory or linked parent: website/parent-transition/child.txt' "$tmp_root/parent-transition.err" || fail "non-directory parent rejection was unclear."
[ ! -e "$parent_transition_host/.jekyll-obsidian-update" ] || fail "non-directory parent rejection created a transaction."

nested_tag_host=$(new_locked_host nested-tag)
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="file://$boundary_remote" \
  "$nested_tag_host/website/bin/update" --check --to 0.1.15 >"$tmp_root/nested-tag.out" 2>"$tmp_root/nested-tag.err"
nested_tag_status=$?
set -e
[ "$nested_tag_status" -eq 1 ] || fail "a release tag pointing to another tag was accepted."
grep -Fq 'official release v0.1.15 failed provenance verification' "$tmp_root/nested-tag.err" || fail "nested annotated tag rejection was unclear."
[ ! -e "$nested_tag_host/.jekyll-obsidian-update" ] || fail "nested tag rejection created a transaction."

preflight_work=$tmp_root/preflight-work
git clone --quiet "$release_remote" "$preflight_work"
git -C "$preflight_work" config user.name 'Update Contract'
git -C "$preflight_work" config user.email 'update-contract@example.invalid'
git -C "$preflight_work" checkout --quiet -B preflight-main 'v0.0.10^{}'
bump_fixture_version "$preflight_work" 0.0.10 0.1.10
awk 'NR == 3 { print "exit 73" } { print }' "$preflight_work/website/bin/integrate" >"$preflight_work/website/bin/integrate.next"
mv -- "$preflight_work/website/bin/integrate.next" "$preflight_work/website/bin/integrate"
chmod +x "$preflight_work/website/bin/integrate"
git -C "$preflight_work" add --all
git -C "$preflight_work" commit --quiet -m 'Candidate integrate failure fixture'
git -C "$preflight_work" tag -a v0.1.10 -m 'Candidate integrate failure fixture'

git -C "$preflight_work" show 'v0.0.10^{}:website/bin/integrate' >"$preflight_work/website/bin/integrate"
chmod +x "$preflight_work/website/bin/integrate"
bump_fixture_version "$preflight_work" 0.1.10 0.1.11
mkdir -p "$preflight_work/website/node_modules"
printf '%s\n' target >"$preflight_work/website/node_modules/collision.txt"
git -C "$preflight_work" add --all
git -C "$preflight_work" add -f website/node_modules/collision.txt
git -C "$preflight_work" commit --quiet -m 'Ignored collision fixture'
git -C "$preflight_work" tag -a v0.1.11 -m 'Ignored collision fixture'

git -C "$preflight_work" rm --quiet -f website/node_modules/collision.txt
bump_fixture_version "$preflight_work" 0.1.11 0.1.12
printf '%s\n' '# state is no longer ignored' >"$preflight_work/website/nested-ignore/.gitignore"
git -C "$preflight_work" add --all
git -C "$preflight_work" commit --quiet -m 'Ignored state contract removal fixture'
git -C "$preflight_work" tag -a v0.1.12 -m 'Ignored state contract removal fixture'

git -C "$preflight_work" checkout --quiet -B real-check-main 'v0.0.10^{}'
bump_fixture_version "$preflight_work" 0.0.10 0.1.16
awk '
  { print }
  NR == 6 {
    print "if [ \"${1:-}\" = --check ] && [ -f \"$HOST_DIR/update-contract-real-check-failure\" ]; then"
    print "  exit 74"
    print "fi"
  }
' "$preflight_work/website/bin/integrate" >"$preflight_work/website/bin/integrate.next"
mv -- "$preflight_work/website/bin/integrate.next" "$preflight_work/website/bin/integrate"
chmod +x "$preflight_work/website/bin/integrate"
git -C "$preflight_work" add --all
git -C "$preflight_work" commit --quiet -m 'Real host post-check failure fixture'
git -C "$preflight_work" tag -a v0.1.16 -m 'Real host post-check failure fixture'

preflight_remote=$tmp_root/preflight-releases.git
git clone --quiet --bare "$preflight_work" "$preflight_remote"
integrate_failure_host=$(new_locked_host candidate-integrate-failure)
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="file://$preflight_remote" \
  "$integrate_failure_host/website/bin/update" --check --to 0.1.10 >"$tmp_root/integrate-failure.out" 2>"$tmp_root/integrate-failure.err"
integrate_failure_status=$?
set -e
[ "$integrate_failure_status" -eq 1 ] || fail "a candidate integrate failure was accepted."
grep -Fq 'release v0.1.10 could not render host integration' "$tmp_root/integrate-failure.err" || fail "candidate integrate failure was not reported."
[ -z "$(git -C "$integrate_failure_host" status --porcelain)" ] || fail "candidate integrate failure changed the host."
[ ! -e "$integrate_failure_host/.jekyll-obsidian-update" ] || fail "candidate integrate failure created a transaction."

real_check_host=$(new_locked_host real-host-post-check)
printf '%s\n' fail >"$real_check_host/update-contract-real-check-failure"
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="file://$preflight_remote" \
  "$real_check_host/website/bin/update" --to 0.1.16 >"$tmp_root/real-check.out" 2>"$tmp_root/real-check.err"
real_check_status=$?
set -e
[ "$real_check_status" -eq 1 ] || fail "a release that failed only the real-host integrate check was accepted."
grep -Fq 'the updated host failed post-update integration verification' "$tmp_root/real-check.err" || fail "real-host post-update integration failure was not reported."
[ "$(cat "$real_check_host/website/update-fixture.txt")" = alpha ] || fail "real-host post-check failure did not roll back managed content."
grep -Fxq 'version=0.0.9' "$real_check_host/.github/jekyll-obsidian.lock" || fail "real-host post-check failure did not roll back provenance."
[ -f "$real_check_host/update-contract-real-check-failure" ] || fail "real-host post-check failure removed host-owned state."
[ ! -e "$real_check_host/.jekyll-obsidian-update" ] || fail "real-host post-check failure retained its transaction."

collision_host=$(new_locked_host ignored-collision)
mkdir -p "$collision_host/website/node_modules"
printf '%s\n' preserve >"$collision_host/website/node_modules/collision.txt"
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="file://$preflight_remote" \
  "$collision_host/website/bin/update" --check --to 0.1.11 >"$tmp_root/collision.out" 2>"$tmp_root/collision.err"
collision_status=$?
set -e
[ "$collision_status" -eq 1 ] || fail "a target file overwrote ignored local state."
grep -Fq 'release file conflicts with preserved local state: website/node_modules/collision.txt' "$tmp_root/collision.err" || fail "ignored collision rejection was unclear."
[ "$(cat "$collision_host/website/node_modules/collision.txt")" = preserve ] || fail "ignored collision rejection changed local state."
[ ! -e "$collision_host/.jekyll-obsidian-update" ] || fail "ignored collision rejection created a transaction."

no_longer_ignored_host=$(new_locked_host ignored-contract-removal)
mkdir -p "$no_longer_ignored_host/website/nested-ignore/state"
printf '%s\n' preserve >"$no_longer_ignored_host/website/nested-ignore/state/local-state.txt"
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="file://$preflight_remote" \
  "$no_longer_ignored_host/website/bin/update" --check --to 0.1.12 >"$tmp_root/no-longer-ignored.out" 2>"$tmp_root/no-longer-ignored.err"
no_longer_ignored_status=$?
set -e
[ "$no_longer_ignored_status" -eq 1 ] || fail "state that lost its target ignore rule was accepted."
grep -Fq 'some ignored website state would no longer be ignored by v0.1.12' "$tmp_root/no-longer-ignored.err" || fail "removed ignore contract rejection was unclear."
[ "$(cat "$no_longer_ignored_host/website/nested-ignore/state/local-state.txt")" = preserve ] || fail "removed ignore contract rejection changed local state."
[ ! -e "$no_longer_ignored_host/.jekyll-obsidian-update" ] || fail "removed ignore contract rejection created a transaction."

unsafe_work=$tmp_root/unsafe-work
git clone --quiet "$release_remote" "$unsafe_work"
git -C "$unsafe_work" config user.name 'Update Contract'
git -C "$unsafe_work" config user.email 'update-contract@example.invalid'
git -C "$unsafe_work" checkout --quiet -B unsafe-main 'v0.0.10^{}'

bump_fixture_version "$unsafe_work" 0.0.10 0.1.2
ln -s update-fixture.txt "$unsafe_work/website/unsafe-link"
git -C "$unsafe_work" add --all
git -C "$unsafe_work" commit --quiet -m 'Unsafe symlink fixture'
git -C "$unsafe_work" tag -a v0.1.2 -m 'Unsafe symlink fixture'

rm -- "$unsafe_work/website/unsafe-link"
bump_fixture_version "$unsafe_work" 0.1.2 0.1.3
printf '%s\n' reserved >"$unsafe_work/website/CON"
git -C "$unsafe_work" add --all
git -C "$unsafe_work" commit --quiet -m 'Unsafe Windows device fixture'
git -C "$unsafe_work" tag -a v0.1.3 -m 'Unsafe Windows device fixture'

rm -- "$unsafe_work/website/CON"
bump_fixture_version "$unsafe_work" 0.1.3 0.1.4
printf '%s\n' stream >"$unsafe_work/website/bad:name"
git -C "$unsafe_work" add --all
git -C "$unsafe_work" commit --quiet -m 'Unsafe Windows stream fixture'
git -C "$unsafe_work" tag -a v0.1.4 -m 'Unsafe Windows stream fixture'

rm -- "$unsafe_work/website/bad:name"
bump_fixture_version "$unsafe_work" 0.1.4 0.1.5
printf '%s\n' trailing >"$unsafe_work/website/trailing."
git -C "$unsafe_work" add --all
git -C "$unsafe_work" commit --quiet -m 'Unsafe trailing-dot fixture'
git -C "$unsafe_work" tag -a v0.1.5 -m 'Unsafe trailing-dot fixture'

rm -- "$unsafe_work/website/trailing."
bump_fixture_version "$unsafe_work" 0.1.5 0.1.6
git -C "$unsafe_work" add --all
upper_blob=$(printf '%s\n' upper | git -C "$unsafe_work" hash-object -w --stdin)
lower_blob=$(printf '%s\n' lower | git -C "$unsafe_work" hash-object -w --stdin)
git -C "$unsafe_work" update-index --add --cacheinfo "100644,$upper_blob,website/Case.txt"
git -C "$unsafe_work" update-index --add --cacheinfo "100644,$lower_blob,website/case.txt"
git -C "$unsafe_work" commit --quiet -m 'Unsafe case-collision fixture'
git -C "$unsafe_work" tag -a v0.1.6 -m 'Unsafe case-collision fixture'

git -C "$unsafe_work" update-index --force-remove -- website/Case.txt website/case.txt
replace_literal_count "$unsafe_work/website/.jekyll-obsidian-release" 'version=0.1.6' 'version=0.1.7' 1
git -C "$unsafe_work" add --all
git -C "$unsafe_work" commit --quiet -m 'Mismatched version fixture'
git -C "$unsafe_work" tag -a v0.1.7 -m 'Mismatched version fixture'

unsafe_remote=$tmp_root/unsafe-releases.git
git clone --quiet --bare "$unsafe_work" "$unsafe_remote"
for unsafe_version in 0.1.2 0.1.3 0.1.4 0.1.5 0.1.6; do
  unsafe_host=$(new_locked_host "unsafe-$unsafe_version")
  set +e
  JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
    JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="file://$unsafe_remote" \
    "$unsafe_host/website/bin/update" --to "$unsafe_version" \
    >"$tmp_root/unsafe-$unsafe_version.out" 2>"$tmp_root/unsafe-$unsafe_version.err"
  unsafe_status=$?
  set -e
  [ "$unsafe_status" -eq 1 ] || fail "unsafe release v$unsafe_version was accepted."
  grep -Fq "release v$unsafe_version contains an unsafe website tree" "$tmp_root/unsafe-$unsafe_version.err" || fail "unsafe release v$unsafe_version was not rejected at the tree boundary."
  [ ! -e "$unsafe_host/.jekyll-obsidian-update" ] || fail "unsafe release v$unsafe_version created a transaction."
done

mismatch_host=$(new_locked_host version-mismatch)
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
  JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="file://$unsafe_remote" \
  "$mismatch_host/website/bin/update" --to 0.1.7 >"$tmp_root/mismatch.out" 2>"$tmp_root/mismatch.err"
mismatch_status=$?
set -e
[ "$mismatch_status" -eq 1 ] || fail "a release with inconsistent package versions was accepted."
grep -Fq 'release v0.1.7 has inconsistent package or Ruby versions' "$tmp_root/mismatch.err" || fail "candidate version mismatch was not reported."
[ ! -e "$mismatch_host/.jekyll-obsidian-update" ] || fail "candidate version mismatch created a transaction."

lightweight_work=$tmp_root/lightweight-work
git clone --quiet "$release_remote" "$lightweight_work"
git -C "$lightweight_work" tag v0.1.8 'v0.0.10^{}'
lightweight_remote=$tmp_root/lightweight-releases.git
git clone --quiet --bare "$lightweight_work" "$lightweight_remote"
lightweight_host=$(new_locked_host lightweight-tag)
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
  JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="file://$lightweight_remote" \
  "$lightweight_host/website/bin/update" --check --to 0.0.9 >"$tmp_root/lightweight.out" 2>"$tmp_root/lightweight.err"
lightweight_status=$?
set -e
[ "$lightweight_status" -eq 1 ] || fail "a release-shaped lightweight tag was silently ignored."
grep -Fq 'release-shaped tag v0.1.8 must be an annotated tag' "$tmp_root/lightweight.err" || fail "lightweight tag rejection was unclear."
[ -z "$(git -C "$lightweight_host" status --porcelain)" ] || fail "lightweight tag rejection changed the host."

moving_work=$tmp_root/moving-work
git clone --quiet "$release_remote" "$moving_work"
git -C "$moving_work" config user.name 'Update Contract'
git -C "$moving_work" config user.email 'update-contract@example.invalid'
git -C "$moving_work" checkout --quiet -B moved-main 'v0.0.9^{}'
printf '%s\n' moved >"$moving_work/moved-tag.txt"
git -C "$moving_work" add moved-tag.txt
git -C "$moving_work" commit --quiet -m 'Move release tag without changing website'
git -C "$moving_work" tag -f -a v0.0.9 -m 'Moved release tag'
moving_remote=$tmp_root/moving-releases.git
git clone --quiet --bare "$moving_work" "$moving_remote"
moving_host=$(new_locked_host moved-tag)
set +e
JEKYLL_OBSIDIAN_UPDATE_TESTING=1 \
  JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN="file://$moving_remote" \
  "$moving_host/website/bin/update" --check --to 0.0.9 >"$tmp_root/moved.out" 2>"$tmp_root/moved.err"
moving_status=$?
set -e
[ "$moving_status" -eq 1 ] || fail "a moved locked release tag was accepted."
grep -Fq 'installed release tag moved or its provenance no longer matches' "$tmp_root/moved.err" || fail "moved tag rejection was unclear."
[ -z "$(git -C "$moving_host" status --porcelain)" ] || fail "moved tag rejection changed the host."

printf '%s\n' "POSIX update contract passed."
