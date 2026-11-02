/* SQL Server from Zero — Volume 1
   Chapter 24: Views, synonyms and sequences — solutions to the exercises
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

/* The exercises create views, a synonym, sequences and practice tables.
   No base table is changed. The clean-up block at the end removes
   everything. Statements marked "FAILS ON PURPOSE" are commented out;
   uncomment one to see its error. */

IF SCHEMA_ID(N'reporting') IS NULL EXEC (N'CREATE SCHEMA reporting');
GO

-- Start from a clean state so that the script can run more than once
DROP SYNONYM IF EXISTS reporting.Officers;
DROP VIEW IF EXISTS
    reporting.vw_CustomerContact,
    reporting.vw_OfficerActiveBook,
    reporting.vw_PracticeUnemployed,
    reporting.vw_LoanPaymentTotals;
DROP TABLE IF EXISTS
    dbo.Practice_Customer,
    dbo.Practice_WriteOffReview;
DROP SEQUENCE IF EXISTS
    dbo.seq_ReportRun,
    dbo.seq_WriteOffReview,
    dbo.seq_Agent;
GO

-- Exercise 24.2 reads the view built in section 2 of the Course
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
    l.InterestRate,
    l.OutstandingBalance
FROM dbo.Loan AS l
INNER JOIN dbo.Product AS p
    ON p.ProductCode = l.ProductCode
INNER JOIN dbo.Branch AS b
    ON b.BranchID = l.BranchID;
GO

-- ------------------------------------------------------------
-- Correction 24.1
-- ------------------------------------------------------------

GO
CREATE OR ALTER VIEW reporting.vw_CustomerContact
AS
SELECT
    CustomerID,
    FirstName,
    LastName,
    Email,            -- NULL for customers without email
    Phone,
    City
FROM dbo.Customer;
GO

SELECT COUNT(*) AS CustomersWithoutEmail
FROM reporting.vw_CustomerContact
WHERE Email IS NULL;  -- = NULL would find nothing

-- ------------------------------------------------------------
-- Correction 24.2
-- ------------------------------------------------------------

SELECT
    BranchName,
    COUNT(*) AS DefaultLoans,
    SUM(OutstandingBalance) AS DefaultOutstanding
FROM reporting.vw_LoanOverview
WHERE LoanStatus = N'Default'      -- filter before grouping
GROUP BY BranchName
ORDER BY DefaultOutstanding DESC;  -- largest first

-- ------------------------------------------------------------
-- Correction 24.3
-- ------------------------------------------------------------

CREATE SEQUENCE dbo.seq_ReportRun
    AS INT
    START WITH 1        -- without this, INT starts at -2147483648
    INCREMENT BY 1;
GO

SELECT NEXT VALUE FOR dbo.seq_ReportRun AS RunNumber;  -- 1
SELECT NEXT VALUE FOR dbo.seq_ReportRun AS RunNumber;  -- 2
SELECT NEXT VALUE FOR dbo.seq_ReportRun AS RunNumber;  -- 3

SELECT
    name,
    CAST(current_value AS INT) AS CurrentValue
FROM sys.sequences
WHERE name = N'seq_ReportRun';

-- ------------------------------------------------------------
-- Correction 24.4
-- ------------------------------------------------------------

CREATE SYNONYM reporting.Officers
    FOR NorthbridgeLending.dbo.LoanOfficer;
GO

SELECT
    b.BranchID,
    b.BranchName,
    COUNT(*) AS Officers
FROM reporting.Officers AS o        -- the synonym
INNER JOIN dbo.Branch AS b
    ON b.BranchID = o.BranchID
GROUP BY b.BranchID, b.BranchName
ORDER BY b.BranchID;

SELECT name, base_object_name
FROM sys.synonyms
WHERE name = N'Officers';

-- ------------------------------------------------------------
-- Correction 24.5
-- ------------------------------------------------------------

DROP VIEW IF EXISTS reporting.vw_PracticeUnemployed;
DROP TABLE IF EXISTS dbo.Practice_Customer;
SELECT * INTO dbo.Practice_Customer FROM dbo.Customer;  -- 500 rows
GO

CREATE OR ALTER VIEW reporting.vw_PracticeUnemployed
AS
SELECT
    CustomerID,
    FirstName,
    LastName,
    Phone,
    EmploymentStatus
FROM dbo.Practice_Customer
WHERE EmploymentStatus = N'Unemployed'
WITH CHECK OPTION;     -- rows must stay inside the view
GO

-- 1. Allowed: the row still satisfies the WHERE clause
UPDATE reporting.vw_PracticeUnemployed
SET Phone = '07700 900123'          -- VARCHAR column: no N prefix
WHERE CustomerID = 21;

-- 2. Refused: the row would leave the view
-- FAILS ON PURPOSE: Msg 550
-- UPDATE reporting.vw_PracticeUnemployed
-- SET EmploymentStatus = N'Employed'
-- WHERE CustomerID = 9;

-- ------------------------------------------------------------
-- Correction 24.6
-- ------------------------------------------------------------

CREATE SEQUENCE dbo.seq_WriteOffReview
    AS INT
    START WITH 1
    INCREMENT BY 1;
GO

DROP TABLE IF EXISTS dbo.Practice_WriteOffReview;
CREATE TABLE dbo.Practice_WriteOffReview
(
    ReviewID INT NOT NULL PRIMARY KEY,
    LoanID INT NOT NULL,
    Balance DECIMAL(12,2) NOT NULL
);
GO

INSERT INTO dbo.Practice_WriteOffReview (ReviewID, LoanID, Balance)
SELECT
    NEXT VALUE FOR dbo.seq_WriteOffReview
        OVER (ORDER BY OutstandingBalance DESC),  -- largest = 1
    LoanID,
    OutstandingBalance
FROM dbo.Loan
WHERE LoanStatus = N'Written Off';

SELECT TOP (5) ReviewID, LoanID, Balance
FROM dbo.Practice_WriteOffReview
ORDER BY ReviewID;

-- ------------------------------------------------------------
-- Correction 24.7
-- ------------------------------------------------------------

GO
CREATE OR ALTER VIEW reporting.vw_LoanPaymentTotals
WITH SCHEMABINDING
AS
SELECT
    LoanID,
    COUNT_BIG(*) AS InstalmentCount,  -- COUNT_BIG, not COUNT
    SUM(AmountDue) AS TotalDue,       -- AmountDue is NOT NULL
    SUM(AmountPaid) AS TotalPaid      -- AmountPaid is NOT NULL
FROM dbo.Payment                      -- two-part name
GROUP BY LoanID;
GO

CREATE UNIQUE CLUSTERED INDEX UCX_vw_LoanPaymentTotals
    ON reporting.vw_LoanPaymentTotals (LoanID);
GO

SELECT TOP (5)
    LoanID,
    InstalmentCount,
    TotalDue,
    TotalPaid,
    TotalDue - TotalPaid AS Shortfall
FROM reporting.vw_LoanPaymentTotals WITH (NOEXPAND)
ORDER BY Shortfall DESC, LoanID;

-- ------------------------------------------------------------
-- Correction 24.8
-- ------------------------------------------------------------

CREATE SEQUENCE dbo.seq_Agent
    AS TINYINT
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1          -- without it, the cycle restarts at 0
    MAXVALUE 3
    CYCLE;
GO

DECLARE @Assignment TABLE
(
    LoanID INT NOT NULL PRIMARY KEY,
    AgentNumber TINYINT NOT NULL
);

INSERT INTO @Assignment (LoanID, AgentNumber)
SELECT
    LoanID,
    NEXT VALUE FOR dbo.seq_Agent OVER (ORDER BY LoanID)
FROM dbo.Loan
WHERE LoanStatus = N'Arrears';

SELECT AgentNumber, COUNT(*) AS LoansAssigned
FROM @Assignment
GROUP BY AgentNumber
ORDER BY AgentNumber;

-- ============================================================
-- Clean-up: remove every object this script created
-- ============================================================

DROP SYNONYM IF EXISTS reporting.Officers;
DROP VIEW IF EXISTS
    reporting.vw_CustomerContact,
    reporting.vw_OfficerActiveBook,
    reporting.vw_PracticeUnemployed,
    reporting.vw_LoanPaymentTotals;
DROP TABLE IF EXISTS
    dbo.Practice_Customer,
    dbo.Practice_WriteOffReview;
DROP SEQUENCE IF EXISTS
    dbo.seq_ReportRun,
    dbo.seq_WriteOffReview,
    dbo.seq_Agent;
GO
DROP VIEW IF EXISTS reporting.vw_LoanOverview;
GO
