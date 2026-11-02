/* SQL Server from Zero — Volume 1
   Chapter 22: Changing and removing tables
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- Works on its own: create the schema if the chapter script has not been run.
IF SCHEMA_ID(N'risk') IS NULL
    EXEC (N'CREATE SCHEMA risk AUTHORIZATION dbo;');
GO

-- ------------------------------------------------------------------
-- Set-up for exercises 22.1 to 22.7: a practice copy of dbo.Customer
-- ------------------------------------------------------------------
DROP TABLE IF EXISTS risk.CustomerMaster, risk.CustomerCopy, risk.CallList;

SELECT CustomerID, FirstName, LastName, Phone, City,
       AnnualIncome, CreditScore
INTO risk.CustomerCopy
FROM dbo.Customer;
GO

-- In case a previous run left the temporal table of exercise 22.8.
IF EXISTS (SELECT 1 FROM sys.tables
           WHERE object_id = OBJECT_ID(N'risk.BranchTarget')
             AND temporal_type = 2)
    ALTER TABLE risk.BranchTarget SET (SYSTEM_VERSIONING = OFF);
DROP TABLE IF EXISTS risk.BranchTarget, risk.BranchTargetHistory;
GO

-- ------------------------------------------------------------------
-- Correction 22.1
-- ------------------------------------------------------------------
ALTER TABLE risk.CustomerCopy
ADD Segment NVARCHAR(20) NULL
        CONSTRAINT DF_CustomerCopy_Segment DEFAULT (N'Retail')
        WITH VALUES,                      -- existing rows filled
    Channel NVARCHAR(20) NULL
        CONSTRAINT DF_CustomerCopy_Channel DEFAULT (N'Branch');
                                          -- existing rows stay NULL
GO

SELECT Segment, COUNT(*) AS Customers
FROM risk.CustomerCopy GROUP BY Segment;

SELECT Channel, COUNT(*) AS Customers
FROM risk.CustomerCopy GROUP BY Channel;
GO


-- ------------------------------------------------------------------
-- Correction 22.2
-- ------------------------------------------------------------------
ALTER TABLE risk.CustomerCopy
ALTER COLUMN Phone VARCHAR(30) NULL;     -- repeat NULL explicitly

SELECT COLUMN_NAME, DATA_TYPE,
       CHARACTER_MAXIMUM_LENGTH AS MaxLen, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = N'risk'
  AND TABLE_NAME = N'CustomerCopy'
  AND COLUMN_NAME = N'Phone';
GO


-- ------------------------------------------------------------------
-- Correction 22.3
-- ------------------------------------------------------------------
-- Deliberate error; uncomment to see it:
-- DROP TABLE risk.CustomerArchive;            -- error 3701
GO
DROP TABLE IF EXISTS risk.CustomerArchive;  -- no error
GO


-- ------------------------------------------------------------------
-- Correction 22.4
-- ------------------------------------------------------------------
-- 1) Fails with error 547: some rows break the rule.
--    (Deliberate error; uncomment to see it.)
-- ALTER TABLE risk.CustomerCopy
-- ADD CONSTRAINT CK_CustomerCopy_MinIncome CHECK (AnnualIncome >= 10000);
GO

-- 2) How many?
SELECT COUNT(*) AS BelowFloor
FROM risk.CustomerCopy
WHERE AnnualIncome < 10000;

-- 3) Create it for future rows only.
ALTER TABLE risk.CustomerCopy WITH NOCHECK
ADD CONSTRAINT CK_CustomerCopy_MinIncome CHECK (AnnualIncome >= 10000);

SELECT name, is_disabled, is_not_trusted
FROM sys.check_constraints
WHERE parent_object_id = OBJECT_ID(N'risk.CustomerCopy');
GO


-- ------------------------------------------------------------------
-- Correction 22.5
-- ------------------------------------------------------------------
ALTER TABLE risk.CustomerCopy
DROP CONSTRAINT DF_CustomerCopy_Segment;   -- the dependant first

ALTER TABLE risk.CustomerCopy
DROP COLUMN Segment;                        -- now free to go
GO


-- ------------------------------------------------------------------
-- Correction 22.6
-- ------------------------------------------------------------------
DROP TABLE IF EXISTS risk.CallList;
CREATE TABLE risk.CallList
(
    CallID      INT NOT NULL IDENTITY(100, 1)
        CONSTRAINT PK_CallList PRIMARY KEY,
    CustomerID  INT NOT NULL
);

INSERT INTO risk.CallList (CustomerID)     -- 36 rows: 100 to 135
SELECT CustomerID FROM dbo.Customer
WHERE AnnualIncome < 10000
ORDER BY CustomerID;

DELETE FROM risk.CallList;                 -- counter stays at 135
INSERT INTO risk.CallList (CustomerID) VALUES (1);   -- 136
SELECT CallID, CustomerID FROM risk.CallList;

TRUNCATE TABLE risk.CallList;              -- counter back to seed
INSERT INTO risk.CallList (CustomerID) VALUES (1);   -- 100
SELECT CallID, CustomerID FROM risk.CallList;
GO


-- ------------------------------------------------------------------
-- Correction 22.7
-- ------------------------------------------------------------------
EXEC sp_rename N'risk.CustomerCopy.City', N'TownCity', N'COLUMN';
EXEC sp_rename N'risk.CK_CustomerCopy_MinIncome',
               N'CK_CustomerMaster_MinIncome', N'OBJECT';
EXEC sp_rename N'risk.CustomerCopy', N'CustomerMaster';   -- bare name

SELECT TABLE_NAME, COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = N'risk'
  AND TABLE_NAME = N'CustomerMaster'
  AND COLUMN_NAME LIKE N'%City%';

SELECT TABLE_NAME, CONSTRAINT_NAME
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
WHERE TABLE_SCHEMA = N'risk'
  AND TABLE_NAME = N'CustomerMaster';
GO


-- ------------------------------------------------------------------
-- Correction 22.8
-- ------------------------------------------------------------------
CREATE TABLE risk.BranchTarget
(
    BranchID       INT            NOT NULL
        CONSTRAINT PK_BranchTarget PRIMARY KEY,
    LendingTarget  DECIMAL(14,2)  NOT NULL,
    ValidFrom      DATETIME2 GENERATED ALWAYS AS ROW START NOT NULL,
    ValidTo        DATETIME2 GENERATED ALWAYS AS ROW END NOT NULL,
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)
)
WITH (SYSTEM_VERSIONING = ON
      (HISTORY_TABLE = risk.BranchTargetHistory));

INSERT INTO risk.BranchTarget (BranchID, LendingTarget)
VALUES (1, 9000000.00), (2, 12000000.00), (3, 11500000.00);

WAITFOR DELAY '00:00:01';
DECLARE @T1 DATETIME2 = SYSUTCDATETIME();     -- before change 1
WAITFOR DELAY '00:00:01';
UPDATE risk.BranchTarget SET LendingTarget = 12500000.00
WHERE BranchID = 2;

WAITFOR DELAY '00:00:01';
DECLARE @T2 DATETIME2 = SYSUTCDATETIME();     -- before change 2
WAITFOR DELAY '00:00:01';
UPDATE risk.BranchTarget SET LendingTarget = 13000000.00
WHERE BranchID = 2;

SELECT 'As of T1' AS Moment, LendingTarget
FROM risk.BranchTarget FOR SYSTEM_TIME AS OF @T1 WHERE BranchID = 2
UNION ALL
SELECT 'As of T2', LendingTarget
FROM risk.BranchTarget FOR SYSTEM_TIME AS OF @T2 WHERE BranchID = 2
UNION ALL
SELECT 'Now', LendingTarget
FROM risk.BranchTarget WHERE BranchID = 2;

SELECT LendingTarget
FROM risk.BranchTarget FOR SYSTEM_TIME ALL
WHERE BranchID = 2
ORDER BY ValidFrom;

ALTER TABLE risk.BranchTarget SET (SYSTEM_VERSIONING = OFF);
DROP TABLE risk.BranchTarget, risk.BranchTargetHistory;
GO

