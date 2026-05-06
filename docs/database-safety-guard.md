# Database Safety Guard

LLMs with Bash access will occasionally run destructive database commands during verification or debugging — `migrate:fresh`, `db:drop`, `TRUNCATE TABLE` — wiping development data without warning. VBW prevents this with a three-layer defense that works regardless of programming language, framework, or database type.

## How It Works

A PreToolUse hook (`bash-guard.sh`) intercepts **every** Bash command before it reaches the shell. It pattern-matches against a blocklist of known destructive commands and blocks matches with exit code 2 (fail-closed). The command never executes.

This fires on the **tool**, not the agent. Every Bash command from every Bash-capable agent — QA, Dev, Debugger, Lead, Docs, and Scout — passes through the same gate. Scout also gets read-only command-shape checks when its role can be detected. When Claude Code omits per-call agent identity but VBW knows any Scout is active, VBW applies the Scout-safe checks conservatively to the ambiguous call. There is no way around hook execution because Claude Code enforces hooks at the platform level, before the command reaches the shell.

```text
Agent wants to run: php artisan migrate:fresh --seed
                              |
                    +─────────v──────────+
                    |  Claude Code sees   |
                    |  Bash tool call     |
                    +─────────┬──────────+
                              |
                    +─────────v──────────+
                    |  PreToolUse fires   |
                    |  bash-guard.sh      |
                    +─────────┬──────────+
                              |
                 +────────────v────────────+
                 | Scout read-only block?    |
                 +──┬───────────────────┬──+
                block              no block
                  |          +────────v────────+
               exit 2       | Generic override?|
               (BLOCK)      +──┬───────────┬──+
                             yes          no
                              |      +─────v──────+
                           exit 0   | Pattern    |
                           (allow)  | match?     |
                                    +──┬──────┬──+
                                    yes      no
                                     |        |
                                  exit 2   exit 0
                                  (BLOCK)  (allow)
```

The agent gets an error message explaining why the command was blocked and adapts — typically falling back to read-only queries or the test suite.

## Three Defense Layers

| Layer | Type | When It Fires | Reliability |
| :--- | :--- | :--- | :--- |
| `bash-guard.sh` | PreToolUse hook | Before every Bash call | Deterministic (regex match) |
| Agent prompt rules | Behavioral guidance | When agent reads its instructions | Probabilistic (model compliance) |
| `forbidden_commands` contract | PostToolUse hard gate | After Bash execution | Deterministic but reactive |

**Layer 1 is the fix.** It blocks destructive commands before they execute, regardless of what the model decides to do. Prompt instructions can't be ignored because the hook runs at the platform level.

**Layer 2 reduces noise.** Every agent with Bash access has safety guidance in its prompt. QA is told to never modify database state. Scout is restricted to read-only live validation. Dev is told to prefer migration files over direct commands. This reduces how often Layer 1 needs to fire.

**Layer 3 is audit insurance.** Plans can declare `forbidden_commands` in their frontmatter. The hard-gate system checks the event log for violations after execution, providing an audit trail and preventing repeat offenses in the same session.

## What's Blocked

40+ patterns across every major ecosystem:

| Category | Examples |
| :--- | :--- |
| **PHP / Laravel** | `artisan migrate:fresh`, `artisan db:wipe`, `artisan db:seed --force` |
| **Ruby / Rails** | `rails db:drop`, `rails db:reset`, `rake db:schema:load` |
| **Python / Django** | `manage.py flush`, `django-admin flush` |
| **Node.js** | `prisma migrate reset`, `knex migrate:rollback --all`, `sequelize db:drop`, `typeorm schema:drop`, `drizzle-kit push --force` |
| **Go** | `migrate ... drop` |
| **Rust** | `diesel database reset`, `diesel migration revert --all`, `sqlx database drop` |
| **Elixir** | `mix ecto.drop`, `mix ecto.reset`, `mix ecto.rollback --all` |
| **Raw SQL** | `DROP DATABASE`, `DROP TABLE`, `TRUNCATE` via mysql, psql, sqlite3, mongosh |
| **Redis** | `redis-cli FLUSHALL`, `redis-cli FLUSHDB` |
| **Docker** | `docker-compose down -v`, `docker volume rm`, `docker system prune --volumes` |
| **File system** | `rm *.sqlite3`, `rm *.db`, `rm -rf /var/lib/mysql` |

Safe commands pass through unblocked: `php artisan migrate` (forward migration), `rails db:migrate`, `prisma migrate dev`, `docker-compose down` (without `-v`), `php artisan test`, all read-only queries.

## Overrides

When you legitimately need to run destructive commands:

1. **Environment variable** — Start your session with `VBW_ALLOW_DESTRUCTIVE=1`. This bypasses the generic destructive-command classifier. Scout-specific read-only blocks still apply when Scout identity is detected.

2. **Config toggle** — Set `"bash_guard": false` in `.vbw-planning/config.json` or run `/vbw:config bash_guard false`. This disables the generic destructive-command classifier for that project. Scout-specific read-only blocks still apply when Scout identity is detected.

3. **Run it yourself** — The hook only fires inside Claude Code. Open a separate terminal and run the command directly. The guard protects against agents doing it unsupervised, not against you.

## Extending the Blocklist

Add project-specific patterns to `.vbw-planning/destructive-commands.local.txt`:

```text
# Block our custom reset script
scripts/nuke-dev-data\.sh

# Block our ORM's destructive commands
myorm\s+schema:destroy
```

One regex per line, same format as the default `config/destructive-commands.txt`. Local patterns supplement the defaults — they don't replace them.

## Design Decisions

**Fail-closed.** If jq is missing, input is unparseable, or anything unexpected happens, the guard blocks the command (exit 2). It never fails open.

**Tool-level first, role-aware where needed.** The hook matches on `Bash` tool calls, so adding a new Bash-capable agent does not create a destructive-command gap. Scout's extra read-only checks are role-aware best-effort guardrails using hook payload/env/active-agent markers when available; they are command-shape filtering, not a complete shell sandbox. These Scout checks block obvious shell evaluation containers (`eval`, shell `-c` including simple control/grouping wrappers, command/process substitution) alongside shell writes, git/API mutations, and sensitive-file reads. `SubagentStart`/`SubagentStop` maintain `.active-agent-roles` counts so that if Scout is active but the later `PreToolUse` payload lacks per-call identity, VBW applies Scout-safe restrictions to ambiguous Bash/Write calls. This can conservatively block another concurrently active agent until Scout stops, which is safer than silently allowing a Scout-prohibited command.

**~50ms overhead.** One jq parse + one grep per Bash call. Negligible compared to the seconds Bash commands typically take. The 5-second timeout in hooks.json provides a safety ceiling.

**Event logging.** Every blocked command is logged to `.vbw-planning/.event-log.jsonl` with command preview (truncated to 40 chars), matched pattern, agent name, and timestamp. Useful for auditing what agents tried to do.
