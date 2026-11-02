/* SQL Server from Zero — Volume 1
   Chapter 03: SELECT, FROM and ORDER BY
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- Correction 03.1

SELECT BranchName,           -- the name of the branch
       City,
       Region
FROM dbo.Branch
ORDER BY BranchName;         -- ascending is the default


-- Correction 03.2

SELECT CONCAT(FirstName, N' ', LastName) AS OfficerName,
       Email
FROM dbo.LoanOfficer
ORDER BY LastName,           -- surname first
         FirstName;          -- then first name for equal surnames


-- Correction 03.3

SELECT ProductName,
       MaxTermMonths,
       MaxTermMonths / 12 AS MaxTermYears  -- integer division
FROM dbo.Product
ORDER BY MaxTermYears DESC,                -- longest first
         ProductName;                      -- tie-breaker


-- Correction 03.4

SELECT TOP (5)
       LoanID,
       Principal,
       OutstandingBalance,
       Principal - OutstandingBalance AS AmountRepaid
FROM dbo.Loan
ORDER BY AmountRepaid DESC,    -- the alias: largest repayment first
         LoanID;               -- tie-breaker


-- Correction 03.5

SELECT TOP (1) WITH TIES       -- the first row and all its ties
       LoanID,
       CustomerID,
       OriginationDate,
       Principal
FROM dbo.Loan
ORDER BY OriginationDate DESC; -- most recent date first


-- Correction 03.6

SELECT CustomerID,
       FirstName,
       LastName
FROM dbo.Customer
ORDER BY LastName,
         FirstName,
         CustomerID            -- unique: makes the paging reliable
OFFSET 40 ROWS                 -- skip pages 1 and 2
FETCH NEXT 20 ROWS ONLY;       -- return page 3


-- Correction 03.7

SELECT TOP (6) PERCENT WITH TIES   -- 6 % of the rows, plus ties
       CustomerID,
       FirstName,
       LastName,
       AnnualIncome
FROM dbo.Customer
ORDER BY AnnualIncome DESC;        -- highest income first


-- Correction 03.8

SELECT CustomerID,
       LastName + N', ' + FirstName
           + N' <' + Email + N'>' AS MailingLine,  -- NULL if no email
       CONCAT(LastName, N', ', FirstName,
              N' <', Email, N'>') AS DisplayLine   -- never NULL
FROM dbo.Customer
ORDER BY CustomerID
OFFSET 4 ROWS                  -- skip customers 1 to 4
FETCH NEXT 4 ROWS ONLY;        -- return customers 5 to 8

