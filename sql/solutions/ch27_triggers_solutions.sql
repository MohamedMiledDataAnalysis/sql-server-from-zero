/* SQL Server from Zero — Volume 1
   Chapter 27: Triggers — solutions to the exercises
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO


-- ==============================================================
-- Exercise setup (run before 27.1, and before each of 27.4 to 27.8)
-- ==============================================================

DROP TABLE IF EXISTS dbo.Practice_Loan;

SELECT *
INTO dbo.Practice_Loan
FROM dbo.Loan;

ALTER TABLE dbo.Practice_Loan
    ADD CONSTRAINT PK_Practice_Loan PRIMARY KEY (LoanID);
GO

-- ==============================================================
-- Correction 27.1
-- ==============================================================

CREATE OR ALTER TRIGGER dbo.trg_Practice_Loan_InsertCount
ON dbo.Practice_Loan
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @n INT;
    SELECT @n = COUNT(*) FROM inserted;   -- rows of the INSERT
    PRINT CONCAT(@n, N' loan(s) inserted.');
END;
GO

INSERT INTO dbo.Practice_Loan
    (LoanID, CustomerID, ProductCode, BranchID, OfficerID,
     ApplicationDate, OriginationDate, Principal, InterestRate,
     TermMonths, MonthlyPayment, MaturityDate, LoanStatus,
     OutstandingBalance)
SELECT LoanID + 1000,             -- 11001 and 11002: free keys
       CustomerID, ProductCode, BranchID, OfficerID,
       ApplicationDate, OriginationDate, Principal, InterestRate,
       TermMonths, MonthlyPayment, MaturityDate, LoanStatus,
       OutstandingBalance
FROM dbo.Loan
WHERE LoanID IN (10001, 10002);
GO

-- ==============================================================
-- Correction 27.2
-- ==============================================================

DISABLE TRIGGER dbo.trg_Practice_Loan_InsertCount
ON dbo.Practice_Loan;

INSERT INTO dbo.Practice_Loan
    (LoanID, CustomerID, ProductCode, BranchID, OfficerID,
     ApplicationDate, OriginationDate, Principal, InterestRate,
     TermMonths, MonthlyPayment, MaturityDate, LoanStatus,
     OutstandingBalance)
SELECT LoanID + 1000, CustomerID, ProductCode, BranchID, OfficerID,
       ApplicationDate, OriginationDate, Principal, InterestRate,
       TermMonths, MonthlyPayment, MaturityDate, LoanStatus,
       OutstandingBalance
FROM dbo.Loan
WHERE LoanID = 10003;

ENABLE TRIGGER dbo.trg_Practice_Loan_InsertCount
ON dbo.Practice_Loan;
GO

-- ==============================================================
-- Correction 27.3
-- ==============================================================

SELECT t.name        AS TriggerName,
       e.type_desc   AS EventName,
       t.is_disabled AS IsDisabled
FROM sys.triggers AS t
INNER JOIN sys.trigger_events AS e
    ON e.object_id = t.object_id          -- one row per event
WHERE t.parent_id = OBJECT_ID(N'dbo.Practice_Loan')
ORDER BY t.name, e.type_desc;
GO

-- ==============================================================
-- Correction 27.4
-- ==============================================================

-- Exercise setup: fresh practice copy
DROP TABLE IF EXISTS dbo.Practice_Loan;

SELECT *
INTO dbo.Practice_Loan
FROM dbo.Loan;

ALTER TABLE dbo.Practice_Loan
    ADD CONSTRAINT PK_Practice_Loan PRIMARY KEY (LoanID);
GO
DROP TABLE IF EXISTS dbo.Practice_LoanDeleted;

CREATE TABLE dbo.Practice_LoanDeleted (
    LoanID     INT            NOT NULL,
    CustomerID INT            NOT NULL,
    BranchID   INT            NOT NULL,
    LoanStatus NVARCHAR(20)   NOT NULL,
    Principal  DECIMAL(12,2)  NOT NULL,
    DeletedAt  DATETIME2(0)   NOT NULL
               CONSTRAINT DF_Practice_LoanDeleted_At
               DEFAULT SYSDATETIME()
);
GO

CREATE OR ALTER TRIGGER dbo.trg_Practice_Loan_ArchiveDelete
ON dbo.Practice_Loan
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.Practice_LoanDeleted
        (LoanID, CustomerID, BranchID, LoanStatus, Principal)
    SELECT LoanID, CustomerID, BranchID, LoanStatus, Principal
    FROM deleted;                      -- every removed row
END;
GO

DELETE FROM dbo.Practice_Loan
WHERE BranchID = 8
  AND LoanStatus = N'Repaid';

SELECT COUNT(*)       AS ArchivedLoans,
       SUM(Principal) AS TotalPrincipal
FROM dbo.Practice_LoanDeleted;
GO

-- ==============================================================
-- Correction 27.5
-- ==============================================================

-- Exercise setup: fresh practice copy
DROP TABLE IF EXISTS dbo.Practice_Loan;

SELECT *
INTO dbo.Practice_Loan
FROM dbo.Loan;

ALTER TABLE dbo.Practice_Loan
    ADD CONSTRAINT PK_Practice_Loan PRIMARY KEY (LoanID);
GO

-- Exercise 27.5: the faulty trigger as given; it keeps one row of a
-- multi-row UPDATE, so it is left commented out.
-- CREATE OR ALTER TRIGGER dbo.trg_Practice_Loan_RateAudit
-- ON dbo.Practice_Loan
-- AFTER UPDATE
-- AS
-- BEGIN
--     DECLARE @LoanID INT, @Old DECIMAL(5,2), @New DECIMAL(5,2);
--     SELECT @LoanID = i.LoanID, @Old = d.InterestRate,
--            @New = i.InterestRate
--     FROM inserted AS i
--     INNER JOIN deleted AS d ON d.LoanID = i.LoanID;
--     IF @Old <> @New
--         INSERT INTO dbo.Practice_RateAudit (LoanID, OldRate, NewRate)
--         VALUES (@LoanID, @Old, @New);
-- END;

DROP TABLE IF EXISTS dbo.Practice_RateAudit;

CREATE TABLE dbo.Practice_RateAudit (
    LoanID  INT           NOT NULL,
    OldRate DECIMAL(5,2)  NOT NULL,
    NewRate DECIMAL(5,2)  NOT NULL
);
GO

CREATE OR ALTER TRIGGER dbo.trg_Practice_Loan_RateAudit
ON dbo.Practice_Loan
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;                    -- missing in the original
    INSERT INTO dbo.Practice_RateAudit (LoanID, OldRate, NewRate)
    SELECT i.LoanID, d.InterestRate, i.InterestRate
    FROM inserted AS i
    INNER JOIN deleted AS d
        ON d.LoanID = i.LoanID
    WHERE i.InterestRate <> d.InterestRate;   -- every changed row
END;
GO

UPDATE dbo.Practice_Loan
SET InterestRate = InterestRate + 0.50
WHERE BranchID = 5
  AND LoanStatus = N'Arrears';

SELECT LoanID, OldRate, NewRate
FROM dbo.Practice_RateAudit
ORDER BY LoanID;
GO

-- ==============================================================
-- Correction 27.6
-- ==============================================================

-- Exercise setup: fresh practice copy
DROP TABLE IF EXISTS dbo.Practice_Loan;

SELECT *
INTO dbo.Practice_Loan
FROM dbo.Loan;

ALTER TABLE dbo.Practice_Loan
    ADD CONSTRAINT PK_Practice_Loan PRIMARY KEY (LoanID);
GO
CREATE OR ALTER VIEW dbo.vPractice_ActiveLoan
AS
SELECT LoanID, CustomerID, BranchID, OutstandingBalance
FROM dbo.Practice_Loan
WHERE LoanStatus = N'Active';
GO

CREATE OR ALTER TRIGGER dbo.trg_vPractice_ActiveLoan_Close
ON dbo.vPractice_ActiveLoan
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE pl
    SET LoanStatus = N'Repaid',          -- close the loan
        OutstandingBalance = 0
    FROM dbo.Practice_Loan AS pl
    INNER JOIN deleted AS d
        ON d.LoanID = pl.LoanID;          -- rows asked for deletion
END;
GO

DELETE FROM dbo.vPractice_ActiveLoan
WHERE OutstandingBalance < 500;
GO

SELECT LoanID, LoanStatus, OutstandingBalance
FROM dbo.Practice_Loan
WHERE LoanID IN (10087, 10566)
ORDER BY LoanID;
GO

-- ==============================================================
-- Correction 27.7
-- ==============================================================

-- Exercise setup: fresh practice copy
DROP TABLE IF EXISTS dbo.Practice_Loan;

SELECT *
INTO dbo.Practice_Loan
FROM dbo.Loan;

ALTER TABLE dbo.Practice_Loan
    ADD CONSTRAINT PK_Practice_Loan PRIMARY KEY (LoanID);
GO
CREATE OR ALTER TRIGGER dbo.trg_Practice_Loan_RateCap
ON dbo.Practice_Loan
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        INNER JOIN deleted AS d
            ON d.LoanID = i.LoanID
        WHERE i.InterestRate - d.InterestRate > 2.00  -- rise > 2 pts
    )
    BEGIN
        PRINT N'Rejected: a rate rise above 2.00 points needs approval.';
        ROLLBACK TRANSACTION;
        RETURN;
    END;
END;
GO

-- Test 1 fails on purpose (message 3609); uncomment to see it:
-- UPDATE dbo.Practice_Loan                 -- test 1: must fail
-- SET InterestRate = InterestRate
--     + CASE WHEN LoanID = 10001 THEN 0.50 ELSE 2.50 END
-- WHERE LoanID IN (10001, 10002);
GO

SELECT LoanID, InterestRate
FROM dbo.Practice_Loan
WHERE LoanID IN (10001, 10002)
ORDER BY LoanID;
GO

UPDATE dbo.Practice_Loan                 -- test 2: must succeed
SET InterestRate = InterestRate + 0.50
WHERE LoanID IN (10001, 10002);

SELECT LoanID, InterestRate
FROM dbo.Practice_Loan
WHERE LoanID IN (10001, 10002)
ORDER BY LoanID;
GO

-- ==============================================================
-- Correction 27.8
-- ==============================================================

-- Exercise setup: fresh practice copy
DROP TABLE IF EXISTS dbo.Practice_Loan;

SELECT *
INTO dbo.Practice_Loan
FROM dbo.Loan;

ALTER TABLE dbo.Practice_Loan
    ADD CONSTRAINT PK_Practice_Loan PRIMARY KEY (LoanID);
GO
DROP TABLE IF EXISTS dbo.Practice_IndexAudit;

CREATE TABLE dbo.Practice_IndexAudit (
    AuditID          INT IDENTITY(1,1) NOT NULL
                     CONSTRAINT PK_Practice_IndexAudit PRIMARY KEY,
    EventType        NVARCHAR(100)  NOT NULL,
    ObjectName       NVARCHAR(128)  NULL,     -- the index
    TargetObjectName NVARCHAR(128)  NULL      -- its table
);
GO

CREATE OR ALTER TRIGGER trg_IndexAudit
ON DATABASE
FOR CREATE_INDEX, DROP_INDEX
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @e XML = EVENTDATA();
    INSERT INTO dbo.Practice_IndexAudit
        (EventType, ObjectName, TargetObjectName)
    VALUES (
        @e.value('(/EVENT_INSTANCE/EventType)[1]', 'NVARCHAR(100)'),
        @e.value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(128)'),
        @e.value('(/EVENT_INSTANCE/TargetObjectName)[1]',
                 'NVARCHAR(128)'));
END;
GO

CREATE INDEX IX_Practice_Loan_CustomerID
    ON dbo.Practice_Loan (CustomerID);

DROP INDEX IX_Practice_Loan_CustomerID
    ON dbo.Practice_Loan;

SELECT AuditID, EventType, ObjectName, TargetObjectName
FROM dbo.Practice_IndexAudit
ORDER BY AuditID;

DROP TRIGGER trg_IndexAudit ON DATABASE;
GO

-- ==============================================================
-- Clean-up: remove every object created by the exercises
-- ==============================================================

DROP TRIGGER IF EXISTS trg_FreezeDrops, trg_IndexAudit ON DATABASE;
GO
DROP VIEW IF EXISTS dbo.vPractice_ActiveLoan;
DROP TABLE IF EXISTS dbo.Practice_IndexAudit;
DROP TABLE IF EXISTS dbo.Practice_RateAudit;
DROP TABLE IF EXISTS dbo.Practice_LoanDeleted;
DROP TABLE IF EXISTS dbo.Practice_Loan;      -- drops its triggers too
GO
