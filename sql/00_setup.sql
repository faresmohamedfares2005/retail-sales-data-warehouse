/* =====================================================================
   00_setup.sql
   Creates the RetailDWH database, the medallion schemas, and the ETL
   log used by every load procedure.

   Safe to run more than once. Uses a NEW database so your original
   DataWarehouse database is left untouched for comparison.
   ===================================================================== */

IF DB_ID('RetailDWH') IS NULL
    CREATE DATABASE RetailDWH;
GO

USE RetailDWH;
GO

IF SCHEMA_ID('bronze') IS NULL EXEC('CREATE SCHEMA bronze');
GO
IF SCHEMA_ID('silver') IS NULL EXEC('CREATE SCHEMA silver');
GO
IF SCHEMA_ID('gold')   IS NULL EXEC('CREATE SCHEMA gold');
GO
IF SCHEMA_ID('etl')    IS NULL EXEC('CREATE SCHEMA etl');
GO

/* ---------- One row per table per load step ---------- */
IF OBJECT_ID('etl.load_log', 'U') IS NULL
CREATE TABLE etl.load_log (
    log_id        INT IDENTITY(1,1) PRIMARY KEY,
    run_id        UNIQUEIDENTIFIER NOT NULL,
    layer         VARCHAR(10)      NOT NULL,   -- bronze / silver / gold
    table_name    VARCHAR(100)     NOT NULL,
    rows_in       INT              NULL,       -- rows read from the layer below
    rows_loaded   INT              NULL,
    rows_rejected AS (rows_in - rows_loaded),  -- dropped by cleaning rules
    status        VARCHAR(10)      NOT NULL,   -- Success / Failed
    message       NVARCHAR(2000)   NULL,
    started_at    DATETIME2(0)     NOT NULL,
    finished_at   DATETIME2(0)     NOT NULL DEFAULT SYSDATETIME()
);
GO

CREATE OR ALTER PROCEDURE etl.log_step
    @run_id      UNIQUEIDENTIFIER,
    @layer       VARCHAR(10),
    @table_name  VARCHAR(100),
    @rows_in     INT,
    @rows_loaded INT,
    @status      VARCHAR(10),
    @started_at  DATETIME2(0),
    @message     NVARCHAR(2000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO etl.load_log
        (run_id, layer, table_name, rows_in, rows_loaded, status, message, started_at)
    VALUES
        (@run_id, @layer, @table_name, @rows_in, @rows_loaded, @status, @message, @started_at);
END;
GO
