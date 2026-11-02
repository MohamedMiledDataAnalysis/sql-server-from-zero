/* SQL Server from Zero — Volume 2
   Chapter 35: Isolation levels, locking and snapshot
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- Every demonstration that needs two sessions is kept below as a
-- commented block: the automated test runs in one session and must
-- never wait for itself. Session settings changed here are reset at
-- the end of the script.
IF @@TRANCOUNT > 0 ROLLBACK;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET LOCK_TIMEOUT -1;
SET DEADLOCK_PRIORITY NORMAL;
GO

-- ==============================================================
-- 1. Four concurrency problems
-- ==============================================================

/* NOT RUN BY THE AUTOMATED TEST: needs two query windows.
   Open two query windows on NorthbridgeLending: Session A and
   Session B. Run each numbered step in the window named, in order.

-- Dirty read ---------------------------------------------------
-- Step 1, Session A
BEGIN TRANSACTION;
UPDATE dbo.Loan
SET OutstandingBalance = 0
WHERE LoanID = 10004;                    -- not committed

-- Step 2, Session B
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT OutstandingBalance                -- 0.00: a dirty read
FROM dbo.Loan
WHERE LoanID = 10004;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- Step 3, Session A
ROLLBACK TRANSACTION;                    -- 0.00 never existed

-- Non-repeatable read ------------------------------------------
-- Step 1, Session B (READ COMMITTED)
BEGIN TRANSACTION;
SELECT OutstandingBalance                -- 12728.03
FROM dbo.Loan
WHERE LoanID = 10004;

-- Step 2, Session A
UPDATE dbo.Loan
SET OutstandingBalance = OutstandingBalance - 599.73
WHERE LoanID = 10004;                    -- autocommit

-- Step 3, Session B
SELECT OutstandingBalance                -- 12128.30: changed
FROM dbo.Loan
WHERE LoanID = 10004;
COMMIT TRANSACTION;

-- Step 4, Session A: put the balance back
UPDATE dbo.Loan
SET OutstandingBalance = 12728.03
WHERE LoanID = 10004;

-- Phantom ------------------------------------------------------
-- Step 1, Session B
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
BEGIN TRANSACTION;
SELECT COUNT(*) AS InArrears             -- 4
FROM dbo.Loan
WHERE BranchID = 7
  AND LoanStatus = N'Arrears';

-- Step 2, Session A: a new loan in arrears at Cardiff
INSERT INTO dbo.Loan
    (LoanID, CustomerID, ProductCode, BranchID, OfficerID,
     ApplicationDate, OriginationDate, Principal, InterestRate,
     TermMonths, MonthlyPayment, MaturityDate, LoanStatus,
     OutstandingBalance)
SELECT 10801, CustomerID, ProductCode, BranchID, OfficerID,
       ApplicationDate, OriginationDate, Principal, InterestRate,
       TermMonths, MonthlyPayment, MaturityDate, N'Arrears',
       OutstandingBalance
FROM dbo.Loan
WHERE LoanID = 10031;

-- Step 3, Session B
SELECT COUNT(*) AS InArrears             -- 5: a phantom
FROM dbo.Loan
WHERE BranchID = 7
  AND LoanStatus = N'Arrears';
COMMIT TRANSACTION;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- Step 4, Session A: remove the new loan
DELETE FROM dbo.Loan
WHERE LoanID = 10801;

-- Lost update --------------------------------------------------
-- Step 1, Session A: one batch that pauses 10 seconds
DECLARE @BalA DECIMAL(12,2);
SELECT @BalA = OutstandingBalance        -- 12728.03
FROM dbo.Loan WHERE LoanID = 10004;
WAITFOR DELAY '00:00:10';                -- the clerk thinks
UPDATE dbo.Loan SET OutstandingBalance = @BalA - 599.73
WHERE LoanID = 10004;                    -- 12128.30

-- Step 2, Session B, within the 10 seconds
DECLARE @BalB DECIMAL(12,2);
SELECT @BalB = OutstandingBalance        -- 12728.03
FROM dbo.Loan WHERE LoanID = 10004;
UPDATE dbo.Loan SET OutstandingBalance = @BalB - 100.00
WHERE LoanID = 10004;                    -- 12628.03

-- Step 3, either session, after both: put the balance back
UPDATE dbo.Loan SET OutstandingBalance = 12728.03
WHERE LoanID = 10004;
*/

-- ==============================================================
-- 2. Locks: modes, granularity and escalation
-- ==============================================================

-- The locks of one UPDATE, seen from inside its transaction
BEGIN TRANSACTION;

UPDATE dbo.Loan
SET InterestRate = InterestRate + 0.10
WHERE LoanID = 10004;

SELECT resource_type,
       request_mode,
       request_status,
       CASE WHEN resource_type = N'OBJECT'
            THEN OBJECT_NAME(resource_associated_entity_id)
       END AS ObjectName
FROM sys.dm_tran_locks
WHERE request_session_id = @@SPID
  AND resource_database_id = DB_ID()
ORDER BY resource_type;

ROLLBACK TRANSACTION;
GO

-- Lock escalation: 6,000 rows in one statement. On the test server the
-- 6,000 KEY X locks remain (no escalation): see the book, section 2.
BEGIN TRANSACTION;

UPDATE dbo.Payment
SET AmountPaid = AmountPaid + 0.01
WHERE PaymentID <= 6000;

SELECT resource_type, request_mode, COUNT(*) AS Locks
FROM sys.dm_tran_locks
WHERE request_session_id = @@SPID
  AND resource_database_id = DB_ID()
GROUP BY resource_type, request_mode
ORDER BY resource_type;

ROLLBACK TRANSACTION;
GO

-- The table option that controls escalation
SELECT name, lock_escalation_desc
FROM sys.tables
WHERE name IN (N'Loan', N'Payment')
ORDER BY name;
GO

-- ==============================================================
-- 3. Blocking, sys.dm_exec_requests and SET LOCK_TIMEOUT
-- ==============================================================

-- Who is blocked, and by whom (no rows when nothing waits)
SELECT r.session_id,
       r.blocking_session_id,
       r.wait_type,
       r.wait_time,
       t.text AS SqlText
FROM sys.dm_exec_requests AS r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE r.blocking_session_id <> 0;
GO

-- Lock timeout of this session
SET LOCK_TIMEOUT 3000;                   -- wait at most 3 seconds
SELECT @@LOCK_TIMEOUT AS LockTimeoutMs;

SET LOCK_TIMEOUT -1;                     -- back to: wait forever
SELECT @@LOCK_TIMEOUT AS LockTimeoutMs;
GO

/* NOT RUN BY THE AUTOMATED TEST: needs two query windows.

-- Step 1, Session A: hold an exclusive lock on loan 10004
BEGIN TRANSACTION;
UPDATE dbo.Loan
SET InterestRate = InterestRate + 0.10
WHERE LoanID = 10004;

-- Step 2, Session B: waits 3 seconds, then error 1222
SET LOCK_TIMEOUT 3000;
SELECT InterestRate
FROM dbo.Loan
WHERE LoanID = 10004;
SET LOCK_TIMEOUT -1;

-- Step 2 bis, Session B (instead of step 2): run the SELECT above
-- without SET LOCK_TIMEOUT, so that it waits; see the blocking with
-- the sys.dm_exec_requests query above, run in a third window.

-- Step 3, Session A
ROLLBACK TRANSACTION;
*/

-- ==============================================================
-- 4. SET TRANSACTION ISOLATION LEVEL
-- ==============================================================

SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

SELECT transaction_isolation_level
FROM sys.dm_exec_sessions
WHERE session_id = @@SPID;

DBCC USEROPTIONS;

SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO

-- The locks a REPEATABLE READ transaction keeps
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
BEGIN TRANSACTION;

SELECT LoanID, LoanStatus
FROM dbo.Loan
WHERE LoanID BETWEEN 10001 AND 10005;

SELECT resource_type, request_mode, COUNT(*) AS Locks
FROM sys.dm_tran_locks
WHERE request_session_id = @@SPID
  AND resource_database_id = DB_ID()
  AND resource_type = N'KEY'
GROUP BY resource_type, request_mode;

ROLLBACK TRANSACTION;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO

-- The same under SERIALIZABLE: key-range locks
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
BEGIN TRANSACTION;

SELECT LoanID, LoanStatus
FROM dbo.Loan
WHERE LoanID BETWEEN 10001 AND 10005;

SELECT resource_type, request_mode, COUNT(*) AS Locks
FROM sys.dm_tran_locks
WHERE request_session_id = @@SPID
  AND resource_database_id = DB_ID()
  AND resource_type = N'KEY'
GROUP BY resource_type, request_mode;

ROLLBACK TRANSACTION;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO

-- ==============================================================
-- 5. Row versioning: SNAPSHOT and READ_COMMITTED_SNAPSHOT
-- ==============================================================

-- The two options, both OFF by default
SELECT name,
       snapshot_isolation_state_desc,
       is_read_committed_snapshot_on
FROM sys.databases
WHERE name = N'NorthbridgeLending';
GO

-- SNAPSHOT before the option is ON (deliberate error 3952)
GO
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
SELECT COUNT(*) AS Loans
FROM dbo.Loan;
GO
IF @@TRANCOUNT > 0 ROLLBACK;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO

-- Allow SNAPSHOT, then use it
ALTER DATABASE NorthbridgeLending
SET ALLOW_SNAPSHOT_ISOLATION ON;
GO
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRANSACTION;

SELECT COUNT(*)                AS Loans,
       SUM(OutstandingBalance) AS TotalBalance
FROM dbo.Loan
WHERE LoanStatus = N'Arrears';

COMMIT TRANSACTION;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO

/* NOT RUN BY THE AUTOMATED TEST: needs two query windows.
   ALLOW_SNAPSHOT_ISOLATION must be ON (above).

-- Step 1, Session B
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRANSACTION;
SELECT OutstandingBalance                -- 12728.03
FROM dbo.Loan
WHERE LoanID = 10004;

-- Step 2, Session A (READ COMMITTED, autocommit)
UPDATE dbo.Loan
SET OutstandingBalance = OutstandingBalance - 599.73
WHERE LoanID = 10004;                    -- 12128.30, committed

-- Step 3, Session B
SELECT OutstandingBalance                -- still 12728.03
FROM dbo.Loan
WHERE LoanID = 10004;

UPDATE dbo.Loan                          -- error 3960: conflict
SET OutstandingBalance = OutstandingBalance - 100.00
WHERE LoanID = 10004;

IF @@TRANCOUNT > 0 ROLLBACK;             -- 3960 already rolled back
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- Step 4, Session A: put the balance back
UPDATE dbo.Loan
SET OutstandingBalance = 12728.03
WHERE LoanID = 10004;
*/

-- READ_COMMITTED_SNAPSHOT: needs a moment alone in the database
ALTER DATABASE NorthbridgeLending
SET READ_COMMITTED_SNAPSHOT ON
WITH ROLLBACK IMMEDIATE;
GO
SELECT name,
       snapshot_isolation_state_desc,
       is_read_committed_snapshot_on
FROM sys.databases
WHERE name = N'NorthbridgeLending';

DBCC USEROPTIONS;
GO

-- Optimized locking (SQL Server 2025): 0 = off, NULL = not available
SELECT DATABASEPROPERTYEX(DB_NAME(), 'IsOptimizedLockingOn')
       AS IsOptimizedLockingOn;
GO

/* NOT RUN BY THE AUTOMATED TEST: SQL Server 2025 only (SQL Server
   2022 does not know OPTIMIZED_LOCKING). Accelerated database
   recovery must be ON before optimized locking.

ALTER DATABASE NorthbridgeLending
SET ACCELERATED_DATABASE_RECOVERY = ON;
ALTER DATABASE NorthbridgeLending
SET OPTIMIZED_LOCKING = ON;

-- To undo, in this order:
ALTER DATABASE NorthbridgeLending
SET OPTIMIZED_LOCKING = OFF;
ALTER DATABASE NorthbridgeLending
SET ACCELERATED_DATABASE_RECOVERY = OFF;
*/

-- Back to the defaults
ALTER DATABASE NorthbridgeLending
SET READ_COMMITTED_SNAPSHOT OFF
WITH ROLLBACK IMMEDIATE;
GO
ALTER DATABASE NorthbridgeLending
SET ALLOW_SNAPSHOT_ISOLATION OFF;
GO

-- ==============================================================
-- 6. Table hints
-- ==============================================================

-- NOLOCK: the same as READ UNCOMMITTED for this table
SELECT COUNT(*) AS Loans
FROM dbo.Loan WITH (NOLOCK)
WHERE LoanStatus = N'Default';
GO

-- UPDLOCK: read now, update later, nobody can slip in between
DECLARE @Balance DECIMAL(12,2);

BEGIN TRANSACTION;

SELECT @Balance = OutstandingBalance
FROM dbo.Loan WITH (UPDLOCK, ROWLOCK)
WHERE LoanID = 10004;

SELECT resource_type, request_mode
FROM sys.dm_tran_locks
WHERE request_session_id = @@SPID
  AND resource_database_id = DB_ID()
  AND resource_type = N'KEY';

UPDATE dbo.Loan
SET OutstandingBalance = @Balance - 599.73
WHERE LoanID = 10004;

SELECT OutstandingBalance
FROM dbo.Loan
WHERE LoanID = 10004;

ROLLBACK TRANSACTION;
GO

-- READPAST: skip the rows another session has locked
SELECT TOP (3) LoanID, OutstandingBalance
FROM dbo.Loan WITH (READPAST)
WHERE LoanStatus = N'Arrears'
ORDER BY LoanID;
GO

-- ==============================================================
-- 7. Deadlocks, DEADLOCK_PRIORITY and the retry pattern
-- ==============================================================

/* NOT RUN BY THE AUTOMATED TEST: needs two query windows.

-- Step 1, Session A
BEGIN TRANSACTION;
UPDATE dbo.Loan SET InterestRate = InterestRate + 0.10
WHERE LoanID = 10004;

-- Step 2, Session B
BEGIN TRANSACTION;
UPDATE dbo.Loan SET InterestRate = InterestRate + 0.10
WHERE LoanID = 10005;

-- Step 3, Session A: waits for B
UPDATE dbo.Loan SET InterestRate = InterestRate + 0.10
WHERE LoanID = 10005;

-- Step 4, Session B: waits for A -> deadlock, one session gets 1205
UPDATE dbo.Loan SET InterestRate = InterestRate + 0.10
WHERE LoanID = 10004;

-- Step 5, both sessions
IF @@TRANCOUNT > 0 ROLLBACK;
*/

SET DEADLOCK_PRIORITY LOW;

SELECT deadlock_priority
FROM sys.dm_exec_sessions
WHERE session_id = @@SPID;

SET DEADLOCK_PRIORITY NORMAL;
GO

-- The retry pattern
SET XACT_ABORT ON;

DECLARE @Attempt     INT = 1,
        @MaxAttempts INT = 3,
        @Done        BIT = 0;

WHILE @Done = 0
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.Loan
        SET InterestRate = InterestRate + 0.10
        WHERE LoanID = 10004;

        COMMIT TRANSACTION;
        SET @Done = 1;
        PRINT CONCAT(N'Succeeded at attempt ', @Attempt, N'.');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        IF ERROR_NUMBER() NOT IN (1205, 1222, 3960)
           OR @Attempt >= @MaxAttempts
        BEGIN
            PRINT CONCAT(N'Giving up at attempt ', @Attempt, N'.');
            THROW;
        END;

        SET @Attempt += 1;
        WAITFOR DELAY '00:00:00.200';    -- let the other one finish
    END CATCH;
END;

SET XACT_ABORT OFF;
GO

SELECT InterestRate
FROM dbo.Loan
WHERE LoanID = 10004;

UPDATE dbo.Loan
SET InterestRate = 7.44                  -- value at 30 Sep 2026
WHERE LoanID = 10004;
GO

-- ==============================================================
-- 8. Application locks: sp_getapplock and sp_releaseapplock
-- ==============================================================

DECLARE @rc INT;

BEGIN TRANSACTION;

EXEC @rc = sys.sp_getapplock
    @Resource    = N'Northbridge.MonthEndClose',
    @LockMode    = N'Exclusive',
    @LockOwner   = N'Transaction',
    @LockTimeout = 0;                    -- do not wait

SELECT @rc AS ReturnCode,
       APPLOCK_MODE(N'public', N'Northbridge.MonthEndClose',
                    N'Transaction') AS HeldMode;

EXEC @rc = sys.sp_releaseapplock
    @Resource  = N'Northbridge.MonthEndClose',
    @LockOwner = N'Transaction';

SELECT @rc AS ReturnCode,
       APPLOCK_MODE(N'public', N'Northbridge.MonthEndClose',
                    N'Transaction') AS HeldMode;

COMMIT TRANSACTION;
GO

-- ==============================================================
-- Applied example: a consistent month-end snapshot
-- ==============================================================

-- Step 1. Allow SNAPSHOT
ALTER DATABASE NorthbridgeLending
SET ALLOW_SNAPSHOT_ISOLATION ON;
GO

-- Step 2. One job at a time, one consistent view
SET XACT_ABORT ON;
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;

DECLARE @rc INT;

BEGIN TRANSACTION;

EXEC @rc = sys.sp_getapplock
    @Resource    = N'Northbridge.MonthEndReport',
    @LockMode    = N'Exclusive',
    @LockOwner   = N'Transaction',
    @LockTimeout = 0;

IF @rc < 0
BEGIN
    ROLLBACK TRANSACTION;
    THROW 50351, N'The month-end report is already running.', 1;
END;

SELECT LoanStatus,
       COUNT(*)                AS Loans,
       SUM(OutstandingBalance) AS Balance
FROM dbo.Loan
GROUP BY LoanStatus
ORDER BY LoanStatus;

SELECT COUNT(*)        AS Payments,
       SUM(AmountPaid) AS Collected
FROM dbo.Payment
WHERE PaidDate >= '2026-09-01'
  AND PaidDate <  '2026-10-01';

COMMIT TRANSACTION;                      -- also releases the app lock

SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET XACT_ABORT OFF;
GO

-- Step 3. Back to the default
ALTER DATABASE NorthbridgeLending
SET ALLOW_SNAPSHOT_ISOLATION OFF;
GO

-- ==============================================================
-- Clean-up: session settings and database options to the defaults
-- ==============================================================

IF @@TRANCOUNT > 0 ROLLBACK;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET LOCK_TIMEOUT -1;
SET DEADLOCK_PRIORITY NORMAL;
SET XACT_ABORT OFF;
GO
ALTER DATABASE NorthbridgeLending
SET READ_COMMITTED_SNAPSHOT OFF
WITH ROLLBACK IMMEDIATE;
GO
ALTER DATABASE NorthbridgeLending
SET ALLOW_SNAPSHOT_ISOLATION OFF;
GO
