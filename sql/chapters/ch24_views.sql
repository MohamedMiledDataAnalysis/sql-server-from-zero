/* SQL Server from Zero — Volume 1
   Chapter 24: Views, synonyms and sequences
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

/* This script creates views, synonyms, sequences and practice tables.
   It changes no base table data. Statements marked "FAILS ON PURPOSE"
   show an error message from the book; they are commented out so
   that the script runs end to end. Uncomment one to see its error. */

-- The reporting schema from chapter 20 (created here if missing)
IF SCHEMA_ID(N'reporting') IS NULL EXEC (N'CREATE SCHEMA reporting');
GO

-- Start from a clean state so that the script can run more than once
DROP SYNONYM IF EXISTS reporting.CollectionsQueue;
DROP SYNONYM IF EXISTS reporting.LoanBook;
DROP SYNONYM IF EXISTS reporting.LoanArchive;
DROP VIEW IF EXISTS
    reporting.vw_CollectionsQueue,
    reporting.vw_BranchStatusExposure,
    reporting.vw_PracticeExposure,
    reporting.vw_PracticeArrears,
    reporting.vw_PracticeBranch,
    reporting.vw_LoanOverviewSorted,
    reporting.vw_LoanOverview;
DROP TABLE IF EXISTS
    dbo.Practice_CollectionsWorklist,
    dbo.Practice_CollectionsCase,
    dbo.Practice_Loan,
    dbo.Practice_Branch;
DROP SEQUENCE IF EXISTS
    dbo.seq_CaseNumber,
    dbo.seq_Tiny,
    dbo.seq_Worklist;
GO

-- ============================================================
-- 1. Creating and querying a view
-- ============================================================

GO
CREATE VIEW reporting.vw_LoanOverview
AS
SELECT
    l.LoanID,
    l.CustomerID,
    p.ProductName,
    p.ProductType,
    b.BranchName,
    l.LoanStatus,
    l.Principal,
    l.OutstandingBalance
FROM dbo.Loan AS l
INNER JOIN dbo.Product AS p
    ON p.ProductCode = l.ProductCode
INNER JOIN dbo.Branch AS b
    ON b.BranchID = l.BranchID;
GO

SELECT TOP (5)
    LoanID,
    ProductName,
    BranchName,
    LoanStatus,
    OutstandingBalance
FROM reporting.vw_LoanOverview
ORDER BY LoanID;

-- ============================================================
-- 2. Inspecting, changing and dropping views
-- ============================================================

SELECT OBJECT_DEFINITION(OBJECT_ID(N'reporting.vw_LoanOverview'))
    AS ViewDefinition;

GO
CREATE OR ALTER VIEW reporting.vw_LoanOverview
AS
SELECT
    l.LoanID,
    l.CustomerID,
    p.ProductName,
    p.ProductType,
    b.BranchName,
    l.LoanStatus,
    l.Principal,
    l.InterestRate,          -- new column
    l.OutstandingBalance
FROM dbo.Loan AS l
INNER JOIN dbo.Product AS p
    ON p.ProductCode = l.ProductCode
INNER JOIN dbo.Branch AS b
    ON b.BranchID = l.BranchID;
GO

SELECT TOP (3)
    LoanID,
    ProductName,
    InterestRate
FROM reporting.vw_LoanOverview
ORDER BY LoanID;

GO
-- FAILS ON PURPOSE: Msg 1033, ORDER BY is invalid in views
-- CREATE OR ALTER VIEW reporting.vw_LoanOverviewSorted
-- AS
-- SELECT LoanID, LoanStatus
-- FROM dbo.Loan
-- ORDER BY LoanID;
GO

DROP VIEW IF EXISTS reporting.vw_LoanOverviewSorted;

-- ============================================================
-- 3. Protecting a view with WITH SCHEMABINDING
-- ============================================================

DROP TABLE IF EXISTS dbo.Practice_Loan;
SELECT * INTO dbo.Practice_Loan FROM dbo.Loan;
GO

CREATE OR ALTER VIEW reporting.vw_PracticeExposure
WITH SCHEMABINDING
AS
SELECT
    LoanID,
    BranchID,
    LoanStatus,
    OutstandingBalance
FROM dbo.Practice_Loan;
GO

-- FAILS ON PURPOSE: Msg 5074 and Msg 4922
-- ALTER TABLE dbo.Practice_Loan
--     DROP COLUMN OutstandingBalance;
GO

ALTER TABLE dbo.Practice_Loan
    DROP COLUMN ApplicationDate;

-- ============================================================
-- 4. Indexed views: storing the result of a view
-- ============================================================

GO
CREATE OR ALTER VIEW reporting.vw_BranchStatusExposure
WITH SCHEMABINDING
AS
SELECT
    BranchID,
    LoanStatus,
    COUNT_BIG(*) AS LoanCount,               -- required
    SUM(OutstandingBalance) AS TotalOutstanding
FROM dbo.Loan
GROUP BY BranchID, LoanStatus;
GO

CREATE UNIQUE CLUSTERED INDEX UCX_vw_BranchStatusExposure
    ON reporting.vw_BranchStatusExposure (BranchID, LoanStatus);
GO

SELECT
    BranchID,
    LoanStatus,
    LoanCount,
    TotalOutstanding
FROM reporting.vw_BranchStatusExposure WITH (NOEXPAND)
WHERE BranchID = 1
ORDER BY LoanStatus;

-- ============================================================
-- 5. Changing data through a view and WITH CHECK OPTION
-- ============================================================

GO
CREATE OR ALTER VIEW reporting.vw_PracticeArrears
AS
SELECT
    LoanID,
    CustomerID,
    LoanStatus,
    OutstandingBalance
FROM dbo.Practice_Loan
WHERE LoanStatus = N'Arrears';
GO

SELECT COUNT(*) AS LoansInView
FROM reporting.vw_PracticeArrears;

UPDATE reporting.vw_PracticeArrears
SET LoanStatus = N'Default'
WHERE LoanID = 10086;

SELECT COUNT(*) AS LoansInView
FROM reporting.vw_PracticeArrears;

GO
CREATE OR ALTER VIEW reporting.vw_PracticeArrears
AS
SELECT
    LoanID,
    CustomerID,
    LoanStatus,
    OutstandingBalance
FROM dbo.Practice_Loan
WHERE LoanStatus = N'Arrears'
WITH CHECK OPTION;
GO

-- FAILS ON PURPOSE: Msg 550, WITH CHECK OPTION
-- UPDATE reporting.vw_PracticeArrears
-- SET LoanStatus = N'Default'
-- WHERE LoanID = 10183;
GO

-- ============================================================
-- 6. Synonyms: a second name for an object
-- ============================================================

CREATE SYNONYM reporting.LoanBook
    FOR NorthbridgeLending.dbo.Loan;
GO

SELECT COUNT(*) AS LoanCount
FROM reporting.LoanBook;

CREATE SYNONYM reporting.LoanArchive
    FOR NorthbridgeLending.dbo.Loan_Archive2025;
GO

-- FAILS ON PURPOSE: error 5313, the target does not exist
-- SELECT COUNT(*) FROM reporting.LoanArchive;
GO

SELECT name, base_object_name
FROM sys.synonyms
WHERE schema_id = SCHEMA_ID(N'reporting')
ORDER BY name;

DROP SYNONYM IF EXISTS reporting.LoanArchive;
GO
CREATE SYNONYM reporting.LoanArchive
    FOR NorthbridgeLending.dbo.Practice_Loan;
GO

SELECT COUNT(*) AS LoanCount
FROM reporting.LoanArchive;

-- ============================================================
-- 7. Sequences: numbers that belong to no table
-- ============================================================

CREATE SEQUENCE dbo.seq_CaseNumber
    AS INT
    START WITH 1000
    INCREMENT BY 1
    NO CYCLE
    CACHE 50;
GO

SELECT NEXT VALUE FOR dbo.seq_CaseNumber AS CaseNumber;
SELECT NEXT VALUE FOR dbo.seq_CaseNumber AS CaseNumber;

DROP TABLE IF EXISTS dbo.Practice_CollectionsCase;

CREATE TABLE dbo.Practice_CollectionsCase
(
    CaseNumber INT NOT NULL
        CONSTRAINT PK_Practice_CollectionsCase PRIMARY KEY
        CONSTRAINT DF_Practice_CollectionsCase_CaseNumber
            DEFAULT (NEXT VALUE FOR dbo.seq_CaseNumber),
    LoanID INT NOT NULL,
    OpenedDate DATE NOT NULL,
    BalanceAtOpening DECIMAL(12,2) NOT NULL
);
GO

INSERT INTO dbo.Practice_CollectionsCase
    (LoanID, OpenedDate, BalanceAtOpening)
VALUES
    (10076, '2026-09-30', 30660.29);

SELECT CaseNumber, LoanID, BalanceAtOpening
FROM dbo.Practice_CollectionsCase;

INSERT INTO dbo.Practice_CollectionsCase
    (CaseNumber, LoanID, OpenedDate, BalanceAtOpening)
SELECT
    NEXT VALUE FOR dbo.seq_CaseNumber OVER (ORDER BY LoanID),
    LoanID,
    '2026-09-30',
    OutstandingBalance
FROM dbo.Loan
WHERE LoanStatus = N'Default';

SELECT TOP (5) CaseNumber, LoanID, BalanceAtOpening
FROM dbo.Practice_CollectionsCase
WHERE CaseNumber > 1002
ORDER BY CaseNumber;

-- ============================================================
-- 8. Managing sequences: ALTER SEQUENCE, ranges and gaps
-- ============================================================

ALTER SEQUENCE dbo.seq_CaseNumber
    RESTART WITH 2000
    INCREMENT BY 5;

SELECT NEXT VALUE FOR dbo.seq_CaseNumber AS CaseNumber;

DECLARE @First SQL_VARIANT,
        @Last  SQL_VARIANT;

EXEC sys.sp_sequence_get_range
    @sequence_name     = N'dbo.seq_CaseNumber',
    @range_size        = 10,
    @range_first_value = @First OUTPUT,
    @range_last_value  = @Last OUTPUT;

SELECT CAST(@First AS INT) AS FirstReserved,
       CAST(@Last  AS INT) AS LastReserved;

CREATE SEQUENCE dbo.seq_Tiny
    AS TINYINT
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    MAXVALUE 3
    NO CYCLE;
GO

SELECT NEXT VALUE FOR dbo.seq_Tiny;   -- 1
SELECT NEXT VALUE FOR dbo.seq_Tiny;   -- 2
SELECT NEXT VALUE FOR dbo.seq_Tiny;   -- 3
-- FAILS ON PURPOSE: error 11728, maximum reached
-- SELECT NEXT VALUE FOR dbo.seq_Tiny;   -- error
GO

ALTER SEQUENCE dbo.seq_Tiny CYCLE;

SELECT NEXT VALUE FOR dbo.seq_Tiny AS AfterCycle;

-- ============================================================
-- Applied example
-- ============================================================

GO
CREATE OR ALTER VIEW reporting.vw_CollectionsQueue
WITH SCHEMABINDING
AS
SELECT
    l.LoanID,
    c.FirstName + N' ' + c.LastName AS CustomerName,
    b.BranchName,
    l.LoanStatus,
    COUNT_BIG(*) AS MissedInstalments,
    SUM(p.AmountDue) AS MissedAmount,
    l.OutstandingBalance
FROM dbo.Loan AS l
INNER JOIN dbo.Customer AS c
    ON c.CustomerID = l.CustomerID
INNER JOIN dbo.Branch AS b
    ON b.BranchID = l.BranchID
INNER JOIN dbo.Payment AS p
    ON p.LoanID = l.LoanID
WHERE l.LoanStatus IN (N'Arrears', N'Default')
  AND p.PaidDate IS NULL                  -- missed instalments
GROUP BY
    l.LoanID, c.FirstName, c.LastName, b.BranchName,
    l.LoanStatus, l.OutstandingBalance;
GO

SELECT
    BranchName,
    COUNT(*) AS Loans,
    SUM(MissedInstalments) AS Missed,
    SUM(MissedAmount) AS MissedAmount
FROM reporting.vw_CollectionsQueue
GROUP BY BranchName
ORDER BY MissedAmount DESC;

CREATE SYNONYM reporting.CollectionsQueue
    FOR NorthbridgeLending.reporting.vw_CollectionsQueue;
GO

SELECT COUNT(*) AS LoansInQueue
FROM reporting.CollectionsQueue;

CREATE SEQUENCE dbo.seq_Worklist
    AS INT
    START WITH 1
    INCREMENT BY 1;
GO

DROP TABLE IF EXISTS dbo.Practice_CollectionsWorklist;

SELECT
    NEXT VALUE FOR dbo.seq_Worklist
        OVER (ORDER BY MissedAmount DESC, LoanID) AS WorkItem,
    LoanID,
    CustomerName,
    MissedAmount
INTO dbo.Practice_CollectionsWorklist
FROM reporting.CollectionsQueue;

SELECT TOP (5) WorkItem, LoanID, CustomerName, MissedAmount
FROM dbo.Practice_CollectionsWorklist
ORDER BY WorkItem;

-- ============================================================
-- Clean-up: remove every object this script created
-- ============================================================

DROP SYNONYM IF EXISTS reporting.CollectionsQueue;
DROP SYNONYM IF EXISTS reporting.LoanBook;
DROP SYNONYM IF EXISTS reporting.LoanArchive;
DROP VIEW IF EXISTS
    reporting.vw_CollectionsQueue,
    reporting.vw_BranchStatusExposure,
    reporting.vw_PracticeExposure,
    reporting.vw_PracticeArrears,
    reporting.vw_PracticeBranch,
    reporting.vw_LoanOverviewSorted,
    reporting.vw_LoanOverview;
DROP TABLE IF EXISTS
    dbo.Practice_CollectionsWorklist,
    dbo.Practice_CollectionsCase,
    dbo.Practice_Loan,
    dbo.Practice_Branch;
DROP SEQUENCE IF EXISTS
    dbo.seq_CaseNumber,
    dbo.seq_Tiny,
    dbo.seq_Worklist;
GO
