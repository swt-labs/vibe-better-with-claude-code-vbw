# Guards

VBW's hooks (`plugin/hooks/hooks.json`) stop the few tool calls that would do
lasting harm, and say why. They are guard rails for an autonomous model, not a
sandbox: a determined program can always write a script and run it. The Claude
Code sandbox and permission rules remain the security boundary.

## What is denied

**Everywhere** (any project, VBW or not):

| Call | Why |
|---|---|
| `vbw approve`, however it is spelled (`"$X/bin/vbw" approve`, `bash bin/vbw approve`, inside `$(...)` or `sh -c`) | Approving the contract is the user's decision: `/vbw:approve` |
| Writing the consent file (`<git-dir>/vbw/consent.json`) by redirect, by a non-reading program, or with a file tool | The same |

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

**In VBW projects** (the session's project directory, `$CLAUDE_PROJECT_DIR`,
holds `.vbw/record.json`; a corrupt record still counts):

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
| Writing a project file outside `lease.files` (file tools, shell redirects; paths resolved, `..` included) | Builders write only their plan's files |
| During `plan`, writing a project file that is neither under `.vbw/` nor a test file (`tests/`, `test/`, `spec/` or `__tests__/` folders; `*.test.*`, `*_test.*`, `test_*.py`) | Planning writes the spec, plans and tests, never product code |
| Writing a protected check file (any check's `files`) during `build` or `fix` | The contract is fixed while building. The Lead runs the project's formatter and linter on check files before approval, and Devs format only their own files, so a formatter never changes an approved file |
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
`node --test`), and writing inside the plan's files. A path held in a variable
cannot be read, so this stays a guard rail (see the first paragraph). Outside a
run, programs are not judged.

**Another session's run** (D11): while a run with an owning session is open
(under 24 hours), a call from a different session (`session_id` differs from
`lease.session`), main conversation or agent, is denied when it writes a file in
`lease.files` (any project file when `files` is null, none when `[]`): file
tools, shell redirects, `tee`, `cp`/`mv` onto it, `sed -i`, `rm`. The message
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
| `deny`, reason starting `VBW guard:` | the Bash and file guards | Blocks the tool call and shows Claude the reason, so it can choose another way |
| `ask`, with a rewritten question (`updatedInput`) | the approval-menu hook on `AskUserQuestion` | Shows the rewritten question to you; you answer it |
| Added context (`additionalContext`) | SessionStart; the approval-answer hook | Adds the text for Claude to read |
| A message for the user (`systemMessage`) | SessionStart (project made by a newer VBW); the approval-answer hook | Shows you the message |
| No answer (no output, exit 0) | every hook, when it has nothing to say | Goes on as it normally would: your permission settings and prompts decide |

### No hook ever answers allow

Claude Code reads `allow` as "the hook decided, do not ask the user". On a
question that would mean the hook answered it in your place, so the approval
hook answers `ask` instead. Only your exact answer `Approve` approves a
contract. A standards test (`tools/check-hook-answers.sh`) fails if any hook
could answer `allow`.

### A failing hook gives no answer

Every hook command ends in `|| true` and exits 0 with no output when it fails
(bad input, missing `jq`, an unreadable record). Claude Code then goes on as
it normally would. A failure never becomes an `allow`, and never a `deny`.

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
- **The project test needs no filesystem call from jq.** The hook passes
  `$CLAUDE_PROJECT_DIR/.vbw/record.json` and a sentinel file as inputs after the
  hook input; jq skips a missing file, so the second input says whether this is
  a VBW project.
- **A guard can never block by accident.** Every PreToolUse command ends in
  `|| true` (exit status 2 would block the call), and errors fall through to
  "allow". A standards test enforces both.
- **Budget:** VBW's own cost (the hook's CPU time minus that of the platform's
  `sh -c jq` startup) is at most 8 ms per call, or at most 1x that startup,
  measured by `tools/bench-hooks.sh` before every test run, including on a
  20 KB heredoc command. CPU time, so waiting for a busy machine never counts.
  The ratio covers a loaded machine, whose slower cores grow startup and the
  guard's cost together; the milliseconds cover a quiet one on any platform
  (startup differs: about 8 ms on a Mac, 3.4 ms on a Linux CI runner). On an
  idle Mac: file tools about 2 ms, Bash about 5 to 7 ms. CI uses 25 ms for its
  slower runners.

## SessionStart

In a VBW project, one line of context: the project state and `vbw next`.
Started in a subdirectory of a VBW project, it says the guards are off and
where to start instead. It never writes and never injects resume directives
(ledger D289).
