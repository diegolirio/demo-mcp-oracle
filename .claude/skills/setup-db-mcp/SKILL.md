---
name: setup-db-mcp
description: "Sets up an MCP server (via uvx) for any database using a connection string. Writes to ~/.mcp.json using environment variables (no sensitive data in config). Works with local Docker containers or remote/existing instances."
argument-hint: "Optional: --connection-string <full_string> --server-name <mcp-server-name>. If omitted, the skill asks interactively."
---

# Setup Database MCP

Configures an MCP server so Claude Code can query a database directly.
The **only input required is a connection string** — the skill infers engine, host, port, credentials, and infrastructure needs from it automatically.

**Security model**: the connection string is stored only as an environment variable in `~/.bashrc` and `~/.zshrc`. The `~/.mcp.json` config file references it via `${ENV_VAR_NAME}` — no credentials are ever written to any config file.

Works transparently for local Docker containers or any remote database, across all environments (terminal, Claude Code CLI, VS Code, IntelliJ).

## When To Use

- User wants Claude Code to introspect or query a database.
- Project needs a local database container for development or integration tests.
- User has an existing database and wants MCP access to it.
- `./.mcp.json` (local) or `~/.mcp.json` (global) is missing or has no entry for this database.

## Supported Engines (inferred from connection string prefix)

| Prefix | Engine | MCP package (uvx) | Entrypoint |
|---|---|---|---|
| `oracle+oracledb://` | Oracle | `oracledb-mcp-server` | `oracledb_mcp_server` |
| `postgresql://` or `postgres://` | PostgreSQL | `mcp-server-postgres` | `mcp_server_postgres` |
| `mysql://` | MySQL | `mcp-server-mysql` | `mcp_server_mysql` |
| `sqlite:///` | SQLite | `mcp-server-sqlite` | `mcp_server_sqlite` |

Add more engines by following the same pattern.

## Connection String Formats

```
# Oracle
oracle+oracledb://user:password@host:1521/?service_name=FREEPDB1

# PostgreSQL
postgresql://user:password@host:5432/dbname

# MySQL
mysql://user:password@host:3306/dbname

# SQLite
sqlite:///path/to/db.sqlite
```

## Env Var Naming Convention

Derive the env var name from the server name:
- Replace hyphens (`-`) with underscores (`_`)
- Convert to uppercase
- Append `_CONNECTION_STRING`

| Server name | Env var name |
|---|---|
| `oracle-db` | `ORACLE_DB_CONNECTION_STRING` |
| `postgres-db` | `POSTGRES_DB_CONNECTION_STRING` |
| `mysql-db` | `MYSQL_DB_CONNECTION_STRING` |

## Procedure

### 1) Ask for Connection String

Ask in a single `AskUserQuestion` with two fields:

> - **Connection string** _(required)_ — paste the full string, e.g.:
>   `oracle+oracledb://app:secret@localhost:1521/?service_name=FREEPDB1`
> - **MCP server name** _(optional)_ — identifier used as the key in `~/.mcp.json`.
>   Leave blank to auto-derive from the engine (e.g. `oracle-db`, `postgres-db`).

If a connection string was passed as an argument, skip asking and use it directly.

If `~/.mcp.json` already contains an entry with the same server name, ask whether to overwrite or skip.

### 2) Parse the Connection String

Extract from the string:
- **engine** — from the scheme prefix (see table above)
- **host** — the hostname or IP
- **port** — the port number
- **user** — the username
- **server-name** — user-provided or auto-derived as `{engine}-db`
- **env-var-name** — derived from server-name using the convention above

Do **not** ask the user for these individually — derive them from the string.

### 3) Local vs Remote — Transparent Detection

Silently determine infrastructure from the parsed host:

- **`localhost` or `127.0.0.1`** → _local path_:
  - Check if a container is already running (`docker compose ps` or `docker ps`).
  - If **running** → skip Docker steps.
  - If **not running and no matching service in `compose.yaml`** → go to step 4.
  - If **not running but service exists in `compose.yaml`** → just start it (`docker compose up -d`).
- **Any other host** → _remote path_: skip steps 4 and 5 entirely. Go straight to step 6.

### 4) Create compose.yaml (local path only, when no container exists)

Write `compose.yaml` using the template for the detected engine.
Skip entirely if `compose.yaml` already has the service (never overwrite existing volumes or data).

- [compose.yaml template](./references/templates/compose.yaml.template)

### 5) Start Container (local path only)

```bash
docker compose up -d {service-name}
```

Wait for healthy status (up to 90 s):

```bash
docker compose ps {service-name}
```

If not healthy after 90 s, print logs and stop:

```bash
docker compose logs {service-name}
```

### 6) Export Env Var to Shell Profiles

Append the export line to **both** `~/.bashrc` and `~/.zshrc` if not already present.
Use a clearly marked block so the user can find and remove it later.

```bash
# MCP: {server-name}
export {ENV_VAR_NAME}="{connection-string}"
```

Steps:
1. Check if the line already exists in each file to avoid duplicates (`grep -q {ENV_VAR_NAME} ~/.bashrc`).
2. Append only if missing.
3. Run `source ~/.bashrc` (or `~/.zshrc` for the active shell) so the var is immediately available in the current session.

**Do not write the actual connection string to any JSON config file.**

### 7) Write .mcp.json — Both Local and Global

Write the MCP entry to **two files**. Both are **always** created/updated regardless of local or remote database:

#### 7a) Local project file — `./.mcp.json` (ALWAYS generated)

Read existing `./.mcp.json` in the current working directory (treat as `{}` if missing).
Merge the new entry under `mcpServers`. This file is committed with the project and activates the MCP only inside this project.

#### 7b) Global user file — `~/.mcp.json`

Read existing `~/.mcp.json` (treat as `{}` if missing).
Merge the same entry. This activates the MCP across all projects for this user.

---

For **both files**, use `${ENV_VAR_NAME}` as the value of `DB_CONNECTION_STRING` — **never** the literal connection string.

- [.mcp.json template](./references/templates/mcp.json.template)

Replace `${ENV_VAR_NAME}` with the actual var name, e.g. `${ORACLE_DB_CONNECTION_STRING}`.

The resulting entry must look like:

```json
{
  "mcpServers": {
    "oracle-db": {
      "command": "uvx",
      "args": ["--from", "oracledb-mcp-server", "oracledb_mcp_server"],
      "env": {
        "DB_CONNECTION_STRING": "${ORACLE_DB_CONNECTION_STRING}"
      }
    }
  }
}
```

> **Note**: `./.mcp.json` can be committed to the repository — it contains no secrets. Add `~/.mcp.json` to `.gitignore` if the project has one, as it may contain entries from other projects.

### 8) Validate Connectivity

Ask the user to restart Claude Code (or reload MCP servers) so the new `~/.mcp.json` entry is picked up and the env var is resolved.

Once the MCP tool is available, run a smoke-test query:

| Engine | Smoke query |
|---|---|
| Oracle | `SELECT 'OK' AS status FROM dual` |
| PostgreSQL / MySQL / SQLite | `SELECT 'OK' AS status` |

If the MCP tool responds, report success.
If not yet available, print the connection string (with password masked) and instruct the user to restart.

### 9) Print Summary

| Item | Value |
|---|---|
| Engine | `{db-engine}` |
| MCP server | `{server-name}` |
| Env var | `{ENV_VAR_NAME}` |
| Config files | `./.mcp.json` (local project) + `~/.mcp.json` (global) |
| Connection string | `{connection-string-with-password-masked}` |
| Docker container | `{server-name}` _(only if local container was created/used)_ |

## IDE / Environment Notes

- **Terminal**: env var is available after `source ~/.bashrc` or opening a new session.
- **VS Code / IntelliJ launched from terminal**: inherits the shell env — works automatically.
- **GUI app launcher (not from terminal)**: if the IDE does not inherit shell env vars, add the same export line to `~/.profile` manually or launch the IDE from a terminal.
- Claude Code CLI, VS Code Claude extension, and IntelliJ Claude extension all read `~/.mcp.json` and expand `${VAR}` references from the process environment.

## Troubleshooting

- **Env var not found at runtime** — run `echo ${ENV_VAR_NAME}` in the terminal where Claude Code runs; if empty, `source ~/.bashrc` and restart.
- **Container never becomes healthy** — Oracle Free needs 60–90 s on first start; other engines are faster.
- **`uvx` not found** — install via `pip install uv` or `brew install uv`.
- **MCP tools not appearing** — restart Claude Code after editing `~/.mcp.json`.
- **Connection refused** — for local: confirm the container is healthy and the port is free. For remote: verify reachability (`telnet {host} {port}`).
- **Invalid credentials** — passwords are case-sensitive; verify user and password in the connection string.
- **Firewall / VPN** — ensure network access to the remote host and port from the machine running Claude Code.

## Reference Files

- [compose.yaml template](./references/templates/compose.yaml.template)
- [.mcp.json template](./references/templates/mcp.json.template)
