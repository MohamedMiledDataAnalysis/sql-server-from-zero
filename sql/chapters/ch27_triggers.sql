/* SQL Server from Zero — Volume 1
   Chapter 27: Triggers
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO


-- ==============================================================
-- 1. What a trigger is: the inserted and deleted tables
-- ==============================================================

-- DDL triggers left by an interrupted run would block the drops below
DROP TRIGGER IF EXISTS trg_ProtectAuditTables, trg_DdlAudit ON DATABASE;
GO

-- Practice copy of dbo.Loan with a primary key
DROP TABLE IF EXISTS dbo.Practice_Loan;

SELECT *
INTO dbo.Practice_Loan          -- copy of the 800 loans (chapter 12)
FROM dbo.Loan;

ALTER TABLE dbo.Practice_Loan
    ADD CONSTRAINT PK_Practice_Loan PRIMARY KEY (LoanID);
GO
-- Peek trigger: reports the row counts of deleted and inserted
CREATE OR ALTER TRIGGER dbo.trg_Practice_Loan_Peek
ON dbo.Practice_Loan
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;               -- hide the trigger's own row counts
    DECLARE @Old INT, @New INT;

    SELECT @Old = COUNT(*) FROM deleted;    -- one value: safe
    SELECT @New = COUNT(*) FROM inserted;
    PRINT CONCAT(N'deleted holds ', @Old, N' row(s); inserted holds ',
                 @New, N' row(s).');
END;
GO
-- Fire it: three loans in arrears at Bristol (BranchID 5)
UPDATE dbo.Practice_Loan
SET InterestRate = InterestRate + 0.25
WHERE BranchID = 5
  AND LoanStatus = N'Arrears';
GO
-- An UPDATE that matches no row still fires the trigger
UPDATE dbo.Practice_Loan
SET InterestRate = InterestRate + 0.25
WHERE LoanID = 99999;          -- no such loan
GO
-- Remove the peek trigger
DROP TRIGGER IF EXISTS dbo.trg_Practice_Loan_Peek;
GO

-- ==============================================================
-- 2. An audit trigger on loan status changes
-- ==============================================================

-- Audit table
DROP TABLE IF EXISTS dbo.Practice_LoanStatusAudit;

CREATE TABLE dbo.Practice_LoanStatusAudit (
    AuditID    INT IDENTITY(1,1) NOT NULL
               CONSTRAINT PK_Practice_LoanStatusAudit PRIMARY KEY,
    LoanID     INT            NOT NULL,
    OldStatus  NVARCHAR(20)   NOT NULL,
    NewStatus  NVARCHAR(20)   NOT NULL,
    OldBalance DECIMAL(12,2)  NOT NULL,
    NewBalance DECIMAL(12,2)  NOT NULL,
    ChangedBy  NVARCHAR(128)  NOT NULL
               CONSTRAINT DF_Practice_LoanStatusAudit_By
               DEFAULT ORIGINAL_LOGIN(),
    ChangedAt  DATETIME2(0)   NOT NULL
               CONSTRAINT DF_Practice_LoanStatusAudit_At
               DEFAULT SYSDATETIME()
);
GO
-- Audit trigger (correct, set-based version)
CREATE OR ALTER TRIGGER dbo.trg_Practice_Loan_StatusAudit
ON dbo.Practice_Loan
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM inserted)
        RETURN;                     -- statement changed no row

    IF NOT UPDATE(LoanStatus)
        RETURN;                     -- LoanStatus not in the SET list

    INSERT INTO dbo.Practice_LoanStatusAudit
        (LoanID, OldStatus, NewStatus, OldBalance, NewBalance)
    SELECT d.LoanID,
           d.LoanStatus,            -- before
           i.LoanStatus,            -- after
           d.OutstandingBalance,
           i.OutstandingBalance
    FROM inserted AS i
    INNER JOIN deleted AS d
        ON d.LoanID = i.LoanID      -- pair old and new version
    WHERE i.LoanStatus <> d.LoanStatus;  -- only real changes
END;
GO
-- Test: four Leeds loans in arrears move to Default
UPDATE dbo.Practice_Loan
SET LoanStatus = N'Default'
WHERE BranchID = 4
  AND LoanStatus = N'Arrears';

SELECT AuditID, LoanID, OldStatus, NewStatus, NewBalance
FROM dbo.Practice_LoanStatusAudit
ORDER BY AuditID;
GO
-- UPDATE(LoanStatus) is TRUE but no value changes: no audit row
UPDATE dbo.Practice_Loan
SET LoanStatus = LoanStatus      -- names the column, changes nothing
WHERE BranchID = 4;

SELECT COUNT(*) AS AuditRows
FROM dbo.Practice_LoanStatusAudit;
GO

-- ==============================================================
-- 3. The multi-row trap, nesting and recursion
-- ==============================================================

-- The multi-row trap is shown as a fragment in the book; exercise 27.5
-- gives a complete faulty trigger to repair.

-- Recursive triggers setting of the database
SELECT name, is_recursive_triggers_on
FROM sys.databases
WHERE name = N'NorthbridgeLending';
GO

-- ==============================================================
-- 4. AFTER INSERT triggers and rejecting a change
-- ==============================================================

CREATE OR ALTER TRIGGER dbo.trg_Practice_Loan_CheckScore
ON dbo.Practice_Loan
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        INNER JOIN dbo.Customer AS c
            ON c.CustomerID = i.CustomerID
        INNER JOIN dbo.Product AS p
            ON p.ProductCode = i.ProductCode
        WHERE p.IsSecured = 0          -- unsecured product
          AND c.CreditScore < 550      -- weak credit score
    )
    BEGIN
        PRINT N'Rejected: unsecured loans need a credit score of 550 '
            + N'or more.';
        ROLLBACK TRANSACTION;
        RETURN;
    END;
END;
GO
-- Test: one forbidden row, the whole statement is rejected
-- (expected: message 3609, the batch is aborted). Commented out so
-- that the script runs end to end; uncomment to see the refusal.
-- INSERT INTO dbo.Practice_Loan
--     (LoanID, CustomerID, ProductCode, BranchID, OfficerID,
--      ApplicationDate, OriginationDate, Principal, InterestRate,
--      TermMonths, MonthlyPayment, MaturityDate, LoanStatus,
--      OutstandingBalance)
-- VALUES
--     (10803, 17, 'PL-STD', 8, 122, '2026-09-21', '2026-09-30',
--      10000.00, 7.90, 36, 312.90, '2029-09-30', N'Active',
--      10000.00),
--     (10804, 49, 'PL-STD', 5, 114, '2026-09-21', '2026-09-30',
--      10000.00, 7.90, 36, 312.90, '2029-09-30', N'Active',
--      10000.00);
GO
-- Proof, in its own batch
SELECT LoanID, CustomerID
FROM dbo.Practice_Loan
WHERE LoanID > 10800
ORDER BY LoanID;
GO

-- ==============================================================
-- 5. INSTEAD OF triggers
-- ==============================================================

CREATE OR ALTER TRIGGER dbo.trg_Practice_Loan_ProtectDelete
ON dbo.Practice_Loan
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Deleted INT, @Refused INT;

    SELECT @Refused = COUNT(*)          -- rows we will not delete
    FROM deleted
    WHERE OutstandingBalance > 0;

    DELETE pl                          -- the real delete
    FROM dbo.Practice_Loan AS pl
    INNER JOIN deleted AS d
        ON d.LoanID = pl.LoanID
    WHERE d.OutstandingBalance = 0;    -- only cleared loans

    SET @Deleted = @@ROWCOUNT;         -- read it immediately

    PRINT CONCAT(N'Deleted: ', @Deleted,
                 N'; refused (balance above zero): ', @Refused, N'.');
END;
GO
-- Customer 56: one active loan, two repaid loans
SET NOCOUNT ON;

DELETE FROM dbo.Practice_Loan
WHERE CustomerID = 56;

SET NOCOUNT OFF;

SELECT LoanID, LoanStatus, OutstandingBalance
FROM dbo.Practice_Loan
WHERE CustomerID = 56
ORDER BY LoanID;
GO

-- ==============================================================
-- 6. DDL triggers and EVENTDATA()
-- ==============================================================

-- DDL history table and DDL audit trigger
DROP TABLE IF EXISTS dbo.Practice_DdlAudit;

CREATE TABLE dbo.Practice_DdlAudit (
    AuditID     INT IDENTITY(1,1) NOT NULL
                CONSTRAINT PK_Practice_DdlAudit PRIMARY KEY,
    EventType   NVARCHAR(100)  NOT NULL,
    SchemaName  NVARCHAR(128)  NULL,
    ObjectName  NVARCHAR(128)  NULL,
    LoginName   NVARCHAR(128)  NULL,
    CommandText NVARCHAR(MAX)  NULL,
    PostTime    DATETIME2(0)   NOT NULL
                CONSTRAINT DF_Practice_DdlAudit_PostTime
                DEFAULT SYSDATETIME()
);
GO

CREATE OR ALTER TRIGGER trg_DdlAudit
ON DATABASE
FOR CREATE_TABLE, ALTER_TABLE, DROP_TABLE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @e XML = EVENTDATA();     -- the event as XML

    INSERT INTO dbo.Practice_DdlAudit
        (EventType, SchemaName, ObjectName, LoginName, CommandText)
    VALUES (
        @e.value('(/EVENT_INSTANCE/EventType)[1]', 'NVARCHAR(100)'),
        @e.value('(/EVENT_INSTANCE/SchemaName)[1]', 'NVARCHAR(128)'),
        @e.value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(128)'),
        @e.value('(/EVENT_INSTANCE/LoginName)[1]', 'NVARCHAR(128)'),
        @e.value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]',
                 'NVARCHAR(MAX)'));
END;
GO
-- Three DDL statements on a throw-away table
CREATE TABLE dbo.Practice_DdlTest (TestID INT NOT NULL);

ALTER TABLE dbo.Practice_DdlTest
    ADD Note NVARCHAR(50) NULL;

DROP TABLE dbo.Practice_DdlTest;

SELECT AuditID, EventType, SchemaName, ObjectName
FROM dbo.Practice_DdlAudit
ORDER BY AuditID;
GO
-- ==============================================================
-- 7. Logon triggers
-- ==============================================================

-- Run only on your own development instance. Read section 7 first.
-- The login nb_night_batch does not exist, so nobody is refused.
DROP TRIGGER IF EXISTS trg_Logon_NightBatchWindow ON ALL SERVER;
GO

CREATE TRIGGER trg_Logon_NightBatchWindow
ON ALL SERVER
FOR LOGON
AS
BEGIN
    IF ORIGINAL_LOGIN() = N'nb_night_batch'
       AND DATEPART(HOUR, SYSDATETIME()) BETWEEN 7 AND 18
        ROLLBACK;                       -- refuse this connection
END;
GO
-- Remove the logon trigger
DROP TRIGGER trg_Logon_NightBatchWindow ON ALL SERVER;
GO

-- ==============================================================
-- 8. Managing triggers: ENABLE, DISABLE, DROP and sys.triggers
-- ==============================================================

-- List the triggers of the database
SELECT t.name                    AS TriggerName,
       t.parent_class_desc       AS ParentClass,
       OBJECT_NAME(t.parent_id)  AS ParentObject,
       e.type_desc               AS EventName,
       t.is_instead_of_trigger   AS IsInsteadOf,
       t.is_disabled             AS IsDisabled
FROM sys.triggers AS t
INNER JOIN sys.trigger_events AS e
    ON e.object_id = t.object_id
ORDER BY t.name, e.type_desc;
GO
-- Read the code of a trigger
SELECT OBJECT_DEFINITION(
           OBJECT_ID(N'dbo.trg_Practice_Loan_StatusAudit'))
       AS TriggerCode;
GO
-- Disable, change, enable
DISABLE TRIGGER dbo.trg_Practice_Loan_StatusAudit
ON dbo.Practice_Loan;

UPDATE dbo.Practice_Loan
SET LoanStatus = N'Active'
WHERE LoanID = 10430;                 -- was Arrears

ENABLE TRIGGER dbo.trg_Practice_Loan_StatusAudit
ON dbo.Practice_Loan;

SELECT COUNT(*) AS AuditRows
FROM dbo.Practice_LoanStatusAudit
WHERE LoanID = 10430;
GO
-- Drop triggers
DROP TRIGGER IF EXISTS dbo.trg_Practice_Loan_CheckScore,
                       dbo.trg_Practice_Loan_ProtectDelete;

DROP TRIGGER IF EXISTS trg_DdlAudit
ON DATABASE;

SELECT name
FROM sys.triggers
ORDER BY name;
GO

-- ==============================================================
-- Applied example: a default watchlist
-- ==============================================================

-- Step 1. Fresh practice copy and watchlist table
DROP TABLE IF EXISTS dbo.Practice_Loan;    -- also drops its triggers

SELECT *
INTO dbo.Practice_Loan
FROM dbo.Loan;

ALTER TABLE dbo.Practice_Loan
    ADD CONSTRAINT PK_Practice_Loan PRIMARY KEY (LoanID);

DROP TABLE IF EXISTS dbo.Practice_DefaultWatch;

CREATE TABLE dbo.Practice_DefaultWatch (
    WatchID   INT IDENTITY(1,1) NOT NULL
              CONSTRAINT PK_Practice_DefaultWatch PRIMARY KEY,
    LoanID    INT            NOT NULL,
    BranchID  INT            NOT NULL,
    OldStatus NVARCHAR(20)   NOT NULL,
    NewStatus NVARCHAR(20)   NOT NULL,
    Balance   DECIMAL(12,2)  NOT NULL
);
GO
-- Step 2. The trigger
CREATE OR ALTER TRIGGER dbo.trg_Practice_Loan_DefaultWatch
ON dbo.Practice_Loan
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM inserted)
        RETURN;
    IF NOT UPDATE(LoanStatus)
        RETURN;

    INSERT INTO dbo.Practice_DefaultWatch
        (LoanID, BranchID, OldStatus, NewStatus, Balance)
    SELECT i.LoanID, i.BranchID, d.LoanStatus, i.LoanStatus,
           i.OutstandingBalance
    FROM inserted AS i
    INNER JOIN deleted AS d
        ON d.LoanID = i.LoanID
    WHERE i.LoanStatus IN (N'Default', N'Written Off')  -- target
      AND d.LoanStatus <> i.LoanStatus;                 -- a real move
END;
GO
-- Step 3. One-row test, then the month-end batch
UPDATE dbo.Practice_Loan
SET LoanStatus = N'Default'
WHERE LoanID = 10196;                -- the one-row test

UPDATE dbo.Practice_Loan
SET LoanStatus = N'Default'
WHERE LoanStatus IN (N'Arrears', N'Default')
  AND OriginationDate < '2025-01-01';

UPDATE dbo.Practice_Loan
SET LoanStatus = N'Written Off'
WHERE LoanID = 10002;

SELECT NewStatus, COUNT(*) AS Entries
FROM dbo.Practice_DefaultWatch
GROUP BY NewStatus
ORDER BY NewStatus;
GO
-- By branch (quoted at the end of step 3)
SELECT b.BranchName,
       COUNT(*)       AS Loans,
       SUM(w.Balance) AS BalanceAtRisk
FROM dbo.Practice_DefaultWatch AS w
INNER JOIN dbo.Branch AS b
    ON b.BranchID = w.BranchID
GROUP BY b.BranchName
ORDER BY BalanceAtRisk DESC;
GO

-- ==============================================================
-- Clean-up: remove every object created in this chapter
-- ==============================================================

-- DDL triggers first, otherwise they could block or record the drops
DROP TRIGGER IF EXISTS trg_ProtectAuditTables, trg_DdlAudit ON DATABASE;
DROP TRIGGER IF EXISTS trg_Logon_NightBatchWindow ON ALL SERVER;
GO
-- Dropping a table also drops its DML triggers
DROP TABLE IF EXISTS dbo.Practice_DefaultWatch;
DROP TABLE IF EXISTS dbo.Practice_DdlAudit;
DROP TABLE IF EXISTS dbo.Practice_DdlTest;
DROP TABLE IF EXISTS dbo.Practice_LoanStatusAudit;
DROP TABLE IF EXISTS dbo.Practice_TriggerPeek;
DROP TABLE IF EXISTS dbo.Practice_Loan;
GO
-- The base tables were never changed by this chapter.
