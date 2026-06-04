#!/usr/bin/env bash

set -euo pipefail

# This wrapper exists because `moonrun moondiff.wasm` cannot reliably read the
# absolute paths that Git difftool passes in $LOCAL and $REMOTE. It copies both
# sides into a private temporary directory, then invokes moondiff with relative
# paths inside that directory.

usage() {
  cat <<'EOF'
Usage:
  moondiff_git_wrapper.sh
  moondiff_git_wrapper.sh OLD_FILE NEW_FILE [MERGED_FILE]

Git difftool sets LOCAL, REMOTE, and MERGED. When OLD_FILE and NEW_FILE are
not provided, this wrapper reads those Git variables from the environment.
For Git's difftool cmd setting, pass "$LOCAL" "$REMOTE" "$MERGED" as arguments
because Git keeps them as shell variables rather than exported environment
variables.

Environment:
  MOONDIFF_WASM  Path to moondiff.wasm. Defaults to
                 $HOME/.local/share/moondiff/moondiff.wasm.
  MOONRUN        moonrun executable. Defaults to moonrun.
EOF
}

die() {
  printf 'moondiff git wrapper: %s\n' "$*" >&2
  exit 1
}

# Return a conservative filename when Git does not provide a useful repository
# path. This is mainly used for /dev/null or direct positional calls.
path_basename() {
  local path=$1
  path=${path%/}
  path=${path##*/}
  if [[ -z "$path" ]]; then
    path="file.mbt"
  fi
  printf '%s\n' "$path"
}

# Pick the relative path that moondiff should display and read under the temp
# directory. Git's $MERGED is normally the repository-relative path, which keeps
# output readable. Absolute paths and parent-directory traversal are discarded
# because this value is later used as a destination path under $TMP_DIR.
relative_hint() {
  local hint=$1
  local fallback=$2

  if [[ -z "$hint" || "$hint" == "/dev/null" ]]; then
    hint=$(path_basename "$fallback")
  fi

  hint=${hint#./}
  while [[ "$hint" == /* ]]; do
    hint=${hint#/}
  done

  case "$hint" in
    ""|"."|".."|../*|*/../*|*/..)
      hint=$(path_basename "$fallback")
      ;;
  esac

  if [[ -z "$hint" || "$hint" == "." || "$hint" == ".." ]]; then
    hint="file.mbt"
  fi

  printf '%s\n' "$hint"
}

# Copy one side of the comparison into $TMP_DIR.
#
# Git represents added or deleted files with /dev/null. moondiff expects regular
# files, so /dev/null becomes an empty file on the corresponding side.
copy_input() {
  local src=$1
  local rel=$2
  local side=$3
  local dst="$TMP_DIR/$side/$rel"
  local src_for_cp

  mkdir -p "$(dirname "$dst")"

  if [[ "$src" == "/dev/null" ]]; then
    : >"$dst"
  else
    # Relative $REMOTE paths are resolved from the repository root, which is
    # where Git runs the configured difftool command.
    if [[ "$src" == /* ]]; then
      src_for_cp=$src
    else
      src_for_cp="./$src"
    fi
    cp "$src_for_cp" "$dst"
  fi

  printf '%s/%s\n' "$side" "$rel"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# Git's difftool command keeps $LOCAL, $REMOTE, and $MERGED as shell variables,
# not exported environment variables. The README configuration therefore passes
# them as positional arguments. The zero-argument path remains useful for manual
# debugging when the variables are explicitly exported.
if [[ $# -eq 0 ]]; then
  OLD_SRC=${LOCAL:-}
  NEW_SRC=${REMOTE:-}
  MERGED_HINT=${MERGED:-}
elif [[ $# -eq 2 || $# -eq 3 ]]; then
  OLD_SRC=$1
  NEW_SRC=$2
  MERGED_HINT=${3:-${MERGED:-}}
else
  usage >&2
  exit 2
fi

[[ -n "${OLD_SRC:-}" ]] || die "missing old file path; set LOCAL or pass OLD_FILE"
[[ -n "${NEW_SRC:-}" ]] || die "missing new file path; set REMOTE or pass NEW_FILE"

MOONRUN_BIN=${MOONRUN:-moonrun}
if ! command -v "$MOONRUN_BIN" >/dev/null 2>&1; then
  die "cannot find moonrun executable: $MOONRUN_BIN"
fi

if [[ -n "${MOONDIFF_WASM:-}" ]]; then
  WASM_PATH=$MOONDIFF_WASM
else
  [[ -n "${HOME:-}" ]] || die "HOME is not set; set MOONDIFF_WASM explicitly"
  WASM_PATH="$HOME/.local/share/moondiff/moondiff.wasm"
fi

# Resolve the wasm path before `cd "$TMP_DIR"`, otherwise a relative
# MOONDIFF_WASM would be interpreted from the temporary directory.
case "$WASM_PATH" in
  /*) ;;
  *) WASM_PATH="$PWD/$WASM_PATH" ;;
esac

[[ -f "$WASM_PATH" ]] || die "moondiff wasm not found: $WASM_PATH"

# Use an isolated temp directory per invocation so concurrent difftool runs and
# repeated comparisons of files with the same name cannot collide.
TMP_PARENT=${TMPDIR:-/tmp}
TMP_DIR=$(mktemp -d "$TMP_PARENT/moondiff-git.XXXXXX")
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT HUP INT TERM

# Both sides use the same relative hint, placed under separate old/ and new/
# roots. That preserves the displayed file path while keeping inputs distinct.
REL=$(relative_hint "$MERGED_HINT" "$NEW_SRC")
OLD_REL=$(copy_input "$OLD_SRC" "$REL" old)
NEW_REL=$(copy_input "$NEW_SRC" "$REL" new)

cd "$TMP_DIR"
"$MOONRUN_BIN" "$WASM_PATH" "$OLD_REL" "$NEW_REL"
