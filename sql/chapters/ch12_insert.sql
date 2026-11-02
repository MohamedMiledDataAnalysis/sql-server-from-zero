/* SQL Server from Zero — Volume 1
   Chapter 12: INSERT and SELECT INTO
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022).
   The deliberate errors of the chapter are commented out, so the script runs
   end to end; remove the comment markers around one of them to see its error. */
USE NorthbridgeLending;
GO

-- Start clean: remove practice tables left by an earlier run.
DROP TABLE IF EXISTS dbo.Practice_Branch;
DROP TABLE IF EXISTS dbo.Practice_LoanEmpty;
DROP TABLE IF EXISTS dbo.Practice_Product;
DROP TABLE IF EXISTS dbo.Practice_Customer;
DROP TABLE IF EXISTS dbo.Practice_Note;
DROP TABLE IF EXISTS dbo.Practice_BranchList;
DROP TABLE IF EXISTS dbo.Practice_Watchlist;
DROP TABLE IF EXISTS dbo.Practice_LoanOfficer;
DROP TABLE IF EXISTS dbo.Practice_RepaidLoan;
DROP TABLE IF EXISTS dbo.Practice_CallLog;
DROP TABLE IF EXISTS dbo.Practice_BranchSummary;
DROP TABLE IF EXISTS dbo.Practice_Contact;
GO

-- ============================================================
-- 1. Practice copies with SELECT INTO
-- ============================================================
SELECT *                      -- every column of the source
INTO dbo.Practice_Branch      -- the new table to create
FROM dbo.Branch;              -- the source table
GO
EXEC sp_help 'dbo.Practice_Branch';
GO
SELECT *
INTO dbo.Practice_LoanEmpty
FROM dbo.Loan
WHERE 1 = 0;                  -- never true: copy the columns, no rows
GO
DROP TABLE IF EXISTS dbo.Practice_Branch;   -- remove the old copy

SELECT *
INTO dbo.Practice_Branch
FROM dbo.Branch;
GO

-- ============================================================
-- 2. INSERT … VALUES: adding one row
-- ============================================================
INSERT INTO dbo.Practice_Branch
    (BranchID, BranchName, City, Region, OpenedDate)
VALUES
    (9, N'Edinburgh Princes Street', N'Edinburgh', N'Scotland',
     '2026-10-05');
GO
SELECT TOP (3) BranchID, BranchName, City, Region, OpenedDate
FROM dbo.Practice_Branch
ORDER BY BranchID DESC;
GO
-- Fails on purpose with Msg 213: four values for five columns.
-- INSERT INTO dbo.Practice_Branch      -- no column list
-- VALUES (11, N'Southampton Ocean Village', N'Southampton',
--         N'South East');      -- four values for five columns
GO

-- ============================================================
-- 3. INSERT … VALUES: many rows in one statement
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Product;

SELECT *
INTO dbo.Practice_Product
FROM dbo.Product;

INSERT INTO dbo.Practice_Product
    (ProductCode, ProductName, ProductType, BaseRate,
     MaxTermMonths, IsSecured)
VALUES
    ('MTG-FIX10', N'Fixed-Rate Mortgage 10 Years', N'Mortgage',
     5.15, 360, 1),
    ('PL-GREEN', N'Green Home Improvement Loan', N'Personal',
     6.95, 84, 0),
    ('SME-OVD', N'Small Business Overdraft', N'SME',
     11.50, 12, 0);
GO

-- ============================================================
-- 4. NULLs, omitted columns and the DEFAULT keyword
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Customer;

SELECT *
INTO dbo.Practice_Customer
FROM dbo.Customer;

INSERT INTO dbo.Practice_Customer
    (CustomerID, FirstName, LastName, DateOfBirth, Email,
     City, Postcode, EmploymentStatus, AnnualIncome,
     CreditScore, JoinedDate, HomeBranchID)   -- Phone is not listed
VALUES
    (501, N'Fiona', N'MacLeod', '1991-04-22', NULL,  -- no email yet
     N'Edinburgh', 'EH2 2ER', N'Employed', 48500.00,
     781, '2026-09-30', 6);
GO
SELECT CustomerID, FirstName, LastName, Email, Phone, City
FROM dbo.Practice_Customer
WHERE CustomerID >= 499
ORDER BY CustomerID;
GO
-- Fails on purpose with Msg 515: LastName does not accept NULL.
-- INSERT INTO dbo.Practice_Customer
--     (CustomerID, FirstName, DateOfBirth, City, Postcode,
--      EmploymentStatus, AnnualIncome, CreditScore, JoinedDate,
--      HomeBranchID)                       -- LastName is missing
-- VALUES
--     (503, N'Amira', '1999-02-14', N'Cardiff', 'CF10 4PA',
--      N'Employed', 33100.00, 745, '2026-09-30', 7);
GO

-- ============================================================
-- 5. INSERT … SELECT: copying rows from a query
-- ============================================================
INSERT INTO dbo.Practice_LoanEmpty
    (LoanID, CustomerID, ProductCode, BranchID, OfficerID,
     ApplicationDate, OriginationDate, Principal, InterestRate,
     TermMonths, MonthlyPayment, MaturityDate, LoanStatus,
     OutstandingBalance)
SELECT LoanID, CustomerID, ProductCode, BranchID, OfficerID,
       ApplicationDate, OriginationDate, Principal, InterestRate,
       TermMonths, MonthlyPayment, MaturityDate, LoanStatus,
       OutstandingBalance
FROM dbo.Loan
WHERE LoanStatus = N'Arrears';
GO
SELECT TOP (5) LoanID, CustomerID, ProductCode, LoanStatus,
       OutstandingBalance
FROM dbo.Practice_LoanEmpty
ORDER BY LoanID;
GO

-- ============================================================
-- 6. DEFAULT VALUES and a first look at IDENTITY
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Note;

SELECT IDENTITY(INT, 1, 1)          AS NoteID,   -- 1, 2, 3 ...
       CAST(NULL AS INT)            AS LoanID,
       CAST(NULL AS NVARCHAR(200))  AS NoteText
INTO dbo.Practice_Note
FROM dbo.Branch
WHERE 1 = 0;
GO
INSERT INTO dbo.Practice_Note DEFAULT VALUES;    -- an empty note

INSERT INTO dbo.Practice_Note (LoanID, NoteText)
VALUES (10535, N'Customer called about the August instalment.');

INSERT INTO dbo.Practice_Note (LoanID, NoteText)
VALUES (10405, DEFAULT);                         -- text not known yet
GO
SELECT NoteID, LoanID, NoteText
FROM dbo.Practice_Note
ORDER BY NoteID;
GO
-- Fails on purpose with Msg 544: NoteID is an identity column.
-- INSERT INTO dbo.Practice_Note (NoteID, LoanID, NoteText)
-- VALUES (10, 10103, N'Promise to pay by 15 October.');
GO

-- ============================================================
-- 7. INSERT … EXEC: inserting the result of a batch (preview)
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_BranchList;

SELECT BranchID, BranchName
INTO dbo.Practice_BranchList
FROM dbo.Branch
WHERE 1 = 0;                                   -- empty structure

INSERT INTO dbo.Practice_BranchList (BranchID, BranchName)
EXEC (N'SELECT BranchID, BranchName
        FROM dbo.Branch
        WHERE Region IN (N''Scotland'', N''Wales'');');
GO
SELECT BranchID, BranchName
FROM dbo.Practice_BranchList
ORDER BY BranchID;
GO

-- ============================================================
-- 8. When an INSERT fails: the four errors to know
-- ============================================================
-- Safe to run: this INSERT always fails and changes nothing.
-- Fails on purpose with Msg 2627: branch 1 already exists.
-- INSERT INTO dbo.Branch
--     (BranchID, BranchName, City, Region, OpenedDate)
-- VALUES
--     (1, N'London Canary Wharf', N'London', N'London', '2026-10-12');
GO
INSERT INTO dbo.Practice_Branch
    (BranchID, BranchName, City, Region, OpenedDate)
VALUES
    (1, N'London Canary Wharf', N'London', N'London', '2026-10-12');
GO
-- Safe to run: customer 9999 does not exist, so this always fails.
-- Fails on purpose with Msg 547: customer 9999 does not exist.
-- INSERT INTO dbo.Loan
--     (LoanID, CustomerID, ProductCode, BranchID, OfficerID,
--      ApplicationDate, OriginationDate, Principal, InterestRate,
--      TermMonths, MonthlyPayment, MaturityDate, LoanStatus,
--      OutstandingBalance)
-- VALUES
--     (10801, 9999, 'PL-STD', 1, 101, '2026-09-20', '2026-09-30',
--      5000.00, 7.90, 36, 156.45, '2029-09-30', N'Active', 5000.00);
GO
-- Fails on purpose with Msg 2628: MTG-OFFSET5 is too long for VARCHAR(10).
-- INSERT INTO dbo.Practice_Product
--     (ProductCode, ProductName, ProductType, BaseRate,
--      MaxTermMonths, IsSecured)
-- VALUES
--     ('PL-TRAVEL', N'Travel Loan', N'Personal', 8.95, 36, 0),
--     ('MTG-OFFSET5', N'Offset Mortgage 5 Years', N'Mortgage',
--      4.99, 360, 1);
GO
SELECT COUNT(*) AS TravelRows
FROM dbo.Practice_Product
WHERE ProductCode = 'PL-TRAVEL';
GO

-- ============================================================
-- Applied example
-- ============================================================

-- ============================================================
-- Step 1. Create the empty structure.
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Watchlist;

SELECT l.LoanID,
       CAST(N'' AS NVARCHAR(81))     AS BorrowerName,
       l.LoanStatus,
       l.OutstandingBalance,
       CAST(0 AS INT)                AS MissedInstalments,
       CAST('2026-09-30' AS DATE)    AS AddedDate,
       CAST(N'' AS NVARCHAR(30))     AS Reason
INTO dbo.Practice_Watchlist
FROM dbo.Loan AS l
WHERE 1 = 0;
GO

-- ============================================================
-- Step 2. Insert the loans that meet the status rule.
-- ============================================================
DECLARE @AsOfDate DATE = '2026-09-30';

INSERT INTO dbo.Practice_Watchlist
    (LoanID, BorrowerName, LoanStatus, OutstandingBalance,
     MissedInstalments, AddedDate, Reason)
SELECT l.LoanID,
       c.FirstName + N' ' + c.LastName,
       l.LoanStatus,
       l.OutstandingBalance,
       (SELECT COUNT(*)
        FROM dbo.Payment AS p
        WHERE p.LoanID = l.LoanID
          AND p.PaidDate IS NULL),       -- missed instalments
       @AsOfDate,                        -- the snapshot date
       N'Status rule'
FROM dbo.Loan AS l
INNER JOIN dbo.Customer AS c
    ON c.CustomerID = l.CustomerID
WHERE l.LoanStatus IN (N'Arrears', N'Default');
GO

-- ============================================================
-- Step 3. Add the officer's referral by hand.
-- ============================================================
INSERT INTO dbo.Practice_Watchlist
    (LoanID, BorrowerName, LoanStatus, OutstandingBalance,
     MissedInstalments, AddedDate, Reason)
VALUES
    (10535, N'Arjun Clarke', N'Active', 171120.47, 0,
     '2026-09-30', N'Officer referral');
GO

-- ============================================================
-- Step 4. Check the content by reason and status.
-- ============================================================
SELECT Reason,
       LoanStatus,
       COUNT(*)                AS Loans,
       SUM(OutstandingBalance) AS TotalBalance,
       SUM(MissedInstalments)  AS TotalMissed
FROM dbo.Practice_Watchlist
GROUP BY Reason, LoanStatus
ORDER BY Reason, LoanStatus;
GO

-- ============================================================
-- Clean-up: remove every practice table created in this chapter.
-- The base tables were not changed (the two INSERTs into
-- dbo.Branch and dbo.Loan in section 8 always fail).
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Branch;
DROP TABLE IF EXISTS dbo.Practice_LoanEmpty;
DROP TABLE IF EXISTS dbo.Practice_Product;
DROP TABLE IF EXISTS dbo.Practice_Customer;
DROP TABLE IF EXISTS dbo.Practice_Note;
DROP TABLE IF EXISTS dbo.Practice_BranchList;
DROP TABLE IF EXISTS dbo.Practice_Watchlist;
DROP TABLE IF EXISTS dbo.Practice_LoanOfficer;
DROP TABLE IF EXISTS dbo.Practice_RepaidLoan;
DROP TABLE IF EXISTS dbo.Practice_CallLog;
DROP TABLE IF EXISTS dbo.Practice_BranchSummary;
DROP TABLE IF EXISTS dbo.Practice_Contact;
GO
