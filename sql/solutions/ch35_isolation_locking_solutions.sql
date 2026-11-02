/* SQL Server from Zero — Volume 2
   Chapter 35: Isolation levels, locking and snapshot — solutions to the exercises
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- ==============================================================
-- Exercise setup: default session settings, no leftover objects
-- ==============================================================

IF @@TRANCOUNT > 0 ROLLBACK;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET LOCK_TIMEOUT -1;
SET DEADLOCK_PRIORITY NORMAL;
GO
DROP PROCEDURE IF EXISTS dbo.usp_Ex35_MonthEndGuard;
DROP PROCEDURE IF EXISTS dbo.usp_Ex35_RaiseRate;
GO

-- ==============================================================
-- Correction 35.1
-- ==============================================================
GO
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

SELECT transaction_isolation_level AS LevelNumber,
       CASE transaction_isolation_level
           WHEN 1 THEN N'READ UNCOMMITTED'
           WHEN 2 THEN N'READ COMMITTED'
           WHEN 3 THEN N'REPEATABLE READ'
           WHEN 4 THEN N'SERIALIZABLE'
           WHEN 5 THEN N'SNAPSHOT'
       END AS LevelName
FROM sys.dm_exec_sessions
WHERE session_id = @@SPID;

SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

SELECT transaction_isolation_level AS LevelNumber
FROM sys.dm_exec_sessions
WHERE session_id = @@SPID;
GO

-- ==============================================================
-- Correction 35.2
-- ==============================================================
GO
SET LOCK_TIMEOUT 2000;
SET DEADLOCK_PRIORITY HIGH;

SELECT @@LOCK_TIMEOUT AS LockTimeoutMs,
       deadlock_priority
FROM sys.dm_exec_sessions
WHERE session_id = @@SPID;

SET LOCK_TIMEOUT -1;
SET DEADLOCK_PRIORITY NORMAL;

SELECT @@LOCK_TIMEOUT AS LockTimeoutMs,
       deadlock_priority
FROM sys.dm_exec_sessions
WHERE session_id = @@SPID;
GO

-- ==============================================================
-- Correction 35.3
-- ==============================================================
GO
SELECT name,
       snapshot_isolation_state_desc,
       is_read_committed_snapshot_on,
       DATABASEPROPERTYEX(name, 'IsOptimizedLockingOn')
           AS IsOptimizedLockingOn
FROM sys.databases
WHERE name = N'NorthbridgeLending';
GO

-- ==============================================================
-- Correction 35.4
-- ==============================================================
GO
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
BEGIN TRANSACTION;

SELECT OutstandingBalance
FROM dbo.Loan
WHERE LoanID = 10004;

SELECT COUNT(*) AS KeyLocks
FROM sys.dm_tran_locks
WHERE request_session_id = @@SPID
  AND resource_database_id = DB_ID()
  AND resource_type = N'KEY';

ROLLBACK TRANSACTION;
GO

SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
BEGIN TRANSACTION;

SELECT OutstandingBalance
FROM dbo.Loan
WHERE LoanID = 10004;

SELECT COUNT(*) AS KeyLocks
FROM sys.dm_tran_locks
WHERE request_session_id = @@SPID
  AND resource_database_id = DB_ID()
  AND resource_type = N'KEY';

ROLLBACK TRANSACTION;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO

-- ==============================================================
-- Correction 35.5
-- ==============================================================
GO
ALTER DATABASE NorthbridgeLending
SET ALLOW_SNAPSHOT_ISOLATION ON;
GO

SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRANSACTION;

SELECT b.Region,
       COUNT(*)                  AS Loans,
       SUM(l.OutstandingBalance) AS Balance
FROM dbo.Loan AS l
INNER JOIN dbo.Branch AS b
    ON b.BranchID = l.BranchID
WHERE l.LoanStatus IN (N'Arrears', N'Default')
GROUP BY b.Region
ORDER BY b.Region;

COMMIT TRANSACTION;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO

ALTER DATABASE NorthbridgeLending
SET ALLOW_SNAPSHOT_ISOLATION OFF;
GO

-- ==============================================================
-- Correction 35.6
-- ==============================================================
GO
CREATE OR ALTER PROCEDURE dbo.usp_Ex35_MonthEndGuard
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rc INT;

    BEGIN TRANSACTION;

    EXEC @rc = sys.sp_getapplock
        @Resource    = N'Northbridge.MonthEnd',
        @LockMode    = N'Exclusive',
        @LockOwner   = N'Transaction',
        @LockTimeout = 0;

    IF @rc < 0
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50352, N'Month-end is already running.', 1;
    END;

    PRINT N'Month-end lock acquired.';

    SELECT COUNT(*) AS DefaultLoans
    FROM dbo.Loan
    WHERE LoanStatus = N'Default';

    COMMIT TRANSACTION;                  -- releases the lock
END;
GO

EXEC dbo.usp_Ex35_MonthEndGuard;
GO

-- ==============================================================
-- Correction 35.7
-- ==============================================================
GO
SELECT r.session_id            AS BlockedSession,
       r.blocking_session_id   AS BlockingSession,
       r.wait_type,
       r.wait_time / 1000      AS WaitSeconds,
       s.login_name            AS BlockerLogin,
       bt.text                 AS BlockedSql,
       ct.text                 AS BlockerLastSql
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s
    ON s.session_id = r.blocking_session_id
INNER JOIN sys.dm_exec_connections AS c
    ON c.session_id = r.blocking_session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS bt
CROSS APPLY sys.dm_exec_sql_text(c.most_recent_sql_handle) AS ct
WHERE r.blocking_session_id > 0
ORDER BY r.wait_time DESC;
GO

-- ==============================================================
-- Correction 35.8
-- ==============================================================
GO
CREATE OR ALTER PROCEDURE dbo.usp_Ex35_RaiseRate
    @LoanID   INT,
    @Increase DECIMAL(5,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET LOCK_TIMEOUT 5000;
    SET DEADLOCK_PRIORITY LOW;

    DECLARE @Attempt INT = 1, @Done BIT = 0;

    WHILE @Done = 0
    BEGIN
        BEGIN TRY
            BEGIN TRANSACTION;

            UPDATE dbo.Loan
            SET InterestRate = InterestRate + @Increase
            WHERE LoanID = @LoanID;

            COMMIT TRANSACTION;
            SET @Done = 1;
            PRINT CONCAT(N'Succeeded at attempt ', @Attempt, N'.');
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;

            IF ERROR_NUMBER() NOT IN (1205, 1222, 3960)
               OR @Attempt >= 3
            BEGIN
                PRINT CONCAT(N'Giving up at attempt ', @Attempt,
                             N'.');
                THROW;
            END;

            SET @Attempt += 1;
            WAITFOR DELAY '00:00:00.200';
        END CATCH;
    END;
END;
GO

EXEC dbo.usp_Ex35_RaiseRate @LoanID = 10005, @Increase = 0.25;

SELECT InterestRate
FROM dbo.Loan
WHERE LoanID = 10005;

BEGIN TRY
    EXEC dbo.usp_Ex35_RaiseRate @LoanID = 10005, @Increase = 999.99;
END TRY
BEGIN CATCH
    PRINT CONCAT(N'Caller caught error ', ERROR_NUMBER(), N'.');
END CATCH;

UPDATE dbo.Loan
SET InterestRate = 4.38                  -- value at 30 Sep 2026
WHERE LoanID = 10005;
GO

/* NOT RUN BY THE AUTOMATED TEST: needs two query windows.
   Test of correction 35.7 (blocking report) and 35.6 (guard).

-- Step 1, Session A
BEGIN TRANSACTION;
UPDATE dbo.Loan
SET InterestRate = InterestRate + 0.10
WHERE LoanID = 10004;
EXEC sys.sp_getapplock @Resource = N'Northbridge.MonthEnd',
                       @LockMode = N'Exclusive';

-- Step 2, Session B: waits on loan 10004
SELECT InterestRate FROM dbo.Loan WHERE LoanID = 10004;

-- Step 3, a third window: the report of correction 35.7 shows
-- Session B blocked by Session A; EXEC dbo.usp_Ex35_MonthEndGuard;
-- fails at once with error 50352.

-- Step 4, Session A
ROLLBACK TRANSACTION;
*/

-- ==============================================================
-- Clean-up: data, objects, session settings and database options
-- ==============================================================

IF @@TRANCOUNT > 0 ROLLBACK;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET LOCK_TIMEOUT -1;
SET DEADLOCK_PRIORITY NORMAL;
SET XACT_ABORT OFF;

UPDATE dbo.Loan
SET InterestRate = 4.38                  -- value at 30 Sep 2026
WHERE LoanID = 10005;
GO
DROP PROCEDURE IF EXISTS dbo.usp_Ex35_MonthEndGuard;
DROP PROCEDURE IF EXISTS dbo.usp_Ex35_RaiseRate;
GO
ALTER DATABASE NorthbridgeLending
SET ALLOW_SNAPSHOT_ISOLATION OFF;
GO
