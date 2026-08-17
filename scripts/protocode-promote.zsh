#!/bin/zsh

set -eu
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:${PATH:-}"

artifact="${PROTOCODE_ARTIFACT:-}"
commit="${PROTOCODE_COMMIT:-}"
upstream_tag="${PROTOCODE_UPSTREAM_TAG:-}"
upstream_commit="${PROTOCODE_UPSTREAM_COMMIT:-}"
release_tag="${PROTOCODE_RELEASE_TAG:-}"
install_root="${PROTOCODE_INSTALL_ROOT:-$HOME/.local/share/protocode}"
pin_file="${PROTOCODE_PIN_FILE:-}"
build_lock_dir="${PROTOCODE_BUILD_LOCK_DIR:-}"

die() {
  print -u2 -- "protocode promote: $*"
  exit 1
}

inject_failure() {
  [[ "${PROTOCODE_PROMOTE_FAIL_AT:-}" != "$1" ]] || die "injected failure after $1"
}

pause_promotion() {
  [[ "${PROTOCODE_PROMOTE_PAUSE_AT:-}" != "$1" ]] || {
    [[ -z "${PROTOCODE_PROMOTE_PAUSE_FILE:-}" ]] || : > "$PROTOCODE_PROMOTE_PAUSE_FILE"
    while true; do :; done
  }
}

builds_root="$install_root/builds"
target="$builds_root/${commit:-invalid}"
current="$install_root/current"
stage=''
current_tmp=''
restore_tmp=''
pin_tmp=''
pin_backup=''
old_current=''
had_pin=0
target_created=0
pin_replaced=0
current_replaced=0
committed=0

cleanup() {
  local exit_status=$? restore_ok=1
  trap - EXIT INT TERM HUP

  if (( ! committed )); then
    if (( current_replaced )); then
      if [[ -n "$old_current" ]]; then
        [[ -z "$restore_tmp" ]] || rm -f -- "$restore_tmp"
        if ! ln -s "$old_current" "$restore_tmp" || ! mv -fh "$restore_tmp" "$current"; then
          print -u2 -- "protocode promote: failed to restore previous current link"
          restore_ok=0
        fi
      elif ! rm -f -- "$current"; then
        print -u2 -- "protocode promote: failed to remove interrupted current link"
        restore_ok=0
      fi
    fi

    if (( pin_replaced )); then
      if (( had_pin )); then
        if ! mv -f -- "$pin_backup" "$pin_file"; then
          print -u2 -- "protocode promote: failed to restore previous pin"
          restore_ok=0
        fi
      elif ! rm -f -- "$pin_file"; then
        print -u2 -- "protocode promote: failed to remove interrupted pin"
        restore_ok=0
      fi
    fi

    if (( target_created && restore_ok )); then
      rm -rf -- "$target" || print -u2 -- "protocode promote: failed to remove interrupted build $target"
    fi
  fi

  [[ -z "$stage" ]] || rm -rf -- "$stage"
  [[ -z "$current_tmp" ]] || rm -f -- "$current_tmp"
  [[ -z "$restore_tmp" ]] || rm -f -- "$restore_tmp"
  [[ -z "$pin_tmp" ]] || rm -f -- "$pin_tmp"
  [[ -z "$pin_backup" ]] || rm -f -- "$pin_backup"
  [[ -z "$build_lock_dir" ]] || rmdir "$build_lock_dir" 2>/dev/null || true
  return "$exit_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

[[ -n "$artifact" ]] || die "PROTOCODE_ARTIFACT is required"
[[ -n "$commit" ]] || die "PROTOCODE_COMMIT is required"
[[ -n "$upstream_tag" ]] || die "PROTOCODE_UPSTREAM_TAG is required"
[[ -n "$upstream_commit" ]] || die "PROTOCODE_UPSTREAM_COMMIT is required"
[[ -n "$release_tag" ]] || die "PROTOCODE_RELEASE_TAG is required"
[[ -n "$pin_file" ]] || die "PROTOCODE_PIN_FILE is required"
[[ "$commit" =~ '^[0-9a-f]{40}$' ]] || die "invalid source commit: $commit"
[[ "$upstream_commit" =~ '^[0-9a-f]{40}$' ]] || die "invalid upstream commit: $upstream_commit"
[[ "$upstream_tag" == v<->.<->.<-> ]] || die "invalid upstream tag: $upstream_tag"
version="${upstream_tag#v}"
[[ "$release_tag" == protocode-${version}-r<-> ]] || die "invalid release tag: $release_tag"
[[ -x "$artifact" ]] || die "build artifact missing: $artifact"

mkdir -p "$builds_root" "${pin_file:h}"

if [[ (-e "$current" || -L "$current") && ! -L "$current" ]]; then
  die "current must be a symbolic link: $current"
fi
if [[ -e "$pin_file" && ! -f "$pin_file" ]]; then
  die "pin must be a regular file: $pin_file"
fi
if [[ -e "$target" && (! -d "$target" || ! -x "$target/protocode") ]]; then
  die "existing build is incomplete: $target"
fi

stage=$(mktemp -d "$builds_root/.stage.XXXXXX")
current_tmp="$install_root/.current.$$"
restore_tmp="$install_root/.current-restore.$$"
pin_tmp="${pin_file}.tmp.$$"
pin_backup="${pin_file}.backup.$$"

cp "$artifact" "$stage/protocode"
chmod 755 "$stage/protocode"
"$stage/protocode" --version
artifact_sha=$(/usr/bin/shasum -a 256 "$stage/protocode")
artifact_sha="${artifact_sha%% *}"
built_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

if [[ -e "$target" ]]; then
  [[ -f "$pin_file" ]] || die "existing build has no trusted pin: $target"
  existing_sha=$(/usr/bin/shasum -a 256 "$target/protocode")
  existing_sha="${existing_sha%% *}"
  pinned_commit=$(grep '^COMMIT=' "$pin_file" 2>/dev/null) || die "existing build pin is malformed: $pin_file"
  pinned_commit="${pinned_commit#COMMIT=}"
  pinned_sha=$(grep '^ARTIFACT_SHA256=' "$pin_file" 2>/dev/null) || die "existing build pin is malformed: $pin_file"
  pinned_sha="${pinned_sha#ARTIFACT_SHA256=}"
  pinned_built=$(grep '^BUILT=' "$pin_file" 2>/dev/null) || die "existing build pin is malformed: $pin_file"
  pinned_built="${pinned_built#BUILT=}"
  [[ "$pinned_commit" == "$commit" && "$pinned_sha" == "$existing_sha" ]] ||
    die "existing build does not match its trusted pin: $target"
  artifact_sha="$existing_sha"
  built_at="$pinned_built"
  rm -rf -- "$stage"
  stage=''
else
  target_created=1
  mv "$stage" "$target"
  stage=''
fi
inject_failure target

[[ ! -L "$current" ]] || old_current=$(/usr/bin/readlink "$current")
if [[ -f "$pin_file" ]]; then
  cp -p "$pin_file" "$pin_backup"
  had_pin=1
fi

ln -s "builds/$commit" "$current_tmp"
{
  print -r -- "UPSTREAM_TAG=$upstream_tag"
  print -r -- "UPSTREAM_COMMIT=$upstream_commit"
  print -r -- "PROTOCODE_TAG=$release_tag"
  print -r -- "COMMIT=$commit"
  print -r -- "ARTIFACT_SHA256=$artifact_sha"
  print -r -- "BUILT=$built_at"
} > "$pin_tmp"

pin_replaced=1
mv -f "$pin_tmp" "$pin_file"
pin_tmp=''
inject_failure pin

current_replaced=1
mv -fh "$current_tmp" "$current"
current_tmp=''
inject_failure current
pause_promotion current
committed=1

touch "$target"
build_dirs=("$builds_root"/*(/omN))
integer index=1
for build_dir in "$build_dirs[@]"; do
  if (( index > 3 )); then
    if ! rm -rf -- "$build_dir"; then
      print -u2 -- "protocode promote: warning: could not prune $build_dir"
    fi
  fi
  (( index += 1 ))
done

print -- "protocode build installed: $target"
print -- "protocode pin updated: $pin_file"
