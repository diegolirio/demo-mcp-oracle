-- ============================================================
-- Schema: APP
-- Database: FREEPDB1
-- Exported: 2026-05-17
-- Objects: PROCEDURE
-- ============================================================

-- ------------------------------------------------------------
-- PROCEDURE: PROC_INSERT_CUSTOMER_COMMAND_HANDLER
-- ------------------------------------------------------------
CREATE OR REPLACE EDITIONABLE PROCEDURE "PROC_INSERT_CUSTOMER_COMMAND_HANDLER" (
    p_name OUT CUSTOMERS.NAME%TYPE,
    p_age  IN  CUSTOMERS.AGE%TYPE,
    p_cpf  IN  CUSTOMERS.CPF%TYPE,
    p_id   OUT CUSTOMERS.ID%TYPE
) AS
BEGIN
    INSERT INTO CUSTOMERS (NAME, AGE, CPF)
    VALUES (p_name, p_age, p_cpf)
    RETURNING ID INTO p_id;
    COMMIT;
EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        ROLLBACK;
        RAISE_APPLICATION_ERROR(-20001, 'CPF already exists: ' || p_cpf);
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END PROC_INSERT_CUSTOMER_COMMAND_HANDLER;
/
