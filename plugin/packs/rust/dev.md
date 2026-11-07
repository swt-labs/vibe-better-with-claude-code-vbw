# Rust, for the Dev

Read this when your plan's files include Cargo.toml or *.rs. It adds to your instructions.

## Building

- A test target written ahead of its code is declared `test = false` in Cargo.toml so whole-crate commands stay green; `cargo test --test NAME` still fails red, which is your red first. Remove the declaration once the target compiles, in the commit that makes it compile.
- When a dependency is added or moved between crates, including one reached through a path dependency (the other workspace's manifest never names it), commit every affected lockfile in the same commit as the dependency, never later.
- Run one crate with `-j 2` (`cargo test -j 2 -p NAME`). Run the whole workspace only alone: when a check is marked alone, run nothing beside it.
- A behaviour change re-pins baselines, generated pages and digests in the same change; a green test that compares against an old baseline is not done.
- Write paths from the project root, also in a nested workspace (crates/pay/src/lib.rs). Format with `rustfmt --edition EDITION FILE...`, which touches your files and the modules they declare; `cargo fmt`, with or without a file named, rewrites the whole crate.

## Committing

One commit per task, naming its files, with Cargo.toml, Cargo.lock and the source it belongs to together.
