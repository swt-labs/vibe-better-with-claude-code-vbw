# Guards

VBW's hooks (`plugin/hooks/hooks.json`) stop the few tool calls that would do
lasting harm, and say why. They are guard rails for an autonomous model, not a
sandbox: a determined program can always write a script and run it. The Claude
Code sandbox and permission rules remain the security boundary.

## What is denied

Every block ends with `Next: ` and says what to do instead, for
example `Next: leave src/x.js as it is; report that the plan needs it, so the
plan can be replanned with vbw apply`. The list of refusal kinds and their next
steps is in docs/workflows.md ("Every refusal and its next step").

Every block reaches you as well as Claude. The whole reason goes to Claude;
beside it you see one line, the reason's first line (what was refused and
why), for example `VBW guard blocked this call: .vbw/record.json is written
only by vbw (vbw help lists the commands)`. The `Next:` step is addressed to
Claude and stays in the reason. You see the line even when Claude finds
another way a moment later, so a refusal never passes unseen.

**Everywhere** (any project, VBW or not):

| Call | Why |
|---|---|
| `vbw approve`, however it is spelled (`"$X/bin/vbw" approve`, `bash bin/vbw approve`, inside `$(...)` or `sh -c`) | Approving the contract is the user's decision: `/vbw:approve` |
| `vbw loop start`, spelled any of those ways | Arming the loop is the user's own act, like approving: `/vbw:loop ITEM... --ceiling USD`. Next: ask the user to run it with the items and the ceiling they choose |
| `vbw loop next`, `vbw loop park` | The kernel's loop steps, run by the Stop hook of `/vbw:loop`, never a tool call. Next: end your turn; the Stop hook gives the next step |
| Writing the consent file (`<git-dir>/vbw/consent.json`) by redirect, by a non-reading program, or with a file tool | The same |
| Writing the store of recorded runs (`<git-dir>/vbw/runs.json`, the read lists that decide which check results are reused) the same ways | A forged read list could make a check pass without running; only the kernel writes it |

Naming the approval command in text (a commit message, `echo`, `grep`, a doc)
is not approving: only a command the shell would actually run is refused.

**Approving by answer.** The approval question (docs/proof.md) is answered in
Claude Code's own interface. A `PostToolUse` hook on `AskUserQuestion`
(`hooks/approve-answer.jq` and `hooks/approve-answer.sh`) runs after the user
answers. It acts only on a question named `Approve contract <12 hex>?`, and
only when the answer is exactly `Approve`; it then runs
`vbw approve --hash <fingerprint>` for that contract. Any other answer
(`Not yet`, or the user's own words) approves nothing and goes back to Claude
as what to change. Before the question is shown, a `PreToolUse` hook on
`AskUserQuestion` (`hooks/approve-ask.jq` and `hooks/approve-ask.sh`) adds
`Approve contract <12 hex>?` in front of an Approve / Not yet menu Claude asked
without it, while a contract waits for approval; other questions, a subagent's
questions and a question that already names a fingerprint are left as they are. The rewritten
question is shown to you as usual and you answer it: the hook never answers it
for you.

The model cannot approve through it. The hook sees only what the user
answered: Claude Code reports an answer to `PostToolUse` only after the user
gives it, so nothing the model writes can stand in for it. A question asked by
a subagent never counts. The guard above still refuses the model's own
`vbw approve`, so the answer hook is the only route besides the user typing
`/vbw:approve`.

**Cost does not grow with history.** A guard needs only three things from the
record: `schema`, `lease` and `protected` (the protected check files, one short
list in schema 4; it never reads the `checks`). While
`.vbw/runtime/glance.json` is current, that is newer than the record, the guard
reads those three from it with a normal parse, so it costs the same on a record
of 10 KB or 10 MB. The kernel keeps the glance newer with every record write
(docs/record.md). The guard reads `.vbw/record.json` instead when the glance is
missing, unreadable, lacks one of the three fields or is not newer (after
`git checkout`, `git reset`, a hand edit or a failed glance write). The answers
are the same; only the cost differs. The glance is never the source of truth.

## While a loop is on

While `/vbw:loop` is on (docs/loop.md), the Bash guard also denies the commands
that send work out of the project. The loop never leaves the project: every
ship stays local for you to review.

| Denied command | Then do it yourself |
|---|---|
| `git push` | push |
| `gh release` (except `list`, `view`, `download`) | release |
| `gh pr create` | open the pull request |
| `npm publish`, `cargo publish` | publish |
| `twine upload` | upload |
| `gem push`, `docker push` | push |
| `vercel` with options only, `vercel deploy`, `netlify deploy`, `fly deploy`, `flyctl deploy`, `wrangler deploy`, `wrangler publish` | deploy |
| `heroku container:push`, `heroku container:release`, `heroku pipelines:promote` | deploy |

`npx` and `bunx` in front of a command do not hide it. The answer is the same
for each, with the command and the last word filled in:

```
the loop never leaves the project: git push is not run while a loop is on
Next: wait for the loop to end, or stop it with /vbw:loop stop, then push yourself
```

It holds for every caller, including the main session and you through Claude:
the guard sees the command, not who sent it. Outside a loop (no loop on, or
after it ended or `/vbw:loop stop`), a plain `git push` stays allowed, as
before. The other guards are unchanged while a loop is on.

## When a guard fails

A guard can fail: it crashes, cannot start (`jq` or the guard's file is missing
or unreadable), or runs past its time limit. What happens depends on where the
call happens:

| Where | What happens |
|---|---|
| During a run (`.vbw/runtime/run-open` exists; the kernel keeps it with the glance) | The call is **blocked**. Claude sees `VBW guard: the guard failed while a run is open, so this call is blocked. Next: run vbw doctor to see why, then retry` (exit status 2). The same holds when the guard must read `.vbw/record.json` and cannot parse it |
| In a VBW project with no open run | The call goes through, silently, as before |
| Outside a VBW project | Nothing changes and nothing is printed |

During a run the guard fails closed: a broken guard never lets a call through.
Nothing ever answers allow.

**Time limit.** A guard may use 5 seconds of CPU time, set with the shell's own
`ulimit -t 5` at the start of the hook command. Past that the shell stops the
guard, and the call is treated as a failed guard (blocked during a run). A
healthy guard takes a few milliseconds, so waiting on a busy machine does not
count: only CPU time does.

**If you are blocked.** Claude's own Bash calls may be blocked too, so run the
check yourself in a terminal, in the project folder:

```
vbw doctor
```

It reports what is wrong (for example `jq` missing) with the fix for each item
(docs/diagnostics.md). Fix it, then ask Claude to retry. If you cannot fix it
and want the run gone, `vbw run end` closes it (docs/workflows.md).

**In VBW projects** (the session's project holds `.vbw/record.json`; a corrupt
record still counts). Every part of VBW finds the project the way the kernel
does: the top folder of the git repository, which is the nearest folder at or
above the session's folder (`$CLAUDE_PROJECT_DIR`) that holds `.git`, never a
folder above it. A session started in a subfolder of a VBW project is guarded
exactly as one started at its top folder; a git repository inside the project
(a submodule, a nested clone) is a project of its own. A path in a tool call
that is not absolute is read from the session's working folder, as the tool
reads it, and "outside the project" means outside that top folder:

| Call | Why |
|---|---|
| `rm -r` of `/`, `~`, `$HOME`, `.`, `..`, `*`, `.git` or `.vbw` | Destroys work |
| `git push` with `--force`, `--force-with-lease`, `--mirror`, `--delete`, `+ref` or `:ref` | Rewrites or deletes remote history |
| `git reset --hard`, `git clean -f`, `git checkout`/`git restore` of the whole tree (`.`, `*`, `:/`; `restore --staged` alone is fine), `git branch -D`, `git stash drop`/`clear`, `filter-branch`, `filter-repo`, `update-ref -d`, `reflog expire`/`delete` | Discards work git cannot give back |
| Reading or writing secret files: `.env` and `.env.*` (except `.example`, `.sample`, `.template`, `.dist`, `.defaults`), `*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.kdbx`, `*.keystore`, `*.jks`, `id_rsa`/`id_dsa`/`id_ecdsa`/`id_ed25519`, `.netrc`, `.pgpass`, `.npmrc`, `.pypirc`, `credentials` | VBW never handles secrets. `ls`, `stat` and `test` on them are fine |
| Writing `.vbw/record.json` (file tools, redirects, any program that is not a reader such as `cat`, `jq`, `grep` or `git`) | Only `vbw` writes the record, validated |

**During a run** (`record.lease`, docs/workflows.md), any **subagent** (the hook
input names an `agent_type`) is also held to the lease. The main session never is.

| Call | Why |
|---|---|
| Writing a project file outside `lease.files` (file tools; in a shell command, redirects, `tee`, `cp`/`rsync`/`install`/`ln` onto it, `mv` from or onto it, `sed -i`, `rm`; paths resolved, `..` included) | Builders write only their plan's files. A shell write gets the same refusal as a redirect to the same path. A copy reads its sources and writes only its destination: the last operand, `-t DIR` (GNU `cp`, `mv`, `install`, `ln`, in any spelling; rsync's `-t` is `--times`), or, for a destination ending in `/`, each source's name in that folder. A flag's value (`install -m 644`, `rsync --exclude X`) is not a file. After a bare `sed -i`, a word starting with `.` is BSD's backup suffix or GNU's file, so it is judged as a file. A folder named without a trailing `/` (`rm -r tests`, `cp a.js src`) is judged as the folder itself, since the guard reads text and cannot tell a folder from a file |
| Writing any path outside the project folder (file tools, shell redirects, programs that write files; `/tmp` included; in a shell command, a path the guard cannot resolve counts as outside: one starting with `~` or holding a shell expansion such as `$HOME`, since the guard reads the text and never expands it (a file tool's path is taken as written, so a plan file named `app/routes/$id.tsx` is written through the file tool); `/dev/null`, `/dev/stdout`, `/dev/stderr` and `/dev/tty` excepted) | A run writes only inside the project, and there only where the lease allows: nothing for a read-only run, the project's test files and `.vbw/` while planning, the plan's files while building. The refusal says so and ends with `Next: write inside the project folder instead, or put scratch work in .vbw/runtime/scratch/`; for a read-only run it ends with `Next: leave it; report what you needed in your result, this run's agents write nothing` |
| During `plan`, writing a project file that is neither under `.vbw/` nor a test file (`tests/`, `test/`, `spec/` or `__tests__/` folders; `.t` files under `t/`; `*.test.*`, `*_test.*`, `*.spec.*`, `*_spec.*`, `test_*.py`) | Planning writes the spec, plans and tests, never product code. The refusal says planning writes the project's test files and `.vbw/` and that product code is the build's, and ends with `Next: leave <file> as it is; put the check in a test file, or name <file> in a plan's files so the build writes it` |
| Writing `.vbw/runtime/glance.json` | Under any run, an agent's write is refused: only `vbw` writes the glance, like the record |
| Writing under `.vbw/runtime/scratch/` during a run | Allowed under `plan`, `build` and `fix`: the agents' one scratch folder for debugging scripts and logs, ignored by git and never read by a proof (agents create it). A read-only run (QA, mapping) still writes nothing, and under `build` or `fix` the rest of `.vbw/runtime/` stays refused as outside the run's files |
| Writing a protected check file (any check's `files`) during `build` or `fix`, or, by a shell command, a folder that holds one or a glob that may match one (`sed -i … tests/*.test.js`, `rm -r t*`; `*` may cross `/`, as zsh's `**` does; brace expansion is not read, and a check file changed that way stops the proof until the user approves it) | The contract is fixed while building; the one exception in a `build` run: after `vbw mutate` records a survivor, the check files that a check of the plan's own rules names, shared with other requirements' checks or not, open for the run's agents; a check file no check of the plan's own rules names stays protected. The opened files wait for one approval before the proof (docs/proof.md). The Lead runs the project's formatter and linter on check files before approval, and Devs format only their own files, so a formatter never changes an approved file |
| Writing a protected check file during a `fix` run | Allowed for every requirement fix, a proof's fix included, for the check files of the fix's own requirement that no other requirement lists; they wait for one approval before the proof (docs/proof.md). A fix for a QA finding may also create a new test file. A project-command fix opens no check file. Any other check file stays protected; the refusal names the file and the files the fix may edit, and for a QA fix ends with `Next: put the regression test in a new test file and register it with vbw fix check` |
| Under `build` or `fix`, an agent's file write on a record of schema 1 to 3, which has no `protected` list | The guard cannot tell which files are protected, so it refuses until the record is saved by this VBW as schema 4. Run any `vbw` command that writes the record (such as `/vbw:vibe`) from the main session, then retry |
| `git commit`, `push`, `rebase`, `merge`, `pull`, `cherry-pick`, `revert`, `am` | Commits go through `vbw commit`, with provenance |
| `git stash` (except `list`, `show`), `switch`, `reset`, `checkout` of a branch; `git checkout -- PATH` or `git restore PATH` outside `lease.files` | Agents share one working tree: nothing may move HEAD or other agents' changes |

**Programs that write files.** During a run, a subagent's `python`, `node`,
`deno`, `bun`, `perl`, `ruby`, `php` or `lua` command is judged like a shell
write: a file it writes outside `lease.files` gets the same refusal, naming the
path. The guard reads the paths the program text names as string literals
(`open('src/a.py', 'w')`, `Path('a').write_text`, `fs.writeFileSync('a', ...)`,
`File.write`, `os.remove`, `shutil.copy` and similar), in `-c`/`-e` code and in
a script given by heredoc (`python3 - <<'EOF'`), and the files given to
`perl -i`/`ruby -i`. Still allowed: reading, running tests (`python3 -m pytest`,
`node --test`), and writing inside the plan's files. A write whose target
the guard cannot read (a variable, an expression, another call) is refused; the
refusal names the call and the fix (a literal path, or the Edit tool). A program
that writes nothing passes, and a script file run by name (`python3 tools/x.py`)
is not read. Outside a run, programs are not judged.

**Another session's run** (D11): while a run with an owning session is open
(under 24 hours), a call from a different session (`session_id` differs from
`lease.session`), main conversation or agent, is denied when it writes a file in
`lease.files` (any project file when `files` is null, none when `[]`): file
tools, shell redirects, `tee`, `cp`/`rsync`/`install`/`ln` onto it, `mv` from
or onto it, `sed -i`, `rm`, read as during a run (copying from it is reading). The message
names the owning session; the user lifts it with `vbw run end --owner-closed`.
Other files stay editable, and the owning session is unaffected. A planning run
holds back only `.vbw/`, so it never blocks another session's source or docs
folders.

A lease older than 24 hours holds no one. During a run the Bash fast path is off
for subagents: every command they run is read.

## What each answer means

A hook gives Claude Code one of these answers. `tests/hook-answers.bats` pins
each one to the exact JSON.

| Answer | Sent by | What Claude Code does |
|---|---|---|
| `deny`, reason starting `VBW guard:`, with a message for you (`systemMessage`) beside it | the Bash and file guards | Blocks the tool call and shows Claude the reason, so it can choose another way; shows you the reason's first line, starting `VBW guard blocked this call:` |
| `ask`, with a rewritten question (`updatedInput`) | the approval-menu hook on `AskUserQuestion` | Shows the rewritten question to you; you answer it |
| Added context (`additionalContext`) | SessionStart; the approval-answer hook | Adds the text for Claude to read |
| A message for the user (`systemMessage`) | SessionStart (project made by a newer VBW, or VBW 2 just removed old VBW 1 command copies and you must reload); the approval-answer hook; the Bash and file guards, beside every `deny` | Shows you the message |
| No answer (no output, exit 0) | every hook, when it has nothing to say | Goes on as it normally would: your permission settings and prompts decide |

### No hook ever answers allow

Claude Code reads `allow` as "the hook decided, do not ask the user". On a
question that would mean the hook answered it in your place, so the approval
hook answers `ask` instead. Only your exact answer `Approve` approves a
contract. A standards test (`tools/check-hook-answers.sh`) fails if any hook
could answer `allow`.

### A failing hook gives no answer, except during a run

Outside a run, the four guard and approval hook commands exit 0 with no
output when they fail (bad input, missing `jq`). During a run the two guards
(Bash and file tools) block instead, as described in "When a guard fails". The
session-start hook has no `|| true`: if it fails (for example, no `jq`), it
prints an error and exits non-zero, but it never prints a decision. When a
hook gives no answer, Claude Code goes on as it normally would. A failure never
becomes an `allow`; it becomes a `deny` only for a guard during a run. A corrupt
`.vbw/record.json` is not a hook failure: the folder still counts as a VBW
project, the guards stay on, and a guarded call such as `vbw approve` is still
denied with a `VBW guard:` reason.

## How a command is read

The Bash guard judges what the shell would execute, not the text:

- Each simple command is found by splitting on `;`, `&&`, `||`, `|`, `&`,
  newlines, parentheses, braces and backticks. Its program is the first word
  after variable assignments and wrappers (`sudo`, `env`, `command`, `exec`,
  `nohup`, `time`, `nice`, `timeout`, `xargs`, `rtk` (RTK's rewrites), `if`/`then`/`do`/...).
- Quoted strings and heredoc bodies are data: `git commit -m "never rm -rf /"`
  is allowed (ledger D281).
- What the shell runs from inside strings is judged too: `$(...)` and `` `...` ``
  inside double quotes, and the script given to `sh -c`/`bash -c` or `eval`
  (three levels deep).
- Only a real substitution counts. In `echo "run vbw approve"`, a commit message
  that mentions `` `vbw approve` ``, or `echo "typed: \$(vbw approve)"` (escaped),
  nothing runs, so nothing is refused. `echo "$(vbw approve)"` runs it and is
  refused.
- Redirect targets (`> file`, `2>> file`, `< file`) are paths like arguments.

Reading the plan of record is not writing it: `cat`, `jq`, `sort`, `awk`
(without in-place editing), and `cp`, `rsync`, `install` or `ln` with the record
as the source are allowed. A copier whose destination is the record, or any
other program that names it, is refused.

A command that contains none of the words any rule needs (`rm`, `git`, `vbw`,
`consent`, `record.json`, a secret file name) is allowed without being read.

## Engineering

- **Per-tool-call hooks are jq itself** (build plan K20): no shell script, no
  interpreter startup of our own. On a Mac, Homebrew bash takes 9 ms just to
  start; jq is required by VBW anyway.
- **The guard command's own shell tests pick the input; jq does the rest.** The
  tests are built into the shell (no other program): they pick the glance, or
  nothing when it is not current. jq then reads the hook input, the record only
  when needed, and a sentinel file. jq skips a missing file, so the sentinel
  says whether this is a VBW project.
- **A guard blocks by accident never, by failure only during a run.** The
  approval-menu command ends in `|| true`. The two guards exit 2 only when
  their run-open flag is set; otherwise a guard that errors prints nothing and
  Claude Code decides as it normally would. `tests/guard-fail-closed.bats`
  pins both.
- **Budget:** VBW's own cost (the hook's CPU time minus that of the platform's
  `sh -c jq` startup) is at most 20 ms per call, judged for each guard alone,
  measured by `tools/bench-hooks.sh` in the release run (CI runs it on every
  pull request), including on a 20 KB heredoc command. CPU time, so waiting for
  a busy machine never counts, and a case over its budget is measured once more
  before it is judged (the bench says so): a slow hook is slow twice. The 20 ms is the
  meaning on a nominal machine (an M1 Max Mac, GitHub's macOS runner). The bench
  first measures a reference workload (a guard-shaped jq call over a fixed
  document and program, both written by the bench) and prints its cost, the nominal cost and the ratio:
  `reference: <X> ms CPU per call; nominal <N> ms (...); ratio <R>`. At a ratio
  of 1 or less every case is judged against 20 ms. Above 1, a case over 20 ms
  but within 20 ms times the ratio is reported slow (the line names the cost,
  the budget, the ratio and the scaled budget) and the bench still passes; a
  case above the scaled budget fails. `VBW_BENCH_REFERENCE_MS` stands in for the
  measured reference. CI sets no reference of its own. Measured in October 2026 (an M1 Max Mac and
  GitHub's macOS runners): the file guard about 4 to 5 ms, the Bash guard about
  10 to 13 ms, the answer hook about 1 ms. A real slowdown
  (an added subprocess costs several ms) still shows. When the machine is too
  busy to measure (starting the shell and jq alone takes longer than 20 ms),
  the benchmark reports that the machine is busy, judges nothing and does not
  fail. CI runs it with the same limit as a local run.

## SessionStart

In a VBW project, one line of context: the project state and what comes next.
The hook runs `vbw next` once, never `vbw status`, and reads the project line
from the glance that command refreshes.
Started in a subfolder of a VBW project, the line also names the project
folder, which VBW's paths (`.vbw/`, plan files) are relative to. It never
injects resume directives (ledger D289). It
writes only for a copy loaded with `claude --plugin-dir`: a PATH line in the
file Claude Code provides for it (`CLAUDE_ENV_FILE`), and the session record
below; and, in the project, when the session that runs a loop is resumed, the
loop's away mark (`.vbw/runtime/loop-away.SESSION`, docs/loop.md), so the time
its session was gone is not counted against the item's time budget.

VBW's one read outside the project is Claude Code's list of chats in `<claude-config-dir>/sessions/`, read for the name of the chat that holds a run and never written (docs/workflows.md). VBW itself writes nothing outside the project except three things: the slot store (`<claude-config-dir>/vbw/slots.json`, the computer-wide limit in docs/proof.md); the session record of a `--plugin-dir` session (`<claude-config-dir>/vbw/sessions/<session id>`, one line naming the loaded plugin folder, read by the status line and `vbw doctor`; records older than 7 days are removed, and an installed copy removes its own session's record; D364); and the user's `settings.json`.
