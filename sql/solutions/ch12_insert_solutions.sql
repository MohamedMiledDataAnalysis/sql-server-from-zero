/* SQL Server from Zero — Volume 1
   Chapter 12: INSERT and SELECT INTO
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022).
   Each example ends with GO so that the deliberate errors of the chapter
   stop only their own batch. Run the script statement by statement (F5 on a selection). */
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
-- Correction 12.1
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_LoanOfficer;

SELECT *
INTO dbo.Practice_LoanOfficer
FROM dbo.LoanOfficer;

INSERT INTO dbo.Practice_LoanOfficer
    (OfficerID, FirstName, LastName, BranchID, HireDate, Email)
VALUES
    (125, N'Grace', N'Patel', 8, '2026-10-01',          -- ISO date
     N'grace.patel@northbridge-lending.co.uk');

SELECT OfficerID, FirstName, LastName, BranchID, HireDate
FROM dbo.Practice_LoanOfficer
WHERE BranchID = 8                                      -- Newcastle
ORDER BY OfficerID;
GO

-- ============================================================
-- Correction 12.2
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Branch;

SELECT *
INTO dbo.Practice_Branch
FROM dbo.Branch;

INSERT INTO dbo.Practice_Branch
    (BranchID, BranchName, City, Region, OpenedDate)
VALUES
    (9,  N'Edinburgh Princes Street', N'Edinburgh',
         N'Scotland', '2026-10-05'),                -- first row
    (10, N'Belfast Victoria Square', N'Belfast',
         N'Northern Ireland', '2026-11-02');        -- second row

SELECT COUNT(*) AS Branches
FROM dbo.Practice_Branch;
GO

-- ============================================================
-- Correction 12.3
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Customer;

SELECT *
INTO dbo.Practice_Customer
FROM dbo.Customer;

INSERT INTO dbo.Practice_Customer
    (CustomerID, FirstName, LastName, DateOfBirth, Email,
     City, Postcode, EmploymentStatus, AnnualIncome,
     CreditScore, JoinedDate, HomeBranchID)   -- no Phone
VALUES
    (501, N'Fiona', N'MacLeod', '1991-04-22',
     NULL,                                     -- keyword, no quotes
     N'Edinburgh', 'EH2 2ER',                  -- Postcode is VARCHAR
     N'Employed', 48500.00, 781, '2026-09-30', 6);

SELECT CustomerID, FirstName, LastName, Email, Phone
FROM dbo.Practice_Customer
WHERE CustomerID = 501;
GO

-- ============================================================
-- Correction 12.4
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_RepaidLoan;

SELECT *
INTO dbo.Practice_RepaidLoan
FROM dbo.Loan
WHERE 1 = 0;                                  -- columns, no rows

INSERT INTO dbo.Practice_RepaidLoan
    (LoanID, CustomerID, ProductCode, BranchID, OfficerID,
     ApplicationDate, OriginationDate, Principal, InterestRate,
     TermMonths, MonthlyPayment, MaturityDate, LoanStatus,
     OutstandingBalance)
SELECT LoanID, CustomerID, ProductCode, BranchID, OfficerID,
       ApplicationDate, OriginationDate, Principal, InterestRate,
       TermMonths, MonthlyPayment, MaturityDate, LoanStatus,
       OutstandingBalance
FROM dbo.Loan
WHERE LoanStatus = N'Repaid'
  AND OriginationDate >= '2021-01-01'         -- from 1 January 2021
  AND OriginationDate <  '2022-01-01';        -- up to 31 December

SELECT COUNT(*)       AS Loans,
       SUM(Principal) AS TotalPrincipal
FROM dbo.Practice_RepaidLoan;
GO

-- ============================================================
-- Correction 12.5
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Branch;

SELECT *
INTO dbo.Practice_Branch
FROM dbo.Branch;

INSERT INTO dbo.Practice_Branch
    (BranchID, BranchName, City, Region, OpenedDate)
VALUES
    (1, N'London Canary Wharf', N'London', N'London',
     '2026-10-12');                         -- BranchID 1 again

SELECT COUNT(*) AS RowsWithBranchID1
FROM dbo.Practice_Branch
WHERE BranchID = 1;
GO

-- ============================================================
-- Correction 12.6
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_CallLog;

SELECT IDENTITY(INT, 1, 1)          AS CallID,   -- seed 1, step 1
       CAST(NULL AS INT)            AS LoanID,   -- nullable INT
       CAST(NULL AS NVARCHAR(100))  AS Outcome   -- nullable text
INTO dbo.Practice_CallLog
FROM dbo.Branch
WHERE 1 = 0;                                     -- no rows

INSERT INTO dbo.Practice_CallLog DEFAULT VALUES; -- CallID 1

INSERT INTO dbo.Practice_CallLog (LoanID, Outcome)
VALUES (10103, N'Left voicemail');               -- CallID 2

INSERT INTO dbo.Practice_CallLog (LoanID, Outcome)
VALUES (10456, DEFAULT);                         -- CallID 3

SELECT CallID, LoanID, Outcome
FROM dbo.Practice_CallLog
ORDER BY CallID;
GO

-- ============================================================
-- Correction 12.7
-- ============================================================
SELECT COUNT(*) AS TooLong                  -- step 1: measure
FROM dbo.Customer
WHERE LEN(Email) > 30;

DROP TABLE IF EXISTS dbo.Practice_Contact;

SELECT CAST(0 AS INT)              AS CustomerID,
       CAST(N'' AS NVARCHAR(81))   AS FullName,
       CAST(NULL AS NVARCHAR(30))  AS Email   -- nullable
INTO dbo.Practice_Contact
FROM dbo.Branch
WHERE 1 = 0;

INSERT INTO dbo.Practice_Contact (CustomerID, FullName, Email)
SELECT CustomerID,
       FirstName + N' ' + LastName,
       Email
FROM dbo.Customer
WHERE Email IS NULL                         -- NULL always fits
   OR LEN(Email) <= 30;                     -- short enough

SELECT COUNT(*)     AS Contacts,
       COUNT(Email) AS WithEmail
FROM dbo.Practice_Contact;
GO

-- ============================================================
-- Correction 12.8
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Customer;

SELECT *
INTO dbo.Practice_Customer
FROM dbo.Customer
WHERE CustomerID <= 250;                    -- first half only

INSERT INTO dbo.Practice_Customer
    (CustomerID, FirstName, LastName, DateOfBirth, Email, Phone,
     City, Postcode, EmploymentStatus, AnnualIncome,
     CreditScore, JoinedDate, HomeBranchID)
SELECT c.CustomerID, c.FirstName, c.LastName, c.DateOfBirth,
       c.Email, c.Phone, c.City, c.Postcode, c.EmploymentStatus,
       c.AnnualIncome, c.CreditScore, c.JoinedDate, c.HomeBranchID
FROM dbo.Customer AS c
WHERE NOT EXISTS (SELECT 1                  -- not already copied
                  FROM dbo.Practice_Customer AS pc
                  WHERE pc.CustomerID = c.CustomerID);

-- Run the INSERT above a second time, then:
SELECT COUNT(*)        AS Customers,
       MIN(CustomerID) AS FirstID,
       MAX(CustomerID) AS LastID
FROM dbo.Practice_Customer;
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
