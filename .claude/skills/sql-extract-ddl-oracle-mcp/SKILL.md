---
name: sql-extract-ddl-oracle-mcp
description: "Connects to an Oracle database via MCP and exports all DDL objects (tables, sequences, constraints, indexes, views, triggers, procedures, functions, packages, types, synonyms) as Flyway-compatible SQL migration files under migrations-staging/. Objects are emitted in dependency-safe order so the scripts can be applied to a clean schema without errors. Files are split at 1000 lines and named following the Flyway pattern V{x}.{y}.{z}__{slug}.sql. Use when the user asks to export DDLs, reverse-engineer a schema, generate migrations from an existing Oracle DB, or mentions \"reverse migration\", \"exportar DDL\", \"gerar migrations\", or \"migrations-staging\"."
argument-hint: "Optional: --version <major.minor.patch> --output <dir> --mcp <server-name>"
---

# Skill: sql-extract-ddl-oracle-mcp

Extracts the complete DDL of an Oracle schema via MCP and writes Flyway-compatible
`.sql` migration files to `./migrations-staging/`.

**Output is exclusively `.sql` files. No shell scripts, no Python scripts, no helper
files of any kind are produced. The only deliverable is the SQL migrations.**

Works in any environment — terminal, Claude Code CLI, VS Code, IntelliJ — because
all work is done through MCP queries and the Write tool, with no dependency on the
local shell beyond `mkdir`.

---

## Step 0 — Auto-detect parameters

Read in priority order:

1. **Arguments** passed by the user (`--version`, `--output`, `--mcp`).
2. **`.mcp.json`** in the current directory — extract every `oracle-*` server.
3. **Defaults**:

| Parameter | Default |
|---|---|
| `mcp-server` | First `oracle-*` entry found in `.mcp.json` |
| `output-dir` | `./migrations-staging/` |
| `version` | `0.0.1` |
| `max-lines` | `1000` |

### If `.mcp.json` is missing or has no `oracle-*` server

**Stop immediately** and show:

> **No Oracle MCP server found.**
>
> This skill requires an Oracle MCP server configured in `.mcp.json`.
> Run `/setup-db-mcp` first to set up the connection, then restart Claude Code
> and run `/sql-extract-ddl-oracle-mcp` again.

Do not proceed to Step 1 until at least one `oracle-*` server exists in `.mcp.json`.

If **more than one** `oracle-*` server is found, ask the user which one to use via
`AskUserQuestion`. Otherwise, proceed silently.

---

## Step 1 — Verify connectivity

Run through the MCP server:

```sql
SELECT USER AS schema_name,
       SYS_CONTEXT('USERENV','DB_NAME') AS db_name
FROM   DUAL
```

Report: `Connected as <USER> on <DB_NAME>.`

On failure: tell the user to check `.mcp.json` and restart Claude Code.

---

## Step 2 — Inventory objects

```sql
SELECT object_type, object_name, status
FROM   user_objects
WHERE  object_type IN (
         'TYPE', 'SEQUENCE', 'TABLE', 'INDEX', 'VIEW',
         'MATERIALIZED VIEW', 'SYNONYM', 'TRIGGER',
         'PROCEDURE', 'FUNCTION', 'PACKAGE', 'PACKAGE BODY'
       )
  AND  object_name NOT LIKE 'SYS_%'
  AND  object_name NOT LIKE 'BIN$%'
ORDER BY object_type, object_name
```

Show a count-by-type summary before continuing.

---

## Step 2.1 — Collect tablespace assignments

Store in memory — used in Steps 3 and 4.

**Table tablespaces:**
```sql
SELECT table_name, tablespace_name
FROM   user_tables
WHERE  tablespace_name IS NOT NULL
ORDER BY table_name
```

**Index tablespaces:**
```sql
SELECT index_name, table_name, tablespace_name
FROM   user_indexes
WHERE  tablespace_name IS NOT NULL
  AND  index_name NOT LIKE 'SYS_%'
  AND  index_name NOT LIKE 'BIN$%'
ORDER BY index_name
```

If the connected user is not the schema owner, use `all_tables` / `all_indexes`
filtered by `owner = '<SCHEMA_NAME>'`.

---

## Step 3 — Extract DDLs in dependency-safe order

**This order is mandatory. Do not deviate.**

| # | Object type | Reason |
|---|---|---|
| 1 | `TYPE` | Used in column definitions and PL/SQL signatures |
| 2 | `SEQUENCE` | Referenced as DEFAULT in columns |
| 3 | `TABLE` (no FK) | Base structure; FK emitted separately to avoid circular deps |
| 4 | `FOREIGN KEY` | After all tables exist |
| 5 | `INDEX` (non-system) | After tables and constraints |
| 6 | `VIEW` | Depends on tables |
| 7 | `MATERIALIZED VIEW` | Depends on tables/views |
| 8 | `SYNONYM` | References existing objects |
| 9 | `TRIGGER` | Depends on tables |
| 10 | `PROCEDURE` / `FUNCTION` | PL/SQL bodies |
| 11 | `PACKAGE` spec, then `PACKAGE BODY` | Spec must precede body |
| 12 | `COMMENT` | After all objects exist |

### Extraction queries

#### TYPES
```sql
SELECT object_name,
       DBMS_METADATA.GET_DDL('TYPE', object_name) AS ddl
FROM   user_objects
WHERE  object_type = 'TYPE'
  AND  object_name NOT LIKE 'SYS_%'
ORDER BY object_name
```

#### SEQUENCES
```sql
SELECT object_name,
       DBMS_METADATA.GET_DDL('SEQUENCE', object_name) AS ddl
FROM   user_objects
WHERE  object_type = 'SEQUENCE'
ORDER BY object_name
```

#### TABLES — suppress FK, then restore

```sql
BEGIN
  DBMS_METADATA.SET_TRANSFORM_PARAM(
    DBMS_METADATA.SESSION_TRANSFORM, 'REF_CONSTRAINTS', FALSE
  );
END;
```

For each table individually:
```sql
SELECT DBMS_METADATA.GET_DDL('TABLE', '<TABLE_NAME>') AS ddl FROM DUAL
```

Restore FK emission after all tables are extracted:
```sql
BEGIN
  DBMS_METADATA.SET_TRANSFORM_PARAM(
    DBMS_METADATA.SESSION_TRANSFORM, 'REF_CONSTRAINTS', TRUE
  );
END;
```

PK/UK constraints are inline in `CREATE TABLE` — do not re-emit them separately.

#### FOREIGN KEYS
```sql
SELECT c.table_name,
       c.constraint_name,
       DBMS_METADATA.GET_DDL('REF_CONSTRAINT', c.constraint_name) AS ddl
FROM   user_constraints c
WHERE  c.constraint_type = 'R'
ORDER BY c.table_name, c.constraint_name
```

#### INDEXES (non-system, non-PK/UK)
```sql
SELECT i.index_name, i.tablespace_name,
       DBMS_METADATA.GET_DDL('INDEX', i.index_name) AS ddl
FROM   user_indexes i
WHERE  i.index_type != 'LOB'
  AND  NOT EXISTS (
         SELECT 1 FROM user_constraints c
         WHERE  c.index_name = i.index_name
           AND  c.constraint_type IN ('P', 'U')
       )
  AND  i.index_name NOT LIKE 'SYS_%'
  AND  i.index_name NOT LIKE 'BIN$%'
ORDER BY i.index_name
```

#### VIEWS
```sql
SELECT object_name,
       DBMS_METADATA.GET_DDL('VIEW', object_name) AS ddl
FROM   user_objects
WHERE  object_type = 'VIEW'
ORDER BY object_name
```

#### MATERIALIZED VIEWS
```sql
SELECT object_name,
       DBMS_METADATA.GET_DDL('MATERIALIZED_VIEW', object_name) AS ddl
FROM   user_objects
WHERE  object_type = 'MATERIALIZED VIEW'
ORDER BY object_name
```

#### SYNONYMS
```sql
SELECT object_name,
       DBMS_METADATA.GET_DDL('SYNONYM', object_name) AS ddl
FROM   user_objects
WHERE  object_type = 'SYNONYM'
ORDER BY object_name
```

#### TRIGGERS
```sql
SELECT object_name,
       DBMS_METADATA.GET_DDL('TRIGGER', object_name) AS ddl
FROM   user_objects
WHERE  object_type = 'TRIGGER'
ORDER BY object_name
```

#### PROCEDURES
```sql
SELECT object_name,
       DBMS_METADATA.GET_DDL('PROCEDURE', object_name) AS ddl
FROM   user_objects
WHERE  object_type = 'PROCEDURE'
ORDER BY object_name
```

#### FUNCTIONS
```sql
SELECT object_name,
       DBMS_METADATA.GET_DDL('FUNCTION', object_name) AS ddl
FROM   user_objects
WHERE  object_type = 'FUNCTION'
ORDER BY object_name
```

#### PACKAGES — spec before body
```sql
SELECT object_name,
       DBMS_METADATA.GET_DDL('PACKAGE', object_name) AS ddl
FROM   user_objects
WHERE  object_type = 'PACKAGE'
ORDER BY object_name
```
```sql
SELECT object_name,
       DBMS_METADATA.GET_DDL('PACKAGE_BODY', object_name) AS ddl
FROM   user_objects
WHERE  object_type = 'PACKAGE BODY'
ORDER BY object_name
```

#### COMMENTS
```sql
SELECT 'COMMENT ON TABLE "' || table_name || '" IS ''' ||
       REPLACE(comments, '''', '''''') || ''';' AS ddl
FROM   user_tab_comments
WHERE  comments IS NOT NULL
ORDER BY table_name
```
```sql
SELECT 'COMMENT ON COLUMN "' || table_name || '"."' || column_name ||
       '" IS ''' || REPLACE(comments, '''', '''''') || ''';' AS ddl
FROM   user_col_comments
WHERE  comments IS NOT NULL
ORDER BY table_name, column_name
```

---

## Step 4 — Normalize DDL text

Apply to every DDL string returned by DBMS_METADATA before writing to disk:

1. **Strip schema qualifier** — remove `"<SCHEMA_NAME>".` prefix everywhere to make
   scripts portable across schemas.
2. **Enforce terminator** — end each DML/DDL statement with `;`. End every PL/SQL
   block (TYPE body, TRIGGER, PROCEDURE, FUNCTION, PACKAGE, PACKAGE BODY) with `\n/\n`.
3. **Always include TABLESPACE** — append `TABLESPACE <name>` to every `CREATE TABLE`
   and `CREATE INDEX`. Add `USING INDEX TABLESPACE <name>` to inline PK/UK constraints.
   Use the values collected in Step 2.1. **Never omit tablespace clauses.**
4. **Strip storage noise** — remove `SEGMENT CREATION DEFERRED`, `PCTFREE`, `PCTUSED`,
   `INITRANS`, `MAXTRANS`, `NOCOMPRESS`, `LOGGING`, `NOPARALLEL` for portability.
5. **Per-object header:**
```sql
-- ------------------------------------------------------------
-- <OBJECT_TYPE>: <OBJECT_NAME>
-- ------------------------------------------------------------
```
6. **INVALID objects** — include in output but prepend:
   `-- WARNING: object was INVALID at export time`

---

## Step 5 — Assemble and split files

### File header (top of every file)
```sql
-- ============================================================
-- Schema  : <USER>
-- Database: <DB_NAME>
-- Exported: <YYYY-MM-DD>
-- File    : <filename>
-- ============================================================
```

### Split rule

- Accumulate DDLs in the order from Step 3.
- When line count reaches **1000**, close the current file and open the next.
- **Never split a statement in the middle** — always complete the current object before
  opening a new file.
- The patch number increments per file: `V0.0.1`, `V0.0.2`, `V0.0.3`, ...

### File naming (Flyway convention)

```
migrations-staging/V{major}.{minor}.{patch}__{slug}.sql
```

Slug rules:
- Use the dominant object type of the file in lowercase snake_case:
  `types`, `sequences`, `tables`, `foreign_keys`, `indexes`, `views`,
  `materialized_views`, `synonyms`, `triggers`, `procedures`, `functions`,
  `packages`, `comments`.
- If a file contains mixed types, use `mixed_objects`.
- Always English, lowercase, underscores only.

---

## Step 6 — Write the SQL files

Create the output directory:
```bash
mkdir -p migrations-staging
```

Write **every file using the Write tool** — one call per `.sql` file.

**Absolute rule: no other file types are ever created. No shell scripts, no Python
scripts, no Makefiles, no README files, no intermediate artifacts of any kind.
The only output of this skill is `.sql` files inside `./migrations-staging/`.**

Confirm each file name to the user as it is written.

---

## Step 7 — Final summary

| File | Object types | Object count | Lines |
|---|---|---|---|
| V0.0.1__types.sql | TYPE | 2 | 45 |
| V0.0.2__sequences.sql | SEQUENCE | 5 | 30 |
| V0.0.3__tables.sql | TABLE | 12 | 320 |
| ... | ... | ... | ... |

List any skipped objects (INVALID, `BIN$...`, `SYS_...`) with the reason.

---

## Portability rules (never break on a clean schema)

| Rule | Detail |
|---|---|
| Tablespace always explicit | `TABLESPACE` on TABLE; `USING INDEX TABLESPACE` on PK/UK inline constraints |
| No hardcoded schema prefix | Strip `"SCHEMA".` from all DDL text |
| FK after all tables | Prevents `ORA-02298` |
| PACKAGE spec before body | Prevents `ORA-04067` |
| TYPE before TABLE | Prevents `ORA-00902` on custom-type columns |
| SEQUENCE before TABLE | Prevents `ORA-02289` on column DEFAULT |
| PL/SQL terminated with `/` | Required by SQL*Plus and SQLcl |
| No `SEGMENT CREATION IMMEDIATE` | Fails on tablespaces without quota |
| INVALID objects flagged | Included with warning comment; never silently dropped |

---

## Troubleshooting

- **`ORA-31603`** — object does not exist or name is wrong; skip and log.
- **`ORA-04043`** — name may be case-sensitive; always quote identifiers.
- **MCP tool not available** — restart Claude Code after editing `.mcp.json`.
- **CLOB truncated** — query objects individually instead of in bulk.
- **`ORA-01031` insufficient privileges** — grant `SELECT_CATALOG_ROLE` to the
  connected user or connect as the schema owner.
