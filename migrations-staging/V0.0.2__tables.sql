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
    PRIMARY KEY ("ID")
        USING INDEX PCTFREE 10 INITRANS 2 MAXTRANS 255
        TABLESPACE "USERS" ENABLE,
    UNIQUE ("CPF")
        USING INDEX PCTFREE 10 INITRANS 2 MAXTRANS 255
        TABLESPACE "USERS" ENABLE
) SEGMENT CREATION DEFERRED
    PCTFREE 10 PCTUSED 40 INITRANS 1 MAXTRANS 255
    NOCOMPRESS LOGGING
    TABLESPACE "USERS";
