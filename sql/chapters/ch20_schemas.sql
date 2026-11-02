/* SQL Server from Zero — Volume 1
   Chapter 20: Schemas and ownership
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- 1. What a schema is
USE NorthbridgeLending;
GO
SELECT s.schema_id,
       s.name  AS SchemaName,
       p.name  AS OwnerName
FROM sys.schemas AS s
INNER JOIN sys.database_principals AS p
    ON p.principal_id = s.principal_id
WHERE s.schema_id < 16384          -- leave out role schemas
ORDER BY s.schema_id;
GO
SELECT SCHEMA_NAME(schema_id) AS SchemaName,
       COUNT(*)               AS TableCount
FROM sys.tables
GROUP BY schema_id
ORDER BY SchemaName;
GO

-- 2. Creating schemas with CREATE SCHEMA
-- Reset: remove what an earlier run of this script left behind
IF SCHEMA_ID(N'risk') IS NOT NULL
    ALTER AUTHORIZATION ON SCHEMA::risk TO dbo;
DROP USER IF EXISTS RiskAnalyst;
DROP TABLE IF EXISTS staging.Payment_Load, risk.Payment_Load,
                     risk.ArrearsLoans, reporting.Branch,
                     dbo.Risk_ArrearsLoans;
DROP SCHEMA IF EXISTS sandbox;
GO

-- The book creates the schemas with plain CREATE SCHEMA batches.
-- The script uses the rerunnable form (end of section 2), so that it
-- can run on a database where the schemas already exist.
IF SCHEMA_ID(N'staging') IS NULL
    EXEC (N'CREATE SCHEMA staging AUTHORIZATION dbo;');
IF SCHEMA_ID(N'risk') IS NULL
    EXEC (N'CREATE SCHEMA risk AUTHORIZATION dbo;');
IF SCHEMA_ID(N'reporting') IS NULL
    EXEC (N'CREATE SCHEMA reporting AUTHORIZATION dbo;');
GO
SELECT s.name AS SchemaName,
       p.name AS OwnerName
FROM sys.schemas AS s
INNER JOIN sys.database_principals AS p
    ON p.principal_id = s.principal_id
WHERE s.name IN (N'staging', N'risk', N'reporting')
ORDER BY s.name;
GO
-- Error demonstration: remove the leading -- and run these lines
-- on their own to see the error described in the book.
-- SELECT 1 AS Step;
-- CREATE SCHEMA sandbox AUTHORIZATION dbo;
GO
IF SCHEMA_ID(N'risk') IS NULL
    EXEC (N'CREATE SCHEMA risk AUTHORIZATION dbo;');

IF SCHEMA_ID(N'staging') IS NULL
    EXEC (N'CREATE SCHEMA staging AUTHORIZATION dbo;');

IF SCHEMA_ID(N'reporting') IS NULL
    EXEC (N'CREATE SCHEMA reporting AUTHORIZATION dbo;');
GO

-- 3. Putting objects in schemas and querying them
-- Raw copy: every missed instalment
SELECT PaymentID, LoanID, InstalmentNumber, DueDate, AmountDue
INTO staging.Payment_Load
FROM dbo.Payment
WHERE PaidDate IS NULL;

-- Curated table: loans in arrears or in default
SELECT LoanID, CustomerID, BranchID, LoanStatus,
       OutstandingBalance
INTO risk.ArrearsLoans
FROM dbo.Loan
WHERE LoanStatus IN (N'Arrears', N'Default');

-- A table with the same name as a dbo table
SELECT BranchID, BranchName, Region
INTO reporting.Branch
FROM dbo.Branch;
GO
SELECT TABLE_SCHEMA, TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_SCHEMA, TABLE_NAME;
GO
SELECT 'dbo.Branch'       AS TableName,
       COUNT(*)           AS RowCnt,
       OBJECT_ID(N'dbo.Branch') AS ObjectID
FROM dbo.Branch
UNION ALL
SELECT 'reporting.Branch',
       COUNT(*),
       OBJECT_ID(N'reporting.Branch')
FROM reporting.Branch;
GO
-- Error demonstration: remove the leading -- and run these lines
-- on their own to see the error described in the book.
-- SELECT LoanID, LoanStatus
-- INTO Risk_ArrearsLoans          -- meant: risk.ArrearsLoans
-- FROM dbo.Loan
-- WHERE LoanStatus = N'Arrears';
GO

-- 4. Name resolution and the default schema
SELECT USER_NAME()   AS CurrentUser,
       SCHEMA_NAME() AS DefaultSchema;
GO
-- A test user with no login; Volume 2 explains CREATE USER in full
CREATE USER RiskAnalyst WITHOUT LOGIN
    WITH DEFAULT_SCHEMA = risk;
GO
EXECUTE AS USER = N'RiskAnalyst';   -- act as the test user

SELECT USER_NAME()   AS CurrentUser,
       SCHEMA_NAME() AS DefaultSchema;

REVERT;                              -- back to yourself
GO

-- 5. Ownership: ALTER AUTHORIZATION
ALTER AUTHORIZATION ON SCHEMA::risk TO RiskAnalyst;

SELECT s.name AS SchemaName,
       p.name AS OwnerName
FROM sys.schemas AS s
INNER JOIN sys.database_principals AS p
    ON p.principal_id = s.principal_id
WHERE s.name = N'risk';
GO
EXECUTE AS USER = N'RiskAnalyst';

-- 1. One-part name: resolved in the default schema, risk
SELECT COUNT(*) AS ArrearsLoans
FROM ArrearsLoans;

-- 2. One-part name that exists only in dbo
SELECT COUNT(*) AS Branches
FROM Branch;

REVERT;
GO
ALTER AUTHORIZATION ON SCHEMA::risk TO dbo;
GO

-- 6. Moving objects: ALTER SCHEMA … TRANSFER
ALTER SCHEMA risk TRANSFER staging.Payment_Load;

SELECT SCHEMA_NAME(schema_id) AS SchemaName,
       name                   AS TableName
FROM sys.tables
WHERE schema_id <> SCHEMA_ID(N'dbo')
ORDER BY SchemaName, TableName;
GO
-- Error demonstration: remove the leading -- and run these lines
-- on their own to see the error described in the book.
-- ALTER SCHEMA risk.Payment_Load TRANSFER staging;   -- reversed
GO

-- 7. Removing schemas: DROP SCHEMA
-- Error demonstration: remove the leading -- and run these lines
-- on their own to see the error described in the book.
-- DROP SCHEMA reporting;
GO
SELECT name, type_desc
FROM sys.objects
WHERE schema_id = SCHEMA_ID(N'reporting')
ORDER BY name;
GO
DROP TABLE IF EXISTS reporting.Branch;   -- chapter 22 in full
GO
CREATE SCHEMA sandbox AUTHORIZATION dbo;
GO
DROP SCHEMA sandbox;                     -- empty: succeeds
DROP SCHEMA IF EXISTS sandbox;           -- absent: no error

SELECT SCHEMA_ID(N'sandbox') AS SandboxID;
GO

-- Applied example

-- Step 1. Make sure the schemas exist
USE NorthbridgeLending;
GO
IF SCHEMA_ID(N'staging') IS NULL
    EXEC (N'CREATE SCHEMA staging AUTHORIZATION dbo;');
IF SCHEMA_ID(N'risk') IS NULL
    EXEC (N'CREATE SCHEMA risk AUTHORIZATION dbo;');
IF SCHEMA_ID(N'reporting') IS NULL
    EXEC (N'CREATE SCHEMA reporting AUTHORIZATION dbo;');

-- Remove last run's tables, so the script can run again
DROP TABLE IF EXISTS staging.Payment_Sep2026,
                     risk.Missed_Sep2026,
                     reporting.BranchMissed_Sep2026;
GO

-- Step 2. Load the raw instalments into staging
DECLARE @MonthStart DATE = '2026-09-01';
DECLARE @MonthEnd   DATE = '2026-09-30';

SELECT PaymentID, LoanID, InstalmentNumber, DueDate,
       AmountDue, PaidDate, AmountPaid
INTO staging.Payment_Sep2026
FROM dbo.Payment
WHERE DueDate BETWEEN @MonthStart AND @MonthEnd;
GO

-- Step 3. Build the curated table in risk
SELECT s.PaymentID,
       s.LoanID,
       l.BranchID,
       s.DueDate,
       s.AmountDue
INTO risk.Missed_Sep2026
FROM staging.Payment_Sep2026 AS s
INNER JOIN dbo.Loan AS l
    ON l.LoanID = s.LoanID
WHERE s.PaidDate IS NULL;
GO

-- Step 4. Publish the branch summary in reporting
SELECT b.BranchID,
       b.BranchName,
       COUNT(*)         AS MissedCount,
       SUM(m.AmountDue) AS AmountMissed
INTO reporting.BranchMissed_Sep2026
FROM risk.Missed_Sep2026 AS m
INNER JOIN dbo.Branch AS b
    ON b.BranchID = m.BranchID
GROUP BY b.BranchID, b.BranchName;

SELECT BranchName, MissedCount, AmountMissed
FROM reporting.BranchMissed_Sep2026
ORDER BY BranchID;
GO

-- Step 5. Inventory of the team's tables
SELECT s.name   AS SchemaName,
       t.name   AS TableName,
       p.rows   AS RowCnt
FROM sys.schemas AS s
INNER JOIN sys.tables AS t
    ON t.schema_id = s.schema_id
INNER JOIN sys.partitions AS p
    ON p.object_id = t.object_id
   AND p.index_id IN (0, 1)
WHERE s.name IN (N'staging', N'risk', N'reporting')
ORDER BY CASE s.name WHEN N'staging' THEN 1
                     WHEN N'risk'    THEN 2
                     ELSE 3 END,
         t.name;
GO

-- Clean-up: remove this chapter's practice tables and test user.
-- The base tables in dbo were never changed. The three schemas
-- staging, risk and reporting stay, empty, for chapter 21.
USE NorthbridgeLending;
GO
IF SCHEMA_ID(N'risk') IS NOT NULL
    ALTER AUTHORIZATION ON SCHEMA::risk TO dbo;
DROP USER IF EXISTS RiskAnalyst;
DROP TABLE IF EXISTS staging.Payment_Load, risk.Payment_Load,
                     risk.ArrearsLoans, reporting.Branch,
                     staging.Payment_Sep2026, risk.Missed_Sep2026,
                     reporting.BranchMissed_Sep2026,
                     dbo.Risk_ArrearsLoans;
DROP SCHEMA IF EXISTS sandbox;
GO
