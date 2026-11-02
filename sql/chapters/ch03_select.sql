/* SQL Server from Zero — Volume 1
   Chapter 03: SELECT, FROM and ORDER BY
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- 1. SELECT and FROM: choosing columns

SELECT ProductCode,          -- the key of the Product table
       ProductName,
       BaseRate              -- annual rate in per cent, e.g. 6.70
FROM dbo.Product
ORDER BY ProductCode;        -- sort by code (section 6 explains it)

-- 2. Aliases: renaming columns with AS

SELECT OfficerID AS Officer,
       FirstName AS [First name],      -- brackets allow a space
       LastName  AS [Last name],
       HireDate  AS StartedOn
FROM dbo.LoanOfficer
ORDER BY HireDate;                     -- the earliest hire first

-- 3. Calculated columns and arithmetic

SELECT TOP (5)
       LoanID,
       TermMonths,
       TermMonths / 12 AS TermYears,       -- whole years
       TermMonths % 12 AS ExtraMonths,     -- months left over
       MonthlyPayment * TermMonths AS TotalRepayable
FROM dbo.Loan
ORDER BY LoanID;

-- 4. Joining text: + and CONCAT

SELECT TOP (7)
       CustomerID,
       FirstName + N' ' + LastName
           + N' <' + Email + N'>' AS PlusVersion,
       CONCAT(FirstName, N' ', LastName,
              N' <', Email, N'>') AS ConcatVersion
FROM dbo.Customer
ORDER BY CustomerID;

-- 5. DISTINCT: removing duplicate rows

SELECT DISTINCT LoanStatus
FROM dbo.Loan
ORDER BY LoanStatus;

SELECT DISTINCT City,
       EmploymentStatus
FROM dbo.Customer
ORDER BY City,
         EmploymentStatus;

-- 6. ORDER BY: sorting the result

SELECT TOP (5)
       CustomerID,
       FirstName,
       LastName,
       CreditScore
FROM dbo.Customer
ORDER BY CreditScore DESC,   -- highest score first
         LastName ASC,       -- then alphabetically
         CustomerID;         -- then by ID: a unique tie-breaker

-- 7. TOP, WITH TIES and PERCENT

SELECT TOP (5) WITH TIES
       LoanID,
       Principal
FROM dbo.Loan
ORDER BY Principal DESC;

SELECT TOP (10) PERCENT
       OfficerID,
       FirstName,
       LastName,
       HireDate
FROM dbo.LoanOfficer
ORDER BY HireDate DESC;        -- most recent hire first

-- 8. OFFSET … FETCH and the logical processing order

SELECT LoanID,
       CustomerID,
       Principal
FROM dbo.Loan
ORDER BY LoanID
OFFSET 5 ROWS                 -- skip page 1 (rows 1 to 5)
FETCH NEXT 5 ROWS ONLY;       -- return rows 6 to 10


-- Applied example

-- Step 1: the first sheet.

SELECT TOP (10)
       CONCAT(N'Loan ', LoanID, N' (', ProductCode, N')')
           AS [Loan],
       Principal AS [Principal (GBP)],
       MonthlyPayment * TermMonths - Principal
           AS [Total interest (GBP)],
       LoanStatus AS [Status]
FROM dbo.Loan
ORDER BY Principal DESC,
         LoanID;

-- Step 2: the second sheet.

SELECT CONCAT(N'Loan ', LoanID, N' (', ProductCode, N')')
           AS [Loan],
       Principal AS [Principal (GBP)],
       LoanStatus AS [Status]
FROM dbo.Loan
ORDER BY Principal DESC,
         LoanID
OFFSET 10 ROWS
FETCH NEXT 10 ROWS ONLY;
