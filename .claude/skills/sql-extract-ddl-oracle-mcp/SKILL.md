---
name: sql-extract-ddl-oracle-mcp
description: >
  Connects to an Oracle database via MCP and exports all DDL objects (tables,
  sequences, constraints, indexes, views, triggers, procedures, functions,
  packages, types, synonyms) as Flyway-compatible SQL migration files under
  migrations-staging/. Objects are emitted in dependency-safe order so the
  scripts can be applied to a clean schema without errors. Files are split at
  1000 lines and named following the Flyway pattern V{x}.{y}.{z}__{slug}.sql.
  Use when the user asks to export DDLs, reverse-engineer a schema, generate
  migrations from an existing Oracle DB, or mentions "reverse migration",
  "exportar DDL", "gerar migrations", or "migrations-staging".
argument-hint: >
  Optional: --version 0.0.1 --output migrations-staging/ --mcp oracle-db
  If omitted, the skill reads .mcp.json and asks interactively for missing values.
---

# Skill: sql-extract-ddl-oracle-mcp

Conecta ao Oracle via MCP e exporta **todos os objetos DDL** do schema em arquivos
SQL prontos para serem aplicados pelo Flyway em outro banco, sem quebrar.

---

## Quando usar

- Usuário quer exportar/reverter o schema Oracle como migrations.
- Precisa levar estrutura de um ambiente para outro (dev → staging, staging → prod).
- Quer versionar o schema existente no Flyway pela primeira vez.
- Menciona "exportar DDL", "gerar migrations", "reverse engineering", "migrations-staging".

---

## Passo 0 — Auto-detecção de parâmetros

Antes de perguntar qualquer coisa, ler em ordem de prioridade:

1. **Argumentos** passados pelo usuário (`--version`, `--output`, `--mcp`).
2. **`.mcp.json`** — extrair todos os servidores `oracle-*` com suas connection strings.
3. **Defaults**:

| Parâmetro | Default |
|---|---|
| `mcp-server` | `oracle-db` (primeiro oracle-* encontrado no .mcp.json) |
| `output-dir` | `migrations-staging/` |
| `version` | `0.0.1` |
| `max-lines` | `1000` |

Se houver **mais de um servidor oracle-*** no `.mcp.json`, perguntar qual usar via `AskUserQuestion`.

---

## Passo 1 — Confirmar conexão

Usar o MCP tool do servidor detectado para validar conectividade:

```sql
SELECT USER AS schema_name, SYS_CONTEXT('USERENV','DB_NAME') AS db_name FROM DUAL
```

Exibir: `Conectado como <USER> no banco <DB_NAME>`.

Se falhar: orientar o usuário a verificar `.mcp.json` e reiniciar o Claude Code.

---

## Passo 2 — Inventariar objetos do schema

Executar a query de inventário para listar todos os objetos relevantes:

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

Exibir resumo do inventário (contagem por tipo) antes de prosseguir.

---

## Passo 3 — Extrair DDLs em ordem de dependência

**A ordem de emissão é crítica.** Seguir exatamente a sequência abaixo para garantir
que o script possa ser aplicado em um banco limpo sem erros de referência:

### Ordem de exportação

| # | Tipo Oracle | Motivo |
|---|---|---|
| 1 | `TYPE` | Tipos customizados usados em colunas e parâmetros |
| 2 | `SEQUENCE` | Referenciadas como DEFAULT em colunas |
| 3 | `TABLE` (sem FK) | Estrutura base; FK separada para evitar dependência circular |
| 4 | `UNIQUE` e `PRIMARY KEY` constraints | Já embutidos no CREATE TABLE — não reemitir |
| 5 | `FOREIGN KEY` constraints | Após todas as tabelas existirem |
| 6 | `INDEX` (apenas os não-sistema) | Após tabelas e constraints |
| 7 | `VIEW` | Dependem de tabelas |
| 8 | `MATERIALIZED VIEW` | Dependem de tabelas/views |
| 9 | `SYNONYM` | Referências a objetos existentes |
| 10 | `TRIGGER` | Dependem de tabelas |
| 11 | `PROCEDURE` / `FUNCTION` | Corpo PL/SQL |
| 12 | `PACKAGE` (spec primeiro, depois body) | Spec antes de body |
| 13 | `COMMENT` | Após todos os objetos existirem |

### Queries por tipo

#### TYPES
```sql
SELECT DBMS_METADATA.GET_DDL('TYPE', object_name) AS ddl
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

#### TABLES (sem foreign keys — suprimir via transformação)
```sql
-- Para cada tabela, executar individualmente:
SELECT DBMS_METADATA.GET_DDL('TABLE', '<TABLE_NAME>') AS ddl
FROM   DUAL
```

> **Nota:** O DDL retornado pelo DBMS_METADATA inclui PK, UNIQUE e CHECK constraints
> inline. Isso é correto e deve ser mantido. **Foreign keys serão emitidas separadamente.**

Para suprimir FK do DDL da tabela, executar antes de extrair cada tabela:

```sql
BEGIN
  DBMS_METADATA.SET_TRANSFORM_PARAM(
    DBMS_METADATA.SESSION_TRANSFORM, 'REF_CONSTRAINTS', FALSE
  );
END;
```

E restaurar depois:
```sql
BEGIN
  DBMS_METADATA.SET_TRANSFORM_PARAM(
    DBMS_METADATA.SESSION_TRANSFORM, 'REF_CONSTRAINTS', TRUE
  );
END;
```

#### FOREIGN KEYS (após todas as tabelas)
```sql
SELECT c.table_name,
       c.constraint_name,
       DBMS_METADATA.GET_DDL('REF_CONSTRAINT', c.constraint_name) AS ddl
FROM   user_constraints c
WHERE  c.constraint_type = 'R'
ORDER BY c.table_name, c.constraint_name
```

#### INDEXES (apenas os não auto-gerados por PK/UK/sistema)
```sql
SELECT i.index_name,
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

#### PACKAGES (spec antes do body)
```sql
-- Specs
SELECT object_name,
       DBMS_METADATA.GET_DDL('PACKAGE', object_name) AS ddl
FROM   user_objects
WHERE  object_type = 'PACKAGE'
ORDER BY object_name
```
```sql
-- Bodies
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

## Passo 4 — Limpar e formatar os DDLs

Para cada DDL retornado pelo DBMS_METADATA aplicar as seguintes normalizações:

1. **Remover schema qualifier** — substituir `"APP".` (ou o nome do schema atual) por string vazia, para tornar o script portável entre schemas.
2. **Garantir terminador** — cada statement deve terminar com `;`. Para PL/SQL (TRIGGER, PROCEDURE, FUNCTION, PACKAGE, TYPE com corpo), usar `\n/\n` como terminador (Oracle SQL*Plus style).
3. **Remover parâmetros de storage desnecessários** para portabilidade quando não forem semanticamente relevantes (`SEGMENT CREATION DEFERRED`, `PCTFREE`, `PCTUSED`, `INITRANS`, `MAXTRANS`, `NOCOMPRESS`, `LOGGING`, `TABLESPACE "USERS"` são opcionais — **manter ou remover conforme preferência do usuário**; o default é manter para fidelidade).
4. **Cabeçalho por objeto:**
```sql
-- ------------------------------------------------------------
-- <OBJECT_TYPE>: <OBJECT_NAME>
-- ------------------------------------------------------------
```

---

## Passo 5 — Montar e dividir os arquivos

### Estrutura do arquivo

```sql
-- ============================================================
-- Schema: <USER>
-- Database: <DB_NAME>
-- Exported: <YYYY-MM-DD>
-- Objects: <lista resumida de tipos>
-- ============================================================

<DDLs em ordem>
```

### Regra de divisão (max-lines = 1000)

- Acumular DDLs na ordem definida no Passo 3.
- Quando a contagem de linhas do arquivo atual atingir **1000**, fechar o arquivo e
  iniciar o próximo.
- **Nunca dividir no meio de um statement** — completar o objeto atual antes de abrir
  novo arquivo.
- O patch number (terceiro dígito da versão) incrementa a cada arquivo:
  `V0.0.1`, `V0.0.2`, `V0.0.3`, ...

### Naming convention (Flyway)

```
V{major}.{minor}.{patch}__{slug}.sql
```

Regras para o slug:
- Usar o tipo do primeiro objeto do arquivo em snake_case (ex: `sequences`, `tables`, `foreign_keys`).
- Se o arquivo contiver tipos mistos, usar `mixed_objects`.
- Sempre em inglês, lowercase, underscores.

Exemplos:
```
V0.0.1__types.sql
V0.0.2__sequences.sql
V0.0.3__tables.sql
V0.0.4__foreign_keys.sql
V0.0.5__indexes.sql
V0.0.6__views.sql
V0.0.7__triggers.sql
V0.0.8__packages.sql
```

---

## Passo 6 — Criar o diretório e escrever os arquivos

```bash
mkdir -p migrations-staging/
```

Escrever cada arquivo com o Write tool. Confirmar ao usuário o nome de cada arquivo criado.

---

## Passo 7 — Sumário final

Exibir tabela com:

| Arquivo | Objetos incluídos | Linhas |
|---|---|---|
| V0.0.1__sequences.sql | CUSTOMERS_SEQ | 12 |
| V0.0.2__tables.sql | CUSTOMERS | 38 |
| ... | ... | ... |

Indicar se algum objeto foi ignorado (status `INVALID`, `BIN$...`, `SYS_...`) e por quê.

---

## Regras de portabilidade (não quebrar em outro banco)

| Regra | Detalhe |
|---|---|
| Sem schema hardcoded | Remover `"APP".` ou `"SCHEMA".` prefix de todos os DDLs |
| FK separada de TABLE | Evita `ORA-02298` por tabela referenciada ainda não existente |
| PACKAGE spec antes de body | `ORA-04067` se body compilar sem spec |
| TYPE antes de TABLE | `ORA-00902` em colunas com tipo customizado |
| SEQUENCE antes de TABLE | `ORA-02289` no DEFAULT de coluna |
| Terminador PL/SQL com `/` | SQL*Plus / SQLcl exigem `/` após bloco PL/SQL |
| Sem `SEGMENT CREATION IMMEDIATE` hardcoded | Pode falhar em tablespaces sem quota |
| Objetos INVALID no source | Avisar o usuário; exportar mesmo assim (pode haver dependências externas) |

---

## Troubleshooting

- **`ORA-31603` no DBMS_METADATA** — objeto não existe ou nome errado; pular e logar.
- **`ORA-04043` object does not exist** — verificar se o nome é case-sensitive no Oracle (sempre usar aspas duplas ao referenciar).
- **MCP tool não disponível** — reiniciar Claude Code após editar `.mcp.json`.
- **DDL retorna CLOB truncado** — o MCP server pode ter limite de tamanho; quebrar em queries menores por objeto individual.
- **Objeto com status INVALID** — incluir no arquivo mas adicionar comentário `-- WARNING: object was INVALID at export time`.
