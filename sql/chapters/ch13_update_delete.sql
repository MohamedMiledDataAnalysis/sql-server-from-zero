/* SQL Server from Zero — Volume 1
   Chapter 13: UPDATE and DELETE
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022).
   The deliberate error of the chapter is commented out, so the script runs
   end to end; remove the comment markers around it to see the error. */
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
-- 1. Practice copies and the SELECT-first habit
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Customer;
DROP TABLE IF EXISTS dbo.Practice_Loan;
DROP TABLE IF EXISTS dbo.Practice_Payment;

SELECT * INTO dbo.Practice_Customer FROM dbo.Customer;
SELECT * INTO dbo.Practice_Loan     FROM dbo.Loan;
SELECT * INTO dbo.Practice_Payment  FROM dbo.Payment;
GO
-- Step 1: which rows will the change touch?
SELECT CustomerID, FirstName, LastName, Phone
FROM dbo.Practice_Customer
WHERE CustomerID = 2;
GO

-- ============================================================
-- 2. UPDATE … SET … WHERE: changing one column
-- ============================================================
UPDATE dbo.Practice_Customer
SET Phone = '07700 900123'     -- VARCHAR(20): no N prefix
WHERE CustomerID = 2;               -- the row checked in section 1
GO
SELECT CustomerID, FirstName, LastName, Phone
FROM dbo.Practice_Customer
WHERE CustomerID = 2;
GO
UPDATE dbo.Practice_Customer
SET Phone = 'unknown'
WHERE Phone = NULL;                 -- wrong: never true
GO
-- ============================================================
-- 3. Several columns and expressions
-- ============================================================
SELECT COUNT(*) AS TrackerLoans
FROM dbo.Practice_Loan
WHERE ProductCode = 'MTG-TRK'
  AND LoanStatus = N'Active';
GO
UPDATE dbo.Practice_Loan
SET InterestRate = InterestRate + 0.25   -- current value plus 0.25
WHERE ProductCode = 'MTG-TRK'
  AND LoanStatus = N'Active';
GO
SELECT TOP (5) p.LoanID,
       l.InterestRate AS OldRate,       -- base table: unchanged
       p.InterestRate AS NewRate        -- practice copy: updated
FROM dbo.Practice_Loan AS p
INNER JOIN dbo.Loan AS l
    ON l.LoanID = p.LoanID
WHERE p.ProductCode = 'MTG-TRK'
  AND p.LoanStatus = N'Active'
ORDER BY p.LoanID;
GO

-- ============================================================
-- 4. UPDATE … FROM: updating from another table
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_LoanActivity;

SELECT LoanID,
       LoanStatus,
       OutstandingBalance,
       CAST(NULL AS DATE)         AS LastPaidDate,
       CAST(0 AS INT)             AS MissedInstalments,
       CAST(NULL AS NVARCHAR(20)) AS CollectionsQueue
INTO dbo.Practice_LoanActivity
FROM dbo.Loan;
GO
UPDATE la
SET LastPaidDate      = s.LastPaid,
    MissedInstalments = s.Missed
FROM dbo.Practice_LoanActivity AS la      -- the table to change
INNER JOIN (SELECT LoanID,
                   MAX(PaidDate)               AS LastPaid,
                   COUNT(*) - COUNT(PaidDate)  AS Missed
            FROM dbo.Payment
            GROUP BY LoanID) AS s         -- one row per loan
    ON s.LoanID = la.LoanID;
GO
SELECT LoanID, LoanStatus, OutstandingBalance, LastPaidDate,
       MissedInstalments
FROM dbo.Practice_LoanActivity
WHERE LoanID BETWEEN 10001 AND 10005
ORDER BY LoanID;
GO

-- ============================================================
-- 5. UPDATE TOP: limiting the number of rows
-- ============================================================
UPDATE TOP (5) dbo.Practice_LoanActivity
SET CollectionsQueue = N'Senior team'
WHERE LoanStatus = N'Arrears';
GO
UPDATE dbo.Practice_LoanActivity
SET CollectionsQueue = NULL
WHERE CollectionsQueue IS NOT NULL;
GO
WITH LargestArrears AS
(
    SELECT TOP (5) LoanID, CollectionsQueue
    FROM dbo.Practice_LoanActivity
    WHERE LoanStatus = N'Arrears'
    ORDER BY OutstandingBalance DESC, LoanID   -- a precise rule
)
UPDATE LargestArrears
SET CollectionsQueue = N'Senior team';
GO
SELECT LoanID, LoanStatus, OutstandingBalance, MissedInstalments,
       CollectionsQueue
FROM dbo.Practice_LoanActivity
WHERE CollectionsQueue IS NOT NULL
ORDER BY OutstandingBalance DESC;
GO

-- ============================================================
-- 6. DELETE … WHERE: removing rows
-- ============================================================
SELECT COUNT(*) AS RepaidLoans
FROM dbo.Practice_Loan
WHERE LoanStatus = N'Repaid';
GO
DELETE FROM dbo.Practice_Loan
WHERE LoanStatus = N'Repaid';
GO
SELECT LoanStatus, COUNT(*) AS Loans
FROM dbo.Practice_Loan
GROUP BY LoanStatus
ORDER BY LoanStatus;
GO
-- Safe to run: this DELETE always fails and changes nothing.
-- Fails on purpose with Msg 547: loans still reference PL-STD.
-- DELETE FROM dbo.Product
-- WHERE ProductCode = 'PL-STD';
GO

-- ============================================================
-- 7. DELETE with a join, and DELETE TOP
-- ============================================================
SELECT COUNT(*) AS RepaidLoanPayments
FROM dbo.Practice_Payment AS p
INNER JOIN dbo.Loan AS l
    ON l.LoanID = p.LoanID
WHERE l.LoanStatus = N'Repaid';
GO
DELETE p                                  -- remove rows of p only
FROM dbo.Practice_Payment AS p
INNER JOIN dbo.Loan AS l
    ON l.LoanID = p.LoanID
WHERE l.LoanStatus = N'Repaid';
GO
DELETE FROM dbo.Practice_Payment
WHERE LoanID IN (SELECT LoanID
                 FROM dbo.Loan
                 WHERE LoanStatus = N'Repaid');
GO

-- ============================================================
-- 8. The "forgot WHERE" disaster and @@ROWCOUNT
-- ============================================================
-- A mistake, on purpose, on a practice copy:
UPDATE dbo.Practice_Customer
SET City = N'London';               -- no WHERE: every customer
GO
SELECT City, COUNT(*) AS Customers
FROM dbo.Practice_Customer
GROUP BY City;
GO
DROP TABLE IF EXISTS dbo.Practice_Customer;

SELECT * INTO dbo.Practice_Customer FROM dbo.Customer;
GO
UPDATE dbo.Practice_Customer
SET Phone = '07700 900123'
WHERE CustomerID = 2;

IF @@ROWCOUNT <> 1                         -- read it at once
    PRINT N'Warning: expected exactly one customer.';
ELSE
    PRINT N'One customer updated.';
GO

-- ============================================================
-- Applied example
-- ============================================================

-- ============================================================
-- Step 1. Build the practice copies, with a WriteOffAmount column on the loan copy.
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Loan;
DROP TABLE IF EXISTS dbo.Practice_Payment;

SELECT l.*,                                     -- all Loan columns
       CAST(NULL AS DECIMAL(12,2)) AS WriteOffAmount
INTO dbo.Practice_Loan
FROM dbo.Loan AS l;

SELECT * INTO dbo.Practice_Payment FROM dbo.Payment;
GO

-- ============================================================
-- Step 2. SELECT first: the loans and the amount to write off.
-- ============================================================
SELECT COUNT(*)                AS Loans,
       SUM(OutstandingBalance) AS AmountToWriteOff
FROM dbo.Practice_Loan
WHERE LoanStatus = N'Written Off';
GO

-- ============================================================
-- Step 3. Move the balance in one UPDATE and check the count.
-- ============================================================
UPDATE dbo.Practice_Loan
SET WriteOffAmount     = OutstandingBalance,  -- the value before
    OutstandingBalance = 0.00                 -- then cleared
WHERE LoanStatus = N'Written Off';

IF @@ROWCOUNT <> 20
    PRINT N'Warning: expected 20 written-off loans.';
ELSE
    PRINT N'20 loans written off.';
GO
SELECT TOP (3) LoanID, LoanStatus, OutstandingBalance,
       WriteOffAmount
FROM dbo.Practice_Loan
WHERE LoanStatus = N'Written Off'
ORDER BY LoanID;
GO

-- ============================================================
-- Step 4. Remove the missed instalments of the written-off loans.
-- ============================================================
SELECT COUNT(*)       AS MissedRows,          -- SELECT first
       SUM(AmountDue) AS MissedAmount
FROM dbo.Practice_Payment AS p
INNER JOIN dbo.Practice_Loan AS l
    ON l.LoanID = p.LoanID
WHERE l.LoanStatus = N'Written Off'
  AND p.PaidDate IS NULL;
GO
DELETE p
FROM dbo.Practice_Payment AS p
INNER JOIN dbo.Practice_Loan AS l
    ON l.LoanID = p.LoanID
WHERE l.LoanStatus = N'Written Off'
  AND p.PaidDate IS NULL;                     -- missed ones only
GO

-- ============================================================
-- Step 5. Prove the result.
-- ============================================================
SELECT LoanStatus,
       COUNT(*)                AS Loans,
       SUM(OutstandingBalance) AS Outstanding,
       SUM(WriteOffAmount)     AS WrittenOff
FROM dbo.Practice_Loan
GROUP BY LoanStatus
ORDER BY LoanStatus;

SELECT COUNT(*)                   AS PaymentRows,
       COUNT(*) - COUNT(PaidDate) AS MissedRows
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
