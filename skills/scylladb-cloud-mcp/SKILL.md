---
name: scylladb-cloud-mcp
description: Help users set up and use the ScyllaDB Cloud MCP server to manage ScyllaDB Cloud clusters via AI agents. Use this skill when a user wants to manage ScyllaDB Cloud programmatically through an AI agent, configure the MCP server, create, delete, or monitor clusters via MCP, or integrate ScyllaDB Cloud management into an agentic workflow. Connecting an application to a cluster goes to scylladb-cloud-setup. Triggers on "ScyllaDB Cloud MCP", "MCP server ScyllaDB", "manage ScyllaDB with AI agent", "ScyllaDB MCP setup".
---

# ScyllaDB Cloud MCP Server

If the task goes beyond this skill, use the parent `scylladb` skill for a ScyllaDB overview and the list of other ScyllaDB skills. If it is not installed, fetch it from `https://raw.githubusercontent.com/scylladb/agent-skills/main/skills/scylladb/SKILL.md`.

The ScyllaDB Cloud MCP server exposes the ScyllaDB Cloud API as tools that AI agents can call. The server is in beta.

## When to Use This Skill

- The user wants to add the ScyllaDB Cloud MCP server to Claude Code, Cursor, or another MCP client
- The user wants an AI agent to create, delete, or monitor ScyllaDB Cloud clusters
- The user needs an API token for the MCP server, or committed a token by mistake
- The user is building an agentic workflow that manages ScyllaDB Cloud resources

For adjacent topics, use the sibling skill instead:

- Connecting an application to a cluster with a CQL driver, or provisioning clusters with Terraform: `scylladb-cloud-setup`
- Self-managed clusters on Kubernetes: `scylladb-kubernetes`

## Setup

1. Fetch the MCP documentation for the server URL, the tool list, and the client configuration: <https://cloud.docs.scylladb.com/stable/api-docs/mcp.md>
2. Guide the user to create a personal API token: <https://cloud.docs.scylladb.com/stable/api-docs/create-api-token.md>
3. Help the user add the server to their MCP client. Keep the token out of git (see below).
4. Ask the client to list the `scylladb-cloud` tools to confirm the setup.

For Claude Code, use this command:

```bash
claude mcp add --transport http scylladb-cloud https://mcp.cloud.scylladb.com \
  --header "Authorization: Bearer ${SCYLLADB_CLOUD_API_TOKEN}"
```

The default `local` scope stores the token in `~/.claude.json`.

## Keep the Token out of Git

The token gives access to the user's ScyllaDB Cloud account. Never write the token value into a file that is committed to git.

- Store the token in an environment variable, for example `SCYLLADB_CLOUD_API_TOKEN`, and reference the variable from the MCP client configuration.
- Prefer user-level or local MCP configuration over project-level files that are committed (such as `.mcp.json` or `.cursor/mcp.json`).
- If the token must be in a file inside the repository, add that file to `.gitignore` before the user saves the token.
- If a token was committed, tell the user to revoke it in **Settings > Personal Tokens** and create a new one. Removing it from git history is not enough.

## Tools That Change Data

`create_cluster` and `delete_cluster` change the user's account. A new cluster incurs cost, and a deleted cluster cannot be recovered.

- Call them only when the user asks for that action.
- Before the call, show the user the cluster name, ID, and settings, and wait for their confirmation.
- Before `delete_cluster`, ask whether to keep the cluster's backups.
- After `create_cluster`, use `track_cluster_progress` to report progress.
