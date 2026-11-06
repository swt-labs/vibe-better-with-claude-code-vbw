# Rust, for the Lead

Read this when the project has Rust (a tracked Cargo.toml or *.rs file). It adds to your plans and checks; it never replaces the contract rules.

## Cutting plans

- Give a plan the whole crate it changes: its Cargo.toml and its *.rs files. When a plan adds a dependency to a crate, name the Cargo.lock of every workspace that path-depends on that crate in the plan's files, because that lock changes in the same commit.
- A behaviour change re-pins what records the old behaviour: baselines, generated pages and digests. Put those files in the plan that changes the behaviour, so they move in the same change.
- Write every path from the project root, including paths inside a nested workspace (crates/pay/Cargo.toml, not Cargo.toml).

## Cutting checks

- A check runs one crate: `cargo test -j 2 -p NAME` or `cargo test -j 2 --test NAME`. Two jobs keep several checks running side by side from starving the machine.
- The whole workspace (`cargo test --workspace`) is a check marked alone, so nothing else runs beside it.
- A test target written ahead of its code is declared `test = false` in its Cargo.toml `[[test]]` entry. Whole-crate commands stay green, while `cargo test --test NAME` still fails red, which is the red the Dev must see first. Tell the Dev to remove the declaration once the target compiles.
