/* SQL Server from Zero — Volume 1
   Chapter 13: UPDATE and DELETE
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022).
   Each example ends with GO so that the deliberate errors of the chapter
   stop only their own batch. Run the script statement by statement (F5 on a selection). */
USE NorthbridgeLending;
GO

-- Start clean: remove practice tables left by an earlier run.
DROP TABLE IF EXISTS dbo.Practice_Customer;
DROP TABLE IF EXISTS dbo.Practice_Loan;
DROP TABLE IF EXISTS dbo.Practice_Payment;
DROP TABLE IF EXISTS dbo.Practice_LoanActivity;
DROP TABLE IF EXISTS dbo.Practice_LoanOfficer;
DROP TABLE IF EXISTS dbo.Practice_CustomerLoans;
GO

-- ============================================================
-- Correction 13.1
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Customer;
SELECT * INTO dbo.Practice_Customer FROM dbo.Customer;

UPDATE dbo.Practice_Customer
SET Phone = '07700 900456'          -- VARCHAR column: no N prefix
WHERE CustomerID = 53;              -- exactly one customer

SELECT CustomerID, FirstName, LastName, Phone
FROM dbo.Practice_Customer
WHERE CustomerID = 53;
GO

-- ============================================================
-- Correction 13.2
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Customer;
SELECT * INTO dbo.Practice_Customer FROM dbo.Customer;

UPDATE dbo.Practice_Customer
SET EmploymentStatus = N'Self-employed',   -- was Unemployed
    AnnualIncome     = 21500.00            -- was 8000.00
WHERE CustomerID = 9;

SELECT CustomerID, FirstName, LastName, EmploymentStatus,
       AnnualIncome
FROM dbo.Practice_Customer
WHERE CustomerID = 9;
GO

-- ============================================================
-- Correction 13.3
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_LoanOfficer;
SELECT * INTO dbo.Practice_LoanOfficer FROM dbo.LoanOfficer;

DELETE FROM dbo.Practice_LoanOfficer
WHERE OfficerID = 101;                       -- one officer

SELECT COUNT(*) AS Officers,
       SUM(CASE WHEN BranchID = 1 THEN 1 ELSE 0 END) AS Branch1
FROM dbo.Practice_LoanOfficer;
GO

-- ============================================================
-- Correction 13.4
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_CustomerLoans;

SELECT CustomerID, FirstName, LastName,
       CAST(NULL AS INT) AS LoanCount         -- to be filled
INTO dbo.Practice_CustomerLoans
FROM dbo.Customer;

UPDATE pc
SET LoanCount = s.Loans
FROM dbo.Practice_CustomerLoans AS pc
INNER JOIN (SELECT CustomerID, COUNT(*) AS Loans
            FROM dbo.Loan
            GROUP BY CustomerID) AS s         -- one row per customer
    ON s.CustomerID = pc.CustomerID;

SELECT COUNT(*) AS WithoutLoans
FROM dbo.Practice_CustomerLoans
WHERE LoanCount IS NULL;
GO

-- ============================================================
-- Correction 13.5
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Customer;
SELECT * INTO dbo.Practice_Customer FROM dbo.Customer;

SELECT COUNT(*) AS NoLoan                      -- SELECT first
FROM dbo.Practice_Customer AS c
WHERE NOT EXISTS (SELECT 1 FROM dbo.Loan AS l
                  WHERE l.CustomerID = c.CustomerID);

DELETE c
FROM dbo.Practice_Customer AS c
WHERE NOT EXISTS (SELECT 1 FROM dbo.Loan AS l
                  WHERE l.CustomerID = c.CustomerID);

SELECT COUNT(*) AS Remaining
FROM dbo.Practice_Customer;
GO

-- ============================================================
-- Correction 13.6
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Payment;
SELECT * INTO dbo.Practice_Payment FROM dbo.Payment;

DECLARE @Deleted INT;

DELETE FROM dbo.Practice_Payment
WHERE LoanID = 10002
  AND PaidDate IS NULL;                 -- missed instalments only

SET @Deleted = @@ROWCOUNT;     -- capture before anything else

PRINT CONCAT(N'Rows deleted: ', @Deleted);

IF @Deleted <> 8
    PRINT N'Warning: expected 8 missed instalments.';
GO

-- ============================================================
-- Correction 13.7
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Loan;
SELECT * INTO dbo.Practice_Loan FROM dbo.Loan;

UPDATE dbo.Practice_Loan
SET LoanStatus = N'Active';                -- the accident: 800 rows

UPDATE p
SET LoanStatus = l.LoanStatus              -- the correct value
FROM dbo.Practice_Loan AS p
INNER JOIN dbo.Loan AS l
    ON l.LoanID = p.LoanID;                -- one match per loan

SELECT LoanStatus, COUNT(*) AS Loans
FROM dbo.Practice_Loan
GROUP BY LoanStatus
ORDER BY LoanStatus;
GO

-- ============================================================
-- Correction 13.8
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Payment;
SELECT * INTO dbo.Practice_Payment FROM dbo.Payment;

SET NOCOUNT ON;                -- hide "(n rows affected)"

DECLARE @Deleted INT = 1;                    -- enter the loop once

WHILE @Deleted > 0
BEGIN
    DELETE TOP (1000) FROM dbo.Practice_Payment
    WHERE DueDate < '2023-01-01';            -- archive rule

    SET @Deleted = @@ROWCOUNT;               -- rows in this batch
    PRINT CONCAT(N'Batch deleted: ', @Deleted);
END;

SET NOCOUNT OFF;

SELECT COUNT(*) AS RemainingPayments
FROM dbo.Practice_Payment;
GO

-- ============================================================
-- Clean-up: remove every practice table created in this chapter.
-- The base tables were not changed (the DELETE on dbo.Product in
-- section 6 always fails).
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Customer;
DROP TABLE IF EXISTS dbo.Practice_Loan;
DROP TABLE IF EXISTS dbo.Practice_Payment;
DROP TABLE IF EXISTS dbo.Practice_LoanActivity;
DROP TABLE IF EXISTS dbo.Practice_LoanOfficer;
DROP TABLE IF EXISTS dbo.Practice_CustomerLoans;
GO
