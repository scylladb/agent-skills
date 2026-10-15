---
name: code-coverage-setup
description: Add, fix, or extend code coverage measurement (unit + integration tests, combined into one report) in a software repository, in any language. Use this whenever the user asks to "add code coverage", "measure test coverage", "set up a coverage tool", wants a coverage badge/report/CI job, or reports that an existing coverage pipeline shows 0%, wrong numbers, missing modules, or silently-empty data — the empirically-verified gotchas here (stale compiled extensions, test-runner fail-fast eating coverage data, flag-parsing quirks, Maven argLine clobbering, counter-mode clashes) are the actual root causes of most "coverage isn't working" reports and are easy to miss without having hit them before. Covers Python, Go, Rust, and Java in detail (see references/), with a general approach for any other language.
---

# Code coverage setup

This skill distills a hands-on session that added coverage measurement to four real
production repositories (a Python driver, a Go driver, a Rust driver, a Java/Maven
multi-module driver), including two rounds of maintainer code review. The single
biggest lesson: **coverage tooling looks like it's working long after it has quietly
stopped measuring anything real.** A clean exit code, a plausible log line ("argLine
set to -javaagent:..."), or a green CI job are not evidence that coverage data is
correct — in this session, three of four languages had a real, silent bug that only
showed up by directly inspecting the output artifact. Assume the same is true here
until proven otherwise.

## Workflow

1. **Research the repo first.** Read the build tool, the test runner, and however
   CI currently invokes tests. Identify how "unit" and "integration" tests are
   currently separated (env var, build tag, Maven profile, pytest marker, cargo
   feature...) and how CI decides pass/fail today. Check for a coverage tool
   already partially wired in (common in Java/Maven — see references/java.md) —
   if one exists, your job is to fix/complete it, not replace it.
2. **Pick the tool for the language** — see references/&lt;language&gt;.md. Prefer
   the ecosystem's modern standard over an older alternative when they behave
   differently under load (e.g. LLVM source-based coverage over ptrace-based
   tools for anything async/multi-threaded — ptrace assumptions break there).
   Don't add a third-party dependency if the language's toolchain already has
   coverage built in.
3. **Design for combining unit + integration into one report.** The point of the
   exercise is usually "what fraction of the codebase do all our tests together
   exercise," not two disconnected numbers. Every language here has a way to
   accumulate multiple separate test-runner invocations into one merged dataset
   before rendering — find it rather than settling for per-run reports users have
   to average in their head.
4. **Implement additively.** Add new targets/scripts/jobs; do not change the
   behavior of existing ones. A `COVER_ARGS`-style variable that defaults to
   empty and gets set only by the new coverage-specific target is the pattern
   used in every language this session — it means `make test` (or equivalent)
   is byte-for-byte unchanged for everyone not asking for coverage.
5. **Verify empirically, not by reading the docs and moving on** (see below).
   This is the step that actually catches bugs; budget real time for it.
6. **Wire CI as its own job**, not folded into an existing compatibility matrix
   (multiple OS/language-version/database-version combinations). One canonical
   configuration is enough for a coverage number; running it N× across a matrix
   just burns CI time for the same information. Give the job `if: always()` (or
   the CI system's equivalent) from the first test-running step onward, so a
   test failure still lets the report generate — otherwise a broken test leaves
   no coverage output at all to diagnose it with.
7. **Surface results without a third-party account by default**: a CI job
   summary (plain text `report -m`/`percent`-style output) plus an uploaded
   HTML/XML artifact covers most needs with zero external setup. Ask before
   wiring up Codecov/Coveralls/etc. — that needs the user to enable the repo on
   an external service and possibly add a secret token, which only they can do.
8. **Don't gate on a threshold yet.** Land the measurement first, observe the
   baseline number for a few runs, then propose a `fail_under`-style gate as a
   follow-up once there's a real number to set it against.
9. **Document known gaps instead of engineering around them.** Every language
   here ended up with at least one thing coverage genuinely can't measure
   (Cython-only Python modules, Go modules with no corresponding pure-Go
   fallback, Rust doctests, whatever). Say so in the docs in one sentence and
   move on — chasing 100% instrumentation coverage of the coverage tool itself
   is not the goal.

## Verify empirically — this is the actual point of this skill

Every high-value bug found this session was found the same way: run the real
tool, then open the actual output file and check it has real, non-zero, sane
content — not by reading a log line and assuming it worked.

- **A "success" message can be lying.** Java's `jacoco:prepare-agent` logged
  `argLine set to -javaagent:...` on every single run, including the runs where
  the flag never reached the test JVM because a module's own Surefire config
  silently overwrote `argLine` afterward. The log was accurate about what
  Maven's plugin did; it said nothing about whether that value survived to be
  used. Trust the artifact (the `.exec`/`.out`/`jacoco.xml` file, its size, its
  contents), not the narration around it.
- **Test the "one failure destroys everything" scenario on purpose.** This
  recurred in three different disguises: a test runner's default fail-fast
  behavior aborting the whole binary (Go, Rust — losing every subsequent
  package/module's coverage, not just failing one test), and a build tool's
  reactor refusing to build anything that depends on a failed module (Java —
  no flag rescues this, since it's not about continuing after failure, it's
  about a real dependency edge in the build graph). Deliberately make one test
  fail during verification and confirm the *other* tests' coverage still shows
  up in the final report. If a real cluster/service isn't available locally to
  reproduce the exact failure, reproduce the mechanism with something faster
  (e.g. a deliberately-broken unit test) — the failure mode is usually
  independent of *why* the test failed.
- **If a reviewer reports something oddly specific, go find the actual
  mechanism — don't rationalize it away.** "The CI log says no tests to run"
  and "coverage flags before test-binary arguments... writes zero coverage
  files" both turned out to be exactly, literally true, with a reproducible
  root cause (Go's flag parser silently defaulting a package pattern to `.`
  once it hit an unrecognized flag). A specific, surprising bug report from
  someone who read real CI output is usually a real bug, not a
  misunderstanding.
- **Local environment differences are not the repo's bug — but they can
  block you from testing, so fix your own machine.** macOS ships an ancient
  GNU Make (3.81, predates `.ONESHELL` from 3.82) that silently splits
  multi-line recipes into separate shell invocations with no error; BSD
  `find`/`readlink` reject GNU-style flags; a system JDK/Python/Go can be too
  new or too old for a plugin the repo depends on. Install a matching modern
  version locally (Homebrew, rustup, etc.) so you can actually run the real
  commands rather than reasoning about them from a distance — but don't
  "fix" the repo to work around your own machine's tool versions. Things
  that are safe to write off as local-only and not worth chasing further:
  missing Docker networking for a specific database image, no loopback
  aliases, no `sudo` in a sandbox. Rely on real CI for whatever leg you
  genuinely cannot reproduce locally, and say so plainly instead of guessing
  at what it would show.
- **Read the failure, don't just retry past it.** A confusing error 1-2 layers
  removed from the real cause (a flag-parse usage dump because a subpackage's
  test binary didn't recognize a flag; "no test files" because the wrong
  package got selected) is a clue, not noise — trace it back to the actual
  mechanism before writing a fix, or the fix will be aimed at the symptom.

## Common review feedback to anticipate

Across two review rounds on real PRs, these came up repeatedly — bake them in
up front rather than waiting to be asked:

- New GitHub Actions workflow files need an explicit `permissions:` block
  (`contents: read` is usually sufficient) — CodeQL and CodeRabbit both flag
  its absence by default.
- If a job is gated by a "disable this" label, add `labeled`/`unlabeled` to the
  `pull_request` trigger's `types`, or removing the label won't re-trigger a
  run until the next unrelated push.
- Shell variables built once and re-expanded unquoted later (e.g. a Makefile
  variable assembled in one target, used in another) need their own embedded
  quoting around anything that might contain a space (a path), because the
  *later* expansion is what actually gets word-split.
- Don't silently truncate coverage scope (skip a hard-to-instrument module,
  sample only some tests) without saying so in the docs or a log line — a
  quiet gap reads as "fully measured" to everyone downstream.

## Language-specific detail

Read the matching reference file before implementing — each one has the exact
tool, the invocation shape for combining unit + integration runs, and the
specific bugs found and fixed for that language's ecosystem this session:

| Language | Tool | Reference |
|---|---|---|
| Python | `coverage.py` (not `pytest-cov`, when the suite already runs as several separate `pytest` invocations) | [references/python.md](references/python.md) |
| Go | Built-in `go test -cover` + `GOCOVERDIR` + `go tool covdata` (Go 1.20+, no dependency needed) | [references/go.md](references/go.md) |
| Rust | `cargo-llvm-cov` (LLVM source-based; not `tarpaulin`, which is ptrace-based and mishandles async/multi-threaded tests) | [references/rust.md](references/rust.md) |
| Java | JaCoCo via `jacoco-maven-plugin` (often already declared but non-functional — check before assuming it needs adding) | [references/java.md](references/java.md) |

### Other languages

No hands-on verification yet for these — treat the tool choice as a reasonable
starting point, not a battle-tested recommendation, and lean extra hard on the
empirical-verification section above:

- **JavaScript/TypeScript**: `c8` (V8's native coverage, works well with any
  runner) or `nyc`/Istanbul for older/Babel-based setups. Combine multiple
  runner invocations by pointing them at the same `nyc_output`/`.nyc_output`
  directory before the final `nyc report`.
- **C/C++**: `gcov`/`lcov` (GCC) or `llvm-cov` (Clang), typically wired through
  `--coverage`/`-fprofile-arcs -ftest-coverage` compiler flags. `lcov --add-tracefile`
  merges multiple `.info` files from separate test binaries/runs.
- **Ruby**: `SimpleCov`, which already supports merging multiple runs via
  `SimpleCov.collate` or `use_merging`.
- **C#/.NET**: `coverlet` (works with `dotnet test`), reports mergeable via
  `ReportGenerator`.

Whatever the tool, the same shape applies: instrument, run unit + integration,
merge, render, verify the merged artifact has real per-file percentages before
declaring victory.
