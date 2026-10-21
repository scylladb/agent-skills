# ScyllaDB Agent Skills

Collection of ScyllaDB agent skills for use in agentic workflows.
These skills provide coding agents with deep knowledge of ScyllaDB.

## Installation

### CLI

**Recommended**: install the `scylladb` parent skill. It gives the agent an overview of ScyllaDB and a map of the other skills.

```sh
npx skills add scylladb/agent-skills --skill scylladb
```

Install all skills:

```sh
npx skills add scylladb/agent-skills
```

#### Install specific skills
```sh
npx skills add scylladb/agent-skills --skill scylladb
npx skills add scylladb/agent-skills --skill scylladb-cloud-setup
npx skills add scylladb/agent-skills --skill scylladb-cloud-mcp
npx skills add scylladb/agent-skills --skill scylladb-data-modeling
npx skills add scylladb/agent-skills --skill scylladb-vector-search
npx skills add scylladb/agent-skills --skill scylladb-alternator
npx skills add scylladb/agent-skills --skill scylladb-kubernetes
npx skills add scylladb/agent-skills --skill scylladb-benchmark
```

### Claude Code plugin
Coming soon.

### Cursor plugin
Available on the Cursor Marketplace: [ScyllaDB Agent Skills](https://cursor.com/marketplace/scylla-db).
```sh
/add-plugin scylladb
```

### Manual install

Clone this repo and copy the skill folders into the appropriate directory for your agent:

| Agent | Skill Directory | Docs |
|-------|-----------------|------|
| Claude Code | `~/.claude/skills/` | [docs](https://code.claude.com/docs/en/skills) |
| Cursor | `~/.cursor/skills/` | [docs](https://cursor.com/docs/context/skills) |
| OpenCode | `~/.config/opencode/skills/` | [docs](https://opencode.ai/docs/skills/) |
| OpenAI Codex | `~/.codex/skills/` | [docs](https://developers.openai.com/codex/skills/) |
| Pi | `~/.pi/agent/skills/` | [docs](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#skills) |

## Skills

| Skill | Description |
|-------|-------------|
| [scylladb](skills/scylladb/SKILL.md) | Start here. Overview of ScyllaDB and a map of the other skills. |
| [scylladb-cloud-setup](skills/scylladb-cloud-setup/SKILL.md) | Guide users through connecting to a ScyllaDB Cloud cluster — credentials, drivers, and connection verification. |
| [scylladb-cloud-mcp](skills/scylladb-cloud-mcp/SKILL.md) | Set up and use the ScyllaDB Cloud MCP server to manage ScyllaDB Cloud clusters via AI agents. |
| [scylladb-data-modeling](skills/scylladb-data-modeling/SKILL.md) | CQL data modeling patterns and anti-patterns. Query-first design, partition keys, clustering columns, compaction, TTL, tombstones, and common pitfalls. |
| [scylladb-vector-search](skills/scylladb-vector-search/SKILL.md) | Implement and optimize Vector Search on ScyllaDB Cloud — vector indexes, ANN queries, filtering, quantization, and driver integration. |
| [scylladb-alternator](skills/scylladb-alternator/SKILL.md) | Build against ScyllaDB's DynamoDB-compatible API — write isolation policies, load balancing (no single endpoint like real DynamoDB), authentication via CQL roles, and compatibility differences to know before porting a DynamoDB app. |
| [scylladb-kubernetes](skills/scylladb-kubernetes/SKILL.md) | Deploy and operate ScyllaDB on Kubernetes via the ScyllaDB Operator — node preparation (CPU pinning, XFS/local storage), ScyllaCluster configuration, installation/upgrades, client access & networking, TLS/mTLS & authentication, multi-datacenter, scaling, and monitoring/backup. |
| [scylladb-benchmark](skills/scylladb-benchmark/SKILL.md) | Load test a ScyllaDB Cloud cluster on AWS with cassandra-stress, from loaders connected through VPC peering. Measure the maximum 50/50 read/write rate at p99 ≤ 10 ms with a measured default recipe, or test the workload of your app, and get a repeatable report with p50, p90, and p99 latency. |

The skills follow the [Agent Skills format](https://agentskills.io).

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for the contribution process and [AGENTS.md](AGENTS.md) for the skill authoring rules. AI coding agents read `AGENTS.md` (Claude Code reads it through `CLAUDE.md`).

### Validating skills locally

Install the validator (requires [Go](https://go.dev/doc/install)):

```sh
go install github.com/agent-ecosystem/skill-validator/cmd/skill-validator@latest
```

Validate all skills:

```sh
./tests/validate-skills.sh
```

Validate a specific skill:

```sh
./tests/validate-skills.sh skills/scylladb-cloud-setup/
```

## ScyllaDB Cloud MCP Server
The [ScyllaDB Cloud MCP server](https://cloud.docs.scylladb.com/master/api-docs/mcp) enables AI agents to manage ScyllaDB Cloud clusters programmatically: create clusters, monitor health, configure networking, and more.
