/* SQL Server from Zero — Volume 2
   Chapter 39: DBCC commands — solutions to the exercises
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- Server-level objects left by an interrupted run
DBCC TRACEOFF (3226, -1) WITH NO_INFOMSGS;
IF DB_ID(N'NorthbridgeLending_Clone') IS NOT NULL
    DROP DATABASE NorthbridgeLending_Clone;
GO


-- ==============================================================
-- Correction 39.1
-- ==============================================================

DBCC CHECKTABLE (N'dbo.Payment');                   -- with messages
GO
DBCC CHECKTABLE (N'dbo.Payment') WITH NO_INFOMSGS;  -- errors only
GO

-- ==============================================================
-- Correction 39.2
-- ==============================================================

DBCC TRACEON (3226, -1);        -- on, for every session
GO
DBCC TRACESTATUS (3226);
GO
DBCC TRACEOFF (3226, -1);       -- back to the default
GO
DBCC TRACESTATUS (3226);
GO

-- ==============================================================
-- Correction 39.3
-- ==============================================================

DROP TABLE IF EXISTS dbo.Practice_DefaultCase;

CREATE TABLE dbo.Practice_DefaultCase (
    CaseID   INT IDENTITY(1,1) NOT NULL
             CONSTRAINT PK_Practice_DefaultCase PRIMARY KEY,
    LoanID   INT   NOT NULL,
    OpenedOn DATE  NOT NULL
);
GO
INSERT INTO dbo.Practice_DefaultCase (LoanID, OpenedOn)
SELECT LoanID, '2026-09-30'
FROM dbo.Loan
WHERE LoanStatus = N'Default'
ORDER BY LoanID;                 -- CaseID 1 = loan 10002
GO
DBCC CHECKIDENT (N'dbo.Practice_DefaultCase', NORESEED);
GO

-- ==============================================================
-- Correction 39.4
-- ==============================================================

DROP TABLE IF EXISTS dbo.Practice_Customer;

SELECT *
INTO dbo.Practice_Customer
FROM dbo.Customer;
GO
ALTER TABLE dbo.Practice_Customer WITH NOCHECK
    ADD CONSTRAINT CK_Practice_Customer_Score
        CHECK (CreditScore >= 400);
GO
DBCC CHECKCONSTRAINTS (N'dbo.Practice_Customer');  -- 3 rows
GO
SELECT CustomerID, CreditScore            -- the rows themselves
FROM dbo.Practice_Customer
WHERE CreditScore < 400                   -- NOT (CreditScore >= 400)
ORDER BY CustomerID;

SELECT name, is_not_trusted
FROM sys.check_constraints
WHERE name = N'CK_Practice_Customer_Score';
GO

-- ==============================================================
-- Correction 39.5
-- ==============================================================

IF OBJECT_ID(N'dbo.Practice_Customer') IS NULL
    SELECT * INTO dbo.Practice_Customer FROM dbo.Customer;
GO
BEGIN TRANSACTION fee_correction;

UPDATE dbo.Practice_Customer
SET Phone = '07700900001'
WHERE CustomerID = 1;

DBCC OPENTRAN (N'NorthbridgeLending');     -- Name : fee_correction

SELECT at.name AS TransactionName,
       @@TRANCOUNT AS OpenLevels
FROM sys.dm_tran_active_transactions AS at
INNER JOIN sys.dm_tran_current_transaction AS ct
    ON ct.transaction_id = at.transaction_id;

ROLLBACK TRANSACTION fee_correction;
GO
DBCC OPENTRAN (N'NorthbridgeLending');     -- nothing open
GO

-- ==============================================================
-- Correction 39.6
-- ==============================================================

DELETE FROM dbo.Practice_DefaultCase
WHERE CaseID > 20;                         -- the three test rows
GO
DBCC CHECKIDENT (N'dbo.Practice_DefaultCase', RESEED, 20);
GO
INSERT INTO dbo.Practice_DefaultCase (LoanID, OpenedOn)
VALUES (10545, '2026-10-31');

SELECT TOP (2) CaseID, LoanID, OpenedOn
FROM dbo.Practice_DefaultCase
ORDER BY CaseID DESC;
GO

-- ==============================================================
-- Correction 39.7
-- ==============================================================

DROP TABLE IF EXISTS dbo.Practice_TableCheckLog;

CREATE TABLE dbo.Practice_TableCheckLog (
    TableName NVARCHAR(128)  NOT NULL,
    RowsFound BIGINT         NOT NULL,
    Outcome   NVARCHAR(200)  NOT NULL
);
GO
CREATE OR ALTER PROCEDURE dbo.usp_CheckBaseTables
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Table NVARCHAR(128), @Sql NVARCHAR(400), @Rows BIGINT;

    DECLARE table_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT t.name
        FROM sys.tables AS t
        WHERE t.schema_id = SCHEMA_ID(N'dbo')
          AND t.name NOT LIKE N'Practice[_]%'  -- [_]: a real underscore
        ORDER BY t.name;

    OPEN table_cursor;
    FETCH NEXT FROM table_cursor INTO @Table;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Sql = N'DBCC CHECKTABLE (N''dbo.' + @Table
                 + N''') WITH NO_INFOMSGS;';

        SELECT @Rows = SUM(p.rows)               -- heap or clustered
        FROM sys.partitions AS p
        WHERE p.object_id = OBJECT_ID(N'dbo.' + QUOTENAME(@Table))
          AND p.index_id IN (0, 1);

        BEGIN TRY
            EXEC sys.sp_executesql @Sql;
            INSERT INTO dbo.Practice_TableCheckLog
            VALUES (@Table, @Rows, N'OK');
        END TRY
        BEGIN CATCH
            INSERT INTO dbo.Practice_TableCheckLog
            VALUES (@Table, @Rows, LEFT(ERROR_MESSAGE(), 200));
        END CATCH;

        FETCH NEXT FROM table_cursor INTO @Table;
    END;

    CLOSE table_cursor;
    DEALLOCATE table_cursor;
END;
GO
EXEC dbo.usp_CheckBaseTables;

SELECT TableName, RowsFound, Outcome
FROM dbo.Practice_TableCheckLog
ORDER BY TableName;
GO

-- ==============================================================
-- Correction 39.8
-- ==============================================================

IF DB_ID(N'NorthbridgeLending_Clone') IS NOT NULL
    DROP DATABASE NorthbridgeLending_Clone;
GO
DBCC CLONEDATABASE (NorthbridgeLending, NorthbridgeLending_Clone)
    WITH NO_STATISTICS, NO_QUERYSTORE;
GO
SELECT s.TableName, s.SourceRows, c.CloneRows
FROM (SELECT N'Customer' AS TableName, COUNT(*) AS SourceRows
          FROM dbo.Customer
      UNION ALL SELECT N'Loan', COUNT(*) FROM dbo.Loan
      UNION ALL SELECT N'Payment', COUNT(*) FROM dbo.Payment) AS s
INNER JOIN
     (SELECT N'Customer' AS TableName, COUNT(*) AS CloneRows
          FROM NorthbridgeLending_Clone.dbo.Customer
      UNION ALL SELECT N'Loan', COUNT(*)
          FROM NorthbridgeLending_Clone.dbo.Loan
      UNION ALL SELECT N'Payment', COUNT(*)
          FROM NorthbridgeLending_Clone.dbo.Payment) AS c
    ON c.TableName = s.TableName
ORDER BY s.TableName;
GO
-- Deliberate error 3906: a clone is read-only
INSERT INTO NorthbridgeLending_Clone.dbo.Branch    -- must fail
    (BranchID, BranchName, City, Region, OpenedDate)
VALUES (9, N'Test', N'Test', N'Test', '2026-09-30');
GO
IF @@TRANCOUNT > 0 ROLLBACK;
GO
DROP DATABASE NorthbridgeLending_Clone;
GO

-- ==============================================================
-- Clean-up: remove every object created by the exercises
-- ==============================================================

DBCC TRACEOFF (3226, -1) WITH NO_INFOMSGS;
IF DB_ID(N'NorthbridgeLending_Clone') IS NOT NULL
    DROP DATABASE NorthbridgeLending_Clone;
GO
DROP PROCEDURE IF EXISTS dbo.usp_CheckBaseTables;
DROP TABLE IF EXISTS dbo.Practice_TableCheckLog;
DROP TABLE IF EXISTS dbo.Practice_DefaultCase;
DROP TABLE IF EXISTS dbo.Practice_Customer;
GO
