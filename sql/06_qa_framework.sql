/* =====================================================================
   06_qa_framework.sql
   Reusable QA engine (same as qa_tests.sql Part 1), installed in RetailDWH.
   Run once. The project's checks are in 07_qa_suite.sql.
   ===================================================================== */

USE RetailDWH;
GO

IF SCHEMA_ID('qa') IS NULL
    EXEC('CREATE SCHEMA qa');
GO

IF OBJECT_ID('qa.test_run') IS NULL
CREATE TABLE qa.test_run (
    run_id       INT IDENTITY(1,1) PRIMARY KEY,
    project_name NVARCHAR(100) NOT NULL,
    started_at   DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    finished_at  DATETIME2(0)  NULL
);
GO

IF OBJECT_ID('qa.test_result') IS NULL
CREATE TABLE qa.test_result (
    result_id    INT IDENTITY(1,1) PRIMARY KEY,
    run_id       INT           NOT NULL REFERENCES qa.test_run(run_id),
    test_name    NVARCHAR(200) NOT NULL,
    layer        NVARCHAR(20)  NOT NULL,   -- bronze / silver / gold
    category     NVARCHAR(50)  NOT NULL,   -- completeness, uniqueness, ...
    severity     NVARCHAR(10)  NOT NULL,   -- error / warning
    status       NVARCHAR(10)  NOT NULL,   -- PASS / FAIL / WARN / ERROR
    bad_rows     BIGINT        NULL,
    details      NVARCHAR(400) NULL,
    bad_rows_sql NVARCHAR(MAX) NULL,       -- run this to see the bad rows
    checked_at   DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);
GO

/* ---------- Start a test run ---------- */
CREATE OR ALTER PROCEDURE qa.start_run
    @project_name NVARCHAR(100),
    @run_id       INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO qa.test_run (project_name) VALUES (@project_name);
    SET @run_id = SCOPE_IDENTITY();
END;
GO

/* ---------- Core engine: count bad rows and log the result ----------
   @bad_rows_sql must be a SELECT that returns the bad rows
   (no ORDER BY, unique column names). */
CREATE OR ALTER PROCEDURE qa.run_check
    @run_id       INT,
    @test_name    NVARCHAR(200),
    @layer        NVARCHAR(20),
    @category     NVARCHAR(50),
    @bad_rows_sql NVARCHAR(MAX),
    @severity     NVARCHAR(10)  = N'error',
    @details      NVARCHAR(400) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @n BIGINT;
    DECLARE @count_sql NVARCHAR(MAX) =
        N'SELECT @n = COUNT_BIG(*) FROM (' + @bad_rows_sql + N') AS bad;';

    BEGIN TRY
        EXEC sp_executesql @count_sql, N'@n BIGINT OUTPUT', @n = @n OUTPUT;

        INSERT INTO qa.test_result
            (run_id, test_name, layer, category, severity, status, bad_rows, details, bad_rows_sql)
        VALUES
            (@run_id, @test_name, @layer, @category, @severity,
             CASE WHEN ISNULL(@n, 0) = 0  THEN N'PASS'
                  WHEN @severity = N'warning' THEN N'WARN'
                  ELSE N'FAIL' END,
             ISNULL(@n, 0), @details, @bad_rows_sql);
    END TRY
    BEGIN CATCH
        INSERT INTO qa.test_result
            (run_id, test_name, layer, category, severity, status, bad_rows, details, bad_rows_sql)
        VALUES
            (@run_id, @test_name, @layer, @category, @severity,
             N'ERROR', NULL, LEFT(ERROR_MESSAGE(), 400), @bad_rows_sql);
    END CATCH
END;
GO

/* ---------- Table must not be empty ---------- */
CREATE OR ALTER PROCEDURE qa.check_not_empty
    @run_id INT, @layer NVARCHAR(20),
    @schema SYSNAME, @table SYSNAME
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @t NVARCHAR(300) = QUOTENAME(@schema) + N'.' + QUOTENAME(@table);
    DECLARE @sql NVARCHAR(MAX) =
        N'SELECT 1 AS table_is_empty WHERE NOT EXISTS (SELECT 1 FROM ' + @t + N')';
    DECLARE @name NVARCHAR(200) = N'Not empty: ' + @t;
    EXEC qa.run_check @run_id, @name, @layer, N'completeness', @sql;
END;
GO

/* ---------- Column must not contain NULLs ---------- */
CREATE OR ALTER PROCEDURE qa.check_not_null
    @run_id INT, @layer NVARCHAR(20),
    @schema SYSNAME, @table SYSNAME, @column SYSNAME,
    @severity NVARCHAR(10) = N'error'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @t NVARCHAR(300) = QUOTENAME(@schema) + N'.' + QUOTENAME(@table);
    DECLARE @sql NVARCHAR(MAX) =
        N'SELECT * FROM ' + @t + N' WHERE ' + QUOTENAME(@column) + N' IS NULL';
    DECLARE @name NVARCHAR(200) = N'No NULLs: ' + @t + N'.' + QUOTENAME(@column);
    EXEC qa.run_check @run_id, @name, @layer, N'completeness', @sql, @severity;
END;
GO

/* ---------- Key must be unique (single or composite, comma-separated) ---------- */
CREATE OR ALTER PROCEDURE qa.check_unique
    @run_id INT, @layer NVARCHAR(20),
    @schema SYSNAME, @table SYSNAME, @key_columns NVARCHAR(400)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @t NVARCHAR(300) = QUOTENAME(@schema) + N'.' + QUOTENAME(@table);
    DECLARE @cols NVARCHAR(MAX) =
        (SELECT STRING_AGG(QUOTENAME(TRIM(value)), N', ')
         FROM STRING_SPLIT(@key_columns, N','));
    DECLARE @sql NVARCHAR(MAX) =
        N'SELECT ' + @cols + N', COUNT(*) AS duplicate_count FROM ' + @t +
        N' GROUP BY ' + @cols + N' HAVING COUNT(*) > 1';
    DECLARE @name NVARCHAR(200) = N'Unique key: ' + @t + N' (' + @cols + N')';
    EXEC qa.run_check @run_id, @name, @layer, N'uniqueness', @sql,
         N'error', N'bad_rows = number of duplicated key values';
END;
GO

/* ---------- Every fact key must exist in its dimension ---------- */
CREATE OR ALTER PROCEDURE qa.check_orphans
    @run_id INT, @layer NVARCHAR(20),
    @fact_schema SYSNAME, @fact_table SYSNAME, @fact_column SYSNAME,
    @dim_schema  SYSNAME, @dim_table  SYSNAME, @dim_column  SYSNAME
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @f NVARCHAR(300) = QUOTENAME(@fact_schema) + N'.' + QUOTENAME(@fact_table);
    DECLARE @d NVARCHAR(300) = QUOTENAME(@dim_schema)  + N'.' + QUOTENAME(@dim_table);
    DECLARE @sql NVARCHAR(MAX) =
        N'SELECT f.* FROM ' + @f + N' AS f LEFT JOIN ' + @d + N' AS d ' +
        N'ON f.' + QUOTENAME(@fact_column) + N' = d.' + QUOTENAME(@dim_column) +
        N' WHERE d.' + QUOTENAME(@dim_column) + N' IS NULL' +
        N' AND f.' + QUOTENAME(@fact_column) + N' IS NOT NULL';
    DECLARE @name NVARCHAR(200) =
        N'No orphans: ' + @f + N'.' + QUOTENAME(@fact_column) + N' -> ' + @d;
    EXEC qa.run_check @run_id, @name, @layer, N'integrity', @sql;
END;
GO

/* ---------- Row counts between layers (tolerance in %) ----------
   Use a tolerance when cleaning is expected to remove some rows. */
CREATE OR ALTER PROCEDURE qa.check_row_count
    @run_id INT, @layer NVARCHAR(20),
    @src_schema SYSNAME, @src_table SYSNAME,
    @tgt_schema SYSNAME, @tgt_table SYSNAME,
    @tolerance_pct DECIMAL(5,2) = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @s NVARCHAR(300) = QUOTENAME(@src_schema) + N'.' + QUOTENAME(@src_table);
    DECLARE @t NVARCHAR(300) = QUOTENAME(@tgt_schema) + N'.' + QUOTENAME(@tgt_table);
    DECLARE @tol NVARCHAR(20) = CONVERT(NVARCHAR(20), @tolerance_pct);
    DECLARE @sql NVARCHAR(MAX) =
        N'SELECT s.cnt AS source_rows, t.cnt AS target_rows ' +
        N'FROM (SELECT COUNT_BIG(*) AS cnt FROM ' + @s + N') AS s ' +
        N'CROSS JOIN (SELECT COUNT_BIG(*) AS cnt FROM ' + @t + N') AS t ' +
        N'WHERE ABS(s.cnt - t.cnt) > s.cnt * ' + @tol + N' / 100.0';
    DECLARE @name NVARCHAR(200) = N'Row count: ' + @s + N' vs ' + @t;
    DECLARE @det  NVARCHAR(400) = N'Allowed difference: ' + @tol + N'%';
    EXEC qa.run_check @run_id, @name, @layer, N'reconciliation', @sql, N'error', @det;
END;
GO

/* ---------- Totals must match between layers ---------- */
CREATE OR ALTER PROCEDURE qa.check_sum_match
    @run_id INT, @layer NVARCHAR(20),
    @src_schema SYSNAME, @src_table SYSNAME, @src_column SYSNAME,
    @tgt_schema SYSNAME, @tgt_table SYSNAME, @tgt_column SYSNAME,
    @tolerance DECIMAL(18,4) = 0.01
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @s NVARCHAR(300) = QUOTENAME(@src_schema) + N'.' + QUOTENAME(@src_table);
    DECLARE @t NVARCHAR(300) = QUOTENAME(@tgt_schema) + N'.' + QUOTENAME(@tgt_table);
    DECLARE @tol NVARCHAR(30) = CONVERT(NVARCHAR(30), @tolerance);
    DECLARE @sql NVARCHAR(MAX) =
        N'SELECT s.total AS source_total, t.total AS target_total ' +
        N'FROM (SELECT SUM(CAST(' + QUOTENAME(@src_column) + N' AS DECIMAL(38,4))) AS total FROM ' + @s + N') AS s ' +
        N'CROSS JOIN (SELECT SUM(CAST(' + QUOTENAME(@tgt_column) + N' AS DECIMAL(38,4))) AS total FROM ' + @t + N') AS t ' +
        N'WHERE ABS(ISNULL(s.total, 0) - ISNULL(t.total, 0)) > ' + @tol;
    DECLARE @name NVARCHAR(200) =
        N'Totals match: ' + @s + N'.' + QUOTENAME(@src_column) +
        N' vs ' + @t + N'.' + QUOTENAME(@tgt_column);
    EXEC qa.run_check @run_id, @name, @layer, N'reconciliation', @sql;
END;
GO

/* ---------- Statistical outliers (warning only) ----------
   Flags values more than @z standard deviations from the average. */
CREATE OR ALTER PROCEDURE qa.check_outliers
    @run_id INT, @layer NVARCHAR(20),
    @schema SYSNAME, @table SYSNAME, @column SYSNAME,
    @z DECIMAL(5,2) = 4
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @t NVARCHAR(300) = QUOTENAME(@schema) + N'.' + QUOTENAME(@table);
    DECLARE @c NVARCHAR(300) = QUOTENAME(@column);
    DECLARE @sql NVARCHAR(MAX) =
        N'SELECT x.* FROM ' + @t + N' AS x CROSS JOIN ' +
        N'(SELECT AVG(CAST(' + @c + N' AS FLOAT)) AS a, STDEV(CAST(' + @c + N' AS FLOAT)) AS sd FROM ' + @t + N') AS s ' +
        N'WHERE s.sd > 0 AND ABS(CAST(x.' + @c + N' AS FLOAT) - s.a) > ' +
        CONVERT(NVARCHAR(20), @z) + N' * s.sd';
    DECLARE @name NVARCHAR(200) = N'Outliers: ' + @t + N'.' + @c;
    DECLARE @det  NVARCHAR(400) = N'Values beyond ' + CONVERT(NVARCHAR(20), @z) + N' std devs. Check with client.';
    EXEC qa.run_check @run_id, @name, @layer, N'plausibility', @sql, N'warning', @det;
END;
GO

/* ---------- Report: summary + everything that needs attention ---------- */
CREATE OR ALTER PROCEDURE qa.report
    @run_id INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE qa.test_run SET finished_at = SYSDATETIME() WHERE run_id = @run_id;

    -- 1) Summary
    SELECT status, COUNT(*) AS tests
    FROM qa.test_result
    WHERE run_id = @run_id
    GROUP BY status
    ORDER BY CASE status WHEN 'ERROR' THEN 1 WHEN 'FAIL' THEN 2
                         WHEN 'WARN'  THEN 3 ELSE 4 END;

    -- 2) What needs attention (copy bad_rows_sql to see the rows)
    SELECT status, layer, category, test_name, bad_rows, details, bad_rows_sql
    FROM qa.test_result
    WHERE run_id = @run_id AND status <> 'PASS'
    ORDER BY CASE status WHEN 'ERROR' THEN 1 WHEN 'FAIL' THEN 2 ELSE 3 END,
             layer, test_name;

    -- 3) Full list (useful to attach to client delivery)
    SELECT layer, category, test_name, status, bad_rows
    FROM qa.test_result
    WHERE run_id = @run_id
    ORDER BY layer, category, test_name;
END;
GO


