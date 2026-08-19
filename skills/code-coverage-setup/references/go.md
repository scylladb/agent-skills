# Go: built-in `go test -cover` + `covdata`

## Tool choice

Use Go's built-in coverage tooling — `go test -cover -coverpkg=./...` plus
`GOCOVERDIR`/`go tool covdata` (available since Go 1.20, see the official
["integration test coverage"](https://go.dev/testing/coverage/) feature) — not
a third-party tool. This is the modern standard and needs zero new
dependencies. Multiple separate `go test` invocations (different packages,
different build tags, unit vs. integration, different modules in a
multi-module repo) can all write into the *same* directory and get merged
together at the end — this is exactly the "combine multiple runs into one
report" mechanism this whole exercise is about.

## Combining unit + integration into one report

```bash
COVDIR=.coverage/data
mkdir -p "$COVDIR"

go test -tags unit -cover -coverpkg=./... ./... -args -test.gocoverdir="$COVDIR"
go test -tags integration -cover -coverpkg=./... . -args -test.gocoverdir="$COVDIR"   # see gotcha #1 below for the package pattern here

go tool covdata percent -i="$COVDIR"                                    # per-package summary
go tool covdata textfmt -i="$COVDIR" -o=coverage.out                    # legacy profile format
go tool cover -html=coverage.out -o=coverage.html
```

No `--no-clean`/merge flag is needed between invocations — accumulation into
the same `GOCOVERDIR` happens automatically; each `go test` process writes its
own uniquely-named counter/meta files into that directory.

`-coverpkg=./...` controls what gets **instrumented** (build-time), completely
separate from what gets **run** (the package pattern argument, e.g. `./...` or
`.`). This distinction matters for gotcha #1 below: you can run a narrower set
of packages while still measuring cross-package coverage of code those
packages call into.

## Multi-module repos: rendering fails across module boundaries

If the repo has nested Go modules (its own `go.mod` in a subdirectory —
common for a vendored/forked dependency, e.g. a compression codec), a single
merged coverage profile spanning two modules will fail at render time:

```
cover: no required module provides package github.com/you/repo/submodule; to add it:
	go get github.com/you/repo/submodule
```

`go tool cover` resolves source files against the module rooted at the
*current directory* — it has no concept of "render across two modules from
one profile." Fix: keep everything in **one shared `GOCOVERDIR`** (accumulation
still works fine across modules), but generate/render each module's report
**separately**, filtering with `covdata`'s `-pkg` flag and running `go tool
cover` from *within* that module's own directory:

```bash
go tool covdata textfmt -i="$COVDIR" -pkg="github.com/you/repo/..." -o=coverage-root.out
go tool cover -html=coverage-root.out -o=coverage-root.html

(cd submodule && go tool covdata textfmt -i="$COVDIR" -pkg="github.com/you/repo/submodule/..." -o=../coverage-submodule.out)
(cd submodule && go tool cover -html=../coverage-submodule.out -o=../coverage-submodule.html)
```

Two reports, one shared underlying dataset — this is the correct outcome, not
a workaround; there's no single Go tool invocation that produces one HTML page
spanning two modules.

## Gotcha #1 (critical, subtle): a custom test flag silently breaks package resolution

If the test suite registers its own CLI flags via `flag.String`/etc. (common
for integration tests that take `-cluster=host:port`, `-distribution=...`,
etc.), **`go test`'s flag parser stops recognizing its own flags — including the
package pattern — the moment it hits the first flag it doesn't know about.**
It does not error. It silently defaults the package pattern to `.` (current
directory) instead of whatever was actually specified (`./...`, a subpackage
path, etc.).

Verify this is happening (or would happen) before assuming your invocation
does what it looks like it does:

```bash
go test -tags yourtag -distribution somevalue -timeout=10s ./some/subpackage/... 2>&1 | tail -5
# if the reported package is the ROOT module, not ./some/subpackage,
# you've hit this. Compare against the same command with -distribution removed.
```

**Consequences and the fix**:
- Anything placed *after* the point of confusion (including `-cover`,
  `-coverpkg`, and especially `-args -test.gocoverdir=...`) is unreliable —
  it may or may not be recognized as intended. Put every flag `go test` itself
  needs to recognize (`-tags`, `-timeout`, `-race`, `-cover`, `-coverpkg`)
  **before** any custom flag, and put the package pattern itself before the
  first custom flag too.
- Use `-args` as an explicit, unambiguous boundary: everything after `-args`
  goes verbatim to the compiled test binary. Put *all* custom flags there,
  together with `-test.gocoverdir=...`.
- **This can still leave the wrong package selected** even with `-args`
  correctly placed, if the package pattern itself (e.g. `./...`) needs to
  reach packages that don't understand the custom flags at all — every
  package matched by the pattern receives the *same* global test-binary args,
  and a package whose test binary doesn't register a given custom flag will
  fail outright with `flag provided but not defined: ...`. If the tests that
  actually need those custom flags all live in one specific package, and
  *other* matched packages have unrelated (even unconditionally-compiled)
  test files that don't understand them, **scope the package pattern down to
  exactly that one package** (e.g. `.` instead of `./...`) rather than trying
  to make every package tolerate flags it doesn't need. `-coverpkg=./...`
  still measures the whole module's code as it gets exercised transitively —
  you lose nothing by not literally running every package's own tests in the
  same invocation, if those tests don't exist under this flag/tag
  configuration anyway.
- If a *different* subset of tests (e.g. a build-tag-gated suite living in its
  own subpackage, with no custom flags of its own) needs to run too, give it
  its **own separate, minimal invocation** targeting exactly that package,
  rather than reusing the flag-heavy command meant for a different package.
  Don't assume reusing an existing invocation "with a different tag" actually
  runs what you think — verify which package actually executed (see above).

## Gotcha #2: fail-fast destroys every other package's coverage data

`go test`'s default is to run every matched package's tests regardless of
earlier failures when invoked directly — but check this is actually true for
your case (e.g. if wrapped by `cargo-nextest`-style tooling or a custom runner,
fail-fast may be the default instead; see references/rust.md for the same
issue in a different tool). If any wrapper/runner here defaults to stopping
after the first failure, and you're also using `--no-report`-style deferred
reporting to accumulate multiple runs, a single early failure can silently
discard *every other test's* coverage data, not just fail that one test.
Deliberately break one test during verification and confirm the *other*
tests' coverage still appears in the final merged report.

## Gotcha #3: counter mode clash when merging

`go tool covdata` refuses to merge data recorded under different coverage
counter modes:

```
error: counter mode clash while reading meta-data file ...: previous file had atomic, new file has set
```

`-race` implicitly forces `atomic` counter mode. If only *some* of your
coverage-instrumented invocations use `-race` (e.g. unit tests do, integration
tests don't), merging them fails with the error above. Fix: pass
`-covermode=atomic` **explicitly on every coverage-instrumented invocation**,
not just the one that happens to also use `-race` — don't rely on `-race` to
provide it implicitly for only one of several runs that need to merge later.

## Review feedback seen in practice

- New workflow files need an explicit `permissions: contents: read` block.
- If a job is gated by a "disable this" label, add `labeled`/`unlabeled` to
  `pull_request.types`, or removing the label doesn't re-trigger a run.
- A shell variable assembled in one Makefile target and re-expanded, unquoted,
  in another target's recipe needs an embedded escaped quote around any path
  that might contain spaces — the word-splitting happens at the *later*
  expansion, not where the variable was built.
