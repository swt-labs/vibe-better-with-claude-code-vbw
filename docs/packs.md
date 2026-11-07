# Stack packs

A stack pack is a folder of plain text that tells VBW's Lead, Dev and QA what is special about one language or toolchain. The first pack is Rust. A project with no Rust gets nothing from it and pays nothing for it.

## How a plan gets a pack

Each plan lists the files it changes. VBW compares those files with the patterns in each pack's manifest. The Rust pack matches `Cargo.toml` and `*.rs`. A plan that touches either gets the Rust pack; a Python plan in the same wave gets none. So a repository with Rust and Python gets the right text for each plan.

- **Dev and QA** get the pack of their own plan, chosen from the plan's files.
- **The Lead** plans before any plan exists, so there are no plan files to compare. It gets the pack from the project's tracked files (`git ls-files`). A tracked `Cargo.toml` selects the Rust pack; an untracked one does not. This is the one place a pack is chosen per project, not per plan.

`vbw next --json` shows the result under `packs` (for plans, phases and the project) with `packs_root`. A project with no match has neither key.

## What the folder holds

`plugin/packs/<name>/` holds exactly four files:

| File | What it is |
|---|---|
| `pack.json` | The `name` and the `patterns` (file globs) that select the pack |
| `lead.md` | What the Lead is told when cutting plans and checks |
| `dev.md` | What a Dev is told when building |
| `qa.md` | What QA is told when verifying |

A pack is not an agent: its files carry no agent frontmatter, and `plugin/agents/` stays at seven agents. The workflows hand the agent the path of the text; they do not read it.

## A pack never touches the contract or the record

A pack is outside the contract and outside the record (`.vbw/record.json`). Editing a pack changes no contract hash, un-approves no plan and adds no key to the record. Upgrading VBW with a better pack never asks you to approve anything again.

## The Rust pack
It tells the roles the points below, and that paths in a nested workspace are written from the project root:

1. A test target written ahead of its code is declared `test = false` in its manifest, so whole-crate commands stay green while its explicit `--test NAME` still fails red. The declaration goes once the target compiles.
2. A plan names every file it changes in a crate. Two plans may share a crate when their file lists have no file in common.
3. A change to Cargo.toml or a lockfile goes in one plan at a time.
4. A file many plans would touch (a module list in lib.rs or mod.rs, a shared enum, a manifest, a lockfile) is set up once in an early skeleton plan, or split so each later plan owns its own module file.
5. A later plan that needs a dependency the skeleton did not add waits (an `after` entry) on the plan that adds it, and the plan states it.
6. When a dependency is added or moved between crates, including one reached through a path dependency (the other workspace's manifest never names it), list every affected lockfile (each workspace's Cargo.lock) in the plan's files, because each lock changes in the same commit.
7. When a dependency is added or moved between crates, including one reached through a path dependency (the other workspace's manifest never names it), commit every affected lockfile in the same commit as the dependency, never later.
8. A dependency added or moved between crates, including one reached through a path dependency (the other workspace's manifest never names it), must show in every affected lockfile in the same commit. A missing lockfile entry is a finding.
9. A check runs one crate with `-j 2`; the whole workspace runs only as a check marked alone.
10. A workspace-wide command inside an ordinary check is a finding only when it compiles or runs tests (cargo test, cargo build, cargo check, cargo clippy). A command that only reads the lockfile or the manifest (cargo metadata, cargo tree, cargo pkgid) or a lockfile diff is no finding.
11. A behaviour change re-pins baselines, generated pages and digests in the same change.

## Contributing a pack

Adding a stack is one more folder under `plugin/packs/`. No code changes: a pack folder is picked up by its manifest.

1. Write `pack.json` with a `name` and the `patterns` of the files that mark the stack.
2. Write `lead.md`, `dev.md` and `qa.md`. Keep each short and specific: what goes wrong in this stack and what to do about it. Add to the contract rules; never replace them.
3. Show it on a real codebase. A pack ships only with evidence from a real project: what it removed from that project's list of failures (a planned test that does not compile, a missing lockfile entry, a gate that fails on a planned check), measured, not judged by how the text reads. A weak pack makes checks look stronger than they are.
4. Open a pull request with the evidence. It gets a decision-style review: for each rule in the pack, is it general to the stack, what does it cost, and what does it replace. A rule that only one project needs is declined (see [CONTRIBUTING.md](../CONTRIBUTING.md)).

Still open (check forms per pack, a mutation step per pack, asking the stack at `vbw init`) is listed in [ideas.md](ideas.md).
