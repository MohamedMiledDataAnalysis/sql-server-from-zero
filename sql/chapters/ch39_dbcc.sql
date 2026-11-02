/* SQL Server from Zero — Volume 2
   Chapter 39: DBCC commands
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- Server-level objects left by an interrupted run: the global trace flag
-- of section 7 and the clone database of section 8
DBCC TRACEOFF (1222, -1) WITH NO_INFOMSGS;
IF DB_ID(N'NorthbridgeLending_Clone') IS NOT NULL
    DROP DATABASE NorthbridgeLending_Clone;
GO


-- ==============================================================
-- 1. What DBCC is
-- ==============================================================

-- The syntax of one DBCC command
DBCC HELP ('CHECKIDENT');
GO
-- The list of DBCC commands that DBCC HELP documents
DBCC HELP ('?');
GO

-- ==============================================================
-- 2. Checking integrity: CHECKDB and its parts
-- ==============================================================

-- When did CHECKDB last succeed? 1900-01-01 means never
SELECT DATABASEPROPERTYEX(N'NorthbridgeLending',
                          'LastGoodCheckDbTime') AS LastGoodCheckDbTime;
GO
-- Full check, every informational message
DBCC CHECKDB (N'NorthbridgeLending');
GO
-- The same check, silent unless something is wrong
DBCC CHECKDB (N'NorthbridgeLending') WITH NO_INFOMSGS;
GO
-- The light check for busy production servers
DBCC CHECKDB (N'NorthbridgeLending') WITH PHYSICAL_ONLY;
GO
-- How much tempdb space a check would need (no check is run)
DBCC CHECKDB (N'NorthbridgeLending') WITH ESTIMATEONLY;
GO
SELECT CASE
           WHEN CAST(DATABASEPROPERTYEX(N'NorthbridgeLending',
                     'LastGoodCheckDbTime') AS DATETIME) > '2000-01-01'
               THEN N'Checked'
           ELSE N'Never checked'
       END AS CheckStatus;
GO
-- One table, with its informational messages
DBCC CHECKTABLE (N'dbo.Loan');
GO
-- The parts of CHECKDB, one by one
DBCC CHECKTABLE (N'dbo.Payment') WITH NO_INFOMSGS;
DBCC CHECKALLOC (N'NorthbridgeLending') WITH NO_INFOMSGS;
DBCC CHECKCATALOG (N'NorthbridgeLending') WITH NO_INFOMSGS;
DBCC CHECKFILEGROUP (1) WITH NO_INFOMSGS;   -- filegroup 1 is PRIMARY
GO

-- ==============================================================
-- 3. Repair options and single-user mode
-- ==============================================================

-- Deliberate error 7919: a repair needs single-user mode
DBCC CHECKDB (N'NorthbridgeLending', REPAIR_REBUILD) WITH NO_INFOMSGS;
GO
IF @@TRANCOUNT > 0 ROLLBACK;
GO
-- The correct sequence: single user, repair, multi user
ALTER DATABASE NorthbridgeLending
    SET SINGLE_USER WITH ROLLBACK IMMEDIATE;   -- others are cut off
GO
DBCC CHECKDB (N'NorthbridgeLending', REPAIR_REBUILD) WITH NO_INFOMSGS;
GO
ALTER DATABASE NorthbridgeLending
    SET MULTI_USER;                            -- open the doors again
GO
SELECT name, user_access_desc
FROM sys.databases
WHERE name = N'NorthbridgeLending';
GO

-- ==============================================================
-- 4. Constraints and identity values: CHECKCONSTRAINTS, CHECKIDENT
-- ==============================================================

-- Practice copy of dbo.Loan (SELECT INTO, chapter 12)
DROP TABLE IF EXISTS dbo.Practice_Loan;

SELECT *
INTO dbo.Practice_Loan
FROM dbo.Loan;

ALTER TABLE dbo.Practice_Loan
    ADD CONSTRAINT PK_Practice_Loan PRIMARY KEY (LoanID);
GO
-- A rate floor added WITH NOCHECK: existing rows are not checked
ALTER TABLE dbo.Practice_Loan WITH NOCHECK
    ADD CONSTRAINT CK_Practice_Loan_MinRate
        CHECK (InterestRate >= 4.50);
GO
-- One row per violating loan
DBCC CHECKCONSTRAINTS (N'dbo.Practice_Loan');
GO
-- Capture the rows to count them
DROP TABLE IF EXISTS #Violation;

CREATE TABLE #Violation (
    TableName      NVARCHAR(300)   NULL,
    ConstraintName NVARCHAR(300)   NULL,
    WhereClause    NVARCHAR(4000)  NULL
);

INSERT INTO #Violation
EXEC (N'DBCC CHECKCONSTRAINTS (N''dbo.Practice_Loan'')
        WITH NO_INFOMSGS;');

SELECT REPLACE(REPLACE(ConstraintName, N'[', N''), N']', N'')
           AS ConstraintName,
       COUNT(*) AS Violations
FROM #Violation
GROUP BY ConstraintName
ORDER BY ConstraintName;
GO
-- A second rule, then switched off and broken on purpose
ALTER TABLE dbo.Practice_Loan
    ADD CONSTRAINT CK_Practice_Loan_Term
        CHECK (TermMonths BETWEEN 12 AND 360);
GO
ALTER TABLE dbo.Practice_Loan
    NOCHECK CONSTRAINT CK_Practice_Loan_Term;

UPDATE dbo.Practice_Loan
SET TermMonths = 480          -- breaks the disabled rule
WHERE LoanID = 10001;
GO
-- ALL_CONSTRAINTS also checks disabled constraints
TRUNCATE TABLE #Violation;

INSERT INTO #Violation
EXEC (N'DBCC CHECKCONSTRAINTS (N''dbo.Practice_Loan'')
        WITH ALL_CONSTRAINTS, NO_INFOMSGS;');

SELECT REPLACE(REPLACE(ConstraintName, N'[', N''), N']', N'')
           AS ConstraintName,
       COUNT(*) AS Violations
FROM #Violation
GROUP BY ConstraintName
ORDER BY ConstraintName;
GO
-- Disabled and untrusted constraints
SELECT name, is_disabled, is_not_trusted
FROM sys.check_constraints
WHERE parent_object_id = OBJECT_ID(N'dbo.Practice_Loan')
ORDER BY name;
GO

-- An identity table: one arrears case per loan in arrears
DROP TABLE IF EXISTS dbo.Practice_ArrearsCase;

CREATE TABLE dbo.Practice_ArrearsCase (
    CaseID   INT IDENTITY(1,1) NOT NULL
             CONSTRAINT PK_Practice_ArrearsCase PRIMARY KEY,
    LoanID   INT   NOT NULL,
    OpenedOn DATE  NOT NULL
);
GO
INSERT INTO dbo.Practice_ArrearsCase (LoanID, OpenedOn)
SELECT LoanID, '2026-09-30'
FROM dbo.Loan
WHERE LoanStatus = N'Arrears'
ORDER BY LoanID;              -- CaseID follows LoanID order
GO
DBCC CHECKIDENT (N'dbo.Practice_ArrearsCase', NORESEED);
GO
-- Remove five test rows: the identity value does not move back
DELETE FROM dbo.Practice_ArrearsCase
WHERE CaseID > 20;
GO
DBCC CHECKIDENT (N'dbo.Practice_ArrearsCase', NORESEED);
GO
-- Set the identity value to 20: the next row gets 20 + 1
DBCC CHECKIDENT (N'dbo.Practice_ArrearsCase', RESEED, 20);
GO
INSERT INTO dbo.Practice_ArrearsCase (LoanID, OpenedOn)
VALUES (10648, '2026-10-31');

SELECT TOP (3) CaseID, LoanID, OpenedOn
FROM dbo.Practice_ArrearsCase
ORDER BY CaseID DESC;
GO
-- A reseed below the highest value...
DBCC CHECKIDENT (N'dbo.Practice_ArrearsCase', RESEED, 5);
GO
-- ...deliberate error 2627: the next value, 6, already exists
INSERT INTO dbo.Practice_ArrearsCase (LoanID, OpenedOn)
VALUES (10763, '2026-10-31');
GO
IF @@TRANCOUNT > 0 ROLLBACK;
GO
-- The repair: RESEED without a value moves up to the column maximum
DBCC CHECKIDENT (N'dbo.Practice_ArrearsCase', RESEED);
GO
DBCC CHECKIDENT (N'dbo.Practice_ArrearsCase', NORESEED);
GO

-- ==============================================================
-- 5. Space: SQLPERF, UPDATEUSAGE, SHRINKFILE and SHRINKDATABASE
-- ==============================================================

-- Log size and use for every database of the instance
DBCC SQLPERF (LOGSPACE);
GO
-- The same information for the current database, from a DMV
SELECT CAST(total_log_size_in_bytes / 1048576.0 AS DECIMAL(10,2))
           AS LogSizeMB,
       CAST(used_log_space_in_percent AS DECIMAL(5,2)) AS UsedPercent
FROM sys.dm_db_log_space_usage;
GO
-- The files of the database (size is counted in 8-KB pages)
SELECT file_id, name, type_desc, size / 128 AS SizeMB
FROM sys.database_files
ORDER BY file_id;
GO
-- Correct page and row counts in the catalog
DBCC UPDATEUSAGE (0, N'dbo.Payment') WITH COUNT_ROWS, NO_INFOMSGS;
GO
-- Shrink the log file to 8 MB after a checkpoint (chapter 38)
CHECKPOINT;                                   -- chapter 38
DBCC SHRINKFILE (N'NorthbridgeLending_log', 8);
GO
-- Release free space at the end of the data file, moving no page
DBCC SHRINKFILE (N'NorthbridgeLending', TRUNCATEONLY);
GO
-- Shrink every file, leaving 10 percent free space
DBCC SHRINKDATABASE (N'NorthbridgeLending', 10);
GO

-- ==============================================================
-- 6. Informational commands: OPENTRAN, INPUTBUFFER, USEROPTIONS,
--    SHOW_STATISTICS
-- ==============================================================

DBCC OPENTRAN (N'NorthbridgeLending');
GO
-- A named transaction with one change (chapter 32)
BEGIN TRANSACTION rate_review;

UPDATE dbo.Practice_Loan
SET InterestRate = InterestRate + 0.10
WHERE LoanID = 10002;

DBCC OPENTRAN (N'NorthbridgeLending');

SELECT at.name AS TransactionName
FROM sys.dm_tran_active_transactions AS at
INNER JOIN sys.dm_tran_current_transaction AS ct
    ON ct.transaction_id = at.transaction_id;

ROLLBACK TRANSACTION rate_review;
GO
DBCC OPENTRAN (N'NorthbridgeLending');
GO
-- The last batch a session sent: the DMV function...
SELECT event_type, parameters, event_info
FROM sys.dm_exec_input_buffer(@@SPID, NULL);
GO
-- ...and the older DBCC command, which needs a constant session ID
DECLARE @Cmd NVARCHAR(100) =
    N'DBCC INPUTBUFFER (' + CAST(@@SPID AS NVARCHAR(10)) + N');';
EXEC sys.sp_executesql @Cmd;
GO
-- The SET options of the current session
DBCC USEROPTIONS;
GO
-- Statistics recap (chapter 23)
UPDATE STATISTICS dbo.Loan PK_Loan WITH FULLSCAN;

DBCC SHOW_STATISTICS (N'dbo.Loan', PK_Loan) WITH DENSITY_VECTOR;
GO

-- ==============================================================
-- 7. Caches and trace flags (test servers only)
-- ==============================================================

-- Empty the plan cache of the whole instance
DBCC FREEPROCCACHE WITH NO_INFOMSGS;            -- every plan
GO
-- Empty the plans of the current database only
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
-- Empty the data cache: write dirty pages first, then drop clean ones
CHECKPOINT;                                      -- write dirty pages
DBCC DROPCLEANBUFFERS WITH NO_INFOMSGS;          -- drop clean pages
GO
-- Empty every system cache
DBCC FREESYSTEMCACHE ('ALL') WITH NO_INFOMSGS;
GO
-- Trace flag 1222: deadlock details in the error log, for every session
DBCC TRACEON (1222, -1);
GO
DBCC TRACESTATUS (1222);
GO
DBCC TRACEOFF (1222, -1);
GO
DBCC TRACESTATUS (1222);
GO

-- ==============================================================
-- 8. CLONEDATABASE: a schema-only copy
-- ==============================================================

DBCC CLONEDATABASE (NorthbridgeLending, NorthbridgeLending_Clone)
    WITH NO_QUERYSTORE;
GO
SELECT DATABASEPROPERTYEX(N'NorthbridgeLending_Clone', 'IsClone')
           AS IsClone,
       DATABASEPROPERTYEX(N'NorthbridgeLending_Clone', 'Updateability')
           AS Updateability;

SELECT COUNT(*) AS LoanRows
FROM NorthbridgeLending_Clone.dbo.Loan;
GO
-- The statistics travelled with the schema
USE NorthbridgeLending_Clone;
GO
DBCC SHOW_STATISTICS (N'dbo.Loan', PK_Loan) WITH DENSITY_VECTOR;
GO
USE NorthbridgeLending;
GO
DROP DATABASE NorthbridgeLending_Clone;
GO

-- ==============================================================
-- Applied example: a weekly integrity-check routine
-- ==============================================================

-- Step 1. The log table
DROP TABLE IF EXISTS dbo.IntegrityCheckLog;

CREATE TABLE dbo.IntegrityCheckLog (
    CheckID      INT IDENTITY(1,1) NOT NULL
                 CONSTRAINT PK_IntegrityCheckLog PRIMARY KEY,
    CheckType    NVARCHAR(20)    NOT NULL,
    StartedAt    DATETIME2(0)    NOT NULL,
    FinishedAt   DATETIME2(0)    NULL,
    Outcome      NVARCHAR(10)    NOT NULL,
    Violations   INT             NULL,
    ErrorNumber  INT             NULL,
    ErrorMessage NVARCHAR(4000)  NULL
);
GO
-- Step 2. The procedure
CREATE OR ALTER PROCEDURE dbo.usp_WeeklyIntegrityCheck
    @FullCheck BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Started    DATETIME2(0) = SYSDATETIME(),
            @Type       NVARCHAR(20) = CASE WHEN @FullCheck = 1
                                            THEN N'FULL'
                                            ELSE N'PHYSICAL_ONLY' END,
            @Violations INT;

    DECLARE @Violation TABLE (
        TableName      NVARCHAR(300)   NULL,
        ConstraintName NVARCHAR(300)   NULL,
        WhereClause    NVARCHAR(4000)  NULL
    );

    BEGIN TRY
        IF @FullCheck = 1
            DBCC CHECKDB (0) WITH NO_INFOMSGS;      -- 0 = this database
        ELSE
            DBCC CHECKDB (0) WITH PHYSICAL_ONLY, NO_INFOMSGS;

        INSERT INTO @Violation                     -- every constraint
        EXEC (N'DBCC CHECKCONSTRAINTS
                WITH ALL_CONSTRAINTS, NO_INFOMSGS;');
        SET @Violations = @@ROWCOUNT;

        INSERT INTO dbo.IntegrityCheckLog
            (CheckType, StartedAt, FinishedAt, Outcome, Violations)
        VALUES (@Type, @Started, SYSDATETIME(),
                CASE WHEN @Violations = 0 THEN N'OK'
                     ELSE N'WARNING' END,
                @Violations);
    END TRY
    BEGIN CATCH
        INSERT INTO dbo.IntegrityCheckLog
            (CheckType, StartedAt, FinishedAt, Outcome,
             ErrorNumber, ErrorMessage)
        VALUES (@Type, @Started, SYSDATETIME(), N'FAILED',
                ERROR_NUMBER(), ERROR_MESSAGE());
        THROW;                                     -- tell the caller
    END CATCH;
END;
GO
-- Step 3. The Sunday run: full check
EXEC dbo.usp_WeeklyIntegrityCheck @FullCheck = 1;
GO
-- Step 4. Correct the data, trust the constraints again, rerun lighter
UPDATE dbo.Practice_Loan
SET TermMonths = 300                   -- the real term of loan 10001
WHERE LoanID = 10001;

ALTER TABLE dbo.Practice_Loan
    WITH CHECK CHECK CONSTRAINT CK_Practice_Loan_Term;

ALTER TABLE dbo.Practice_Loan          -- existing contracts stay valid
    DROP CONSTRAINT CK_Practice_Loan_MinRate;
GO
EXEC dbo.usp_WeeklyIntegrityCheck @FullCheck = 0;
GO
-- Step 5. Read the log
SELECT CheckID, CheckType, Outcome, Violations, ErrorNumber
FROM dbo.IntegrityCheckLog
ORDER BY CheckID;
GO
-- Step 6. Schedule it with SQL Server Agent
-- NOT RUN BY THE AUTOMATED TEST: SQL Server Agent is not enabled in the
-- default Docker container (MSSQL_AGENT_ENABLED=true enables it), and a
-- job is a server-level object that outlives the database.
/*
EXEC msdb.dbo.sp_add_job
    @job_name = N'Northbridge weekly integrity check';

EXEC msdb.dbo.sp_add_jobstep
    @job_name      = N'Northbridge weekly integrity check',
    @step_name     = N'Full CHECKDB and constraints',
    @subsystem     = N'TSQL',
    @database_name = N'NorthbridgeLending',
    @command       = N'EXEC dbo.usp_WeeklyIntegrityCheck @FullCheck = 1;';

EXEC msdb.dbo.sp_add_schedule
    @schedule_name          = N'Sunday 02:00',
    @freq_type              = 8,        -- weekly
    @freq_interval          = 1,        -- Sunday
    @freq_recurrence_factor = 1,        -- every week
    @active_start_time      = 020000;   -- 02:00:00

EXEC msdb.dbo.sp_attach_schedule
    @job_name      = N'Northbridge weekly integrity check',
    @schedule_name = N'Sunday 02:00';

EXEC msdb.dbo.sp_add_jobserver
    @job_name    = N'Northbridge weekly integrity check',
    @server_name = N'(local)';
*/

-- ==============================================================
-- Clean-up: remove every object created by this chapter
-- ==============================================================

DBCC TRACEOFF (1222, -1) WITH NO_INFOMSGS;
IF DB_ID(N'NorthbridgeLending_Clone') IS NOT NULL
    DROP DATABASE NorthbridgeLending_Clone;
GO
DROP PROCEDURE IF EXISTS dbo.usp_WeeklyIntegrityCheck;
DROP TABLE IF EXISTS dbo.IntegrityCheckLog;
DROP TABLE IF EXISTS dbo.Practice_ArrearsCase;
DROP TABLE IF EXISTS dbo.Practice_Loan;
DROP TABLE IF EXISTS #Violation;
GO
