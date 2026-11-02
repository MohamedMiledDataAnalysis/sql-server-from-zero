/* SQL Server from Zero — Volume 1
   Chapter 14: MERGE and OUTPUT
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022).
   Each example ends with GO so that the deliberate errors of the chapter
   stop only their own batch. Run the script statement by statement (F5 on a selection). */
USE NorthbridgeLending;
GO

-- Start clean: remove practice tables left by an earlier run.
DROP TABLE IF EXISTS dbo.Practice_Product;
DROP TABLE IF EXISTS dbo.Practice_ProductFeed;
DROP TABLE IF EXISTS dbo.Practice_Branch;
DROP TABLE IF EXISTS dbo.Practice_BranchFeed;
DROP TABLE IF EXISTS dbo.Practice_Loan;
DROP TABLE IF EXISTS dbo.Practice_Payment;
DROP TABLE IF EXISTS dbo.Practice_PaymentArchive;
DROP TABLE IF EXISTS dbo.Practice_ProductAudit;
DROP TABLE IF EXISTS dbo.Practice_RateAudit;
DROP TABLE IF EXISTS dbo.Practice_MortgageFeed;
DROP TABLE IF EXISTS dbo.Practice_CustomerScore;
DROP TABLE IF EXISTS dbo.Practice_ScoreAudit;
DROP TABLE IF EXISTS dbo.Practice_LoanOfficer;
DROP TABLE IF EXISTS dbo.Practice_Customer;
DROP TABLE IF EXISTS dbo.Practice_Watchlist;
GO

-- Exercise 14.6 uses the product feed of section 1: build it here.
DROP TABLE IF EXISTS dbo.Practice_Product;
DROP TABLE IF EXISTS dbo.Practice_ProductFeed;

SELECT * INTO dbo.Practice_Product FROM dbo.Product;   -- target

SELECT *
INTO dbo.Practice_ProductFeed                          -- source
FROM dbo.Product
WHERE 1 = 0;                                           -- no rows

INSERT INTO dbo.Practice_ProductFeed
    (ProductCode, ProductName, ProductType, BaseRate,
     MaxTermMonths, IsSecured)
VALUES
    ('AUTO-NEW', N'New Car Loan', N'Auto',
     6.70, 60, 1),
    ('AUTO-USD', N'Used Car Loan', N'Auto',
     8.45, 48, 1),
    ('MTG-FIX2', N'Fixed-Rate Mortgage 2 Years', N'Mortgage',
     4.89, 360, 1),
    ('MTG-FIX5', N'Fixed-Rate Mortgage 5 Years', N'Mortgage',
     4.49, 360, 1),
    ('MTG-TRK', N'Tracker Mortgage', N'Mortgage',
     5.49, 300, 1),
    ('PL-CONS', N'Debt Consolidation Loan', N'Personal',
     9.40, 84, 0),
    ('PL-STD', N'Personal Loan', N'Personal',
     7.90, 60, 0),
    ('MTG-FIX10', N'Fixed-Rate Mortgage 10 Years', N'Mortgage',
     5.15, 360, 1),
    ('PL-GREEN', N'Green Home Improvement Loan', N'Personal',
     6.95, 84, 0);
GO

-- ============================================================
-- Correction 14.1
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_LoanOfficer;
SELECT * INTO dbo.Practice_LoanOfficer FROM dbo.LoanOfficer;

INSERT INTO dbo.Practice_LoanOfficer
    (OfficerID, FirstName, LastName, BranchID, HireDate, Email)
OUTPUT inserted.OfficerID, inserted.FirstName,      -- the new row
       inserted.LastName, inserted.BranchID
VALUES
    (125, N'Grace', N'Patel', 8, '2026-10-01',
     N'grace.patel@northbridge-lending.co.uk');
GO

-- ============================================================
-- Correction 14.2
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Customer;
SELECT * INTO dbo.Practice_Customer FROM dbo.Customer;

UPDATE dbo.Practice_Customer
SET Phone = '07700 900123'
OUTPUT inserted.CustomerID,
       deleted.Phone  AS OldPhone,          -- value before
       inserted.Phone AS NewPhone           -- value after
WHERE CustomerID = 2;
GO

-- ============================================================
-- Correction 14.3
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_LoanOfficer;
SELECT * INTO dbo.Practice_LoanOfficer FROM dbo.LoanOfficer;

DELETE FROM dbo.Practice_LoanOfficer
OUTPUT deleted.OfficerID, deleted.FirstName,   -- the removed row
       deleted.LastName, deleted.HireDate
WHERE OfficerID = 101;
GO

-- ============================================================
-- Correction 14.4
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Branch;
DROP TABLE IF EXISTS dbo.Practice_BranchFeed;

SELECT * INTO dbo.Practice_Branch FROM dbo.Branch;

SELECT *
INTO dbo.Practice_BranchFeed
FROM dbo.Branch
WHERE 1 = 0;                                    -- empty staging table

INSERT INTO dbo.Practice_BranchFeed
    (BranchID, BranchName, City, Region, OpenedDate)
VALUES
    (2, N'Manchester Spinningfields', N'Manchester',
        N'North West', '2011-06-13'),          -- renamed
    (9, N'Edinburgh Princes Street', N'Edinburgh',
        N'Scotland', '2026-10-05');            -- new

MERGE INTO dbo.Practice_Branch AS t
USING dbo.Practice_BranchFeed AS s
    ON t.BranchID = s.BranchID                  -- key only
WHEN MATCHED THEN
    UPDATE SET BranchName = s.BranchName,
               City       = s.City,
               Region     = s.Region,
               OpenedDate = s.OpenedDate
WHEN NOT MATCHED BY TARGET THEN
    INSERT (BranchID, BranchName, City, Region, OpenedDate)
    VALUES (s.BranchID, s.BranchName, s.City, s.Region,
            s.OpenedDate);                      -- semicolon required

SELECT BranchID, BranchName, City
FROM dbo.Practice_Branch
WHERE BranchID IN (1, 2, 9)
ORDER BY BranchID;
GO

-- ============================================================
-- Correction 14.5
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Loan;
DROP TABLE IF EXISTS dbo.Practice_RateAudit;

SELECT * INTO dbo.Practice_Loan FROM dbo.Loan;

SELECT CAST(0 AS INT)            AS LoanID,
       CAST(0 AS DECIMAL(5,2))   AS OldRate,
       CAST(0 AS DECIMAL(5,2))   AS NewRate
INTO dbo.Practice_RateAudit
FROM dbo.Branch
WHERE 1 = 0;

UPDATE dbo.Practice_Loan
SET InterestRate = InterestRate + 0.25
OUTPUT inserted.LoanID, deleted.InterestRate, inserted.InterestRate
INTO dbo.Practice_RateAudit (LoanID, OldRate, NewRate)
WHERE ProductCode = 'MTG-TRK'
  AND LoanStatus = N'Active';

SELECT COUNT(*)               AS AuditRows,
       MIN(OldRate)           AS LowestOldRate,
       MAX(NewRate)           AS HighestNewRate,
       SUM(NewRate - OldRate) AS TotalIncrease
FROM dbo.Practice_RateAudit;
GO

-- ============================================================
-- Correction 14.6
-- ============================================================
INSERT INTO dbo.Practice_ProductFeed
    (ProductCode, ProductName, ProductType, BaseRate,
     MaxTermMonths, IsSecured)
VALUES
    ('AUTO-USD', N'Used Car Loan', N'Auto',
     8.50, 48, 1);

SELECT ProductCode, COUNT(*) AS Occurrences   -- the check
FROM dbo.Practice_ProductFeed
GROUP BY ProductCode
HAVING COUNT(*) > 1;
GO
DELETE FROM dbo.Practice_ProductFeed
WHERE ProductCode = 'AUTO-USD'
  AND BaseRate = 8.50;                     -- the duplicate only
GO

-- ============================================================
-- Correction 14.7
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Payment;
DROP TABLE IF EXISTS dbo.Practice_PaymentArchive;

SELECT * INTO dbo.Practice_Payment FROM dbo.Payment;

SELECT *
INTO dbo.Practice_PaymentArchive
FROM dbo.Payment
WHERE 1 = 0;                                     -- same columns

DELETE FROM dbo.Practice_Payment
OUTPUT deleted.PaymentID, deleted.LoanID, deleted.InstalmentNumber,
       deleted.DueDate, deleted.AmountDue, deleted.PaidDate,
       deleted.AmountPaid, deleted.DaysLate
INTO dbo.Practice_PaymentArchive
     (PaymentID, LoanID, InstalmentNumber, DueDate, AmountDue,
      PaidDate, AmountPaid, DaysLate)
WHERE DueDate < '2023-01-01';

SELECT N'Archive' AS Source, COUNT(*) AS Instalments,
       SUM(AmountDue) AS TotalDue
FROM dbo.Practice_PaymentArchive
UNION ALL
SELECT N'Copy', COUNT(*), SUM(AmountDue)
FROM dbo.Practice_Payment
UNION ALL
SELECT N'Base table', COUNT(*), SUM(AmountDue)
FROM dbo.Payment;
GO

-- ============================================================
-- Correction 14.8
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Watchlist;

SELECT LoanID, LoanStatus, OutstandingBalance
INTO dbo.Practice_Watchlist
FROM dbo.Loan
WHERE LoanStatus IN (N'Arrears', N'Written Off');   -- last month

DECLARE @Changes TABLE (ActionTaken NVARCHAR(10), LoanID INT);

MERGE INTO dbo.Practice_Watchlist WITH (HOLDLOCK) AS t
USING (SELECT LoanID, LoanStatus, OutstandingBalance
       FROM dbo.Loan
       WHERE LoanStatus IN (N'Arrears', N'Default')) AS s -- now
    ON t.LoanID = s.LoanID
WHEN MATCHED AND (t.LoanStatus <> s.LoanStatus
               OR t.OutstandingBalance <> s.OutstandingBalance) THEN
    UPDATE SET LoanStatus         = s.LoanStatus,
               OutstandingBalance = s.OutstandingBalance
WHEN NOT MATCHED BY TARGET THEN
    INSERT (LoanID, LoanStatus, OutstandingBalance)
    VALUES (s.LoanID, s.LoanStatus, s.OutstandingBalance)
WHEN NOT MATCHED BY SOURCE THEN                     -- left the list
    DELETE
OUTPUT $action, COALESCE(inserted.LoanID, deleted.LoanID)
INTO @Changes (ActionTaken, LoanID);

SELECT ActionTaken, COUNT(*) AS Loans
FROM @Changes
GROUP BY ActionTaken
ORDER BY ActionTaken;
GO
-- NULL-safe version of the WHEN MATCHED clause (a fragment, shown in the book;
-- replace the clause of the MERGE above with it):
-- WHEN MATCHED AND (t.LoanStatus <> s.LoanStatus
--                OR t.OutstandingBalance <> s.OutstandingBalance
--                OR (t.OutstandingBalance IS NULL
--                    AND s.OutstandingBalance IS NOT NULL)
--                OR (t.OutstandingBalance IS NOT NULL
--                    AND s.OutstandingBalance IS NULL)) THEN

-- ============================================================
-- Clean-up: remove every practice table created in this chapter.
-- The base tables were not changed.
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Product;
DROP TABLE IF EXISTS dbo.Practice_ProductFeed;
DROP TABLE IF EXISTS dbo.Practice_Branch;
DROP TABLE IF EXISTS dbo.Practice_BranchFeed;
DROP TABLE IF EXISTS dbo.Practice_Loan;
DROP TABLE IF EXISTS dbo.Practice_Payment;
DROP TABLE IF EXISTS dbo.Practice_PaymentArchive;
DROP TABLE IF EXISTS dbo.Practice_ProductAudit;
DROP TABLE IF EXISTS dbo.Practice_RateAudit;
DROP TABLE IF EXISTS dbo.Practice_MortgageFeed;
DROP TABLE IF EXISTS dbo.Practice_CustomerScore;
DROP TABLE IF EXISTS dbo.Practice_ScoreAudit;
DROP TABLE IF EXISTS dbo.Practice_LoanOfficer;
DROP TABLE IF EXISTS dbo.Practice_Customer;
DROP TABLE IF EXISTS dbo.Practice_Watchlist;
GO
