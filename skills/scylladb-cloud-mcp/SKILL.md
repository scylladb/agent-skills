---
name: scylladb-cloud-mcp
description: Help users set up and use the ScyllaDB Cloud MCP server to manage ScyllaDB Cloud clusters via AI agents. Use this skill when a user wants to manage ScyllaDB Cloud programmatically through an AI agent, configure the MCP server, create, delete, or monitor clusters via MCP, or integrate ScyllaDB Cloud management into an agentic workflow. Triggers on "ScyllaDB Cloud MCP", "MCP server ScyllaDB", "manage ScyllaDB with AI agent", "ScyllaDB MCP setup".
---

# ScyllaDB Cloud MCP Server

The ScyllaDB Cloud MCP server exposes the ScyllaDB Cloud API as tools that AI agents can call. It works with any MCP-compatible client (Claude Code, Cursor, OpenCode, and others). The server is in beta.

Full documentation: <https://cloud.docs.scylladb.com/stable/api-docs/mcp.html>

## Step 1: Create a Personal API Token

The MCP server authenticates with a ScyllaDB Cloud personal API token. Guide the user to create one:

1. Sign in to [ScyllaDB Cloud](https://cloud.scylladb.com/account/login).
2. Go to **Settings > Personal Tokens**.
3. Click **Generate Token**.
4. Enter a description and an expiration time (the default is *Never*; suggest a finite expiration).
5. Click **Create** and copy the token from the pop-up window.

The token has the same permissions as the user's role (Admin, Maintainer, or Viewer). A Viewer token cannot create or delete clusters. If the user has more than one ScyllaDB Cloud account, they need a token for each account.

Details: <https://cloud.docs.scylladb.com/stable/api-docs/create-api-token.html>

## Step 2: Keep the Token out of Git

The token gives access to the user's ScyllaDB Cloud account. Never write the token value into a file that is committed to git.

- Store the token in an environment variable, for example `SCYLLADB_CLOUD_API_TOKEN`, and reference the variable from the MCP client configuration.
- Prefer user-level or local MCP configuration over project-level files that are committed (such as `.mcp.json` or `.cursor/mcp.json`).
- If the token must be in a file inside the repository, add that file to `.gitignore` before the user saves the token.
- If a token was committed, tell the user to revoke it in **Settings > Personal Tokens** and create a new one. Removing it from git history is not enough.

## Step 3: Add the Server to the MCP Client

Connection details:

- **Server URL:** `https://mcp.cloud.scylladb.com`
- **Header:** `Authorization: Bearer <PERSONAL_API_TOKEN>`

### Claude Code

```bash
claude mcp add --transport http scylladb-cloud https://mcp.cloud.scylladb.com \
  --header "Authorization: Bearer ${SCYLLADB_CLOUD_API_TOKEN}"
```

The shell expands the variable when the command runs. The default `local` scope stores the configuration in `~/.claude.json`, outside the repository. Do not use `--scope project`: it writes the token to `.mcp.json` in the repository.

### OpenCode

Add the server under the `mcp` key in `opencode.jsonc`:

```json
"mcp": {
  "scylladb-cloud": {
    "type": "remote",
    "url": "https://mcp.cloud.scylladb.com",
    "headers": {
      "Authorization": "Bearer {env:SCYLLADB_CLOUD_API_TOKEN}"
    },
    "timeout": 30000
  }
}
```

### Other Clients

Use the server URL and header above with the client's remote (HTTP) MCP server configuration. Refer to the client's documentation.

After the client connects, ask it to list the `scylladb-cloud` tools to confirm the setup.

## Available Tools

| Tool | Description |
|------|-------------|
| `get_account_info` | Get account details and associated cloud accounts. |
| `list_clusters` | List all clusters with optional metrics. |
| `get_cluster_overview` | Get cluster details, data centers, and nodes in a single call. |
| `get_cluster_health` | Get node health, data center metrics, and cluster-level metrics. |
| `get_cluster_requests` | List cluster operation requests with optional type and status filters, or get details for a specific request. |
| `track_cluster_progress` | Track the progress of a cluster creation request. |
| `monitor_cluster` | Fetch time-series performance metrics for a cluster, broken down by data center. |
| `create_cluster` | Create a new cluster. Walks through the cluster configuration and requires explicit human confirmation. |
| `delete_cluster` | Delete a cluster, with an option to keep its backups. Requires explicit human confirmation. |
| `get_documentation` | Browse API documentation, models, and product documentation. |

## Tools That Change Data

`create_cluster` and `delete_cluster` change the user's account. A new cluster incurs cost, and a deleted cluster cannot be recovered.

- Call them only when the user asks for that action.
- Before the call, show the user the cluster name, ID, and settings, and wait for their confirmation.
- Before `delete_cluster`, ask whether to keep the cluster's backups.
- After `create_cluster`, use `track_cluster_progress` to report progress.
