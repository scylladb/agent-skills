# ScyllaDB Agent Skills

Collection of ScyllaDB agent skills for use in agentic workflows.
These skills provide coding agents with deep knowledge of ScyllaDB Cloud, 
ScyllaDB CQL data modeling, and ScyllaDB Vector Search.

## Installation

### CLI
```sh
npx skills add scylladb/agent-skills
```

#### Install specific skills
```sh
npx skills add scylladb/agent-skills --skill scylladb-cloud-setup
npx skills add scylladb/agent-skills --skill scylladb-cloud-mcp
npx skills add scylladb/agent-skills --skill scylladb-data-modeling
npx skills add scylladb/agent-skills --skill scylladb-vector-search
npx skills add scylladb/agent-skills --skill scylladb-alternator
npx skills add scylladb/agent-skills --skill scylladb-kubernetes
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
| [scylladb-cloud-setup](skills/scylladb-cloud-setup/SKILL.md) | Guide users through connecting to a ScyllaDB Cloud cluster — credentials, drivers, and connection verification. |
| [scylladb-cloud-mcp](skills/scylladb-cloud-mcp/SKILL.md) | Set up and use the ScyllaDB Cloud MCP server to manage ScyllaDB Cloud clusters via AI agents. |
| [scylladb-data-modeling](skills/scylladb-data-modeling/SKILL.md) | CQL data modeling patterns and anti-patterns. Query-first design, partition keys, clustering columns, and common pitfalls. |
| [scylladb-vector-search](skills/scylladb-vector-search/SKILL.md) | Implement and optimize Vector Search on ScyllaDB Cloud — vector indexes, ANN queries, filtering, quantization, and driver integration. |
| [scylladb-alternator](skills/scylladb-alternator/SKILL.md) | Build against ScyllaDB's DynamoDB-compatible API — write isolation policies, load balancing (no single endpoint like real DynamoDB), authentication via CQL roles, and compatibility differences to know before porting a DynamoDB app. |
| [scylladb-kubernetes](skills/scylladb-kubernetes/SKILL.md) | Deploy and operate ScyllaDB on Kubernetes via the ScyllaDB Operator — node preparation (CPU pinning, XFS/local storage), ScyllaCluster configuration, installation/upgrades, client access & networking, TLS/mTLS & authentication, multi-datacenter, scaling, and monitoring/backup. |

The skills follow the [Agent Skills format](https://agentskills.io).

## Development

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
