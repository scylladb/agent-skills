# ScyllaDB Agent Skills

Collection of ScyllaDB agent skills for use in agentic workflows. These skills provide coding agents with deep knowledge of ScyllaDB Cloud, CQL data modeling, and Vector Search.

## Installation

### Local install from repository

1. Clone the repository:

   ```bash
   git clone https://github.com/zseta/scylladb-agent-skills.git
   ```

2. Install the skills for your platform:

   Copy the `skills/` directory to the location where your coding agent
   reads its skills or context files. Refer to your agent's documentation
   for the correct path.

## Skills

| Skill | Description |
|-------|-------------|
| [scylladb-cloud-setup](skills/scylladb-cloud-setup/SKILL.md) | Guide users through connecting to a ScyllaDB Cloud cluster — credentials, drivers, and connection verification. |
| [scylladb-data-modeling](skills/scylladb-data-modeling/SKILL.md) | CQL data modeling patterns and anti-patterns. Query-first design, partition keys, clustering columns, and common pitfalls. |
| [scylladb-vector-search](skills/scylladb-vector-search/SKILL.md) | Implement and optimize Vector Search on ScyllaDB Cloud — vector indexes, ANN queries, filtering, quantization, and driver integration. |
