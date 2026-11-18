# Coordinates and Build

How to change the build files when moving from Java driver 3.x to 4.x. The group id stays `com.scylladb`; every artifact name changes. See [What changes for ScyllaDB users](https://java-driver.docs.scylladb.com/stable/upgrade_guide/from_3x/index.md#what-changes-for-scylladb-users) in the migration guide.

## Artifact Mapping

| 3.x artifact | 4.x artifact(s) |
| --- | --- |
| `com.scylladb:scylla-driver-core` | `com.scylladb:java-driver-core`. Add `com.scylladb:java-driver-query-builder` only if the code uses `QueryBuilder`. |
| `com.scylladb:scylla-driver-mapping` | `com.scylladb:java-driver-mapper-runtime`, plus `com.scylladb:java-driver-mapper-processor` as an annotation processor |
| `com.scylladb:scylla-driver-extras` | Nothing to add. Most of its codecs are in `java-driver-core` as `ExtraTypeCodecs`; see [types-and-codecs](types-and-codecs.md). |
| `com.datastax.cassandra:cassandra-driver-core` (DataStax 3.x) | `com.scylladb:java-driver-core`. The 3.x API is the same as ScyllaDB's 3.x, so the rest of this skill applies unchanged. |

Use one version for every `java-driver-*` artifact. The latest is 4.19.4.0; check [Maven Central](https://central.sonatype.com/artifact/com.scylladb/java-driver-core) for newer releases.

### Wrong

```xml
<!-- Upstream driver: no shard-aware or tablet-aware routing -->
<dependency>
  <groupId>org.apache.cassandra</groupId>
  <artifactId>java-driver-core</artifactId>
  <version>4.19.0</version>
</dependency>
```

The same applies to `com.datastax.oss:java-driver-core`. Both compile against the same API, so the mistake only shows up as lost performance in production.

### Right: Maven

```xml
<properties>
  <scylla.driver.version>4.19.4.0</scylla.driver.version>
</properties>

<dependencies>
  <dependency>
    <groupId>com.scylladb</groupId>
    <artifactId>java-driver-core</artifactId>
    <version>${scylla.driver.version}</version>
  </dependency>
  <!-- Only if the code uses QueryBuilder -->
  <dependency>
    <groupId>com.scylladb</groupId>
    <artifactId>java-driver-query-builder</artifactId>
    <version>${scylla.driver.version}</version>
  </dependency>
  <!-- Only if the code uses the object mapper -->
  <dependency>
    <groupId>com.scylladb</groupId>
    <artifactId>java-driver-mapper-runtime</artifactId>
    <version>${scylla.driver.version}</version>
  </dependency>
</dependencies>
```

The mapper processor goes in the compiler plugin, not in `<dependencies>`:

```xml
<plugin>
  <groupId>org.apache.maven.plugins</groupId>
  <artifactId>maven-compiler-plugin</artifactId>
  <configuration>
    <release>11</release>
    <annotationProcessorPaths>
      <path>
        <groupId>com.scylladb</groupId>
        <artifactId>java-driver-mapper-processor</artifactId>
        <version>${scylla.driver.version}</version>
      </path>
    </annotationProcessorPaths>
  </configuration>
</plugin>
```

If the project already lists other processors there, such as Lombok, add this one next to them. Listing `annotationProcessorPaths` turns off processor discovery on the classpath.

### Right: Gradle

```kotlin
dependencies {
    implementation("com.scylladb:java-driver-core:4.19.4.0")
    implementation("com.scylladb:java-driver-query-builder:4.19.4.0")   // only with QueryBuilder
    implementation("com.scylladb:java-driver-mapper-runtime:4.19.4.0")  // only with the mapper
    annotationProcessor("com.scylladb:java-driver-mapper-processor:4.19.4.0") // only with the mapper
}
```

## Java Version

- 4.19.2.0 and later are compiled for Java 11 (`<release>11</release>`). On Java 8 they fail with `UnsupportedClassVersionError`.
- 4.19.0.x is the last line that runs on Java 8. Use it only if the user cannot move off Java 8, and tell them it is a dead end.

## Guava

3.x exposed Guava in its API (`ListenableFuture`, `Futures`) and brought it in as a transitive dependency. 4.x shades Guava into `java-driver-guava-shaded`, so it is no longer on the application's classpath.

- Rewrite driver futures to `CompletionStage`; see [statements-and-results](statements-and-results.md#async-execution).
- If application code uses Guava for its own purposes, add `com.google.guava:guava` as a direct dependency. Do not import from the driver's shaded package (`com.datastax.oss.driver.shaded.guava`): it is internal and changes without notice.

## Logging

4.19.4.0 depends on `slf4j-api` 2.x. SLF4J 1.7 bindings are ignored, so the driver logs nothing and the application prints `No SLF4J providers were found` at startup. If the project has a 1.7-era binding, move it to its SLF4J 2 version:

| 1.7 binding | SLF4J 2 binding |
| --- | --- |
| `org.slf4j:slf4j-simple:1.7.x`, `slf4j-reload4j` | Same artifact, version 2.0.x |
| `ch.qos.logback:logback-classic:1.2.x` | `logback-classic` 1.3 or later |
| `org.apache.logging.log4j:log4j-slf4j-impl` | `org.apache.logging.log4j:log4j-slf4j2-impl` |

## Metrics and JMX

3.x reported metrics to JMX by default. 4.x does not, and session and node metrics are opt-in by name. To keep JMX, add `io.dropwizard.metrics:metrics-jmx` and register the reporter, as described in the [Metrics section](https://java-driver.docs.scylladb.com/stable/upgrade_guide/from_3x/index.md#metrics) of the migration guide. To use Micrometer instead, add `com.scylladb:java-driver-metrics-micrometer`.

## Remove the Old Artifacts

After the code compiles, remove every `scylla-driver-*` and `cassandra-driver-*` dependency, and any exclusion or version pin that existed only for them, such as Guava or Netty pins. Then rerun the first two inventory greps from SKILL.md; they must return nothing. Guava imports may remain if the build now declares `com.google.guava:guava` itself.
