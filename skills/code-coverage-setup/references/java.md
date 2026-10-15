# Java: JaCoCo (`jacoco-maven-plugin`)

## Tool choice and first step: check if it's already there, and whether it works

JaCoCo is the de facto standard for JVM coverage. In an established Maven
project, it's common to find `jacoco-maven-plugin` **already declared** in the
POM — `prepare-agent` bound to instrument the JVM, `report` bound to generate
an HTML/XML report. Before assuming coverage needs to be added from scratch,
check for this, and if it's there, **verify it actually produces non-empty
data** (see the gotcha below) before doing anything else. In the one real case
this was checked, the plugin was fully declared and had been for a while, but
was silently producing zero data for exactly the module that mattered most.

If it's genuinely absent, add it to the parent POM's `pluginManagement` and
`plugins`:

```xml
<plugin>
  <groupId>org.jacoco</groupId>
  <artifactId>jacoco-maven-plugin</artifactId>
  <executions>
    <execution>
      <goals><goal>prepare-agent</goal></goals>
    </execution>
    <execution>
      <id>report</id>
      <phase>prepare-package</phase>
      <goals><goal>report</goal></goals>
    </execution>
  </executions>
</plugin>
```

## Gotcha #1 (critical, high-value): a module's own `<argLine>` silently clobbers JaCoCo's

`jacoco:prepare-agent` works by setting the Maven property `argLine` to
include a `-javaagent:...` JVM flag, at **build-execution time**. If a
module's own Surefire (unit tests) or Failsafe (integration tests)
configuration sets `<argLine>` to just its *own* flags —

```xml
<!-- BROKEN: silently discards whatever jacoco:prepare-agent already set -->
<argLine>${some.other.jvm.flag}</argLine>
```

— it **completely replaces** the property instead of appending to it. The
`-javaagent` flag never reaches the forked test JVM. No error, no warning.
`jacoco:prepare-agent`'s own log line (`argLine set to -javaagent:...`) still
prints, correctly describing what *it* did — it has no way to know a later
plugin execution will overwrite the property before the JVM actually forks.

**How to detect this**: run the module's tests, then check whether
`target/jacoco.exec` exists and has non-trivial size (tens of KB at least for
a real module, not 0 bytes or missing entirely). If prepare-agent's log line
looks right but this file is missing or absent, this is almost certainly why.

**The fix** — Maven's *deferred* property syntax, `@{...}` instead of
`${...}`, combined with the module's own flags:

```xml
<argLine>@{argLine} ${some.other.jvm.flag}</argLine>
```

`@{argLine}` (not `${argLine}`) matters specifically because
`jacoco:prepare-agent` sets the property at build-execution time, *after* the
POM's own `${...}` references would already have been resolved — `${argLine}`
would just be empty/undefined at the point Maven interpolates it, while
`@{argLine}` is resolved later, when the actual value is available. This is
the standard, documented JaCoCo/Surefire integration pattern; search for
"argLine is not applied" in JaCoCo's own docs/issue tracker if more context is
needed. Check **every** module's Surefire/Failsafe config for this pattern,
not just the obvious main one — it's easy for a project to have made the same
mistake in more than one module (e.g. a distribution/packaging test module
that copies the same config as the main one).

## Multi-module aggregation: a dedicated `report-aggregate` module

Each module's own `jacoco:report` only knows about that module's own classes.
Code in module A exercised *through* module B's tests (very common — e.g. a
core library module exercised by a separate integration-test module) never
gets attributed back to module A's source without an aggregation step.

Add a new module (`packaging=pom`) that depends on every module whose exec
data + class files should be merged, and runs `jacoco:report-aggregate`:

```xml
<project>
  ...
  <artifactId>your-project-coverage-report</artifactId>
  <packaging>pom</packaging>
  <dependencies>
    <dependency><groupId>com.you</groupId><artifactId>module-a</artifactId></dependency>
    <dependency><groupId>com.you</groupId><artifactId>module-b</artifactId></dependency>
    <dependency><groupId>com.you</groupId><artifactId>integration-tests</artifactId><version>${project.version}</version></dependency>
    <!-- every module whose exec data + classes should be merged -->
  </dependencies>
  <build>
    <plugins>
      <plugin>
        <groupId>org.jacoco</groupId>
        <artifactId>jacoco-maven-plugin</artifactId>
        <executions>
          <!-- disable the inherited default executions: this module has no
               tests/classes of its own for them to act on. Use the SAME id
               as the parent's execution -- often literally "default" when
               the parent declared an execution with no explicit <id>. -->
          <execution>
            <id>default</id>
            <phase>none</phase>
          </execution>
          <execution>
            <id>report</id>
            <phase>none</phase>
          </execution>
          <execution>
            <id>report-aggregate</id>
            <phase>verify</phase>
            <goals><goal>report-aggregate</goal></goals>
          </execution>
        </executions>
      </plugin>
    </plugins>
  </build>
</project>
```

Register the new module in the parent POM's `<modules>`, and exclude it from
any "don't publish this artifact" list the project already maintains (a
distribution/examples/integration-tests module is usually already excluded
from publishing the same way — follow that existing convention).

**Do not use `jacoco.skip=true`** to try to suppress the aggregator module's
inherited default executions — that property is checked by *every* JaCoCo
goal, including `report-aggregate` itself, so it silences the one execution
you actually want to run. Use `<phase>none</phase>` overrides with matching
execution IDs instead (confirmed empirically: `jacoco.skip=true` produces
"Skipping JaCoCo execution because property jacoco.skip is set" for the
`report-aggregate` goal too, not just the inherited ones).

To generate: run whichever test targets you want measured first (so their
`jacoco.exec` files exist on disk), *then* build the aggregator module with
its dependencies (`-am`) and `-DskipTests` (so that rebuild doesn't re-run —
or overwrite the already-collected data for — any module's tests):

```bash
mvn verify -pl your-project-coverage-report -am -DskipTests
```

## Gotcha #2: Maven's reactor stops at the first failing module — and skips everything depending on it

A plain `mvn test` (or any reactor-wide build) marks a module "FAILURE" the
moment its own tests fail, and **Maven then refuses to build any module that
depends on it**, even just to run *that* module's own unrelated tests. This is
not a fail-fast *setting* that a flag can override — it's a real edge in the
build dependency graph. Confirmed empirically: `-fae` (fail-at-end) and
`--fail-never` do **not** rescue this for a module with a genuine `<dependency>`
on the failed one; those flags only let Maven continue building *independent*
modules that don't depend on the failure. A test failure in a foundational
module (e.g. `core`) silently costs every dependent module's coverage data
too, not just `core`'s own.

**Fix**: for a coverage-instrumented unit-test run across a multi-module
reactor, don't rely on one `mvn test` call for the whole reactor. Instead:

```bash
mvn install -DskipTests ...                          # once: get every module's artifact into the local repo, tests skipped so nothing can fail here
for module in core module-b module-c ...; do          # every module with real unit tests
  mvn test -pl "$module" ...  || true                  # each is now its own invocation
done
```

Because every module is already installed in step 1, testing them
independently in step 2 doesn't need `-am` (also-make) and doesn't re-trigger
a rebuild of the whole reactor per module. One module's test failure in the
loop can now only cost that module's own coverage data — verified empirically
by deliberately having one module's tests fail and confirming the other
modules' `jacoco.exec` files still populated with real data afterward.

Integration tests using `maven-failsafe-plugin` typically **don't** need this
treatment: Failsafe already separates *running* integration tests
(`integration-test` phase, which completes regardless of failures) from
*failing the build* on their results (`verify` phase) — so a test failure
there was never able to prevent coverage data from being written in the first
place. Confirm this is actually the plugin in use before assuming it, though.

## Local environment gotchas (don't fix the repo for these)

- macOS ships GNU Make 3.81 (2006), which predates `.ONESHELL` (introduced in
  3.82) — a Makefile using `.ONESHELL:` for multi-line recipes silently gets
  each line run as a *separate* shell invocation instead, with no error,
  breaking anything that depends on shared shell state (loops, variables) across
  lines. Install a modern Make (`brew install make`, use as `gmake` or put
  `gnubin` first on `PATH`) to verify locally; this is not something to change
  in the project's Makefile.
- A build-time formatter/annotation-processing plugin can be incompatible with
  a JDK newer than what CI uses (e.g. a Java-source-manipulating plugin built
  against older `javac` internals breaking on JDK 21+). Match the JDK version
  CI actually uses (check the workflow file) rather than assuming "newest
  available" is the safe choice for local verification.
- A target name that happens to match a real file or directory in the repo
  (e.g. a new module directory named the same as its Make target) needs an
  explicit `.PHONY:` declaration, or `make` treats the target as already
  up to date (since the path exists) and silently skips the recipe entirely.
