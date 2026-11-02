/* SQL Server from Zero — Volume 2
   Chapter 38: CHECKPOINT, KILL, RECONFIGURE, sp_configure and SHUTDOWN
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022).
   Server-level objects: database NorthbridgePractice; the server options 'show advanced options',
   'max server memory (MB)', 'cost threshold for parallelism', 'max degree of parallelism' and
   'backup compression default'. Their values are saved in dbo.Practice_ConfigBefore before any
   change and restored from it; the clean-up block drops NorthbridgePractice. */
USE NorthbridgeLending;
GO


-- ==============================================================
-- Preparation: remove what an earlier run may have left
-- ==============================================================

IF DB_ID(N'NorthbridgePractice') IS NOT NULL
BEGIN
    ALTER DATABASE NorthbridgePractice
    SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE NorthbridgePractice;
END;
GO
DROP TABLE IF EXISTS dbo.Practice_Payment;
DROP TABLE IF EXISTS dbo.Practice_MaintenanceLog;
GO


-- ==============================================================
-- 1. Sessions, connections and requests
-- ==============================================================

-- The user sessions of the server (values differ on every server)
SELECT session_id, login_name, host_name, program_name,
       status, DB_NAME(database_id) AS DatabaseName
FROM sys.dm_exec_sessions
WHERE is_user_process = 1
ORDER BY session_id;
GO

-- My session and its running request
SELECT s.status              AS SessionStatus,
       r.status              AS RequestStatus,
       r.command,
       DB_NAME(r.database_id) AS DatabaseName,
       r.blocking_session_id
FROM sys.dm_exec_sessions AS s
INNER JOIN sys.dm_exec_requests AS r
    ON r.session_id = s.session_id
WHERE s.session_id = @@SPID;                -- my session
GO

-- The network side of my connection
SELECT net_transport, encrypt_option, client_net_address
FROM sys.dm_exec_connections
WHERE session_id = @@SPID;
GO

-- Documented, and undocumented (prefer the DMVs)
EXEC sp_who;
EXEC sp_who2;
GO


-- ==============================================================
-- 2. KILL: ending a session
-- ==============================================================

-- Deliberate error 6104: you cannot kill your own session
DECLARE @Sql NVARCHAR(100) =
    N'KILL ' + CAST(@@SPID AS NVARCHAR(10)) + N';';
EXEC (@Sql);
GO

-- Deliberate error 6106: no session 9999
KILL 9999;
GO

-- NOT RUN BY THE AUTOMATED TEST: needs two query windows
-- (dbo.Practice_Payment is created in section 4)
-- -- Window B: start a transaction and leave it open
-- BEGIN TRANSACTION;
-- UPDATE dbo.Practice_Payment
-- SET AmountPaid = AmountPaid
-- WHERE LoanID = 10196;
-- -- (no COMMIT: the locks stay)
--
-- -- Window A: find the blocker, then end it
-- SELECT session_id, blocking_session_id, wait_type
-- FROM sys.dm_exec_requests
-- WHERE blocking_session_id <> 0;
--
-- KILL 57;                    -- the blocking_session_id found above
-- KILL 57 WITH STATUSONLY;    -- error 6120 once the rollback is over


-- ==============================================================
-- 3. Closing a database: SINGLE_USER, RESTRICTED_USER, MULTI_USER
-- ==============================================================

CREATE DATABASE NorthbridgePractice;
GO

ALTER DATABASE NorthbridgePractice
SET SINGLE_USER WITH ROLLBACK IMMEDIATE;

SELECT name, user_access_desc
FROM sys.databases
WHERE name = N'NorthbridgePractice';
GO

ALTER DATABASE NorthbridgePractice
SET RESTRICTED_USER WITH ROLLBACK IMMEDIATE;

ALTER DATABASE NorthbridgePractice
SET MULTI_USER;

SELECT name, user_access_desc
FROM sys.databases
WHERE name = N'NorthbridgePractice';
GO


-- ==============================================================
-- 4. CHECKPOINT: dirty pages and the log
-- ==============================================================

DROP TABLE IF EXISTS dbo.Practice_Payment;

SELECT *
INTO dbo.Practice_Payment          -- copy of the payments (chapter 12)
FROM dbo.Payment;

UPDATE dbo.Practice_Payment
SET AmountDue = AmountDue + 0.01;  -- a real change on every row
GO

-- Dirty pages of the copy: above zero
SELECT COUNT(*) AS DirtyPages
FROM sys.dm_os_buffer_descriptors AS bd
INNER JOIN sys.allocation_units AS au
    ON au.allocation_unit_id = bd.allocation_unit_id
INNER JOIN sys.partitions AS p
    ON p.hobt_id = au.container_id
WHERE bd.database_id = DB_ID()
  AND bd.is_modified = 1                         -- dirty
  AND p.object_id = OBJECT_ID(N'dbo.Practice_Payment');

CHECKPOINT;
GO

-- After the checkpoint: 0
SELECT COUNT(*) AS DirtyPages
FROM sys.dm_os_buffer_descriptors AS bd
INNER JOIN sys.allocation_units AS au
    ON au.allocation_unit_id = bd.allocation_unit_id
INNER JOIN sys.partitions AS p
    ON p.hobt_id = au.container_id
WHERE bd.database_id = DB_ID()
  AND bd.is_modified = 1
  AND p.object_id = OBJECT_ID(N'dbo.Practice_Payment');
GO

-- A checkpoint spread over 5 seconds
CHECKPOINT 5;
GO


-- ==============================================================
-- 5. sp_configure, RECONFIGURE and sys.configurations
-- ==============================================================

-- Deliberate error 15123: advanced options are hidden
EXEC sys.sp_configure N'max degree of parallelism', 4;
GO

-- Write down before you change (kept if the script is rerun)
IF OBJECT_ID(N'dbo.Practice_ConfigBefore') IS NULL
    SELECT configuration_id, name,
           CAST(value AS INT) AS value       -- sql_variant to INT
    INTO dbo.Practice_ConfigBefore
    FROM sys.configurations
    WHERE name IN (N'show advanced options',
                   N'max server memory (MB)',
                   N'cost threshold for parallelism',
                   N'max degree of parallelism',
                   N'Ad Hoc Distributed Queries',
                   N'backup compression default');
GO

EXEC sys.sp_configure N'show advanced options', 1;
RECONFIGURE;

SELECT name, is_dynamic, is_advanced
FROM sys.configurations
WHERE configuration_id IN
      (SELECT configuration_id FROM dbo.Practice_ConfigBefore)
ORDER BY name;
GO


-- ==============================================================
-- 6. The options a bank changes, and putting them back
-- ==============================================================

EXEC sys.sp_configure N'cost threshold for parallelism', 50;
EXEC sys.sp_configure N'max degree of parallelism', 4;

SELECT name, value, value_in_use
FROM sys.configurations
WHERE name IN (N'cost threshold for parallelism',
               N'max degree of parallelism')
ORDER BY name;
GO

RECONFIGURE;

EXEC sys.sp_configure N'max server memory (MB)', 4096;
EXEC sys.sp_configure N'backup compression default', 1;
RECONFIGURE WITH OVERRIDE;
GO

-- After RECONFIGURE: both columns agree
SELECT name, value, value_in_use
FROM sys.configurations
WHERE name IN (N'cost threshold for parallelism',
               N'max degree of parallelism')
ORDER BY name;
GO

-- Put every changed value back, 'show advanced options' last
DECLARE @Name NVARCHAR(35), @Value INT;

DECLARE config_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT b.name, b.value
    FROM dbo.Practice_ConfigBefore AS b
    INNER JOIN sys.configurations AS c
        ON c.configuration_id = b.configuration_id
    WHERE CAST(c.value AS INT) <> b.value       -- changed since
    ORDER BY CASE WHEN b.name = N'show advanced options'
                  THEN 1 ELSE 0 END,           -- this one last
             b.name;

OPEN config_cursor;
FETCH NEXT FROM config_cursor INTO @Name, @Value;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC sys.sp_configure @configname = @Name, @configvalue = @Value;
    RECONFIGURE;
    FETCH NEXT FROM config_cursor INTO @Name, @Value;
END;
CLOSE config_cursor;
DEALLOCATE config_cursor;
GO

SELECT COUNT(*) AS StillDifferent
FROM dbo.Practice_ConfigBefore AS b
INNER JOIN sys.configurations AS c
    ON c.configuration_id = b.configuration_id
WHERE CAST(c.value AS INT) <> b.value;
GO


-- ==============================================================
-- 7. ALTER DATABASE SCOPED CONFIGURATION
-- ==============================================================

ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 2;

SELECT name, value
FROM sys.database_scoped_configurations
WHERE name = N'MAXDOP';
GO

ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 0;   -- default
GO


-- ==============================================================
-- 8. The error log and SHUTDOWN
-- ==============================================================

SELECT SERVERPROPERTY('ErrorLogFileName') AS ErrorLogFile;

EXEC sys.sp_readerrorlog 0, 1, N'Recovery is complete';
GO

-- NOT RUN BY THE AUTOMATED TEST: SHUTDOWN stops the whole server
-- (and the Docker container). Never run it on a shared server.
-- SHUTDOWN;
-- SHUTDOWN WITH NOWAIT;


-- ==============================================================
-- Applied example: a maintenance window on NorthbridgePractice
-- ==============================================================

-- Step 1. The log table
DROP TABLE IF EXISTS dbo.Practice_MaintenanceLog;

CREATE TABLE dbo.Practice_MaintenanceLog (
    StepNo     INT           NOT NULL
               CONSTRAINT PK_Practice_MaintenanceLog PRIMARY KEY,
    StepName   NVARCHAR(40)  NOT NULL,
    UserAccess NVARCHAR(60)  NOT NULL,
    LoggedAt   DATETIME2(0)  NOT NULL
               CONSTRAINT DF_Practice_MaintenanceLog_At
               DEFAULT SYSDATETIME()
);
GO

-- Step 2. Record the state, then restrict access
INSERT INTO dbo.Practice_MaintenanceLog (StepNo, StepName, UserAccess)
SELECT 1, N'Before the window', user_access_desc
FROM sys.databases
WHERE name = N'NorthbridgePractice';

ALTER DATABASE NorthbridgePractice
SET RESTRICTED_USER WITH ROLLBACK IMMEDIATE;

INSERT INTO dbo.Practice_MaintenanceLog (StepNo, StepName, UserAccess)
SELECT 2, N'Restricted', user_access_desc
FROM sys.databases
WHERE name = N'NorthbridgePractice';
GO

-- Step 3. Work inside the database, then checkpoint
USE NorthbridgePractice;
GO

DROP TABLE IF EXISTS dbo.Practice_RateTable;

SELECT ProductCode, BaseRate
INTO dbo.Practice_RateTable
FROM NorthbridgeLending.dbo.Product;     -- three-part name

UPDATE dbo.Practice_RateTable
SET BaseRate = BaseRate + 0.25;          -- the weekend rate change

CHECKPOINT;                              -- in NorthbridgePractice

INSERT INTO NorthbridgeLending.dbo.Practice_MaintenanceLog
    (StepNo, StepName, UserAccess)
SELECT 3, N'Work done, checkpoint', user_access_desc
FROM sys.databases
WHERE name = N'NorthbridgePractice';
GO

USE NorthbridgeLending;
GO

-- Step 4. Reopen and report
ALTER DATABASE NorthbridgePractice
SET MULTI_USER;

INSERT INTO dbo.Practice_MaintenanceLog (StepNo, StepName, UserAccess)
SELECT 4, N'Reopened', user_access_desc
FROM sys.databases
WHERE name = N'NorthbridgePractice';

SELECT StepNo, StepName, UserAccess
FROM dbo.Practice_MaintenanceLog
ORDER BY StepNo;
GO


-- ==============================================================
-- Clean-up (step 5): restore every setting, remove every object
-- ==============================================================

USE NorthbridgeLending;
GO

-- Server options: restore any value still different from the saved one
IF OBJECT_ID(N'dbo.Practice_ConfigBefore') IS NOT NULL
BEGIN
    DECLARE @Name NVARCHAR(35), @Value INT;

    DECLARE config_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT b.name, b.value
        FROM dbo.Practice_ConfigBefore AS b
        INNER JOIN sys.configurations AS c
            ON c.configuration_id = b.configuration_id
        WHERE CAST(c.value AS INT) <> b.value
        ORDER BY CASE WHEN b.name = N'show advanced options'
                      THEN 1 ELSE 0 END,
                 b.name;

    OPEN config_cursor;
    FETCH NEXT FROM config_cursor INTO @Name, @Value;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC sys.sp_configure @configname = @Name,
                              @configvalue = @Value;
        RECONFIGURE;
        FETCH NEXT FROM config_cursor INTO @Name, @Value;
    END;
    CLOSE config_cursor;
    DEALLOCATE config_cursor;
END;
GO

-- Proof: no option differs from its saved value
SELECT COUNT(*) AS StillDifferent
FROM dbo.Practice_ConfigBefore AS b
INNER JOIN sys.configurations AS c
    ON c.configuration_id = b.configuration_id
WHERE CAST(c.value AS INT) <> b.value;
GO

-- Database scoped MAXDOP back to its default
ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 0;
GO

DROP TABLE IF EXISTS dbo.Practice_ConfigBefore;
DROP TABLE IF EXISTS dbo.Practice_MaintenanceLog;
DROP TABLE IF EXISTS dbo.Practice_Payment;
GO

IF DB_ID(N'NorthbridgePractice') IS NOT NULL
BEGIN
    ALTER DATABASE NorthbridgePractice
    SET SINGLE_USER WITH ROLLBACK IMMEDIATE;   -- in case of visitors
    DROP DATABASE NorthbridgePractice;
END;
GO

SELECT COUNT(*) AS PracticeDatabases
FROM sys.databases
WHERE name = N'NorthbridgePractice';
GO
