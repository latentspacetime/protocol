#!/bin/zsh

set -eu
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:${PATH:-}"

protocol_root="${0:A:h:h}"
source_root="${PROTOCODE_SOURCE_ROOT:-${CODE_WORKSPACE:-$HOME/Code}/protocode}"
install_root="${PROTOCODE_INSTALL_ROOT:-$HOME/.local/share/protocode}"
pin_file="${PROTOCODE_PIN_FILE:-$protocol_root/protocode.pin}"

die() {
  print -u2 -- "protocode build: $*"
  exit 1
}

run() {
  print -- "==> $*"
  "$@"
}

[[ "$OSTYPE" == darwin* ]] || die "macOS is required"
command -v git >/dev/null 2>&1 || die "git is required"
command -v bun >/dev/null 2>&1 || die "Bun 1.3 or newer is required"

bun_version=$(bun --version)
bun_parts=("${(@s:.:)bun_version}")
if (( ${bun_parts[1]:-0} < 1 || (${bun_parts[1]:-0} == 1 && ${bun_parts[2]:-0} < 3) )); then
  die "Bun 1.3 or newer is required; found $bun_version"
fi

[[ -d "$source_root/.git" || -f "$source_root/.git" ]] || die "source clone missing: $source_root"
source_root="${source_root:A}"

branch=$(git -C "$source_root" branch --show-current)
[[ "$branch" == "stable" ]] || die "source must be on stable; found ${branch:-detached HEAD}"
[[ -z "$(git -C "$source_root" diff --name-only --diff-filter=U)" ]] || die "source has unresolved conflicts"
[[ -z "$(git -C "$source_root" status --porcelain)" ]] || die "source has uncommitted or untracked files"

upstream_url=$(git -C "$source_root" remote get-url upstream 2>/dev/null) || die "upstream remote is missing"
case "$upstream_url" in
  https://github.com/anomalyco/opencode|https://github.com/anomalyco/opencode.git|git@github.com:anomalyco/opencode.git) ;;
  *) die "upstream must resolve to anomalyco/opencode; found $upstream_url" ;;
esac

commit=$(git -C "$source_root" rev-parse HEAD)
upstream_tag=$(git -C "$source_root" describe --tags --match 'v[0-9]*' --abbrev=0 "$commit") ||
  die "no upstream stable tag is reachable from $commit"
[[ "$upstream_tag" == v<->.<->.<-> ]] || die "invalid upstream stable tag: $upstream_tag"
version="${upstream_tag#v}"

trusted_tag_ref="refs/protocode/upstream-tags/$upstream_tag"
run /usr/bin/perl -e 'alarm shift; exec @ARGV or die "exec: $!"' 30 \
  git -C "$source_root" fetch --quiet --force --no-tags upstream \
  "refs/tags/$upstream_tag:$trusted_tag_ref"
upstream_commit=$(git -C "$source_root" rev-parse "$upstream_tag^{}")
trusted_upstream_commit=$(git -C "$source_root" rev-parse "$trusted_tag_ref^{}")
[[ "$upstream_commit" == "$trusted_upstream_commit" ]] ||
  die "$upstream_tag does not match the tag fetched from upstream"

tag_output=$(git -C "$source_root" tag --points-at "$commit" --list "protocode-${version}-r*")
release_tags=("${(@f)tag_output}")
if [[ -z "$tag_output" || ${#release_tags} -ne 1 ]]; then
  die "exactly one protocode-${version}-r<N> tag must point at $commit"
fi
release_tag="$release_tags[1]"
[[ "$release_tag" == protocode-${version}-r<-> ]] || die "invalid Protocode release tag: $release_tag"
revision="${release_tag##*-r}"
build_version="${version}-protocode.${revision}"

mkdir -p "$install_root"
lock_dir="$install_root/.build-lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
  die "another build is active; remove $lock_dir only after confirming no build process is running"
fi
opencode_test_log=''
cleanup() {
  [[ -z "$opencode_test_log" ]] || rm -f -- "$opencode_test_log"
  rmdir "$lock_dir" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

cd "$source_root"
run bun install --frozen-lockfile
run bun run lint
run bun run typecheck
run bun run --cwd packages/tui test
run bun --cwd packages/core test test/pty/bun-pty-listener.test.ts
opencode_test_log=$(mktemp "$install_root/.opencode-test.XXXXXX")
if ! run bun run --cwd packages/opencode test > >(tee "$opencode_test_log") 2>&1; then
  # Bun 1.3.14 can rarely corrupt loopback HTTP responses in two known tests.
  # Retry only those exact test/signature pairs.
  known_pty_failure=0
  known_error_middleware_failure=0
  if grep -Fq 'error: ManagedRuntime disposed' "$opencode_test_log" &&
     grep -Fq 'v2 pty HttpApi' "$opencode_test_log"; then
    known_pty_failure=1
  fi
  if grep -Fq 'HttpApi error middleware > returns a safe body for unknown 500 defects' "$opencode_test_log" &&
     grep -Fq 'ECONNRESET' "$opencode_test_log"; then
    known_error_middleware_failure=1
  fi
  unexpected_failures=$(grep '^(fail)' "$opencode_test_log" |
    grep -Fv 'v2 pty HttpApi' |
    grep -Fv 'HttpApi error middleware > returns a safe body for unknown 500 defects' || true)
  if (( ! known_pty_failure && ! known_error_middleware_failure )) || [[ -n "$unexpected_failures" ]]; then
    die "OpenCode tests failed without the known Bun loopback signature"
  fi
  print -u2 -- "protocode build: OpenCode tests failed; retrying the complete suite once"
  run bun run --cwd packages/opencode test
fi
rm -f -- "$opencode_test_log"
opencode_test_log=''
run env OPENCODE_VERSION="$build_version" ./packages/opencode/script/build.ts --single

[[ -z "$(git status --porcelain)" ]] || die "verification modified the source tree"

case "$(uname -m)" in
  arm64) artifact="$source_root/packages/opencode/dist/opencode-darwin-arm64/bin/opencode" ;;
  x86_64) artifact="$source_root/packages/opencode/dist/opencode-darwin-x64/bin/opencode" ;;
  *) die "unsupported macOS architecture: $(uname -m)" ;;
esac
[[ -x "$artifact" ]] || die "build artifact missing: $artifact"
run "$artifact" --version

export PROTOCODE_ARTIFACT="$artifact"
export PROTOCODE_COMMIT="$commit"
export PROTOCODE_UPSTREAM_TAG="$upstream_tag"
export PROTOCODE_UPSTREAM_COMMIT="$upstream_commit"
export PROTOCODE_RELEASE_TAG="$release_tag"
export PROTOCODE_INSTALL_ROOT="$install_root"
export PROTOCODE_PIN_FILE="$pin_file"
export PROTOCODE_BUILD_LOCK_DIR="$lock_dir"
exec "$protocol_root/scripts/protocode-promote.zsh"
