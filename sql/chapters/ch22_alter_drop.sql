/* SQL Server from Zero — Volume 1
   Chapter 22: Changing and removing tables
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- ------------------------------------------------------------------
-- Before you start
-- ------------------------------------------------------------------
USE NorthbridgeLending;

IF SCHEMA_ID(N'risk') IS NULL
    EXEC (N'CREATE SCHEMA risk;');

-- A temporal table must stop versioning before it can be dropped.
IF EXISTS (SELECT 1 FROM sys.tables
           WHERE object_id = OBJECT_ID(N'risk.ProductRate')
             AND temporal_type = 2)
    ALTER TABLE risk.ProductRate SET (SYSTEM_VERSIONING = OFF);
IF EXISTS (SELECT 1 FROM sys.tables
           WHERE object_id = OBJECT_ID(N'risk.CollateralRegister')
             AND temporal_type = 2)
    ALTER TABLE risk.CollateralRegister
        SET (SYSTEM_VERSIONING = OFF);

DROP TABLE IF EXISTS risk.QueueNote, risk.ReviewQueue,
    risk.LoanCopy, risk.LoanSnapshot,
    risk.ProductRate, risk.ProductRateHistory,
    risk.CollateralRegister, risk.CollateralRegisterHistory;

-- The practice copy: types and NOT NULL are copied, constraints not.
SELECT LoanID, CustomerID, ProductCode, BranchID, Principal,
       InterestRate, LoanStatus, OutstandingBalance
INTO risk.LoanCopy
FROM dbo.Loan;
GO


-- ------------------------------------------------------------------
-- 1. Adding columns
-- ------------------------------------------------------------------
ALTER TABLE risk.LoanCopy
ADD WatchFlag NVARCHAR(10) NULL;
GO

SELECT TOP (3) LoanID, LoanStatus, WatchFlag
FROM risk.LoanCopy
ORDER BY LoanID;
GO

-- Deliberate error 4901 (no default for a NOT NULL column):
-- ALTER TABLE risk.LoanCopy
-- ADD ReviewRequired BIT NOT NULL;

ALTER TABLE risk.LoanCopy
ADD ReviewRequired BIT NOT NULL
    CONSTRAINT DF_LoanCopy_ReviewRequired DEFAULT (0);
GO

SELECT ReviewRequired, COUNT(*) AS Loans
FROM risk.LoanCopy
GROUP BY ReviewRequired;
GO

ALTER TABLE risk.LoanCopy
ADD SourceSystem NVARCHAR(20) NULL
    CONSTRAINT DF_LoanCopy_SourceSystem DEFAULT (N'Core')
    WITH VALUES;
GO

SELECT SourceSystem, COUNT(*) AS Loans
FROM risk.LoanCopy
GROUP BY SourceSystem;
GO


-- ------------------------------------------------------------------
-- 2. Changing a column: ALTER COLUMN
-- ------------------------------------------------------------------
ALTER TABLE risk.LoanCopy
ALTER COLUMN LoanStatus NVARCHAR(30) NOT NULL;

SELECT COLUMN_NAME, DATA_TYPE,
       CHARACTER_MAXIMUM_LENGTH AS MaxLen, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = N'risk'
  AND TABLE_NAME = N'LoanCopy'
  AND COLUMN_NAME = N'LoanStatus';
GO

-- Deliberate error 515 (WatchFlag holds NULL in 800 rows):
-- ALTER TABLE risk.LoanCopy
-- ALTER COLUMN WatchFlag NVARCHAR(10) NOT NULL;

UPDATE risk.LoanCopy
SET WatchFlag = CASE WHEN LoanStatus IN (N'Arrears', N'Default')
                     THEN N'Watch' ELSE N'None' END;

ALTER TABLE risk.LoanCopy
ALTER COLUMN WatchFlag NVARCHAR(10) NOT NULL;

SELECT WatchFlag, COUNT(*) AS Loans
FROM risk.LoanCopy
GROUP BY WatchFlag
ORDER BY WatchFlag;
GO


-- ------------------------------------------------------------------
-- 3. Removing a column: DROP COLUMN
-- ------------------------------------------------------------------
ALTER TABLE risk.LoanCopy
DROP COLUMN WatchFlag;
GO

-- Deliberate errors 5074 and 4922 (a default depends on the column):
-- ALTER TABLE risk.LoanCopy
-- DROP COLUMN ReviewRequired;

ALTER TABLE risk.LoanCopy
DROP CONSTRAINT DF_LoanCopy_ReviewRequired;

ALTER TABLE risk.LoanCopy
DROP COLUMN ReviewRequired;

ALTER TABLE risk.LoanCopy
DROP CONSTRAINT IF EXISTS DF_LoanCopy_SourceSystem;

ALTER TABLE risk.LoanCopy
DROP COLUMN IF EXISTS SourceSystem;
GO


-- ------------------------------------------------------------------
-- 4. Adding, removing and suspending constraints
-- ------------------------------------------------------------------
ALTER TABLE risk.LoanCopy
ADD CONSTRAINT PK_LoanCopy PRIMARY KEY (LoanID);

ALTER TABLE risk.LoanCopy
ADD CONSTRAINT FK_LoanCopy_Branch
    FOREIGN KEY (BranchID) REFERENCES dbo.Branch (BranchID);
GO

-- Deliberate error 547 (29 rows break the rule):
-- ALTER TABLE risk.LoanCopy
-- ADD CONSTRAINT CK_LoanCopy_Balance
--     CHECK (OutstandingBalance <= Principal);

SELECT LoanStatus, COUNT(*) AS Loans
FROM risk.LoanCopy
WHERE OutstandingBalance > Principal
GROUP BY LoanStatus
ORDER BY LoanStatus;
GO

ALTER TABLE risk.LoanCopy
ADD CONSTRAINT CK_LoanCopy_Balance
    CHECK (OutstandingBalance <= Principal
        OR LoanStatus IN (N'Arrears', N'Default', N'Written Off'));
GO

ALTER TABLE risk.LoanCopy WITH NOCHECK
ADD CONSTRAINT CK_LoanCopy_RateFloor CHECK (InterestRate >= 4.50);

SELECT name, is_disabled, is_not_trusted
FROM sys.check_constraints
WHERE parent_object_id = OBJECT_ID(N'risk.LoanCopy')
ORDER BY name;
GO

ALTER TABLE risk.LoanCopy NOCHECK CONSTRAINT CK_LoanCopy_Balance;
-- ... a load that must bypass the rule would run here ...
ALTER TABLE risk.LoanCopy CHECK CONSTRAINT CK_LoanCopy_Balance;
GO

ALTER TABLE risk.LoanCopy
    WITH CHECK CHECK CONSTRAINT CK_LoanCopy_Balance;
GO


-- ------------------------------------------------------------------
-- 5. Removing tables: DROP TABLE
-- ------------------------------------------------------------------
CREATE TABLE risk.ReviewQueue
(
    QueueID  INT  NOT NULL IDENTITY(1, 1)
        CONSTRAINT PK_ReviewQueue PRIMARY KEY,
    LoanID   INT  NOT NULL
);

CREATE TABLE risk.QueueNote
(
    NoteID   INT            NOT NULL IDENTITY(1, 1)
        CONSTRAINT PK_QueueNote PRIMARY KEY,
    QueueID  INT            NOT NULL
        CONSTRAINT FK_QueueNote_ReviewQueue
            REFERENCES risk.ReviewQueue (QueueID),
    NoteText NVARCHAR(200)  NOT NULL
);

-- Deliberate error 3726 (QueueNote references the queue):
-- DROP TABLE risk.ReviewQueue;
GO

-- Keep both tables for section 6.


-- ------------------------------------------------------------------
-- 6. Emptying a table: TRUNCATE TABLE or DELETE
-- ------------------------------------------------------------------
INSERT INTO risk.ReviewQueue (LoanID)
SELECT LoanID
FROM risk.LoanCopy
WHERE LoanStatus <> N'Repaid'
ORDER BY LoanID;

DELETE FROM risk.ReviewQueue;

INSERT INTO risk.ReviewQueue (LoanID) VALUES (10002);

SELECT QueueID, LoanID FROM risk.ReviewQueue;
GO

-- Deliberate error 4712 (referenced by a foreign key):
-- TRUNCATE TABLE risk.ReviewQueue;

DROP TABLE risk.QueueNote;

TRUNCATE TABLE risk.ReviewQueue;

INSERT INTO risk.ReviewQueue (LoanID) VALUES (10002);

SELECT QueueID, LoanID FROM risk.ReviewQueue;
GO


-- ------------------------------------------------------------------
-- 7. Renaming with sp_rename
-- ------------------------------------------------------------------
CREATE INDEX IX_LoanCopy_BranchID ON risk.LoanCopy (BranchID);

EXEC sp_rename N'risk.LoanCopy.CustomerID', N'BorrowerID', N'COLUMN';
EXEC sp_rename N'risk.LoanCopy.IX_LoanCopy_BranchID',
               N'IX_LoanCopy_Branch', N'INDEX';
EXEC sp_rename N'risk.LoanCopy', N'LoanSnapshot';
EXEC sp_rename N'risk.PK_LoanCopy', N'PK_LoanSnapshot', N'OBJECT';
GO

SELECT name, index_id
FROM sys.indexes
WHERE object_id = OBJECT_ID(N'risk.LoanSnapshot')
ORDER BY index_id;
GO


-- ------------------------------------------------------------------
-- 8. System-versioned temporal tables
-- ------------------------------------------------------------------
CREATE TABLE risk.ProductRate
(
    ProductCode  VARCHAR(10)   NOT NULL
        CONSTRAINT PK_ProductRate PRIMARY KEY,
    BaseRate     DECIMAL(5,2)  NOT NULL,
    ValidFrom    DATETIME2     GENERATED ALWAYS AS ROW START NOT NULL,
    ValidTo      DATETIME2     GENERATED ALWAYS AS ROW END NOT NULL,
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)
)
WITH (SYSTEM_VERSIONING = ON
      (HISTORY_TABLE = risk.ProductRateHistory));

INSERT INTO risk.ProductRate (ProductCode, BaseRate)
SELECT ProductCode, BaseRate FROM dbo.Product;

WAITFOR DELAY '00:00:01';
DECLARE @Before DATETIME2 = SYSUTCDATETIME();
WAITFOR DELAY '00:00:01';

UPDATE risk.ProductRate
SET BaseRate = BaseRate + 0.25
WHERE ProductCode LIKE 'MTG%';

SELECT cur.ProductCode,
       prev.BaseRate AS RateBefore,
       cur.BaseRate  AS RateNow
FROM risk.ProductRate AS cur
INNER JOIN risk.ProductRate FOR SYSTEM_TIME AS OF @Before AS prev
    ON prev.ProductCode = cur.ProductCode
ORDER BY cur.ProductCode;
GO

SELECT ProductCode, BaseRate,
       CASE WHEN ValidTo = '9999-12-31 23:59:59.9999999'
            THEN 'Current' ELSE 'History' END AS VersionType
FROM risk.ProductRate FOR SYSTEM_TIME ALL
WHERE ProductCode = 'MTG-FIX5'
ORDER BY ValidFrom;
GO

ALTER TABLE risk.ProductRate SET (SYSTEM_VERSIONING = OFF);
DROP TABLE risk.ProductRate, risk.ProductRateHistory;
GO


-- ------------------------------------------------------------------
-- Applied example
-- ------------------------------------------------------------------

-- ------------------------------------------------------------------
-- Applied example, Step 1. Copy the data.
-- ------------------------------------------------------------------
SELECT CollateralID, LoanID, CollateralType, Description,
       ValuationAmount, ValuationDate
INTO risk.CollateralRegister
FROM dbo.Collateral;
GO


-- ------------------------------------------------------------------
-- Applied example, Step 2. Add the key, the rules and a clearer name.
-- ------------------------------------------------------------------
ALTER TABLE risk.CollateralRegister
ADD CONSTRAINT PK_CollateralRegister PRIMARY KEY (CollateralID),
    CONSTRAINT FK_CollateralRegister_Loan
        FOREIGN KEY (LoanID) REFERENCES dbo.Loan (LoanID),
    CONSTRAINT CK_CollateralRegister_Value
        CHECK (ValuationAmount > 0);

EXEC sp_rename N'risk.CollateralRegister.Description',
               N'AssetDescription', N'COLUMN';
GO


-- ------------------------------------------------------------------
-- Applied example, Step 3. Add the revaluation date.
-- ------------------------------------------------------------------
ALTER TABLE risk.CollateralRegister
ADD RevaluationDue DATE NULL;
GO

UPDATE risk.CollateralRegister
SET RevaluationDue =
    DATEADD(YEAR,
            CASE WHEN CollateralType LIKE N'%Property' THEN 3 ELSE 1 END,
            ValuationDate);

ALTER TABLE risk.CollateralRegister
ALTER COLUMN RevaluationDue DATE NOT NULL;

SELECT CollateralType,
       COUNT(*) AS Items,
       SUM(CASE WHEN RevaluationDue < '2026-09-30'
                THEN 1 ELSE 0 END) AS Overdue
FROM risk.CollateralRegister
GROUP BY CollateralType
ORDER BY CollateralType;
GO


-- ------------------------------------------------------------------
-- Applied example, Step 4. Turn on history.
-- ------------------------------------------------------------------
ALTER TABLE risk.CollateralRegister
ADD ValidFrom DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
        CONSTRAINT DF_CollateralRegister_ValidFrom
            DEFAULT (SYSUTCDATETIME()),
    ValidTo DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
        CONSTRAINT DF_CollateralRegister_ValidTo
            DEFAULT (CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999')),
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo);

ALTER TABLE risk.CollateralRegister
SET (SYSTEM_VERSIONING = ON
     (HISTORY_TABLE = risk.CollateralRegisterHistory));
GO


-- ------------------------------------------------------------------
-- Applied example, Step 5. Revalue and compare.
-- ------------------------------------------------------------------
WAITFOR DELAY '00:00:01';
DECLARE @Before DATETIME2 = SYSUTCDATETIME();
WAITFOR DELAY '00:00:01';

UPDATE risk.CollateralRegister
SET ValuationAmount = CAST(ValuationAmount * 0.95 AS DECIMAL(12,2)),
    ValuationDate   = '2026-09-30',
    RevaluationDue  = '2029-09-30'
WHERE CollateralType = N'Residential Property'
  AND RevaluationDue < '2026-09-30';

SELECT 'Before' AS State, SUM(ValuationAmount) AS TotalValue
FROM risk.CollateralRegister FOR SYSTEM_TIME AS OF @Before
UNION ALL
SELECT 'After', SUM(ValuationAmount)
FROM risk.CollateralRegister;

SELECT COUNT(*) AS HistoryRows
FROM risk.CollateralRegisterHistory;
GO


-- ------------------------------------------------------------------
-- Applied example, Step 6. Read the audit trail of one item.
-- ------------------------------------------------------------------
SELECT CollateralID, ValuationAmount, ValuationDate
FROM risk.CollateralRegister FOR SYSTEM_TIME ALL
WHERE CollateralID = 1
ORDER BY ValidFrom;
GO


-- ------------------------------------------------------------------
-- Clean-up (optional). The base tables are never changed by this
-- script; uncomment to remove the practice tables.
-- ------------------------------------------------------------------
-- ALTER TABLE risk.CollateralRegister SET (SYSTEM_VERSIONING = OFF);
-- DROP TABLE IF EXISTS risk.CollateralRegister,
--     risk.CollateralRegisterHistory, risk.ReviewQueue,
--     risk.QueueNote, risk.LoanSnapshot;
-- GO
