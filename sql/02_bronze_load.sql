/* =====================================================================
   02_bronze_load.sql
   bronze.load_bronze: truncates and reloads all 19 bronze tables from
   the CSV folder you pass in.

   Usage
     EXEC bronze.load_bronze @source_path = N'D:\Projects\RetailDWH\datasets\';

   Notes
   - The path is read by the SQL Server service, so it must exist on the
     machine where SQL Server runs and the service account needs read access.
   - Files are UTF-8 with Windows line endings: CODEPAGE 65001, and '\n',
     which BULK INSERT reads as CR+LF.
   - One file failing does not stop the others. Every table is logged in
     etl.load_log, and the procedure raises an error at the end if any
     file failed, so the pipeline stops before silver.
   ===================================================================== */

USE RetailDWH;
GO

CREATE OR ALTER PROCEDURE bronze.load_bronze
    @source_path NVARCHAR(400),
    @run_id      UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @run_id IS NULL SET @run_id = NEWID();
    IF RIGHT(@source_path, 1) <> N'\' SET @source_path = @source_path + N'\';

    DECLARE @tables TABLE (table_name SYSNAME PRIMARY KEY);
    INSERT INTO @tables (table_name) VALUES
        ('brands'), ('customers'), ('deliveries'), ('delivery_providers'),
        ('departments'), ('employees'), ('inventory'), ('online_orders'),
        ('online_order_items'), ('payments'), ('pos_transactions'),
        ('products'), ('product_suppliers'), ('promotions'), ('registers'),
        ('stores'), ('suppliers'), ('transaction_items'), ('warehouses');

    DECLARE @table   SYSNAME,
            @file    NVARCHAR(600),
            @sql     NVARCHAR(MAX),
            @rows    INT,
            @started DATETIME2(0),
            @failed  INT = 0;

    DECLARE table_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT table_name FROM @tables ORDER BY table_name;

    OPEN table_cursor;
    FETCH NEXT FROM table_cursor INTO @table;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @started = SYSDATETIME();
        SET @file = @source_path + UPPER(@table) + N'.csv';

        SET @sql = N'
            TRUNCATE TABLE bronze.' + QUOTENAME(@table) + N';
            BULK INSERT bronze.' + QUOTENAME(@table) + N'
            FROM ''' + REPLACE(@file, N'''', N'''''') + N'''
            WITH (
                FIRSTROW        = 2,
                FIELDTERMINATOR = '','',
                ROWTERMINATOR   = ''\n'',
                CODEPAGE        = ''65001'',
                TABLOCK
            );
            SELECT @rows = COUNT(*) FROM bronze.' + QUOTENAME(@table) + N';';

        BEGIN TRY
            EXEC sp_executesql @sql, N'@rows INT OUTPUT', @rows = @rows OUTPUT;
            EXEC etl.log_step @run_id, 'bronze', @table, NULL, @rows,
                 'Success', @started, @file;
        END TRY
        BEGIN CATCH
            SET @failed += 1;
            DECLARE @err NVARCHAR(2000) = LEFT(@file + N' | ' + ERROR_MESSAGE(), 2000);
            EXEC etl.log_step @run_id, 'bronze', @table, NULL, 0,
                 'Failed', @started, @err;
        END CATCH;

        FETCH NEXT FROM table_cursor INTO @table;
    END;

    CLOSE table_cursor;
    DEALLOCATE table_cursor;

    IF @failed > 0
    BEGIN
        DECLARE @msg NVARCHAR(400) =
            CONCAT(N'Bronze load: ', @failed, N' file(s) failed. See etl.load_log for run ', @run_id, N'.');
        THROW 50001, @msg, 1;
    END;
END;
GO
