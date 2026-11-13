# Workflows and agents

VBW's engine is nine Claude Code workflows (`plugin/workflows/*.js`) and
VBW 1's team of seven agents (`plugin/agents/*.md`): Architect, Lead, Dev, QA,
Scout, Debugger and Docs, with their VBW 1 mandates. The workflows hold the
procedure: who runs, in what order, in parallel or not. The agents hold the
standard: what good output is. Every write to the plan of record goes through
`vbw`.

| Workflow | Started when | Agents | Ends with |
|---|---|---|---|
| `vbw:planning` | `vbw next` says `plan` | Architect (decide) → Architect (scope) → Lead | `needs_decisions` (up to 4 questions for the user, each with options, trade-offs and a recommendation; the router asks them, records the answers with `vbw decide`, and runs the workflow again with `decided: true` and the reply's `research`), or phases with goals and criteria, plans with tasks and checks in the record, test files written and failing, the Lead's own `choices` and the Architect's scope `notes`. Each stage hands the next what it verified in the code (`research`, `path:line — fact`): decide to scope, scope to the Lead with its `notes`, so no stage researches the same code again (#720) |
| `vbw:building` | `build` (one wave: the ready plans, no two sharing a file) | one Dev for every plan (Docs for documentation plans), all at the same time; VBW sets no limit | each plan `done` (one commit per task, its checks green) or `blocked` with a reason |
| `vbw:fixing` | `fix` (`detail.groups`: open fixes that share files, grouped) | one Dev for every group, all at the same time; after every Dev returns, one `vbw fix done` for every fix whose Dev reported done | each fix `fixed` (verified, committed) or its plan `blocked` |
| `vbw:verifying` | `qa` (built phases not yet verified on the proven code) | one QA agent for every phase, all at the same time | each phase's verdict recorded (`vbw qa record`), its findings as fixes (`vbw qa finding`) |
| `vbw:mapping` | `spec` or `plan` on existing code without `.vbw/map.md` | Scouts, one per angle, then one merge | the map, saved to `.vbw/map.md` by `vbw run end --map` in the map run's record commit; a test or lint result in it is a snapshot marked with its commit and date, and no advice in the map rests on one; every test or lint command in its Tests section carries one of two marks, `ran as of <short commit>, <date>: <what happened, how long it took>` when a scout ran it, or `Not run` when none did, and the router chooses the spec's `## Commands` from them (#733; pinned at L1 by wording checks, at L3 only by the `mapnotrun` scenario of `tools/l3-suite.sh` once it has run); its Tests section names, per test framework, the command that runs one test file (run once while mapping) and what a new test file needs, so the Lead does not work it out while planning (#721) |
| `vbw:researching` | the user runs `/vbw:research` | four Scouts (sources, practice, current state, this project), then one answer | a sourced answer with a recommendation |
| `vbw:investigating` | the user runs `/vbw:debug` | three Debuggers (reproduce, trace, history), then one diagnosis; with the diagnosis given, one Debugger fixes it | the root cause with evidence and rejected hypotheses; or the fix, its regression test and commit |
| `vbw:recommending` | after `vbw ship`, or the user asks `/vbw:vibe what's next` | one Architect | a recommendation: a top pick and up to two runners-up (docs/whats-next.md) |
| `vbw:tooling` | the user runs `/vbw:skills`, or the interview, after the user agrees to a tool search | one Scout per angle (safety, quality, tests, skills) | a short sourced list of tools |

After `build` and `fix`, the router runs `vbw prove` (deterministic, no agent);
after a passing proof, QA verifies what the checks cannot (docs/proof.md). Then
`vbw next` decides again. Approval, acceptance and shipping are human gates.

A workflow returns one object to the session. When Claude Code keeps a large
result saved to a file, the returned object sits under `result`: the session
reads the field it needs with jq (`.result.map`, `.result.recommendation`).

Each Dev and Docs prompt of `vbw:building` and `vbw:fixing` starts the agent
on its plan or fix, then on `vbw show decisions --since-approval` with the
plan's or the fixes' ids: the decisions recorded after the latest approval of
the contract that changed that plan (for a fix, a plan of its requirement, or
any plan for a project command). An approval that left the plan as it was,
such as one a decision itself needed to change a check, hides nothing from its
Dev; one that rewrote the plan to hold the decision does. Each approval records
the plans it changed (`plans` on its decision); without a list, such as the
first approval in a clone, every plan counts as changed. Without ids the
command lists the decisions after the latest approval. A decision there
overrides the plan where they differ; one that needs files outside the plan
blocks it (`vbw plan block`) for a new plan.

The Architect and the Lead choose the optimal, future-proof design, never the
merely safe or simple one, and name any known cost or debt. The Lead's
self-review refuses a design that pays a recurring cost (time, tokens,
re-runs) to avoid thinking, and QA fails a phase that brings in such a
shortcut or a debt nobody named.

Every stop ends with one plain line, **What I need from you:** followed by the
one thing you must do now, or "nothing" when VBW needs nothing.

## The run lease

The router opens a lease before it starts a workflow and closes it after:

```
vbw run start build P1.1 P1.2     # or: fix F1 F2 | plan | qa | map
vbw run confirm P1.1 P1.2         # build, fix and qa runs: was it recorded?
vbw run end                       # a map run: vbw run end --map < MAP
```

A workflow closes its own run, except `vbw:mapping` (below). The router passes `args.session` (its
`${CLAUDE_SESSION_ID}`) to every workflow. Without it, a workflow closes
nothing and the router ends the run as before. With it:

- `vbw:building`, `vbw:fixing` and `vbw:verifying` finish with one last agent,
  the Lead (label `close run`), that runs `vbw run confirm` for every plan, fix
  or phase of the run, then `vbw run end` whatever confirm said, then
  `vbw run state` for the same ids, and returns what it printed exactly as
  printed (the required `state` field). The workflow takes the run's end and
  each result's record from that answer only, never from the agent's own
  `ended`, `recorded` or `closed`: a run the answer shows still open, or an
  answer that is missing or is not its JSON, counts as not done, and the log
  gives the command to run by hand (`vbw run end`, `vbw fix done F1`). In
  `vbw:fixing` the Lead first runs one `vbw fix done` for the fixes whose Dev
  reported done, and waits for it to end, before `vbw run confirm`. Without
  `args.session`, `vbw:fixing` still runs it, with an agent of its own. A fix
  whose Dev was blocked or stopped is left out and named with its status. The
  result's `fixdone` field says which fixes closed and which stayed open, and
  `fixdone.approval` names the check files that `vbw fix done` said wait for
  the user's approval: then no check ran, the workflow logs that the approval
  comes next, and `vbw next` asks for it before the proof. It answers
  `{ended, recorded, report}`. The workflow returns that answer as
  `confirmation` and sets `complete` to true only when no agent stopped early
  and `recorded` and `ended` are both true.
- A check file changed only by added lines is added-to. `vbw next` then says
  `prove` (not `approve`) and carries `added_to: [{file, lines}]`; it prints
  `check file X: N lines added since the approval; the proof judges it with the
  approved content until they are approved at the next gate` (`1 line added` for
  one). The build and fix workflows go on to the proof. A removed or altered
  line, a new file or a file a fix added still makes `vbw next` say `approve`
  first.
- `vbw:planning` closes with the same Lead on every way out, including a stop
  for decisions or an error. Its closing agent also checks each planned phase
  with `vbw show phase`; a phase with no plans makes the workflow return
  `status: "blocked"` with the Lead's report instead of `planned`.
- `vbw:mapping` never ends its run, with or without `args.session` (#731). It
  returns the map, and its caller (`/vbw:map`, or the router's map step) ends
  the run with it: `vbw run end --map`, the map on stdin (from a saved result,
  `jq -er '.result.map' FILE | vbw run end --map`). The kernel writes
  `.vbw/map.md` and then makes the run's record commit, so that commit holds
  the map and no VBW file is left changed. It refuses an empty map, a run that
  is not a map run, no open run and another session's run, and then writes
  nothing.
- A run's record commit that git or the project's pre-commit hook refuses is
  not only a warning: it is the commit step of `vbw next` (needs the user),
  which comes before any other step and shows the hook's reason, so no
  approval is asked that cannot be recorded. VBW never passes `--no-verify`.
  See docs/next.md.
- A requirement the code already meets cannot have a check that fails today.
  The Architect raises it as a decision (drop it or reword it); if one still
  reaches the Lead, the Lead applies nothing and returns `status: "blocked"`
  with `Rn is already met: <the passing run>`. The router asks the user to drop
  or reword it in `.vbw/spec.md` (`vbw spec sync`), records the answer with
  `vbw decide`, and plans again.

The closing step (the `close run` agent, and `vbw:fixing`'s own `fix done` agent when there is no session) runs on Haiku in every profile, whatever the Lead's model (`model.lead`) is: it runs a few fixed commands, and the record stays the source of truth, so a wrong answer can only blur the summary line while `vbw next` still asks for any missing work.

### Who records, and why each agent's own instructions say so

Claude Code marks a workflow's task text as not coming from the user, so an
agent may refuse to follow an instruction that appears only there. VBW
therefore puts the recording duty in each agent's own instructions
(`plugin/agents/*.md`), which are VBW's: a Dev or Docs agent runs
`vbw plan done` or `vbw plan block` before it returns; a fixing Dev commits its
fix and runs `vbw check` on its own fixes' checks, and never runs `vbw fix
done`: the Lead runs the round's `vbw fix done` once, after every Dev returns; QA runs
`vbw qa finding` and `vbw qa record`; the Lead runs `vbw apply` and the closing
step. The Scout changes nothing and never closes a run.

### The closing agent never refuses

The Lead's instructions have a section "Close a run": confirm, then end, as its
own duty even when the task text is marked as not from the user. If it cannot
finish, it says which command to run by hand and why. When the closing agent
stops without an answer, or reports that something was not recorded or the run
did not end, the workflow writes the commands to its log and sets `complete` to
`false`. Run them from the project, with the session of the run:

```
vbw fix done F8 F9                                   # fix rounds only: the done fixes
VBW_SESSION_ID=<session> vbw run confirm P1.1 P1.2   # names anything unrecorded
VBW_SESSION_ID=<session> vbw run end
vbw run state P1.1 P1.2                              # the kernel's answer the workflow reads
```

The log lines read `the closing agent stopped: run by hand: ...`, `the closing
agent gave no readable vbw run state, so nothing is taken as done: ...`, `not
everything was recorded: check by hand with ...`, `the run is still open: run
by hand: ...` and `F1 is not done: the kernel has not recorded it; run by
hand: ... vbw fix done F1`. A planning run logs only the `vbw run end` line.

The router's own `vbw next` stays the final word: it reads the record and asks
for anything still missing, whatever a workflow reported.

The router then finds no open run. `vbw run end` with nothing open prints
`no run is open` and exits 0, so the router's own call is harmless.

### `vbw run confirm ID...`

Reads the record and prints one line per ID. It changes nothing.

```
$ vbw run confirm P1.1 P1.2
P1.1: recorded (done)
P1.2: not recorded (still building)
```

### `vbw run state ID...`

The kernel's answer a workflow takes after its close step: one JSON line,
`{"open": true|false, "recorded": {"P1.1": true, ...}}`. `open` is true while a
run lease is open and false once it ended. Each ID is recorded by the rules
below, also after the run ended (a fix still open is not recorded; a phase
counts only a verdict from the latest QA run). It writes nothing and refuses an
unknown ID, naming it.

What counts as recorded, by the kind of the open run:

| Run | ID is | Recorded when |
|---|---|---|
| `build` | a plan | its status is `done` or `blocked` |
| `fix` | a fix | its status is no longer `open` |
| `qa` | a phase | it holds a verdict dated after the run started |

It exits 1 when any ID was not recorded: an agent that stopped early or
skipped its `vbw plan done`, `vbw fix done` or `vbw qa record` is named, not
hidden. A plan left `building` goes back to `planned` when the run ends, so
the next wave picks it up. It also refuses, with an error, when no run is open, an unknown ID,
the run is a `plan` or `map` run, or no IDs are given.

`record.lease` is `{run, kind, started_at, session, files}`. `session` is the
Claude Code session that opened the run (skills pass it as `VBW_SESSION_ID=${CLAUDE_SESSION_ID}`).
In any other session `vbw next` answers that the run belongs to another session
and to wait or check status; it never says to end it. `vbw run end` from a
non-owner session is refused. Two exceptions: the user states the owning session
is closed (`vbw run end --owner-closed`), or the run is older than 24 hours
(`VBW_LEASE_HOURS`).

The holder's name never enters the record or git history. `vbw run start` reads
it from Claude Code's list of chats (`<claude-config-dir>/sessions/`; with
several entries for one session the newest wins) and stores
`{run, session, session_name}` in `.vbw/runtime/holder.json` (never in the record, on this
computer only) and in the glance's `holder`. `vbw run end` removes both. The record
validator refuses a lease that carries `session_name`. With no list, no entry for
the session or an unreadable folder, `session_name` is `null` and the run still
starts; a malformed file in the list is skipped.

Messages show a display name, chosen in this order: the list's current name for
the lease's session (so a `/rename` during the run shows at once), else the
stored name (a closed chat keeps it), else the first 8 characters of the session
id, else `a session VBW cannot name`. A name is cleaned of control characters and
escape sequences, and one longer than 40 characters is cut to its first 39 plus
`…`. It shows in `vbw next`, in the `vbw run start` and `vbw run end` refusals
(which keep the words "another session"), in the loop's stop, and in the guards'
reason (which uses the glance's stored name alone, else 8 characters of the id).

`files` holds the paths the
run's agents may write: the plans' files for `build`; for `fix`, the files of
every plan that serves a fixed requirement; `[".vbw/"]` for `plan` (planning
agents write VBW's own files, and also test files, which no plan owns yet: a
path in a `tests/`, `test/`, `spec/` or `__tests__/` folder, a `.t` file under
`t/`, or named `*.test.*`, `*_test.*`, `*.spec.*`, `*_spec.*` or `test_*.py`); `[]` for `qa` and `map` (their agents
only read; the lease also tells the autonomy gate a workflow is still running). While a lease is active, any **subagent**
(the hook input carries `agent_type`) is held to it:

- it writes only files in `lease.files` (when not null); in a `plan` run, also test files;
- it never writes a protected check file (any check's `files`) during `build` or `fix`;
- it never runs `git commit`, `commit-tree`, `push`, `rebase`, `merge`, `pull`, `cherry-pick`, `revert` or `am`: commits go through `vbw commit`;
- it never moves HEAD or other agents' changes in the shared working tree: no `git stash` (except `list`/`show`), `switch`, `reset`, or `checkout` of a branch, and `git checkout -- PATH`/`git restore PATH` only for paths in `lease.files`.

The main session is never held to a lease, so the user can always step in. A
lease older than 24 hours is ignored (a crashed run must not lock a project).

## The recommending workflow

`vbw:recommending` writes the what's-next recommendation
([docs/whats-next.md](whats-next.md)). The `vbw:whats-next` skill runs it; it
opens no run lease, and it is not started while another run is open.

`args`: `summary` (the output of `vbw triage --json`), `declined` (declined
suggestions), `models`, `effort` and `profile`. It makes one Architect call,
with `models.architect`, the effort `architect.recommend` and a reply schema
(top pick with `text`, `reason`, `size` and optional `source`; up to two
runners-up). The Architect reads the record only.

It returns `{recommendation: {top, runners}}`. With no open requirement and an
empty backlog it runs no agent and returns `{recommendation: {empty: true}}`.
If the Architect fails it returns `{error}` and no recommendation. The skill
pipes a recommendation to `vbw recommend`, which stores it.

## Help on every command

`--help` or `-h` after any `vbw` command prints that command's usage and
changes nothing. It also works right after a subcommand. With no command,
`vbw --help` lists them all.

```
$ vbw run start --help
usage: vbw run start KIND [IDS] | run confirm ID... | run state ID... | run end [--owner-closed | --map < MAP]   open the run lease, check what its agents recorded, close it (a map run with its map)
```

Help writes no record, makes no commit and does not touch the index. It works
outside a VBW project and while another session's run is open. Text that
merely contains `--help` (for example a todo) is still text. The test is
`tests/help-every-command.bats`.

## Kernel commands agents use

| Command | Who | What |
|---|---|---|
| `vbw show plan P1.2 [--json]` | Dev | the plan, its requirements, its checks, its files. A rule or check of another plan is marked; the plan's own stay unmarked. A rule of P1.3 reads `... [P1.3's, built after this plan]`, a check only P1.3's rules use reads `... [P1.3's: red until it is built, not this plan's to pass]`. The order is `built before this plan`, `built after this plan`, `built beside this plan`, `done` (`[P1.3's, done]`) or `blocked` (`[P1.3's, blocked]`). `--json` adds `plan`, `own` and `order` to each rule, and `own` and `plans` to each check |
| `vbw show fix F1 [--json]` | Dev | the fix, its requirement, failing checks and output (with the path of each kept full output, under `.vbw/runtime/output/`), the files it may touch |
| `vbw check [--expect-red] [C1 ...]` | Dev | run approved checks and report; a failing check's full output is kept in `.vbw/runtime/output/<check>.log` and named under its line. `--expect-red`: every check must fail (red-first); the run is kept in the plan's evidence (`red_runs`), and nothing else is written |
| `vbw mutate P1.2 R3.1 "what you broke" FILE...` | Dev, Docs | break one rule (or `taskK`) of the plan on purpose and record whether a check noticed; the kernel leaves each named file as given (the break stays in the working copy) and the Dev edits it out. `--queue` sets a rule break aside to run later; `vbw mutate P1.2 --run` runs the queued breaks side by side. A check that reads the project through git takes `--none REASON` on its reason alone (git case, below). Standard and deep only (below) |
| `vbw commit P1.2 "feat(x): ..." [FILE...]` | Dev | commit the plan's changed files with provenance trailers. After a mutation survivor it also commits a check file that a check of the plan's own rules names, shared with other requirements or not; a check file no check of the plan's own rules names, or any before a survivor, is refused by name |
| `vbw commit --fix F1 "fix(x): ..." FILE...` | Dev | commit the named changed files of an open fix. For a requirement fix of any source (QA finding or failing test), the files are check files of its own requirement; the commit carries `VBW-Fix: F1` and `VBW-Req` trailers, and the files wait for one approval before the proof. Code goes through its plan with `vbw commit PLAN`. A check file of another requirement, a code file and `.vbw/` files are refused. For a failing project command, the named changed files commit even when no plan lists them, with the `VBW-Fix` trailer |
| `vbw plan done P1.2` / `vbw plan block P1.2 "reason"` | Dev | the plan's outcome. `done` is verified: none of the plan's files has uncommitted changes, and the checks of the requirements it completes pass. It also prints one line, `Red first: ...`, naming the plan's own checks that never ran red (`vbw check --expect-red`, kept in the plan's evidence) before the plan's first code commit, or saying every one did; a check another plan owns counts that plan's red run, and a plan with no own checks prints none. Red first never refuses `done`: a check of behaviour that already exists is green from its first run. `vbw next` hands QA each such check, and QA judges it as a deviation from test first in its notes, not as a failure. The plan also needs a commit with its `VBW-Plan` trailer (`vbw commit`); without one, every file must be committed in `HEAD` (for example by the approval commit) and a check of its requirements must pass, or `done` is refused and names the failing check. A blocked plan stops only the plans that depend on it (docs/next.md). `block` refuses a plan that is already done, says so, and changes nothing; reset the plan first if it must be built again |
| `vbw fix done F1` or `vbw fix done F8 F9` | Lead (the fix round's closing step, run by the workflow) | verified (several fixes in one command run the checks they serve once; one that cannot close is named, the others still close, and the exit code is non-zero): no uncommitted changes in the files it may touch, and the checks of every finished requirement those files serve pass; then awaiting proof. While check files wait for the user's approval it runs no check: it names them, and the fixes await the proof after the approval |
| `vbw run state ID...` | Lead (the closing step, after `vbw run end`) | the kernel's answer a workflow takes the run's end and each result's record from: `{"open": ..., "recorded": {ID: ...}}`; writes nothing, refuses an unknown ID |
| `vbw fix check F1 < check.json` | Dev | in a fix that QA opened: register the regression test as a check of the finding's requirement. The JSON has `run` and `files`, and optionally `exit`, `output`, `timeout`, `alone`. It waits for the user's approval before the proof (docs/proof.md) |
| `vbw apply < plan.json` | Lead | replace phases, plans and checks, and set each `auto` requirement's rules, in one validated write (a plan row may carry `awaits`, check ids of the plan's own requirements, judged as `--amend` judges them and kept when a later apply leaves them out; refused while a build or fix run is open; a plan that has started must come back unchanged and keeps its status, note and breaks across every `vbw apply`; a requirement that another milestone owns or that a phase of another milestone already covers is refused with the `vbw apply --add` message, and nothing is written) |
| `vbw apply --patch < patch.json` | Lead | change only the plans, checks and rules in the document; a plan or check row with an existing id is merged field by field (fields it leaves out keep their values, an explicit `null` removes an optional field, a missing required field is refused naming it; a plan row may carry `awaits`); everything else stays byte for byte as it was. A patch judges the rigor floor and the one-plan-per-express rule only for the phases that have not started whose plans it changes or adds, so a phase it does not touch never blocks it; a touched phase whose floor rose above its tier is raised to that floor (an express phase given a second plan to standard), never lowered, and said in one line. A check change on a started plan keeps the plan's status, tasks and commits and an open build run stays open (no `vbw plan reset`); the contract then reads NOT APPROVED until the user approves what the check now asserts. A change to plans or rules while a run is open is still refused |
| `vbw apply --amend < amend.json` | main session | a correction that changes what no check asserts, on an approved contract only, with or without an open run: `{"plans": [{"id", "files"?, "awaits"?}], "checks": [{"id", "files"?}]}` adds files to a plan (never a protected check file), files to a check, and records that a plan awaits checks of its own requirements. Anything else (a title, a command, an expected result, a rule, a phase, a removal) is refused in one line that names the field, `vbw apply --patch` and the approval, and the record stays as it was. Each addition is recorded on the plan or check as an amendment (what, when, the session's 8-character short id, never a name); the contract stays approved (the approval is re-pinned), an open run stays open (a plan's added file joins the lease, a check's joins the protected files at once), and the next approval, `vbw show contract --changes` and `vbw ship` list the amendments made since approval. The router says one chat line for it; a run agent is refused by the guard |
| `vbw apply --add < phase.json` | router | add one new phase with its plans (each may carry `awaits`), checks and rules to the milestone; every other phase, plan, check and rule stays as it was |

## The mutation check

```
vbw mutate P1.2 R3.1 "return true always" src/pay.sh
vbw mutate P1.2 task2 --check C7 "drop the retry" src/pay.sh
vbw mutate P1.2 task2 --none "documentation only"
vbw mutate P1.2 R3.1 --none "the figures are a decision in the record"
vbw mutate P1.2 R3.2 --queue "skip the rounding" src/pay.sh
vbw mutate P1.2 --run
```

After its checks are green, the Dev of a plan breaks its own code on purpose
and confirms that a check notices. A test that stays green on broken code
cannot fail, and QA would otherwise find it one round at a time.

- **When it runs:** at standard and deep. Never at express, and never in a fix.
- **Rule form** (`Rn.k`): break rule k of requirement Rn in the named files.
  Only that rule's own check runs. `vbw show plan` numbers the rules this way.
- **Task form** (`taskK`): break task K. Without `--check`, a task break runs
  the checks of the plan's own rules (a task break's set), the ones `vbw show plan` leaves unmarked:
  those of every rule that names the plan,
  plus those of the requirements the plan completes. A check shared by several
  of these rules runs once, and no other requirement's check runs. Only `--check
  ID` narrows the run, to the named checks of the plan's requirements. The Dev's red-first and green steps use only the plan's own checks, and another plan's red check is no blocker (it stays red until that plan is built). A plan
  that owns no rule runs the checks of its requirements. If an owed check is red
  on the unbroken code, the command refuses and writes nothing. It names the
  check and three ways out: make it pass and commit, `--check ID`, or `--none
  REASON` naming the plan that completes the rule. `--none REASON` on a task
  records that the task has no behaviour a test could notice.
- **A rule with no code to break** (`Rn.k --none REASON`): a rule may be
  recorded `--none` only when its check reads nothing that any plan of its
  requirement builds, for example a check that judges a measurement kept as a
  decision in the record. The kernel verifies this from the check's recorded
  read list (the run store in the clone, where every proof keeps what each unit
  read; the command runs the check once in a clean copy when the store has no
  current run). The rule is accepted only when the list names no file and no
  listed folder that a `files` entry of any plan of the requirement covers, done
  or not. Otherwise it refuses, writes nothing, names each file with its plan
  and ends "break the rule in that code instead". It also refuses a run that
  reads the project through git ("reads the project through git, so its files
  are unknown") and a run with no read list (the file system recorded none).
  The verdict has one limit, and the accepting line says it: a check that only
  tests whether a plan file exists, without opening it, never reads that file,
  so such a check is not detected and the rule is accepted though deleting the
  file would fail the check.
- **A check that reads through git** (`Rn.k --none REASON`): no read list can
  vouch for it, so the command accepts it on the reason alone. It prints one
  line naming the check, git and the reason, and records the excuse on the rule
  marked git. A missing reason is refused. Each git-read excuse is listed at the
  next gate (`vbw show contract`, `--changes`, `vbw ship`) until the next
  approval. `vbw show plan` prints "no break possible: CHECK reads the project
  through git (REASON)" for it, and `vbw plan done` counts it. A check with a
  read list never needs it.
- **Side by side** (`--queue`, then `--run`): a rule break can wait instead of
  running. `--queue` sets its broken bytes aside and puts the files back at
  once, running nothing, so the Dev makes the next break straight away. `vbw
  mutate PLAN --run` then runs every queued break of the plan: each rule's
  check once on the unbroken code (as a single break does, never once per
  break), then each break in its own clean copy, as many at a time as
  `check_jobs` allows under the computer-wide limit. It prints how many breaks
  run and how many at a time, then each result as a single break would, records
  them, and exits non-zero on a survivor. A break queued before a later commit
  is dropped and named (its bytes belong to older files): make it again. A
  check that fails on the unbroken code (a busy heavy-job lane can cause it)
  stops the run: it exits non-zero naming each failing check and its status,
  and says how many queued breaks are kept for the next run. Every queued break
  stays as it was, so once the checks pass the next `--run` runs them all
  without queueing any again. Check
  files that differ from their last commit stop the run, and `vbw plan done`
  names breaks still queued. Only a rule break queues; a task break and
  `--none` run at once. VBW refuses a second `--run` of the same plan while one
  is still running: it exits non-zero, before it reads or copies anything, with
  a line naming the running one (its pid, the time it started as HH:MM, and its
  command) and `Next: wait for it to finish`. The same holds for `vbw plan done`:
  one run per plan at a time (R293). While a `vbw plan done P` runs, a second
  one of the same plan is refused at once, before any check runs, with the same
  line and a `Next:` line to wait and never start a second one; it queues
  nothing at the check gate. Its marker is the file `plan-done.P.pid` directly in
  `.vbw/runtime/`, and a plan done of another plan is never refused. The running one holds a marker, `run.pid` under
  `.vbw/runtime/mutate-queue/PLAN/`, with its pid from before it reads the
  queue until it ends. A marker whose process has ended (or that is empty or
  not a number) never blocks: the next run takes it over. A run waiting for a
  slot holds the marker for the whole wait, on purpose: a second run would
  compete for the same slots. A long run can pass Claude Code's 10-minute limit
  for one command, so start it in the background, wait for it and read its
  whole result.
- **Where the time went:** a break that ran ends with three lines, after the
  result lines (and after a survivor's line, which keeps its exit 1):

```
VBW's own work: 0.4 of 1.2 min
  steps of 24.6 s: copies 3.1, unbroken 9.0, break R3.1 11.2, waits 0.0, saving 1.3
  copies: 1 kept copy claimed (0 refreshed), 0 made
```

  Each entry is one step:
  `copies` is making or bringing up to date the clean copies, then breaking,
  restoring and handing them back;
  `unbroken` is the checks on the unbroken code;
  each break has one entry, named by its target (`break R3.1`, `break task2`);
  with `--run` side by side, one entry per wave names its targets (`breaks R1.1 R1.2`);
  `waits` is the seconds spent waiting for a computer-wide slot;
  `saving` is recording the result in the record.
  The figures are measured by the proof's clock, and the steps sum to the total within rounding.
  The last line says what the run did with its clean copies: the kept copies it
  claimed, of those the ones that needed an ignored path copied again, and the
  copies it made (docs/proof.md, Kept copies).
  The breakdown changes no verdict, record or exit code.
  A refusal prints no breakdown, and `--queue` and `--none` print none.
- **The break stays in the working copy.** `vbw mutate` never writes to or
  deletes a named file: the Dev commits every finished task before a break, and
  the Dev edits the break out right after each `vbw mutate` (and before the
  next `--queue`), so no uncommitted work is lost. The same broken bytes sent
  twice at the same commit are refused as a forgotten break, naming the earlier
  break; nothing runs and nothing is recorded. The command also refuses, and
  writes nothing, if none of the named files differs from their last commit
  (the break is the difference), a file is outside the plan, or a check file is
  touched.
- **What it records:** `vbw show plan` lists each break: target, description,
  red or survivor, and each check's result. A survivor makes `vbw mutate` exit
  non-zero. What to do with it: docs/proof.md.

The Docs agent breaks the statements its documents deliver in the same way.
What is broken at each tier: docs/rigor.md.

## `vbw apply` and rules

The Lead's one write is a JSON document on stdin. The optional `rules` key
lists what each `auto` requirement states, with the check that tests it:

```json
{"phases": [{"id": "P1", "title": "Pay", "reqs": ["R1"]}],
 "plans":  [{"id": "P1.1", "phase": "P1", "title": "Pay", "reqs": ["R1"], "files": ["src/pay.sh"], "after": []}],
 "checks": [{"id": "C1", "req": "R1", "run": ["sh", "tests/pay.sh"], "files": ["tests/pay.sh"]},
            {"id": "C2", "req": "R1", "run": ["sh", "tests/twice.sh"], "files": ["tests/twice.sh"]}],
 "rules":  [{"req": "R1", "text": "A payment succeeds", "check": "C1"},
            {"req": "R1", "text": "Paying twice is refused", "check": "C2"}]}
```

A full apply also refuses a requirement that belongs to another milestone
(`R2 belongs to milestone M1`) or that a phase of another milestone already
covers (`R1 is already covered by P1`). The message is the one `vbw apply --add`
gives, and nothing is written.

When the key is present, `vbw apply` refuses, writes nothing, and names the
problem when:

- a rule's `check` is not a check of that rule's requirement in this plan
  ("the rule ... names C9, which is not a check of R1 in this plan");
- a rule is for a `human` requirement;
- an `auto` requirement of the plan's phases lists no rules (`R1 lists no
  rules`), counting rules the record already holds that are not retired;
- a check's rules name two plans of the milestone that are not yet built,
  order or not, naming the check and both plans: when they build
  one after the other (directly, by sharing a file or by an earlier wave), the
  earlier plan's mutation step would find the check red on unbroken code; when
  they share a wave, the first Dev's mutation step would run the check before
  the other Dev committed, a race that fails only sometimes;
- a requirement's rules name a plan on only some of them: every rule names a
  plan, or none does;
- a check running a bats file with a case filter (`--filter`) that
  matches no case name in the file, naming the check and the file: a new check
  is red because its cases fail, never because none exist.

An accepted document stores each requirement's rules in the record
(docs/record.md): the requirement's retired rules stay, and the document's
rules fill the other places in order. A retired rule moves up only when the
document drops a live rule before it. Re-planning without the key keeps the stored rules. Without
the key on a first plan, nothing changes (see docs/proof.md for the approval
consequence).

### The single-file test form

When the project's test runner can run one test file, the Lead adds
`test_files` to the document, with that runner's documented syntax:

```json
{"test_files": {"run": ["bats", "{file}"], "files": ["tests/*.bats"]}}
```

A project with several test runners (a monorepo with one per subproject) gives
one named form per runner, each with the folder its runner starts in when it is
not the project root:

```json
{"test_files": [
  {"name": "webapp", "dir": "apps/webapp", "run": ["npx", "vitest", "run", "{file}"], "files": ["apps/webapp/**/*.test.ts"]},
  {"name": "api", "run": ["pytest", "{file}"], "files": ["api/tests/test_*.py"]}]}
```

`vbw apply` refuses the forms before anything changes when the section they make
would not parse (docs/proof.md, Test files: a pathspec outside its form's dir, a
name given twice, a run without `{file}` once), or when a committed file is
matched by two forms. `vbw apply` writes it into the spec's `## Test files` section. It changes
nothing else about the document, and it takes effect only after the user
approves it, like a command (see docs/proof.md, Test files).

### Changing one thing: `vbw apply --patch`

```
echo '{"checks": [{"id": "C2", "req": "R2", "run": ["sh", "tests/c2.sh", "--strict"], "files": ["tests/c2.sh"]}]}' | vbw apply --patch
```

The document may carry `plans`, `checks` and `rules`, in the same shape as a
full apply, and nothing else. VBW merges them into the record:

- a plan or check with an existing `id` is merged field by field: fields the
  row leaves out keep their values, so `{"id": "P1.1", "files": [...]}` changes
  only the files. An explicit `null` removes an optional field (plan: `after`,
  `tasks`, `role`; check: `exit`, `output`, `timeout`, `alone`, `files`). `null`
  on a required field (plan: `phase`, `title`, `reqs`, `files`; check: `req`,
  `run`) is refused, naming the row and the field. A new `id` is added, and a
  new row missing a required field is refused as `--patch refused: ...` naming
  the row and the field (a new plan needs a phase that exists);
- a rule is matched by requirement and text: the same text with another
  `check` changes it, new text adds it, and the requirement's other rules stay;
- a rule named by its address instead (`"rule": "R1.2"`, the second rule of
  `R1`, as `vbw show req R1` numbers them) is reworded or retired, in any
  milestone, a shipped one included:
  `{"rule": "R1.2", "text": "the new words"}` gives it new words (`check` and
  `plan` may change the same way), and
  `{"rule": "R1.2", "retire": "R4 lets a customer pay twice"}` retires it. A
  retired rule stays in its place with its reason, so no other rule's address
  moves; it is owed no mutation break and is left out of the plan's rules
  (docs/proof.md, Rules);
- phases, requirements and every plan, check and rule not named are untouched.

```
echo '{"rules": [{"rule": "R1.2", "retire": "R4 lets a customer pay twice"}]}' | vbw apply --patch
```

An address that names no rule, a rule already retired, the same address
twice, or an entry with other fields is refused, and so is an address in a
full apply or `--add` (they take rules by requirement and text). A retired rule
stays as it is: when its behaviour comes back, add it as a new rule.

A patch with `phases` is refused (`a patch carries plans, checks and rules,
never phases: change phases with a full apply`). Every other rule of a full
apply holds: a started plan cannot change, a rule must name a check of its
requirement, and no build or fix run may be open. A refused patch writes
nothing. A changed check or plan changes the contract, so the user approves it
again (docs/proof.md).

### Adding one phase: `vbw apply --add`

```
echo '{"phases": [{"id": "P2", "title": "Shout", "reqs": ["R3"], "tier": "express"}],
 "plans": [{"id": "P2.1", "phase": "P2", "title": "Shout", "reqs": ["R3"], "files": ["greet.sh"], "after": [], "tasks": ["--shout prints capitals"]}],
 "checks": [{"id": "C3", "req": "R3", "run": ["sh", "tests/shout.sh"], "files": ["tests/shout.sh"]}],
 "rules": [{"req": "R3", "text": "--shout Ana prints HELLO, ANA!", "check": "C3"}]}' | vbw apply --add
```

The router uses this for a small change (docs/rigor.md) in a milestone that
already has work: the document holds one new phase, for requirements that
have no phase yet, with its plans, checks and rules, in the same shape as a
full apply. The milestone's other phases, plans, checks and rules stay as
they were, started or not. `vbw apply --add` refuses, and writes nothing, a
phase whose id already exists in any milestone, a requirement that a phase of
another milestone covers, a requirement that a phase of this milestone covers
while that phase's work has not started (`R1 is already covered by P1, whose
work has not started`: change P1 with a full apply instead), or a requirement
of an earlier milestone (`R2 belongs to milestone M1`). Once a phase's work has
started, a new phase for further work on a requirement it covers is accepted
beside it (R157). The other refusals are the ones the full `vbw apply` makes. Every rule of a full apply holds, including the express file limit:
in a repository tracking more than 30 files, an express phase over more than
two files is refused (`its signals set the floor at standard`). The new phase
changes the contract, so you approve it once.

### Reopening a shipped requirement

A requirement of a shipped milestone stays closed. To work on it again, change
its text or its proof type (`[auto]` or `[human]`) in `.vbw/spec.md` and run
`vbw spec sync`. The requirement moves to the current milestone, status `open`.
A full `vbw apply` then accepts a new phase that covers it:

```
echo '{"phases": [{"id": "P3", "title": "Notes again", "reqs": ["R1"], "goal": "Notes read better", "criteria": ["notes read better"], "tier": "standard"}],
 "plans": [{"id": "P3.1", "phase": "P3", "title": "Again", "reqs": ["R1"], "files": ["src/n3.txt"], "after": []}],
 "checks": []}' | vbw apply
```

The shipped milestone's phase keeps its id, title, requirements, goal,
criteria, tier and plans, each plan with its status. A requirement of a shipped
milestone that was not reopened is still refused (`R1 belongs to milestone M1`).

### Once work has started

When any plan of a phase is no longer `planned`, a planning round (a full
`vbw apply`) cannot reshape that phase. It is refused, with the reason, when it:

- renames the phase or changes its requirements
  (`P1 has work started: its title stays "Pay"`);

A phase has *started* when any of its plans is no longer `planned`, or it has
an escalation. It is *finished* when its work is done. Either way it stays
exactly as it was, with its finished plans.

A new phase is welcome beside a started or finished one, including for more
work on a requirement that phase already covers. Example: `P1` (started) covers
`R1`. A re-plan keeps `P1` unchanged and adds `P2` for `R1`'s further work.
Before any work has started planning may rename and reshape phases freely. To add or
change a plan that has not started, add plans to the phase or use `vbw apply --patch`.

A phase that has not started (every plan `planned`, no tier raise) may change
its goal and criteria in a full `vbw apply`; its id, title, requirements and
plans stay as they were. For a started phase the goal and criteria stay. A
change is refused (`P1 has work started: its goal and criteria stay as they are;
add a new phase for the further work`). Add a new phase for the new work, for a
requirement nobody planned yet or one reopened as above. `vbw apply --patch`
never changes a phase.

### Refusal messages name their mode and end with a next step

Every `vbw apply` refusal starts with the mode it came from, then the reason,
and ends with `Next: ` and what to do instead. Nothing is
written.

| Mode | Example |
|---|---|
| full apply (no option) | `vbw: full apply refused: apply needs a JSON object on stdin`<br>`Next: pipe one JSON object into vbw apply: {"phases": [], "plans": [], "checks": []}` |
| `--add` | `vbw: --add refused: --add needs a JSON object with the new phases ({id, title, reqs}) and their plans, checks and rules`<br>`Next: send --add a JSON object whose "phases" array holds the new phases, with their plans, checks and rules` |
| `--patch` | `vbw: --patch refused: a patch carries plans, checks and rules, never phases: change phases with a full apply`<br>`Next: remove "phases" from the document, or send it to a full apply (vbw apply) to change phases` |

### Every refusal and its next step

Each refusal below ends with `Next: ` and the step in the right column
(`tests/refusal-next-step.bats` fails when one has none).

| Refusal | Next step |
|---|---|
| `vbw apply`: a document that is not a JSON object, or has no phases, plans and checks arrays | Send one JSON object with those arrays |
| `vbw apply`: an unknown field, or a tier that is not `express`, `standard` or `deep` | Remove the field, or set a valid tier |
| `vbw apply`: a phase or plan or check id already in use (`--add`) | Use an unused id, or change the existing one with `--patch` or a full apply |
| `vbw apply`: a requirement of another milestone, or already covered by a phase | Take it out of the document; for `--add`, when the covering phase of this milestone has not started, change that phase with a full apply instead |
| `vbw apply`: a bats check (`tests/x.bats`) whose case filter matches no case name in the file | write the cases the filter names into tests/x.bats (each @test name matching the pattern), see them fail with the runner, then send the document again; or correct the pattern |
| `vbw apply`: `test_files` that is not one form `{run, files, dir?}` or an array of named forms `{name, run, files, dir?}` | Give `test_files` in one of those shapes, with one form per test runner, or leave it out |
| `vbw apply`: named test-file forms the spec refuses (`test_files: ...`: a pathspec outside its dir, a dir that is a symbolic link, a name given twice, a committed file two forms match) | Change `test_files` as the message says (docs/proof.md, Test files), or leave it out |
| `vbw apply`: a started plan or phase changed or dropped | Put it back as the record has it (`vbw show plan ID`) and add a new plan or phase for further work |
| `vbw apply`: a missing rule, or a rule naming no check of its requirement | Add one rule per condition, each with its check |
| `vbw apply`: a check whose rules two plans own that build one after the other, or beside each other (a shared wave) | give each plan's rules a check of their own (a separate test file, or the same file with a case filter as a distinct check), or move the rules to one plan |
| `vbw apply`: a requirement whose rules name a plan on only some of them | name a plan on every rule of the requirement, or on none (vbw apply --patch rewords a rule: {"rule": "Rn.k", "plan": "P1.1"}) |
| `vbw ship`: an uncommitted change to a file of the milestone's work (a plan's file or a protected check file, in the project or in a submodule, named by project path with the plan that names it; your own files never block) | commit it with `vbw commit PLAN "type(scope): description"` (a check file of an open fix with `vbw commit --fix FIX "type(scope): description" FILE`), then `vbw ship` |
| `vbw apply`: a tier below its floor, or an express phase with two plans | Raise the tier, or merge the plans (a `--patch` raises the touched phase itself) |
| `vbw apply`: a build or fix run is open | End the run (`vbw run end`), then plan again |
| `vbw run start`: an unknown plan or fix | Check the id with `vbw status` |
| `vbw run start`: a plan or fix not ready (done, or not open) | Build a plan that is planned (`vbw next` shows which) |
| `vbw run start`: a plan waiting for another | Build those first, or run `vbw next` |
| `vbw run start`: two plans sharing a file | Start one now and the other after it ends |
| `vbw run start`: a run already open | In this session, `vbw run end`; in another session, wait for it or check `vbw status` |
| `vbw run confirm`: no run open | Nothing to do; `vbw status` shows what each plan and fix recorded |
| `vbw run confirm`: an unknown plan, fix or phase | Confirm the ids the run was started with (`vbw status` names them) |
| `vbw run confirm` on a run of another kind (plan, map) | End the run with `vbw run end`: only build, fix and qa runs are confirmed |
| Any command whose change would leave the record invalid (`vbw: refused: ...`, nothing written) | Give the command a valid value, or run `vbw doctor` if the record itself is damaged |
| `/vbw:loop`: the ship of an item refused (the loop ends) | Run `/vbw:vibe` to take the item to its ship, then `/vbw:loop` for the items left |
| Guards (docs/guards.md): a secret file, the record, the consent file, `vbw approve` | Use the `vbw` command or `/vbw:approve` instead of writing directly |
| Guards: a file outside the run's plan, a protected check file, a read-only run, another session's files | Leave the file; report the need, or work on other files until the run ends |
| Guards: a project file that is neither a test file nor under `.vbw/`, written while planning | Leave the file; put the check in a test file, or name the file in a plan's files so the build writes it |
| Guards: `git commit-tree` (with commit, push, rebase, merge, pull, cherry-pick, revert, am) by an agent under a lease | Commit through `vbw commit PLAN "type(scope): description"` |
| Guards: a git history change by VBW's chat while an autonomous run or loop is armed | Follow the proof's Next line, or `vbw commit`; the user's own commands are never checked. The rule holds on a ship refusal too: follow the refusal's Next line, a `vbw commit` of the milestone's files. The user's own files are never committed by VBW's chat, which asks the user what to do with them |
| Guards: a program (python, node, perl, ruby, ...) writing a file the guard cannot name, its target a variable, an expression or another call | name the file as a literal path in the program, or write it with the Edit tool (Write for a new file) |
| Guards: a shell command (`rm -r`, `cp`, `mv`, `tee`, `sed -i`, ...) writing a folder that holds a protected check file | Leave the protected check files as they are; name only the files you write |
| Guards: a shell command writing a glob that may match a protected check file (`sed -i … tests/*.sh`) | Leave the protected check files as they are; name only the files you write, without a glob that reaches a check file |
| Guards: `vbw loop start` by a tool call (arming the loop) | Ask the user to run `/vbw:loop` with the items and the ceiling they choose |
| Guards: `vbw loop next` or `vbw loop park` by a tool call (the loop steps) | End your turn; the loop's Stop hook gives the next step |
| Guards: a push, release, publish or deploy while a loop is on (leaving the project) | Wait for the loop to end, or stop it with `/vbw:loop stop`, then do it yourself |
| Guards: an MCP tool the project has not opened to the agent's role | The user adds or marks it with `vbw config set mcp` |
| Guards: a tool outside the agent's role (another role's built-in, or one VBW does not know) | The agent goes on with its own tools; a tool a role should have is a VBW change, not a setting |
| Guards: a guard that failed during a run | Run `vbw doctor`, then retry |

An unknown option prints the usage line for the three modes and exits 2.

### Refusals reach the user

A refusal inside a workflow is printed to an agent, not to you. So every
agent's result schema requires a `refused` list: each refusal the agent got
(a `vbw` command that refused, its message starting `vbw:`, or a tool call a
guard blocked, its reason starting `VBW guard:`), copied verbatim and whole,
through its `Next:` line, or `[]` when there was none. The workflow collects
them, logs each one (`dev P1.1 was refused: ...`) and returns them all in its
result as `refused`, each named by the agent that got it:

```
"refused": [{"by": "dev P1.1", "text": "vbw: apply refused: ...\nNext: ..."}]
```

Every workflow result has `refused`, `[]` when nothing was refused, including
a workflow that stops before starting any agent. The router (`/vbw:vibe`)
shows each refusal to you as written, in a quote naming the agent, before its
own summary, and never paraphrases it; it shows a `vbw` refusal it gets itself
the same way. Comms and Mission Control show each refusal too, in amber with
its time ([panel.md](panel.md#refusals)).

## The loop and `autonomy_cap`

The steps of `/vbw:loop` (docs/loop.md) are not counted against
`autonomy_cap`. The loop's ceiling is its cap. Its workflows take a lease like
any other run.

## Agents

Agents are specifications of good output, not procedures (design §4). Each
returns a structured result through the workflow's `schema`, so Claude Code
validates it and retries on a mismatch. A completion gate of our own is not
needed.

- **Architect**: requirements to roadmap. First the decisions only the user
  should make (cost, data, security, user experience, hard to undo); then the
  phases, each with a goal and goal-backward success criteria, must-haves
  separated from nice-to-haves. Planning only; it writes nothing.
- **Lead**: research, then each phase decomposed into plans of 3 to 5 tasks
  (no shared files in a wave; documentation plans marked `docs`), checks that
  fail today (each shown red by running its own argv once, never the whole
  suite), a self-review, and `vbw apply`.
- **Dev**: executes a plan's tasks (or a group of fixes) within its files, one
  commit per task, checks red first and then green; deviations classified
  DEVN-01 to DEVN-05; database safety.
- **QA**: goal-backward verification of a built phase at the profile's tier
  (quick, standard, deep): the goal and criteria met, test gaps, and every
  deviation from the plan as a failure. One deviation is found for it at every
  tier: a file its plans delivered that `HEAD` no longer holds as VBW left it (a
  hand edit or deletion after the build). The proof lists such files, the QA
  prompt names them, and `vbw qa record PHASE pass` refuses while one stands that
  no decision of the user covers (docs/proof.md, Delivered files). It changes
  nothing but its record.
- **Scout**: research from one angle (codebase, web, documentation), verified
  and sourced, read-only.
- **Debugger**: the scientific method: reproduce, hypothesize, evidence,
  diagnose; in fix mode a minimal root-cause fix with a regression test.
- **Docs**: documentation plans (README, changelog, guides, API and inline
  docs), concise and example-first; documentation files only.

**MCP tools by role.** A project names the MCP servers its agents may use with
`vbw config set mcp`. Dev, Debugger and Docs get every named tool; Architect,
Lead, Scout and QA only a tool marked read-only. Agents inherit the session's
tools, and the tools guard holds each to its role. See "MCP tools by role" in
[docs/guards.md](guards.md).

## The project folder

Every skill that starts a workflow passes `args.root`, the project folder: the
router from `vbw next --json` (`root`), the other skills from `vbw root`. A
session started in a subfolder of the project starts its agents there too, so
each workflow appends one sentence to the task of every agent it starts:

```
The project folder is /path/to/project. Every path VBW names (plan and check
files, .vbw/...) is relative to it, whatever folder you start in: give file
tools and shell redirects absolute paths under it, and run other shell commands
from it (cd "/path/to/project" && ...).
```

Without `args.root` nothing is added. The guards judge a path in a tool call
from the agent's working folder, so an absolute path under the project folder,
`.vbw/runtime/scratch/` included, is judged by the run's rules (docs/guards.md).
All nine workflows do this.

## Submodules

A project may hold other git repositories: submodules, or a clone nested in a
folder. A plan or check file inside one is still named by its path from the
project folder (`apps/mobile/src/comms.ts`), and VBW does its git work for that
file in the repository that tracks it: the nearest folder at or above the file
that holds `.git` (the rule the guards use, docs/guards.md). A folder that a
symbolic link takes outside the project is never such a repository: VBW does
nothing outside the project, so a plan file reached through it stays the
project's, and git refuses to commit a path beyond a symbolic link.

- `vbw commit` makes one commit per repository that holds a changed file, each
  with the same message and trailers (`VBW-Plan:`, `VBW-Req:`, or `VBW-Fix:`),
  and prints one line per commit, naming the submodule:
  `committed 1a2b3c4 in apps/mobile for P1.1 (1 file)`. The approval's commit
  of the check files does the same.
- The project's pointer to the submodule is never moved: VBW commits inside the
  submodule and stops there, since many projects bump submodule pointers only on
  purpose. The project's `git status` shows the submodule as changed (`M
  apps/mobile`) until you record the pointer yourself. A plan never commits a
  pointer, even one whose files name the folder above the submodule.
- A plan's folder entry (`apps/`, or `*`) covers the files of each submodule
  inside it: `vbw commit` commits them in the submodule, and `vbw plan done`
  counts them as uncommitted until it has.
- When one repository's commit fails (a pre-commit hook refuses, say) after
  another's went in, `vbw commit` stops, names the repository that failed and
  each commit already made (`git commit failed in the project; already
  committed: 1a2b3c4 in apps/mobile (1 file)`), and raises the phase's rigor
  for what was committed. Run the same `vbw commit` again once git's reason is
  fixed: it commits only the files still changed.
- A submodule with a changed file must be on a branch. On a detached HEAD (as
  `git submodule update` leaves one) `vbw commit` commits nothing anywhere and
  says `apps/mobile is on no branch`, with the way out (`git -C apps/mobile
  switch BRANCH`): a commit there would be left behind by the next submodule
  update.
- `vbw plan done` reads the plan's files' changes, and looks for the plan's
  commit, in the repository that tracks each file. Every reader of VBW's
  commits reads each submodule's history as well as the project's: the scope
  check and the delivered-files check (a hand change in the submodule is a
  deviation, named by its project path), `vbw show req` and the loop's report
  (a submodule's commit with `(in apps/mobile)` after it), `vbw show contract
  --changes` (the approved content of a test file in a submodule), and QA's
  fingerprint of a phase (a commit in the submodule sends a passed phase back to
  QA). In a submodule the record's own history ([Whose commits VBW
  judges](proof.md#whose-commits-vbw-judges)) starts after the commit the
  record's first commit pointed the submodule at.
- The proof copy (`vbw prove`, `vbw mutate`, `vbw fix done`) holds each
  checked-out submodule at its own `HEAD`, and `vbw mutate` puts a broken file
  back as its own repository's last commit (docs/proof.md, `vbw prove`). When
  git cannot write the copy because Claude Code's sandbox refuses to create a
  file named `.gitmodules`, VBW makes it again with every `.gitmodules` file
  unwritten: git reads it from the index, VBW still finds the submodules, and
  the copy's `git status` stays clean.
- `vbw ship` wants only the milestone's own files committed: the files its
  plans name and the protected check files (the same set `vbw commit` commits),
  in the project and in each checked-out submodule, named by project path. A
  plan file inside a submodule's own submodule, named by an exact entry, is named
  by its project path too. Your own files, staged or not, never block the ship
  and are never named by it. A moved submodule pointer is no change.
- A `vbw` command run inside a submodule that has no `.vbw/` of its own works on
  the project above it, and a Claude session started there is guarded as that
  project (docs/guards.md). A clone nested in the project (its `.git` a folder)
  and a linked worktree nested in it (its `.git` file points into a
  `worktrees/` folder) stay projects of their own.
- `vbw mutate` judges a break by the committed code with each submodule at its
  own `HEAD`, under the contract it ran with: a commit made only in a submodule,
  or an approved change to a check's `run`, makes the checks run on the
  unbroken code again; a commit made only in a submodule also drops a break
  queued before it.
- `## Test files` matches a pathspec inside a submodule only when the pathspec
  names it (`apps/mobile/src/**/*.spec.ts`), and an exclude that names it
  (`:!apps/mobile/src/legacy/**`) applies inside it: a test file there is a
  test file of its own, named by its project path. A pattern that names no
  submodule (`*/tests/*.sh`) matches the project's own files only, so a vendored
  submodule's tests never become units.

Known limits:

- **A check that reads `.gitmodules` as a file, under Claude Code's sandbox:**
  the sandbox keeps VBW from writing `.gitmodules` into the proof copy, so such
  a check fails in the proof while it passes in your working folder. Read it
  through git instead (`git config --blob :.gitmodules ...`). Outside the
  sandbox the copy holds the file.

- **A parked loop item** reverts its commits in the project only: its commits in
  a submodule stay.
- **The loop's approval of strengthened check files** reads the project's
  history only: for a check file in a submodule it leaves the approval to you.
- **Uncommitted edits inside a submodule** are not seen by `vbw next`'s
  fingerprint of the working folder or by proof reuse: a submodule counts at its
  `HEAD` until you commit there.
- **One level of submodules:** apart from `vbw ship`'s check, a submodule
  inside a submodule is not followed: its folder is empty in the proof copy, so
  a check reading inside it fails, and `## Test files` lists none of its files.
- **A survivor strengthened only in a submodule:** `vbw mutate` finds the
  strengthened check files by diffing the project's history from the survivor's
  `head`, so a check file strengthened and committed only in a submodule is not
  marked strengthened, and the next red break of that rule reports that the
  break survives the approved check.
- **A submodule that was once a VBW project:** when the record's first commit
  had no submodule at that path, VBW reads the submodule's whole history, so
  `VBW-Plan:` commits from its own earlier VBW work can count as a plan's
  commit there.
- **A clone nested in the project that is not its submodule:** a plan file named
  inside it is committed there, but a plan's folder entry above it does not
  reach into it (its pointer is never committed either), and it is not brought
  into the proof copy, the fingerprints or the readers of VBW's history.

## The user's level

The router passes `args.profile` (the `profile` key of `vbw next --json`,
docs/next.md) to every workflow: `{level, depth, involvement, ...}`
(docs/interview.md). Each workflow turns it into one sentence and appends it to
the task of every agent it starts:

```
The user's level: professionally. Explanation depth: plain with technical terms
explained. Involvement: I make the calls. Write whatever the user will read at
that level and depth.
```

Without `args.profile`, or for a missing value, the workflow uses the middle
choices (`small scripts or no-code`, `plain with technical terms explained`,
`options with a recommendation`). All nine workflows do this.

Each agent file has a section on the user's words: what reaches the user is the
agent's summary, notes and questions, and those follow the level and depth.
Where a choice is the user's, the agent follows involvement: Architect returns
a decision instead of options for `decide and tell me`, and lists every
decision, obvious ones included, for `I make the calls`. The `schema` fields
stay as the schema defines them at every level.

## Planning scope

The router passes `args.requirements` (the `requirements` key of `vbw next
--json`, docs/next.md) to `vbw:planning`: only the active milestone's
requirements, as `{id, text, proof}`. The workflow lists exactly those in the
task of both Architect jobs (decide and scope) under "Requirements of this
milestone (the only ones to consider)", so the Architect never asks about
requirements of shipped milestones. When every listed requirement is an
internal technical change, it returns no decision.

Without `args.requirements`, or with an empty list, the workflow starts no
agent and returns `status: "blocked"` with the summary "planning needs the
requirements of this milestone ... and got none".

## One test run per QA round

A QA round does not run the project's test command once per agent. The proof
already ran it (the project command named `test`), and `vbw next --json` returns
that result as `round.suite` at the `qa` step: `{command, status, exit, seconds,
tail}`. The router passes `round` to `vbw:verifying` as `args.round` (the whole
object; the workflow returns an error without starting an agent for anything
else, a number say, and treats a missing or `null` round as none), and the
workflow adds the result to every QA agent's prompt with an instruction not to
run the suite. When the command did not run (`skipped` or `not run`), the
prompt says so and tells the agents not to retry it; the workflow logs it, and
QA says in its summary that the suite was not run. A project without a test
command has `round.suite` null, and each prompt says "This project has no test
command" and asks QA to say so in its summary, so QA does not guess one.

QA's own instructions say where the command lives: the `test:` line under
`project commands` in `vbw show contract`. QA uses the result in its prompt as
evidence and does not run the command itself.

A phase QA failed before, whose goal, criteria, plans and `auto` requirements
are unchanged since, comes back as a re-check: `round.focus` holds, per phase,
the failed verdict's commit, the round number and its QA fixes. The workflow
tells that phase's QA agent to verify only those fixes, the files changed since
that commit and what they reach, and the goal; anything else it notices is a
note (docs/proof.md, Re-check rounds). Every other phase gets the whole sweep.

`round.deviations` holds, per phase, the files its plans delivered that the
last proof found changed outside any plan: `{file, plan, change, commit, by,
decision}`. The workflow tells that phase's QA agent each one, in the words
of `vbw show phase` (`NOTES.md (P1.1) deleted outside any plan, by
abc123456789`). It also says that each one no decision covers is a deviation
to record as a finding, and that `vbw qa record PHASE pass` refuses while one
stands. A deviation that a decision covers carries its id (`covered by D3`).
QA checks that the decision is the user's and covers that change. A phase with
no deviation gets no such sentence.

## One test run per fix round

In a fix round (`vbw:fixing`) each Dev commits its fix and runs `vbw check` on its own fixes' checks. The Lead runs the round's `vbw fix done` once, after every Dev returns. They never run the project's test command or its quick command. The project's test command runs once, in the proof after the round. A fix for a failing test command runs only the failing tests it needs.

## Rigor

The router passes `args.rigor` (the `rigor` key of `vbw next --json`, docs/next.md)
to the building, verifying and fixing workflows. It maps each phase id to
`{tier, agents, qa, models}` (docs/rigor.md).

- `vbw:building`: each Dev runs on `rigor[phase].models.dev`, falling back to `args.models.dev`; a documentation plan's Docs agent runs on `args.models.docs`. `rigor[phase].tier` decides whether a Dev or Docs agent is told to do the mutation step (standard and deep; docs/rigor.md).
- `vbw:verifying`: each phase is verified at `rigor[phase].qa` (`quick`, `standard` or `deep`), falling back to `args.tier`, on `rigor[phase].models.qa`.
- `vbw:fixing`: a fix has no phase of its own, so every Dev runs on the Dev model of the highest-tier phase in `args.rigor`.

Without `args.rigor`, each workflow uses `args.models` and `args.tier` as before.

## Phase numbers

The router passes `args.next_phase` (the `next_phase` key of `vbw next --json`,
docs/next.md) to `vbw:planning`. The task of both Architect jobs tells it to
number new phases from that number, in order, and to leave started phases as
they are, so planning needs no renumbering round. Without it, the workflow adds
no such instruction.

## Effort

Each agent runs at an effort level, set per role and step by the profile
(`quality`, `balanced` or `budget`; docs/record.md). Lower levels go to closing
a run and to documentation, higher ones to planning and QA.

```
vbw config effort
{"architect":{"decide":"xhigh","scope":"high","recommend":"medium"},"lead":{"plan":"high","close":"low"},...}
```

The table lives in `plugin/lib/efforts.json`: one object per profile, each
holding roles and, under each role, steps. The levels are `low`, `medium`,
`high`, `xhigh` and `max`. The roles and steps:

| Role | Steps |
|---|---|
| `architect` | `decide`, `scope`, `recommend` |
| `lead` | `plan`, `close` |
| `dev` | `build`, `fix` |
| `docs` | `build` |
| `qa` | `verify` |
| `scout` | `survey`, `merge` |
| `debugger` | `investigate`, `diagnose`, `fix` |

The profile's `lead.close` effort is still sent to the closing step, which runs on Haiku in every profile; `model.lead` sets the model the Lead plans with and does not change the closing step.

`vbw next --json` returns the current profile's table as `effort`, and the
router passes it to every workflow as `args.effort`. A workflow gives each
agent call the level for its role and step through Claude Code's per-agent
`effort` option. A role or step missing from `args.effort`, or an `args.effort`
that is not an object, adds no option.

A Claude Code without a per-agent effort setting runs agents as before.
VBW refuses a value Claude Code does not accept (anything but the five levels
above) before a run starts: `vbw next` and `vbw config effort` stop with an
error naming the role and step, for example `the effort table for profile
'balanced' is wrong at dev build: effort "huge" is not one of low, medium,
high, xhigh, max (fix plugin/lib/efforts.json)`.

## Models

A workflow agent inherits the session model unless `args.models` names one for
its role (`{architect, lead, dev, qa, scout, debugger, docs}`), which the router fills from the
project's model profile. The session itself must run an auto-mode-capable model
(Sonnet, Opus or Fable; probe G4).

## Why agents share one folder (decided 2026-10-01)

Devs in one wave share the working tree. The kernel never puts two plans
that share a file in one wave (`vbw next`, and `vbw run start build` refuses
such a wave), fixes that share files go to one Dev, and the guards stop a
Dev from stashing, switching or resetting the tree, so commits never
conflict. A Dev can still see another's half-written file while it runs
its checks; its own checks decide its result, and `vbw prove` after the wave is
the authority.

Per-agent git worktrees (`isolation: 'worktree'`) would isolate Devs
fully, but a worktree holds only tracked files: ignored dependencies
(`node_modules`, a virtualenv) and build outputs are missing. Devs would
reinstall per copy, fail checks for unrelated reasons, or, sharing the main
checkout's dependencies (an editable install), prove the main checkout's code
instead of their own. A false proof is the one failure VBW must not have, so
worktrees may come later only as an opt-in setting with a per-copy install
step.

## Real-user scenarios for amendments, queued requirements and linked worktrees

Three scenarios in `tools/l3-suite.sh` (L3: the real Claude Code on a small project, judged in the record, git and the transcripts, never on screen text) cover what the unit tests held alone. A result file is written only by a passing run.

- `amendfile`: a build is open and `vbw apply --amend` adds a file to its plan. It judges the amendment entry on the plan (what, at, session), that no new approval was recorded and the contract is still approved, that the run was not ended (the same lease stood right after, and the run ended later), that the plan finished, and that the added file is in a commit of the plan.
- `queuedreq`: the user adds a requirement while a build runs. It judges that the requirement was queued during the run, that the mark is cleared when the run ends, that a later plan covers it and is built, and that the first build's plan is as it was approved and built (not re-planned).
- `rustpack`: a two-crate Cargo workspace and a spec of two requirements (one per crate), with no plan, go through `/vbw:vibe`, so the Lead plans with the Rust pack (docs/packs.md). It judges, in the record and the transcripts, that a planning workflow ran, that every plan names the files it changes, that no two plans change the same file, and that the plans are built and proven with cargo.
- `worktreewrite`: a Dev works from a linked worktree (`git worktree add`) while the main checkout holds an open build run, and writes into the main checkout's protected check file. It judges that the guard's refusal (a reason starting `VBW guard:`) is in the transcripts, that the main checkout's file is unchanged, and that the Dev's own plan is done in its worktree.
