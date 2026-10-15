# Python: coverage.py

## Tool choice

Use `coverage.py` directly (CLI: `coverage run` / `coverage combine` / `coverage
report` / `coverage html` / `coverage xml`), not the `pytest-cov` plugin, **when**
the suite already runs as several separate `pytest` invocations (one per
reactor/backend/test category, as is common in drivers with multiple I/O
backends, or a separate unit vs. integration invocation). `pytest-cov` only adds
value inside a single pytest invocation; wrapping each existing invocation with
`coverage run` (parallel mode) and merging with `coverage combine` afterward is
more transparent here and avoids an extra pytest plugin dependency for no real
benefit. If the project only ever runs `pytest` once for everything, `pytest-cov`
is a perfectly fine, simpler choice — don't force the CLI-wrapping approach where
it isn't needed.

## Config (pyproject.toml or .coveragerc)

```toml
[tool.coverage.run]
source = ["your_package"]
branch = true
parallel = true          # each `coverage run` writes .coverage.<suffix> instead of clobbering
relative_files = true
omit = ["your_package/_version.py"]  # generated files, vendored code

[tool.coverage.report]
show_missing = true
exclude_lines = ["pragma: no cover", "raise NotImplementedError", "if TYPE_CHECKING:"]

[tool.coverage.html]
directory = "htmlcov"
```

`parallel = true` means every `coverage run` invocation gets its own uniquely-
suffixed data file automatically — no `--parallel-mode` flag needed on each
call, and no risk of one invocation's data clobbering another's.

## Combining unit + integration + multiple test categories

```bash
rm -f .coverage .coverage.*
coverage run -m pytest tests/unit ...
SOME_BACKEND=x coverage run -m pytest tests/unit/backend_x_tests ...   # repeat per category
coverage run -m pytest tests/integration ...    # only if a live service is reachable

coverage combine
coverage report -m
coverage html
coverage xml
```

Every invocation above accumulates into the same coverage data set as long as
`parallel = true` is set and you don't `coverage erase` between them. Guard the
integration leg on whatever env var signals a live service is configured
(`DATABASE_URL`, `SCYLLA_VERSION`, etc.) so contributors without one locally
still get a useful unit-only report.

## The gotcha: stale compiled extensions shadow the instrumented source

If the package has **optional C/Cython/native extensions** (common in drivers —
a compiled accelerator with a pure-Python fallback), this is the single most
likely reason a coverage report comes back at 0% for exactly the files that
matter most, while everything else looks fine.

**Mechanism**: `coverage.py` (like any `sys.settrace`-based tool) can only trace
plain Python bytecode — it cannot see inside a compiled extension. If the
package is normally built with the accelerator enabled, you need to force a
pure-Python build (an env var like `PACKAGE_NO_EXTENSIONS=1`, or whatever the
project's build system exposes) so the files you actually want line coverage
for compile to bytecode instead. That much is usually documented and easy.

**The trap**: Python's import system prefers a compiled extension (`.so`/`.pyd`)
over the `.py` source **whenever both exist in the same directory**, regardless
of what env var is set for the *current* build. If a normal (accelerated) build
ran even once before — which it will have, for any contributor who just cloned
and set up the project normally — the old `.so` file is still sitting there,
and forcing pure-Python mode for the *next* build doesn't delete it. The new
build tool run may not even recreate that particular file (since the env var
tells the build "don't build this one"), so the stale compiled file from the
previous build silently wins on import. `coverage.py` then dutifully traces
the *compiled* module — which produces zero coverage line hits, since it isn't
Python bytecode at all — while every log line looks completely normal.

**Fix**: before switching build modes for a coverage run, explicitly delete the
compiled artifacts for the modules affected, then do a clean rebuild/reinstall:

```bash
find package_dir -name "*.so" -delete -o -name "*.pyd" -delete
PACKAGE_NO_EXTENSIONS=1 pip install --reinstall-package your-package  # or the project's equivalent
```

Don't delete *every* compiled artifact indiscriminately if the package also has
extensions with no pure-Python fallback at all (rare, but check) — those simply
won't build in this mode and won't be measured either way; deleting them just
adds unnecessary rebuild cost elsewhere.

**Verify this actually worked**: after the rebuild, `import the_module; print(the_module.__file__)`
should point at a `.py` file, not a `.so`/`.pyd`. Don't just trust that the env
var was set — confirm the import resolved to source.

## Review feedback seen in practice

- **Concurrency modes**: if any test category uses `gevent`/`eventlet`
  monkey-patching or greenlets, pass `coverage run --concurrency=gevent,thread`
  (or `eventlet,thread`) explicitly for that invocation — the default
  concurrency setting can silently produce incomplete or incorrect trace data
  under monkey-patched I/O.
- Set env vars that affect the build (like the no-extensions flag) at the CI
  **job level**, not just for the test step — some build systems cache and
  rebuild based on env var changes, and setting it only for the test-run step
  can trigger a redundant rebuild partway through, wasting a couple of minutes
  per run.
- If the project pins a lockfile (`uv.lock`, `poetry.lock`, etc.), remember to
  update/commit it if the new coverage dependency changes resolved versions —
  a lockfile-check CI step will otherwise fail on an unrelated-looking diff.
