#!/usr/bin/env bash
# The clean copy vbw prove runs on (docs/proof.md): a detached git worktree of
# HEAD inside the project, so uncommitted changes and untracked files change no
# proof result. Git-ignored paths (dependencies, env files) are linked in from
# the working folder; they are the project's environment, not its code.

# proofcopy_create: make the copy; sets PROOF_COPY (absolute path). Called
# directly, never in $(...), so the guard that removes it on interrupt holds.
proofcopy_create() {
  local dir p
  dir=$(mktemp -d "$VBW_RUNTIME/proof.XXXXXX") || vbw_die "cannot create a directory in $VBW_RUNTIME"
  vbw_guard_add dir "$dir"
  PROOF_COPY="$dir/tree"
  git -C "$VBW_ROOT" worktree prune 2> /dev/null || true
  git -C "$VBW_ROOT" -c core.hooksPath=/dev/null worktree add -q --detach "$PROOF_COPY" HEAD > /dev/null 2>&1 \
    || vbw_die "cannot make a clean copy of the committed code (does the project have a commit?)"
  while IFS= read -r -d '' p; do
    p=${p%/}
    case "$p" in .git | .git/* | .vbw | .vbw/*) continue ;; esac
    [ ! -e "$PROOF_COPY/$p" ] && [ ! -L "$PROOF_COPY/$p" ] || continue
    mkdir -p "$PROOF_COPY/$(dirname "$p")"
    ln -s "$VBW_ROOT/$p" "$PROOF_COPY/$p"
  done < <(git -C "$VBW_ROOT" ls-files -z --others --ignored --exclude-standard --directory)
}

# proofcopy_remove: unlink the links first (nothing is ever removed through
# them), then drop the worktree and whatever is left of the directory.
proofcopy_remove() {
  [ -n "${PROOF_COPY:-}" ] || return 0
  find "$PROOF_COPY" -path "$PROOF_COPY/.git" -prune -o -type l -exec rm -f {} + 2> /dev/null || true
  git -C "$VBW_ROOT" worktree remove --force "$PROOF_COPY" > /dev/null 2>&1 || true
  git -C "$VBW_ROOT" worktree prune 2> /dev/null || true
  vbw_guard_drop "$(dirname "$PROOF_COPY")"
  PROOF_COPY=
}

# proofcopy_verify HASH RECORD: die naming every check file whose committed
# bytes differ from the approved ones.
proofcopy_verify() {
  local f bad=""
  [ "$(VBW_ROOT="$PROOF_COPY" contract_hash "$2")" != "$1" ] || return 0
  while IFS= read -r -d '' f; do
    cmp -s "$VBW_ROOT/$f" "$PROOF_COPY/$f" 2> /dev/null || bad="$bad $f"
  done < <(printf '%s' "$2" | jq -j '[.checks[].files // [] | .[]] | unique[] | . + "\u0000"')
  proofcopy_remove
  vbw_die "check files not committed as approved:${bad:- (the committed contract differs)}: commit them, then /vbw:approve"
}
