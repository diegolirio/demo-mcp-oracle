---
name: setup-db-mcp
description: "Sets up an MCP server (via uvx) for any database: Oracle, PostgreSQL, MySQL, or SQLite. Works with local Docker containers or remote/existing instances. Creates .mcp.json and optionally compose.yaml, then validates connectivity."
argument-hint: "Optional: --engine <oracle|postgres|mysql|sqlite> --host <host> --port <port> --service <service_name> --user <db-user> --password <db-password> --server-name <mcp-server-name> --connection-string <full_string>. If omitted, the skill asks interactively."
---

# Setup Database MCP

Configures an MCP server so Claude Code can query a database directly.
Works with **any** database engine — Oracle, PostgreSQL, MySQL, SQLite, or any engine with a compatible MCP server package.
The skill determines what infrastructure to set up based on the connection details; the user never selects a "mode".

## When To Use

- User wants Claude Code to introspect or query a database.
- Project needs a local database container for development or integration tests.
- User has an existing database and wants MCP access to it.
- `.mcp.json` is missing or has no entry for this database.

## Supported Engines

| Engine | MCP package (uvx) | Entrypoint | Connection string format |
|---|---|---|---|
| Oracle | `oracledb-mcp-server` | `oracledb_mcp_server` | `oracle+oracledb://user:pass@host:port/?service_name=svc` |
| PostgreSQL | `mcp-server-postgres` | `mcp_server_postgres` | `postgresql://user:pass@host:port/dbname` |
| MySQL | `mcp-server-mysql` | `mcp_server_mysql` | `mysql://user:pass@host:port/dbname` |
| SQLite | `mcp-server-sqlite` | `mcp_server_sqlite` | `sqlite:///path/to/db.sqlite` |

Add more engines by following the same pattern.

## Auto-Detection (run before asking anything)

Check these sources in order to pre-fill values:

1. **Arguments** passed by the user — highest priority.
2. **Existing `.mcp.json`** — parse `DB_CONNECTION_STRING` if present.
3. **`compose.yaml`** — extract password, user, and port mapping if a matching service exists.
4. **Defaults** — use only when a value cannot be found elsewhere.

| Parameter | Default |
|---|---|
| `db-engine` | `oracle` |
| `db-host` | `localhost` |
| `db-port` | engine default (Oracle: 1521, PostgreSQL: 5432, MySQL: 3306) |
| `service-name / db-name` | `FREEPDB1` (Oracle) / `app` (others) |
| `db-user` | `app` |
| `db-password` | _(none — must ask)_ |
| `server-name` | `{db-engine}-db` (e.g. `oracle-db`, `postgres-db`) |

If the user provides a **full connection string**, parse it and skip asking for individual fields.

## Local vs Remote — Transparent Detection

After collecting connection details, determine infrastructure silently:

- **`db-host` is `localhost` or `127.0.0.1`** → _local path_:
  - Check if a Docker container is already running (`docker compose ps` or `docker ps`).
  - If **not running and no matching service in `compose.yaml`** → create `compose.yaml` and start the container.
  - If **already running** → skip Docker steps entirely.
- **Any other host** → _remote path_: skip all Docker steps. Just write `.mcp.json`.

Do **not** ask the user which mode to use — derive it from the host value.

## Procedure

### 1) Collect Parameters — Ask Interactively

Ask only for values that could **not** be auto-detected. Minimum required: `db-password` (never has a safe default).

Ask in a single `AskUserQuestion` call covering all missing fields. Example prompt:

> "To connect to the database I need a few details:"
> - **Engine** (oracle / postgres / mysql / sqlite)
> - **Host** (leave blank for localhost)
> - **Port** (leave blank for engine default)
> - **Service / database name**
> - **User**
> - **Password** _(required)_
> - **MCP server name** (leave blank for `{engine}-db`)
>
> Or paste a full connection string.

If `.mcp.json` already contains an entry with the same `server-name`, ask whether to overwrite or skip before proceeding.

### 2) Create or Update compose.yaml (local path only)

Only when `db-host` is `localhost`/`127.0.0.1` **and** no matching container or service was found.

If `compose.yaml` already exists and has the service, skip (never overwrite existing volumes or data).
Otherwise write the file using the appropriate template for the engine:

- [compose.yaml template](./references/templates/compose.yaml.template)

### 3) Create or Update .mcp.json

Read existing `.mcp.json` (treat as `{}` if missing).
Merge the new entry under `mcpServers` using `{server-name}` as the key:

- [.mcp.json template](./references/templates/mcp.json.template)

Build the connection string using the format for the chosen engine (see table above).

Both `DB_CONNECTION_STRING` and `COMMENT_DB_CONNECTION_STRING` point to the same string.

### 4) Start Container (local path only)

Only when a new `compose.yaml` was written in step 2.

```bash
docker compose up -d {service-name}
```

Wait for healthy status (up to 90 s):

```bash
docker compose ps {service-name}
```

If not healthy after 90 s, print the logs and stop:

```bash
docker compose logs {service-name}
```

### 5) Validate Connectivity

Ask the user to restart Claude Code (or reload MCP servers) so the new `.mcp.json` entry is picked up.

Then run a smoke-test query via the MCP tool once it is available. Use a query appropriate for the engine:

| Engine | Smoke query |
|---|---|
| Oracle | `SELECT 'OK' AS status FROM dual` |
| PostgreSQL / MySQL / SQLite | `SELECT 'OK' AS status` |

If the MCP tool responds, report success.
If not yet available (server not reloaded), print the connection string and instruct the user to restart.

### 6) Print Summary

| Item | Value |
|---|---|
| Engine | `{db-engine}` |
| Host | `{db-host}` |
| Port | `{db-port}` |
| Service / DB | `{service-name}` |
| User | `{db-user}` |
| Docker container | `{server-name}` _(created/used — only if local)_ |
| MCP server | `{server-name}` |
| Connection string | `{connection-string-with-password-masked}` |

## Troubleshooting

- **Container never becomes healthy** — Oracle Free needs 60–90 s on first start; other engines are faster.
- **`uvx` not found** — install via `pip install uv` or `brew install uv`.
- **MCP tools not appearing** — restart Claude Code after editing `.mcp.json`.
- **Connection refused** — for local: confirm `docker compose ps` shows healthy and the port is free. For remote: verify reachability (`telnet {db-host} {db-port}`).
- **Invalid credentials** — double-check user and password; passwords are case-sensitive.
- **Firewall / VPN** — for remote DBs, ensure network access to `{db-host}:{db-port}` from the machine running Claude Code.

## Reference Files

- [compose.yaml template](./references/templates/compose.yaml.template)
- [.mcp.json template](./references/templates/mcp.json.template)
