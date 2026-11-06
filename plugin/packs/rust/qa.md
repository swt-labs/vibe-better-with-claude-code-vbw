# Rust, for QA

Read this when the phase's plans touched Cargo.toml or *.rs. It adds to what you verify.

- A test target still declared `test = false` in Cargo.toml after its code compiles is a finding: the declaration must go once it compiles, or the test never runs. Its `--test NAME` run must be red before the code and green after.
- A dependency added to a crate must show in the Cargo.lock of every workspace that path-depends on it, in the same commit. A stale lockfile elsewhere is a finding.
- A behaviour change must have re-pinned baselines, generated pages and digests in the same change. Look for an old baseline that a changed output no longer matches, or one regenerated without a reason.
- A check runs one crate with `-j 2`; the whole workspace runs only as a check marked alone. A workspace-wide command inside an ordinary check is a finding.
- Paths of a nested workspace are written from the project root, in plans, checks and commits.
