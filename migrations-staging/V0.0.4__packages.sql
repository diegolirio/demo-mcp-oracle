-- ============================================================
-- Schema: APP
-- Database: FREEPDB1
-- Exported: 2026-05-17
-- Objects: PACKAGE, PACKAGE BODY
-- ============================================================

-- ------------------------------------------------------------
-- PACKAGE: PKG_CUSTOMERS_QUERY_HANDLER (spec)
-- ------------------------------------------------------------
CREATE OR REPLACE EDITIONABLE PACKAGE "PKG_CUSTOMERS_QUERY_HANDLER" AS
    FUNCTION GET_BY_ID(p_id IN CUSTOMERS.ID%TYPE) RETURN SYS_REFCURSOR;
    FUNCTION GET_BY_CPF(p_cpf IN CUSTOMERS.CPF%TYPE) RETURN SYS_REFCURSOR;
END PKG_CUSTOMERS_QUERY_HANDLER;
/

-- ------------------------------------------------------------
-- PACKAGE BODY: PKG_CUSTOMERS_QUERY_HANDLER
-- ------------------------------------------------------------
CREATE OR REPLACE EDITIONABLE PACKAGE BODY "PKG_CUSTOMERS_QUERY_HANDLER" AS

    FUNCTION GET_BY_ID(p_id IN CUSTOMERS.ID%TYPE) RETURN SYS_REFCURSOR IS
        v_cursor SYS_REFCURSOR;
    BEGIN
        OPEN v_cursor FOR
            SELECT ID, NAME, AGE, CPF
            FROM   CUSTOMERS
            WHERE  ID = p_id;
        RETURN v_cursor;
    END GET_BY_ID;

    FUNCTION GET_BY_CPF(p_cpf IN CUSTOMERS.CPF%TYPE) RETURN SYS_REFCURSOR IS
        v_cursor SYS_REFCURSOR;
    BEGIN
        OPEN v_cursor FOR
            SELECT ID, NAME, AGE, CPF
            FROM   CUSTOMERS
            WHERE  CPF = p_cpf;
        RETURN v_cursor;
    END GET_BY_CPF;

END PKG_CUSTOMERS_QUERY_HANDLER;
/
