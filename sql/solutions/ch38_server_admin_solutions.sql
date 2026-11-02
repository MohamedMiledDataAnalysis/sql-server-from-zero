/* SQL Server from Zero — Volume 2
   Chapter 38: CHECKPOINT, KILL, RECONFIGURE, sp_configure and SHUTDOWN — solutions to the exercises
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022).
   Server-level objects: database NorthbridgePractice (exercise 38.3) and the server options
   'show advanced options', 'cost threshold for parallelism' and 'backup compression default'.
   Every exercise restores the options it changes; the clean-up block checks them against a
   snapshot taken at the start and drops NorthbridgePractice. */
USE NorthbridgeLending;
GO


-- ==============================================================
-- Setup: a snapshot of every server option, taken before any change
-- ==============================================================

DROP TABLE IF EXISTS dbo.Practice_Saved384;
DROP TABLE IF EXISTS dbo.Practice_ConfigBaseline;
DROP PROCEDURE IF EXISTS dbo.usp_KillSessionsOfLogin;
GO
IF OBJECT_ID(N'dbo.Practice_SolutionsStart') IS NULL
    SELECT configuration_id, name, CAST(value AS INT) AS value
    INTO dbo.Practice_SolutionsStart
    FROM sys.configurations;
GO


-- ==============================================================
-- Correction 38.1
-- ==============================================================

SELECT s.status   AS SessionStatus,
       r.status   AS RequestStatus,
       r.command,
       CASE WHEN s.session_id = @@SPID THEN 1 ELSE 0 END
                  AS IsMySession
FROM sys.dm_exec_sessions AS s
INNER JOIN sys.dm_exec_requests AS r
    ON r.session_id = s.session_id
WHERE s.session_id = @@SPID;
GO


-- ==============================================================
-- Correction 38.2
-- ==============================================================

SELECT name, is_dynamic, is_advanced
FROM sys.configurations
WHERE name IN (N'max server memory (MB)',
               N'cost threshold for parallelism',
               N'backup compression default',
               N'remote access')
ORDER BY name;
GO


-- ==============================================================
-- Correction 38.3
-- ==============================================================

IF DB_ID(N'NorthbridgePractice') IS NULL
    CREATE DATABASE NorthbridgePractice;
GO

ALTER DATABASE NorthbridgePractice
SET SINGLE_USER WITH ROLLBACK IMMEDIATE;

SELECT name, user_access_desc
FROM sys.databases
WHERE name = N'NorthbridgePractice';

ALTER DATABASE NorthbridgePractice
SET MULTI_USER;

SELECT name, user_access_desc
FROM sys.databases
WHERE name = N'NorthbridgePractice';
GO


-- ==============================================================
-- Correction 38.4
-- ==============================================================

DROP TABLE IF EXISTS dbo.Practice_Saved384;

SELECT name, CAST(value AS INT) AS value     -- the originals
INTO dbo.Practice_Saved384
FROM sys.configurations
WHERE name IN (N'show advanced options',
               N'cost threshold for parallelism');
GO

EXEC sys.sp_configure N'show advanced options', 1;
RECONFIGURE;
EXEC sys.sp_configure N'cost threshold for parallelism', 30;
-- no RECONFIGURE here: configured value only

SELECT name, value, value_in_use
FROM sys.configurations
WHERE name IN (N'show advanced options',
               N'cost threshold for parallelism')
ORDER BY name;
GO

-- put both back, advanced option first
DECLARE @Cost INT, @Show INT;
SELECT @Cost = value FROM dbo.Practice_Saved384
WHERE name = N'cost threshold for parallelism';
SELECT @Show = value FROM dbo.Practice_Saved384
WHERE name = N'show advanced options';

EXEC sys.sp_configure N'cost threshold for parallelism', @Cost;
RECONFIGURE;
EXEC sys.sp_configure N'show advanced options', @Show;
RECONFIGURE;
DROP TABLE dbo.Practice_Saved384;
GO


-- ==============================================================
-- Correction 38.5
-- ==============================================================

ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 1;

SELECT
    (SELECT CAST(value_in_use AS INT)
     FROM sys.configurations
     WHERE name = N'max degree of parallelism')   AS ServerMaxdop,
    (SELECT CAST(value AS INT)
     FROM sys.database_scoped_configurations
     WHERE name = N'MAXDOP')                      AS DatabaseMaxdop;

ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 0;
GO


-- ==============================================================
-- Correction 38.6
-- ==============================================================

SELECT s.session_id,
       s.login_name,
       s.status,
       DB_NAME(s.database_id)            AS DatabaseName,
       s.open_transaction_count,
       ISNULL(r.blocking_session_id, 0)  AS BlockedBy
FROM sys.dm_exec_sessions AS s
LEFT JOIN sys.dm_exec_requests AS r
    ON r.session_id = s.session_id
WHERE s.is_user_process = 1
  AND s.session_id <> @@SPID               -- not me
ORDER BY s.session_id;
GO


-- ==============================================================
-- Correction 38.7
-- ==============================================================

CREATE OR ALTER PROCEDURE dbo.usp_KillSessionsOfLogin
    @LoginName SYSNAME,
    @Execute   BIT = 0                 -- 0: print only
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Sql NVARCHAR(MAX), @Found INT;

    SELECT @Found = COUNT(*),
           @Sql = STRING_AGG(
                     CAST(N'KILL ' AS NVARCHAR(MAX))
                     + CAST(session_id AS NVARCHAR(10)) + N';',
                     NCHAR(10))
    FROM sys.dm_exec_sessions
    WHERE login_name = @LoginName
      AND is_user_process = 1
      AND session_id <> @@SPID;        -- never my own session

    PRINT CONCAT(@Found, N' session(s) found for ', @LoginName, N'.');

    IF @Found > 0
    BEGIN
        PRINT @Sql;                    -- what would run
        IF @Execute = 1
            EXEC (@Sql);
    END;
END;
GO

EXEC dbo.usp_KillSessionsOfLogin @LoginName = N'nb_batch_user',
                                 @Execute = 0;
GO


-- ==============================================================
-- Correction 38.8
-- ==============================================================

DROP TABLE IF EXISTS dbo.Practice_ConfigBaseline;

SELECT configuration_id, name, CAST(value AS INT) AS value
INTO dbo.Practice_ConfigBaseline
FROM sys.configurations;
GO

EXEC sys.sp_configure N'show advanced options', 1;
RECONFIGURE;
EXEC sys.sp_configure N'backup compression default', 1;
EXEC sys.sp_configure N'cost threshold for parallelism', 40;
RECONFIGURE;
GO

SELECT b.name,
       b.value                 AS SavedValue,
       CAST(c.value AS INT)    AS CurrentValue
FROM dbo.Practice_ConfigBaseline AS b
INNER JOIN sys.configurations AS c
    ON c.configuration_id = b.configuration_id
WHERE CAST(c.value AS INT) <> b.value
ORDER BY b.name;
GO

DECLARE @Name NVARCHAR(35), @Value INT;
DECLARE drift_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT b.name, b.value
    FROM dbo.Practice_ConfigBaseline AS b
    INNER JOIN sys.configurations AS c
        ON c.configuration_id = b.configuration_id
    WHERE CAST(c.value AS INT) <> b.value
    ORDER BY CASE WHEN b.name = N'show advanced options'
                  THEN 1 ELSE 0 END, b.name;
OPEN drift_cursor;
FETCH NEXT FROM drift_cursor INTO @Name, @Value;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC sys.sp_configure @configname = @Name, @configvalue = @Value;
    RECONFIGURE;
    FETCH NEXT FROM drift_cursor INTO @Name, @Value;
END;
CLOSE drift_cursor;
DEALLOCATE drift_cursor;
GO

SELECT COUNT(*) AS Differences
FROM dbo.Practice_ConfigBaseline AS b
INNER JOIN sys.configurations AS c
    ON c.configuration_id = b.configuration_id
WHERE CAST(c.value AS INT) <> b.value;
GO


-- ==============================================================
-- Clean-up: every option as at the start, every object removed
-- ==============================================================

-- Safety net: restore anything still different from the start snapshot
DECLARE @Name NVARCHAR(35), @Value INT;
DECLARE restore_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT b.name, b.value
    FROM dbo.Practice_SolutionsStart AS b
    INNER JOIN sys.configurations AS c
        ON c.configuration_id = b.configuration_id
    WHERE CAST(c.value AS INT) <> b.value
    ORDER BY CASE WHEN b.name = N'show advanced options'
                  THEN 1 ELSE 0 END, b.name;
OPEN restore_cursor;
FETCH NEXT FROM restore_cursor INTO @Name, @Value;
WHILE @@FETCH_STATUS = 0
BEGIN
    -- advanced options need 'show advanced options' = 1 while they change
    IF @Name <> N'show advanced options'
       AND (SELECT CAST(value_in_use AS INT) FROM sys.configurations
            WHERE name = N'show advanced options') = 0
    BEGIN
        EXEC sys.sp_configure N'show advanced options', 1;
        RECONFIGURE;
    END;
    EXEC sys.sp_configure @configname = @Name, @configvalue = @Value;
    RECONFIGURE;
    FETCH NEXT FROM restore_cursor INTO @Name, @Value;
END;
CLOSE restore_cursor;
DEALLOCATE restore_cursor;
GO
-- 'show advanced options' may have been switched on by the safety net
DECLARE @Show INT = (SELECT value FROM dbo.Practice_SolutionsStart
                     WHERE name = N'show advanced options');
IF (SELECT CAST(value AS INT) FROM sys.configurations
    WHERE name = N'show advanced options') <> @Show
BEGIN
    EXEC sys.sp_configure N'show advanced options', @Show;
    RECONFIGURE;
END;
GO

SELECT COUNT(*) AS StillDifferent
FROM dbo.Practice_SolutionsStart AS b
INNER JOIN sys.configurations AS c
    ON c.configuration_id = b.configuration_id
WHERE CAST(c.value AS INT) <> b.value;
GO

ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 0;
GO
DROP PROCEDURE IF EXISTS dbo.usp_KillSessionsOfLogin;
DROP TABLE IF EXISTS dbo.Practice_ConfigBaseline;
DROP TABLE IF EXISTS dbo.Practice_Saved384;
DROP TABLE IF EXISTS dbo.Practice_SolutionsStart;
GO
IF DB_ID(N'NorthbridgePractice') IS NOT NULL
BEGIN
    ALTER DATABASE NorthbridgePractice
    SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE NorthbridgePractice;
END;
GO
