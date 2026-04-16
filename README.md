# ScyllaDB Agent Skills

Collection of ScyllaDB agent skills for use in agentic workflows. These skills provide coding agents with deep knowledge of ScyllaDB Cloud, ScyllaDB data modeling, and ScyllaDB Vector Search.

## Installation

## CLI
```sh
npx skills add scylladb/agent-skills
```

### Install specific skills
```sh
npx skills add scylladb/agent-skills --skill scylladb-cloud-setup
npx skills add scylladb/agent-skills --skill scylladb-data-modeling
npx skills add scylladb/agent-skills --skill scylladb-vector-search
```

## Claude Code plugin
```sh
claude plugin marketplace add scylladb/agent-skills

claude plugin install scylladb-cloud-setup@scylladb
claude plugin install scylladb-data-modeling@scylladb
claude plugin install scylladb-vector-search@scylladb
```

## Cursor plugin
Install from the Cursor marketplace: https://cursor.com/marketplace/scylladb

```sh
/add-plugin scylladb
```

## Skills

| Skill | Description |
|-------|-------------|
| [scylladb-cloud-setup](skills/scylladb-cloud-setup/SKILL.md) | Guide users through connecting to a ScyllaDB Cloud cluster — credentials, drivers, and connection verification. |
| [scylladb-data-modeling](skills/scylladb-data-modeling/SKILL.md) | CQL data modeling patterns and anti-patterns. Query-first design, partition keys, clustering columns, and common pitfalls. |
| [scylladb-vector-search](skills/scylladb-vector-search/SKILL.md) | Implement and optimize Vector Search on ScyllaDB Cloud — vector indexes, ANN queries, filtering, quantization, and driver integration. |

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