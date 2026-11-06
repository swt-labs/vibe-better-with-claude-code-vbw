# shellcheck shell=bash
# Shared fixtures: build a project once per test file, copy it for each test.
# Load after helper and the builder's own helper:
#   load helper
#   load loop-helper
#   load fixture-helper
#
# How to convert a file
#   Before:  setup() { loop_project; }
#            teardown() { vbw_teardown; }
#   After:   setup_file() { fixture_build loop loop_project; }
#            setup() { fixture_copy loop; }
#            teardown() { vbw_teardown; }
#            teardown_file() { fixture_teardown; }
# - setup_file: one fixture_build NAME BUILDER [ARGS...] per variant the file
#   uses, each under its own name (fixture_build human loop_project human).
#   The builder runs unchanged: it calls vbw_setup itself. Build only here,
#   never lazily in setup(): tools/test.sh runs bats --jobs, the tests of one
#   file then run in parallel, and only setup_file runs once before them all.
# - setup: fixture_copy NAME, then whatever setup() did after the builder. A
#   test that needs another variant than setup's calls fixture_copy OTHER as
#   its first line; the copy setup() made is removed first.
# - teardown stays vbw_teardown; teardown_file is fixture_teardown.
# - Never change a test's name, an assertion, or the order of the steps inside
#   a test. A converted test proves exactly what it proved before.
# - The copy is the fixture's bytes, timestamps included: a builder step whose
#   result must be fresh for each test (a clock-sensitive figure, a lock, a
#   running process) stays in setup() after fixture_copy.
# - fixture_build fails, naming the place, when the fixture holds its own path
#   (a file, a symbolic link, git history, a variable in a form it cannot
#   re-point): a copy would point back at the original. Move that step into
#   setup(). A builder must make everything inside its TEST_ROOT: nothing
#   outside it is copied, so every test would share it.
#
# fixture_copy restores the shell variables the builder set or changed,
# exported or not (TEST_ROOT, PROJECT, HOME and any of the builder's own), with
# every path into the old TEST_ROOT re-pointed into the new one, and returns to
# the directory the builder ended in. Arrays set by a builder are refused.
# After each build, setup_file's own variables and directory are put back, so
# one variant's builder never leaks into another's copies.

# fixture_store: the folder of this test file's fixtures, one folder per name
# (root/ the built TEST_ROOT, from its old paths, cwd its last directory, vars
# its variables). It lives in the file's own BATS_FILE_TMPDIR, so a bats run
# inside a test (a nested file) never shares or removes it; VBW_FIXTURE_STORE,
# never exported, overrides it for this helper's own tests.
fixture_store() {
  printf '%s\n' "${VBW_FIXTURE_STORE:-${BATS_FILE_TMPDIR:?fixtures need bats 1.4 or later}/vbw-fixtures}"
}

# _fixture_names: the shell variables a builder may set (bash's, bats', and
# this helper's own are left out), one per line.
_fixture_names() {
  compgen -v | grep -vxE 'BASH.*|BATS_.*|COMP_.*|EPOCH.*|FUNCNAME|LINENO|RANDOM|SRANDOM|SECONDS|PIPESTATUS|_|OLDPWD|PWD|SHLVL|HISTCMD|DIRSTACK|GROUPS|REPLY|OPTIND|OPTARG|OPTERR|COLUMNS|LINES|PPID|UID|EUID|SHELLOPTS|status|output|lines|stderr|stderr_lines|_fx_.*|_FIXTURE_COPY|VBW_FIXTURE_STORE'
}

# _fixture_replace VALUE OLD NEW: VALUE with every OLD made NEW, in _fx_r. No
# pattern substitution: bash 3.2 keeps quotes in its replacement, bash 5.2 reads
# & in an unquoted one.
_fixture_replace() {
  local s=$1
  _fx_r=
  while :; do
    case $s in
      *"$2"*) _fx_r=$_fx_r${s%%"$2"*}$3; s=${s#*"$2"} ;;
      *) break ;;
    esac
  done
  _fx_r=$_fx_r$s
}

# _fixture_selfpath ROOT NEEDLE: print each place under ROOT that holds NEEDLE
# (a file's contents or name, a link target, the objects of a git repository).
_fixture_selfpath() {
  local root=$1 needle=$2 f t g
  grep -rlF -- "$needle" "$root" 2> /dev/null | while IFS= read -r f; do printf '  %s\n' "${f#"$root"/}"; done
  find "$root" -mindepth 1 -name "*$needle*" -print | while IFS= read -r f; do printf '  %s (its name)\n' "${f#"$root"/}"; done
  while IFS= read -r -d '' f; do
    t=$(readlink "$f")
    case $t in *"$needle"*) printf '  %s -> %s\n' "${f#"$root"/}" "$t" ;; esac
  done < <(find "$root" -type l -print0)
  while IFS= read -r -d '' g; do
    g=${g%/objects}
    [ -f "$g/HEAD" ] || continue
    if git --git-dir="$g" cat-file --batch-all-objects --batch 2> /dev/null | grep -qaF -- "$needle"; then
      printf '  %s (git history)\n' "${g#"$root"/}"
    fi
  done < <(find "$root" -type d -name objects -prune -print0)
  return 0
}

# _fixture_back: put setup_file's variables back as they were before the build.
_fixture_back() {
  local n b e
  while IFS= read -r n; do
    b="_fx_b_$n"; e="_fx_e_$n"
    if [ -n "${!b+x}" ]; then
      printf -v "$n" '%s' "${!b}"
      if [ -n "${!e:-}" ]; then export "${n?}"; else export -n "${n?}"; fi
    else
      unset "$n"
    fi
  done < "$1"
}

# fixture_build NAME BUILDER [ARGS...]: run BUILDER [ARGS...] (it calls vbw_setup)
# and keep the project it built as the fixture NAME. From setup_file only.
fixture_build() {
  local _fx_name=${1:-} _fx_builder=${2:-} _fx_was_root=${TEST_ROOT:-} _fx_here=$PWD
  local _fx_n='' _fx_v='' _fx_b='' _fx_e='' _fx_r='' _fx_rc='' _fx_root='' _fx_phys='' _fx_tag='' _fx_dir='' _fx_cwd='' _fx_bad=''
  local _fx_arrays_before='' _fx_arrays_after='' _fx_exported=''
  case $_fx_name in '' | *[!A-Za-z0-9_-]*) echo "fixture_build: a fixture name of letters, digits, - and _ is needed, not '$_fx_name'" >&2; return 1 ;; esac
  [ -n "$_fx_builder" ] || { echo "fixture_build $_fx_name: no builder named" >&2; return 1; }
  shift 2
  _fx_dir=$(fixture_store) || return 1
  mkdir -p "$_fx_dir" || return 1
  _fx_dir="$_fx_dir/$_fx_name"
  [ ! -e "$_fx_dir" ] || { echo "fixture_build $_fx_name: already built" >&2; return 1; }
  # What the variables are before the build, kept beside them as _fx_b_NAME
  # (value) and _fx_e_NAME (exported).
  for _fx_n in $(_fixture_names); do
    [ -n "${!_fx_n+x}" ] || continue
    printf -v "_fx_b_$_fx_n" '%s' "${!_fx_n}"
  done
  for _fx_n in $(compgen -e); do printf -v "_fx_e_$_fx_n" '%s' 1; done
  _fx_arrays_before=$(for _fx_n in $(compgen -A arrayvar | grep -vxE 'BASH.*|BATS_.*|COMP_.*|FUNCNAME|PIPESTATUS|DIRSTACK|GROUPS|lines|stderr_lines'); do declare -p "$_fx_n"; done)
  # A plain call: under setup_file's errexit, any failing step of the builder
  # fails the build, as it failed setup() before.
  "$_fx_builder" "$@"
  _fx_rc=$?
  _fx_bad=
  if [ "$_fx_rc" -ne 0 ]; then
    _fx_bad="the builder $_fx_builder failed ($_fx_rc)"
  elif [ -z "${TEST_ROOT:-}" ] || [ ! -d "$TEST_ROOT" ] || [ "$TEST_ROOT" = "$_fx_was_root" ]; then
    _fx_bad="the builder $_fx_builder made no TEST_ROOT of its own (it calls vbw_setup)"
  fi
  _fx_root=${TEST_ROOT:-}
  if [ -z "$_fx_bad" ]; then
    # A kept proof copy (#738) belongs to the folder it was made in, by its
    # path: the fixture keeps none, and each copy of it makes its own.
    while IFS= read -r _fx_n; do
      chmod -R u+rwx "$_fx_n" && rm -rf "$_fx_n" || _fx_bad="cannot remove the kept proof copy $_fx_n"
    done < <(find "$_fx_root" -type d -path '*/.vbw/runtime/proof.keep.*' -prune -print)
    # Their worktree entries, in each repository and submodule repository.
    while IFS= read -r _fx_n; do
      git --git-dir="${_fx_n%/worktrees}" worktree prune || _fx_bad="cannot prune the worktrees of ${_fx_n%/worktrees}"
    done < <(find "$_fx_root" -type d -name worktrees -path '*.git/*' -prune -print)
  fi
  if [ -z "$_fx_bad" ]; then
    _fx_phys=$(cd "$_fx_root" && pwd -P)
    # The random part of the TEST_ROOT's name finds the path in any spelling
    # (/private/var or /var, or with / and . made -, as Claude Code keys projects).
    _fx_tag=${_fx_root##*/}; _fx_tag=${_fx_tag##*.}
    [ "${#_fx_tag}" -ge 6 ] || _fx_tag=${_fx_root##*/}
    _fx_cwd=
    case $PWD/ in
      "$_fx_root"/*) _fx_cwd=${PWD#"$_fx_root"} ;;
      "$_fx_phys"/*) _fx_cwd=${PWD#"$_fx_phys"} ;;
      *) _fx_bad="the builder $_fx_builder ended outside its TEST_ROOT ($PWD)" ;;
    esac
  fi
  if [ -z "$_fx_bad" ]; then
    _fx_arrays_after=$(for _fx_n in $(compgen -A arrayvar | grep -vxE 'BASH.*|BATS_.*|COMP_.*|FUNCNAME|PIPESTATUS|DIRSTACK|GROUPS|lines|stderr_lines'); do declare -p "$_fx_n"; done)
    [ "$_fx_arrays_after" = "$_fx_arrays_before" ] || _fx_bad="the builder $_fx_builder set an array, which a copy cannot restore: set it in setup()"
  fi
  mkdir -p "$_fx_dir"
  : > "$_fx_dir/changed"
  # The variables the builder set, changed, exported or unset: NAME, then
  # set/unset, exported 1/0 and the value, NUL-separated.
  : > "$_fx_dir/vars"
  _fx_exported=" $(compgen -e | tr '\n' ' ') "
  for _fx_n in $( { _fixture_names; compgen -A variable _fx_b_ | sed 's/^_fx_b_//'; } | sort -u); do
    _fx_b="_fx_b_$_fx_n"; _fx_e="_fx_e_$_fx_n"
    _fx_v=0; case $_fx_exported in *" $_fx_n "*) _fx_v=1 ;; esac
    if [ -n "${!_fx_n+x}" ]; then
      if [ -n "${!_fx_b+x}" ] && [ "${!_fx_b}" = "${!_fx_n}" ] && [ "${!_fx_e:-0}" = "$_fx_v" ]; then continue; fi
      printf '%s\0set\0%s\0%s\0' "$_fx_n" "$_fx_v" "${!_fx_n}" >> "$_fx_dir/vars"
      if [ -z "$_fx_bad" ] && [ -n "$_fx_tag" ]; then
        case ${!_fx_n} in *"$_fx_tag"*)
          _fixture_replace "${!_fx_n}" "$_fx_phys" ""; _fixture_replace "$_fx_r" "$_fx_root" ""
          case $_fx_r in *"$_fx_tag"*) _fx_bad="the variable $_fx_n names the fixture in a form a copy cannot re-point: set it in setup()" ;; esac ;;
        esac
      fi
    elif [ -n "${!_fx_b+x}" ]; then
      printf '%s\0unset\0\0\0' "$_fx_n" >> "$_fx_dir/vars"
    else
      continue
    fi
    printf '%s\n' "$_fx_n" >> "$_fx_dir/changed"
  done
  if [ -z "$_fx_bad" ]; then
    _fx_v=$(_fixture_selfpath "$_fx_root" "$_fx_tag")
    [ -z "$_fx_v" ] || _fx_bad="the fixture holds its own path ($_fx_root), so a copy would point back at it:
$_fx_v
build that part in setup() instead"
  fi
  cd "$_fx_here" || cd / || return 1
  _fixture_back "$_fx_dir/changed"
  for _fx_n in $(compgen -A variable _fx_b_; compgen -A variable _fx_e_); do unset "$_fx_n"; done
  if [ -n "$_fx_bad" ]; then
    [ -z "$_fx_root" ] || [ "$_fx_root" = "$_fx_was_root" ] || rm -rf "$_fx_root"
    rm -rf "$_fx_dir"
    printf 'fixture_build %s: %s\n' "$_fx_name" "$_fx_bad" >&2
    return 1
  fi
  printf '%s\n%s\n' "$_fx_root" "$_fx_phys" > "$_fx_dir/from"
  printf '%s' "$_fx_cwd" > "$_fx_dir/cwd"
  mv "$_fx_root" "$_fx_dir/root"
}

# fixture_root [NAME]: the fixture's directory (the built TEST_ROOT), read only.
fixture_root() {
  local name=${1:-} store d
  store=$(fixture_store) || return 1
  if [ -z "$name" ]; then
    for d in "$store"/*/root; do
      [ -d "$d" ] || continue
      [ -z "$name" ] || { echo "fixture_root: several fixtures are built; name one" >&2; return 1; }
      name=${d%/root}; name=${name##*/}
    done
  fi
  [ -n "$name" ] && [ -d "$store/$name/root" ] || { echo "fixture_root: no fixture '${1:-}' was built in setup_file" >&2; return 1; }
  printf '%s\n' "$store/$name/root"
}

# fixture_copy [NAME]: a fresh TEST_ROOT (vbw_setup) holding a copy of the
# fixture NAME (the only one, when no name is given), the builder's variables
# re-pointed into it, in the builder's last directory.
fixture_copy() {
  local _fx_src='' _fx_dir='' _fx_n='' _fx_op='' _fx_x='' _fx_v='' _fx_r='' _fx_old='' _fx_oldp='' _fx_newp='' _fx_cwd=''
  _fx_src=$(fixture_root "${1:-}") || return 1
  _fx_dir=${_fx_src%/root}
  # A second copy in one test replaces the first.
  if [ -n "${_FIXTURE_COPY:-}" ] && [ "${TEST_ROOT:-}" = "$_FIXTURE_COPY" ]; then vbw_teardown; fi
  vbw_setup || return 1
  _FIXTURE_COPY=$TEST_ROOT
  cp -Rp "$_fx_src/." "$TEST_ROOT/" || { echo "fixture_copy: copying $_fx_src failed" >&2; return 1; }
  { IFS= read -r _fx_old; IFS= read -r _fx_oldp; } < "$_fx_dir/from"
  _fx_newp=$(cd "$TEST_ROOT" && pwd -P)
  while IFS= read -r -d '' _fx_n && IFS= read -r -d '' _fx_op && IFS= read -r -d '' _fx_x && IFS= read -r -d '' _fx_v; do
    if [ "$_fx_op" = unset ]; then unset "$_fx_n"; continue; fi
    _fixture_replace "$_fx_v" "$_fx_oldp" "$_fx_newp"
    _fixture_replace "$_fx_r" "$_fx_old" "$TEST_ROOT"
    printf -v "$_fx_n" '%s' "$_fx_r"
    if [ "$_fx_x" = 1 ]; then export "${_fx_n?}"; else export -n "${_fx_n?}"; fi
  done < "$_fx_dir/vars"
  _fx_cwd=$(cat "$_fx_dir/cwd")
  cd "$TEST_ROOT$_fx_cwd" || return 1
}

# fixture_teardown: remove every fixture of the file. From teardown_file.
fixture_teardown() {
  local store
  store=$(fixture_store) || return 1
  rm -rf "$store"
}
