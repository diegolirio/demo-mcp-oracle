---
name: setup-oracle-mcp
description: "Sets up Oracle MCP server (oracledb-mcp-server via uvx) for any Oracle database: local Docker container or remote/existing instance. Creates .mcp.json and optionally compose.yaml, then validates connectivity. Use when the user wants to add Oracle DB access to Claude Code via MCP."
argument-hint: "Optional: --host <host> --port <port> --service <service_name> --user <db-user> --password <db-password> --connection-string <full_string>. If omitted, the skill asks interactively."
---

# Setup Oracle MCP

Configures the `oracledb-mcp-server` MCP server so Claude Code can query an Oracle database directly.
Works transparently with **any** Oracle instance — local Docker container, shared dev/staging, or cloud-hosted.
The skill figures out what infrastructure to set up based on the connection details; the user never chooses a "mode".

## When To Use

- User wants Claude Code to introspect or query an Oracle DB.
- Project needs a local Oracle container for development or integration tests.
- User has an existing Oracle DB and wants MCP access to it.
- `.mcp.json` is missing or has no `oracle-db` entry.

## Auto-Detection (run before asking anything)

Check these sources in order to pre-fill values:

1. **Arguments** passed by the user — highest priority.
2. **Existing `.mcp.json`** — parse `DB_CONNECTION_STRING` if present.
3. **`compose.yaml`** — extract `ORACLE_PASSWORD`, `APP_USER`, `APP_USER_PASSWORD`, port mapping if an `oracle` service exists.
4. **Defaults** — use only when a value cannot be found elsewhere.

| Parameter | Default |
|---|---|
| `db-host` | `localhost` |
| `db-port` | `1521` |
| `service-name` | `FREEPDB1` |
| `db-user` | `app` |
| `db-password` | _(none — must ask)_ |
| `oracle-password` | `secret` |

If the user provides a **full connection string**
(`oracle+oracledb://user:pass@host:port/?service_name=svc`), parse it and skip asking for individual fields.

## Local vs Remote — Transparent Detection

After collecting connection details, determine infrastructure silently:

- **`db-host` is `localhost` or `127.0.0.1`** → _local path_:
  - Check if a Docker oracle container is already running (`docker compose ps oracle` or `docker ps`).
  - If **not running and no `compose.yaml` oracle service** → create `compose.yaml` and start the container.
  - If **already running** → skip Docker steps entirely.
- **Any other host** → _remote path_: skip all Docker steps. Just write `.mcp.json`.

Do **not** ask the user which mode to use — derive it from the host value.

## Procedure

### 1) Collect Parameters — Ask Interactively

Ask only for values that could **not** be auto-detected. Minimum required: `db-password` (never has a safe default).

Ask in a single `AskUserQuestion` call covering all missing fields. Example prompt:

> "To connect to Oracle I need a few details:"
> - **Host** (leave blank for localhost)
> - **Port** (leave blank for 1521)
> - **Service name** (e.g. FREEPDB1, ORCL, XE)
> - **User**
> - **Password** _(required)_
>
> Or paste a full connection string: `oracle+oracledb://user:pass@host:port/?service_name=svc`

If `.mcp.json` already contains an `oracle-db` entry, ask whether to overwrite or skip before proceeding.

### 2) Create or Update compose.yaml (local path only)

Only when `db-host` is `localhost`/`127.0.0.1` **and** no oracle service or running container was found.

If `compose.yaml` already exists and has an `oracle` service, skip (never overwrite existing volumes or data).
Otherwise write the file:

- [compose.yaml template](./references/templates/compose.yaml.template)

### 3) Create or Update .mcp.json

Read existing `.mcp.json` (treat as `{}` if missing).
Merge the `oracle-db` entry under `mcpServers`:

- [.mcp.json template](./references/templates/mcp.json.template)

Connection string format:
```
oracle+oracledb://{db-user}:{db-password}@{db-host}:{db-port}/?service_name={service-name}
```

Both `DB_CONNECTION_STRING` and `COMMENT_DB_CONNECTION_STRING` point to the same string.

### 4) Update .claude/settings.local.json

Ensure `enableAllProjectMcpServers` is `true`.
Merge — do not remove existing permissions or other keys.

- [settings.local.json snippet](./references/templates/settings.local.json.template)

### 5) Start Oracle Container (local path only)

Only when a new `compose.yaml` was written in step 2.

```bash
docker compose up -d oracle
```

Wait for healthy status (up to 90 s):

```bash
docker compose ps oracle
```

If not healthy after 90 s, print the logs and stop:

```bash
docker compose logs oracle
```

### 6) Validate MCP Connectivity

Ask the user to restart Claude Code (or reload MCP servers) so the new `.mcp.json` entry is picked up.

Then run a smoke-test query via the MCP tool if available:

```sql
SELECT 'OK' AS status FROM dual
```

If `mcp__oracle-db__execute_sql` responds, report success.
If not yet available (server not reloaded), print the connection string and instruct the user to restart.

### 7) Print Summary

| Item | Value |
|---|---|
| Oracle host | `{db-host}` |
| Port | `{db-port}` |
| Service | `{service-name}` |
| User | `{db-user}` |
| Docker container | `oracle-db` _(created/used — only if local)_ |
| MCP server | `oracle-db` (uvx oracledb-mcp-server) |
| Connection string | `oracle+oracledb://{db-user}:***@{db-host}:{db-port}/?service_name={service-name}` |

## Troubleshooting

- **Container never becomes healthy** — Oracle Free needs 60–90 s on first start; disk I/O matters.
- **`uvx` not found** — install via `pip install uv` or `brew install uv`.
- **MCP tools not appearing** — restart Claude Code after editing `.mcp.json`.
- **ORA-12541 / connection refused** — for local: confirm `docker compose ps oracle` shows healthy and port 1521 is free. For remote: verify host/port reachability (`telnet {db-host} {db-port}`).
- **ORA-01017 / invalid credentials** — double-check `db-user` and `db-password`; passwords are case-sensitive.
- **`APP_USER` not created** — `gvenzl/oracle-free` creates the app user automatically via `APP_USER` + `APP_USER_PASSWORD` env vars.
- **Firewall / VPN** — for remote DBs, ensure network access to `{db-host}:{db-port}` from the machine running Claude Code.

## Reference Files

- [compose.yaml template](./references/templates/compose.yaml.template)
- [.mcp.json template](./references/templates/mcp.json.template)
- [settings.local.json template](./references/templates/settings.local.json.template)
