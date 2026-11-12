# Diagnostics

## vbw report

```
$ vbw report
### Environment

- VBW 2.0.0
- Darwin 25.5.0
- bash 5.3.20(1)-release

### vbw doctor
...
! vbw on PATH is /x/cache/2.0.34/bin/vbw (version 2.0.34), not the loaded plugin's: /dev/vbw/plugin (version 2.0.35)
    fix: run /dev/vbw/plugin/bin/vbw, or put /dev/vbw/plugin/bin first on PATH
...
A project rule that hides one of VBW's own files (a rule for the whole `.vbw` folder, such as `.vbw/` or `*`) fails the check. The line names the file and the rule's source as `git check-ignore -v` gives it (file:line:pattern), then the fix line, and `vbw doctor` exits 1:

```
! .vbw/record.json is hidden from git by .gitignore:3:*
    fix: remove that line, or change it to .vbw/runtime/
```

Without such a rule, the doctor says nothing about hidden files.

In a VBW project the doctor also prints one info line naming the branch the next VBW commit lands on, or `detached HEAD at <12 characters>` of the commit when no branch is checked out. Outside a VBW project it prints no branch line.

When VBW's last record commit was refused (a pre-commit hook, say) and still stands, the doctor prints one warning with the time and the hook's first line of reason, `VBW's files could not be committed at <HH:MM>: <reason>`, and the way on: fix what the hook flagged, allow it in the checker's settings, or commit the VBW files yourself, then run `vbw next` (docs/next.md, The commit step). When a refused approval left nothing to commit, the way on is to fix what the hook flagged and run `vbw approve` again, and the failure stands until a VBW commit succeeds. With no such failure it says nothing of it.

VBW needs `jq 1.7 or newer`. The doctor prints the installed version as `jq <version>`. With an older jq it fails the line, names the version, and gives the fix: download a current jq from github.com/jqlang/jq/releases; on Debian 12, run `apt install -t bookworm-backports jq`. Every other `vbw` command refuses an older jq up front with the same message and writes nothing; the doctor still shows its full report.

### Project state

milestone M1 active
requirements: proven 3, unproven 1
plans: done 2
checks: 4
fixes: none
lease: none
evidence: 2026-10-02T02:20:53Z passed=true failing=
profile: balanced
last next: prove
```

`vbw report` prints diagnostic facts for a bug report about VBW (no spec text or code). Paste its output into the issue. It runs from any directory and changes nothing.

It prints:

- **Environment:** the VBW version, the operating system and the bash version.
- **`vbw doctor`:** the result of every check VBW needs, with the fix for anything wrong.
  One check compares the `vbw` on PATH with the copy this session loaded (the copy Claude Code started the session with, read from the session's record), never with the kernel doctor itself runs from. It says ok when they match, and warns when they differ, naming both folders. The fix: start or resume the session again, so the session start writes the loaded copy's PATH line. Without a session id, or when the session has no record, it says it cannot tell which copy the session loaded, and does not compare. It also warns when there is no `vbw` on PATH. `vbw --version` prints the version of the `vbw` you run.
  Another check reads whether Claude Code's auto-update is on for `vbw-marketplace` and warns when it is off (the default for a marketplace like VBW's, so nothing tells you a new VBW is out), with the way to turn it on. It reads the files Claude Code keeps and makes no network call. See [docs/update.md](update.md).
- **Project state** (inside a VBW project): the milestone, and counts of requirements, plans and checks by status. It also prints the fixes with their status and attempts, the run lease, the last proof (time, pass, failing check ids), the profile and the last step `vbw next` chose. An empty list prints `none`.

It never prints the spec's text, requirement text, code, file contents or check output. If `.vbw/record.json` does not parse, it prints `record: corrupt` and none of the content. Outside a git repository, it prints the environment and doctor sections only.

`/vbw:report` runs this command, drafts the GitHub issue around its output, and sends nothing until you confirm.

## vbw rtk

```
$ vbw rtk
rtk: installed (rtk 0.9.1, /opt/homebrew/bin/rtk)
claude hook: on (rtk init -g)
install with: brew install rtk
```

`vbw rtk [status]` shows the state of RTK (command-output compression). RTK is a third-party tool ([rtk-ai/rtk](https://github.com/rtk-ai/rtk)) that shrinks command output before it reaches Claude's context. `vbw rtk` and `vbw rtk status` print the same thing and change nothing.

The three lines:

- **rtk:** `installed` with its version and path, or `not installed`.
- **claude hook:** `on (rtk init -g)` when RTK's hook is in your Claude settings `PreToolUse` hooks, otherwise `off`.
- **install with:** the install command for your machine: `brew install rtk` if Homebrew is present, else `cargo install --git https://github.com/rtk-ai/rtk` if Cargo is present, else a pointer to the RTK page.

`/vbw:rtk` explains this state, and with your yes installs RTK (the install command, then `rtk init -g`) or removes its hook (`rtk init -g --uninstall`). VBW's safety guard judges the command inside `rtk ...`, so the two work together.
