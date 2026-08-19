# Rust: cargo-llvm-cov

## Tool choice

Use [`cargo-llvm-cov`](https://github.com/taiki-e/cargo-llvm-cov) — LLVM
source-based coverage — not `cargo-tarpaulin`. Tarpaulin is ptrace-based, and
ptrace-based instrumentation is known to misbehave with async/multi-threaded
test suites (which is most nontrivial Rust code using tokio/async-std). If the
project uses `cargo-nextest` as its test runner (common — check for a
`.config/nextest.toml` or `cargo nextest run` in CI/Makefile/justfile),
`cargo-llvm-cov` has a `nextest` subcommand that wraps it directly:
`cargo llvm-cov nextest ...` instead of `cargo llvm-cov ...` (which drives
plain `cargo test`).

Install (also needs the `llvm-tools` rustup component, which `cargo install`
prompts for automatically):

```bash
rustup component add llvm-tools-preview
cargo install cargo-llvm-cov cargo-nextest --locked
```

## Combining unit + integration into one report

```bash
cargo llvm-cov clean --workspace          # once, at the start of the whole session

cargo llvm-cov nextest --all-features --no-report --no-fail-fast
cargo llvm-cov nextest --all-features --no-report --no-fail-fast -E 'test(integration::)' # or however the project selects its integration suite

cargo llvm-cov report --summary-only
cargo llvm-cov report --html --output-dir target/llvm-cov
cargo llvm-cov report --lcov --output-path target/llvm-cov/lcov.info
```

`--no-report` on each run defers rendering; accumulation across multiple
`--no-report` invocations happens **automatically** — no `--no-clean` flag is
needed between them, only the one `cargo llvm-cov clean --workspace` at the
very start of the session to avoid mixing in stale data from a previous run.

## Gotcha: nextest's default fail-fast destroys every other test's coverage data

`cargo nextest run`'s default behavior is to **stop the entire run** after the
first failing test binary. Combined with `--no-report` (needed so multiple
invocations can accumulate into one merged report instead of each producing
an independent one), a single failure can silently throw away coverage data
for every test that would have run after it — not just fail that one test.

Confirmed by direct comparison in this session: without `--no-fail-fast`, 11
failing tests (out of 667, due to no live external service being reachable in
that environment) reduced the number of *collected* tests all the way down to
11 — everything after the failure point never ran and contributed nothing.
With `--no-fail-fast` added, all 667 ran and contributed real coverage data,
regardless of the same 11 still failing.

**Fix**: always pass `--no-fail-fast` on every coverage-instrumented
`cargo llvm-cov nextest` invocation. Verify this by deliberately breaking one
test and confirming coverage numbers for unrelated modules are still
populated in the final report, not zeroed out.

## Known gap: doctests aren't measured

`cargo-llvm-cov`'s doctest coverage support requires a **nightly** toolchain.
If the project targets stable Rust (check the MSRV / `rust-toolchain.toml`),
doctests simply won't be instrumented. Don't chase this — run doctests
separately via plain `cargo test --doc` for correctness (so they still catch
regressions), and document in one sentence that they aren't included in the
coverage number. This mirrors how the project's own test runner may already
treat doctests as a separate concern (e.g. because `cargo-nextest` itself
doesn't support running them either, forcing `cargo test --doc` to be a
separate step already).

## Review feedback seen in practice

- New workflow files need an explicit `permissions: contents: read` block.
- Surface results via CI job summary + uploaded artifact by default, not a
  third-party service, unless asked.
