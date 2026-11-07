# Rust, for the Lead

Read this when the project has Rust (a tracked Cargo.toml or *.rs file). It adds to your plans and checks; it never replaces the contract rules.

## Cutting plans

- A plan names every file it changes in a crate. Two plans may share a crate when their file lists have no file in common.
- A change to Cargo.toml or a lockfile goes in one plan at a time.
- A file many plans would touch (a module list in lib.rs or mod.rs, a shared enum, a manifest, a lockfile) is set up once in an early skeleton plan, or split so each later plan owns its own module file.
- A later plan that needs a dependency the skeleton did not add waits (an `after` entry) on the plan that adds it, and the plan states it.
- When a dependency is added or moved between crates, including one reached through a path dependency (the other workspace's manifest never names it), list every affected lockfile (each workspace's Cargo.lock) in the plan's files, because each lock changes in the same commit.
- A behaviour change re-pins what records the old behaviour: baselines, generated pages and digests. Put those files in the plan that changes the behaviour, so they move in the same change.
- Write every path from the project root, including paths inside a nested workspace (crates/pay/Cargo.toml, not Cargo.toml).

## Cutting checks

- A check runs one crate: `cargo test -j 2 -p NAME` or `cargo test -j 2 --test NAME`. Two jobs keep several checks running side by side from starving the machine.
- The whole workspace (`cargo test --workspace`) is a check marked alone, so nothing else runs beside it.
- A test target written ahead of its code is declared `test = false` in its Cargo.toml `[[test]]` entry. Whole-crate commands stay green, while `cargo test --test NAME` still fails red, which is the red the Dev must see first. Tell the Dev to remove the declaration once the target compiles.
