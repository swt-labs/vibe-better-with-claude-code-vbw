# Rust, for QA

Read this when the phase's plans touched Cargo.toml or *.rs. It adds to what you verify.

- A test target still declared `test = false` in Cargo.toml after its code compiles is a finding: the declaration must go once it compiles, or the test never runs. Its `--test NAME` run must be red before the code and green after.
- A dependency added or moved between crates, including one reached through a path dependency (the other workspace's manifest never names it), must show in every affected lockfile in the same commit. A missing lockfile entry is a finding.
- A behaviour change must have re-pinned baselines, generated pages and digests in the same change. Look for an old baseline that a changed output no longer matches, or one regenerated without a reason.
- A check runs one crate with `-j 2`; the whole workspace runs only as a check marked alone.
- A workspace-wide command inside an ordinary check is a finding only when it compiles or runs tests (cargo test, cargo build, cargo check, cargo clippy). A command that only reads the lockfile or the manifest (cargo metadata, cargo tree, cargo pkgid) or a lockfile diff is no finding.
- Paths of a nested workspace are written from the project root, in plans, checks and commits.
