# demo-mcp-oracle

Projeto de demonstração do uso de skills do Claude Code para conectar, inspecionar e exportar schemas Oracle via MCP.

---

## Visão geral

```
compose.yaml          → containers Oracle (oracle-db / oracle-db2)
.mcp.json             → servidores MCP configurados para cada banco
migrations-staging/   → DDLs exportados pelo skill sql-dbmigrations-oracle-mcp
```

---

## Pré-requisitos

| Ferramenta | Instalação |
|---|---|
| Docker + Docker Compose | [docs.docker.com](https://docs.docker.com/get-docker/) |
| `uv` / `uvx` | `pip install uv` ou `brew install uv` |
| Claude Code | `npm install -g @anthropic-ai/claude-code` |

---

## Skill 1 — `setup-db-mcp`

Configura um servidor MCP para que o Claude Code consiga consultar um banco de dados diretamente.
Recebe apenas a **connection string** e cuida automaticamente de criar o `compose.yaml`, subir o container e escrever o `.mcp.json`.

### Como usar

No prompt do Claude Code, digite:

```
/setup-db-mcp
```

O skill irá perguntar:

- **Connection string** (obrigatória) — ex.:
  ```
  oracle+oracledb://app:app@localhost:1521/?service_name=FREEPDB1
  ```
- **Nome do servidor MCP** (opcional) — chave usada no `.mcp.json`. Se omitido, será derivado do engine (ex.: `oracle-db`).

### Engines suportados

| Prefixo | Engine |
|---|---|
| `oracle+oracledb://` | Oracle |
| `postgresql://` / `postgres://` | PostgreSQL |
| `mysql://` | MySQL |
| `sqlite:///` | SQLite |

### O que o skill faz

1. Detecta se o host é local (`localhost`) ou remoto.
2. **Local** → verifica se o container já está rodando; se não estiver, cria/inicia via `docker compose`.
3. Escreve (ou atualiza) `.mcp.json` com a entrada do servidor MCP.
4. Valida conectividade com uma query smoke-test.

### Exemplo: dois bancos Oracle locais

```
# Banco 1
oracle+oracledb://app:app@localhost:1521/?service_name=FREEPDB1

# Banco 2
oracle+oracledb://app2:app2@localhost:1522/?service_name=FREEPDB1
```

Resultado em `.mcp.json`:

```json
{
  "mcpServers": {
    "oracle-db": {
      "command": "uvx",
      "args": ["--from", "oracledb-mcp-server", "oracledb_mcp_server"],
      "env": {
        "DB_CONNECTION_STRING": "oracle+oracledb://app:app@localhost:1521/?service_name=FREEPDB1",
        "COMMENT_DB_CONNECTION_STRING": "oracle+oracledb://app:app@localhost:1521/?service_name=FREEPDB1"
      }
    },
    "oracle-db2": {
      "command": "uvx",
      "args": ["--from", "oracledb-mcp-server", "oracledb_mcp_server"],
      "env": {
        "DB_CONNECTION_STRING": "oracle+oracledb://app2:app2@localhost:1522/?service_name=FREEPDB1",
        "COMMENT_DB_CONNECTION_STRING": "oracle+oracledb://app2:app2@localhost:1522/?service_name=FREEPDB1"
      }
    }
  }
}
```

### Troubleshooting

| Sintoma | Solução |
|---|---|
| Container nunca fica healthy | Oracle Free demora 60–90 s no primeiro start; aguarde. |
| `uvx` not found | `pip install uv` |
| MCP tools não aparecem | Reinicie o Claude Code após editar `.mcp.json`. |
| Connection refused | Confirme que o container está healthy e a porta está livre. |
| Credenciais inválidas | Senhas são case-sensitive; verifique user/password na connection string. |

---

## Skill 2 — `sql-dbmigrations-oracle-mcp`

Conecta ao Oracle via MCP e exporta **todos os objetos DDL** do schema como arquivos SQL compatíveis com Flyway, prontos para serem aplicados em outro banco sem erros de dependência.

### Como usar

No prompt do Claude Code, digite:

```
/sql-dbmigrations-oracle-mcp
```

Argumentos opcionais (podem ser passados diretamente):

```
/sql-dbmigrations-oracle-mcp --version 0.0.1 --output migrations-staging/ --mcp oracle-db
```

Se houver mais de um servidor `oracle-*` no `.mcp.json`, o skill pergunta qual usar.

### O que é exportado

| # | Tipo | Motivo da ordem |
|---|---|---|
| 1 | TYPE | Usado em colunas e parâmetros |
| 2 | SEQUENCE | Referenciadas como DEFAULT em colunas |
| 3 | TABLE (sem FK) | Estrutura base |
| 4 | FOREIGN KEY | Após todas as tabelas existirem |
| 5 | INDEX | Após tabelas e constraints |
| 6 | VIEW | Dependem de tabelas |
| 7 | MATERIALIZED VIEW | Dependem de tabelas/views |
| 8 | SYNONYM | Referências a objetos existentes |
| 9 | TRIGGER | Dependem de tabelas |
| 10 | PROCEDURE / FUNCTION | Corpo PL/SQL |
| 11 | PACKAGE (spec → body) | Spec compilada antes do body |
| 12 | COMMENT | Após todos os objetos existirem |

### Arquivos gerados

Os arquivos são criados em `migrations-staging/` seguindo o padrão Flyway:

```
migrations-staging/
  V0.0.1__sequences.sql
  V0.0.2__tables.sql
  V0.0.3__procedures.sql
  V0.0.4__packages.sql
  V0.0.5__comments.sql
```

Cada arquivo tem no máximo 1000 linhas. Statements nunca são cortados no meio.

### Exemplo de arquivo gerado

```sql
-- ============================================================
-- Schema: APP
-- Database: FREEPDB1
-- Exported: 2026-05-17
-- Objects: TABLE
-- ============================================================

-- ------------------------------------------------------------
-- TABLE: CUSTOMERS
-- ------------------------------------------------------------
CREATE TABLE "CUSTOMERS"
(
    "ID"   NUMBER        DEFAULT "CUSTOMERS_SEQ"."NEXTVAL",
    "NAME" VARCHAR2(200) NOT NULL ENABLE,
    "AGE"  NUMBER(3, 0),
    "CPF"  VARCHAR2(11)  NOT NULL ENABLE,
    PRIMARY KEY ("ID") ENABLE,
    UNIQUE ("CPF") ENABLE
);
```

### Troubleshooting

| Sintoma | Solução |
|---|---|
| `ORA-31603` no DBMS_METADATA | Objeto não existe ou nome errado; o skill pula e loga. |
| MCP tool não disponível | Reiniciar Claude Code após editar `.mcp.json`. |
| DDL truncado | O MCP server tem limite de tamanho; o skill quebra em queries individuais. |
| Objeto com status INVALID | Exportado mesmo assim com aviso `-- WARNING: object was INVALID at export time`. |

---

## Fluxo completo (exemplo)

```bash
# 1. Suba os containers Oracle
docker compose up -d

# 2. No Claude Code, configure o MCP para o banco de origem
/setup-db-mcp
# → informe: oracle+oracledb://app:app@localhost:1521/?service_name=FREEPDB1

# 3. Reinicie o Claude Code para carregar o MCP server

# 4. Exporte o schema como migrations Flyway
/sql-dbmigrations-oracle-mcp

# 5. Aplique em outro banco (ex.: com Flyway CLI)
flyway -url=jdbc:oracle:thin:@//target-host:1521/FREEPDB1 \
       -user=app -password=app \
       -locations=filesystem:migrations-staging migrate
```
