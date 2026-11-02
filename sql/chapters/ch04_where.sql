/* SQL Server from Zero — Volume 1
   Chapter 04: Filtering rows with WHERE
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- 1. WHERE and the comparison operators

SELECT LoanID,
       CustomerID,
       OutstandingBalance
FROM dbo.Loan
WHERE LoanStatus = N'Default'      -- text goes between quotes
ORDER BY OutstandingBalance DESC;

-- Wrong version, shown in the book; kept as a comment:
-- SELECT LoanID,
--        Principal - OutstandingBalance AS AmountRepaid
-- FROM dbo.Loan
-- WHERE AmountRepaid > 150000;      -- WRONG: the alias does not exist yet

-- 2. AND, OR, NOT and precedence

SELECT LoanID,
       CustomerID,
       OutstandingBalance
FROM dbo.Loan
WHERE LoanStatus = N'Arrears'
  AND OutstandingBalance > 100000    -- both tests must be true
ORDER BY OutstandingBalance DESC;

-- Wrong version, shown in the book; kept as a comment:
-- SELECT LoanID,
--        LoanStatus,
--        OutstandingBalance
-- FROM dbo.Loan
-- WHERE LoanStatus = N'Arrears'
--    OR LoanStatus = N'Default'
--   AND OutstandingBalance > 300000   -- WRONG: AND binds first
-- ORDER BY OutstandingBalance;

SELECT LoanID,
       LoanStatus,
       OutstandingBalance
FROM dbo.Loan
WHERE (LoanStatus = N'Arrears'
       OR LoanStatus = N'Default')     -- evaluated first
  AND OutstandingBalance > 300000
ORDER BY OutstandingBalance DESC;

-- 3. IN and NOT IN

SELECT LoanID,
       CustomerID,
       LoanStatus,
       OutstandingBalance
FROM dbo.Loan
WHERE LoanStatus IN (N'Arrears', N'Default', N'Written Off')
ORDER BY LoanID;

-- 4. BETWEEN: ranges

SELECT CustomerID,
       FirstName,
       LastName,
       CreditScore
FROM dbo.Customer
WHERE CreditScore BETWEEN 650 AND 749   -- 650 and 749 included
ORDER BY CreditScore,
         CustomerID;

-- 5. LIKE: matching text patterns

SELECT CustomerID,
       FirstName,
       LastName
FROM dbo.Customer
WHERE LastName LIKE N'%son'     -- anything, then "son" at the end
ORDER BY LastName,
         FirstName,
         CustomerID;

SELECT CustomerID,
       FirstName,
       LastName,
       City,
       Postcode
FROM dbo.Customer
WHERE Postcode LIKE 'B[0-9]%'   -- B, then a digit, then anything
ORDER BY CustomerID;

-- 6. NULL, IS NULL and three-valued logic

-- Wrong version, shown in the book; kept as a comment:
-- SELECT CustomerID,
--        FirstName,
--        LastName
-- FROM dbo.Customer
-- WHERE Email = NULL;             -- WRONG: never true

SELECT CustomerID,
       FirstName,
       LastName,
       Phone
FROM dbo.Customer
WHERE Email IS NULL             -- the right test for a missing value
ORDER BY CustomerID;

-- 7. Filtering dates

SELECT PaymentID,
       LoanID,
       InstalmentNumber,
       DueDate,
       AmountDue
FROM dbo.Payment
WHERE PaidDate IS NULL              -- missed
  AND DueDate >= '2026-09-01'       -- from 1 September included
  AND DueDate <  '2026-10-01'       -- to 1 October excluded
ORDER BY AmountDue DESC,
         PaymentID;

SELECT LoanID,
       CustomerID,
       ProductCode,
       OriginationDate,
       Principal
FROM dbo.Loan
WHERE OriginationDate >= '2025-01-01'
  AND OriginationDate <  '2026-01-01'
  AND ProductCode = 'SME-TERM'        -- small-business loans only
ORDER BY OriginationDate,
         LoanID;


-- Applied example

-- Step 1: missed or very late in the quarter.

SELECT PaymentID,
       LoanID,
       DueDate,
       PaidDate,
       DaysLate,
       AmountDue
FROM dbo.Payment
WHERE (PaidDate IS NULL           -- missed
       OR DaysLate > 30)          -- or more than 30 days late
  AND DueDate >= '2026-07-01'
  AND DueDate <  '2026-10-01'
ORDER BY LoanID,
         DueDate;

-- Step 2: keep the large amounts.

SELECT PaymentID,
       LoanID,
       DueDate,
       PaidDate,
       DaysLate,
       AmountDue
FROM dbo.Payment
WHERE (PaidDate IS NULL
       OR DaysLate > 30)
  AND DueDate >= '2026-07-01'
  AND DueDate <  '2026-10-01'
  AND AmountDue >= 2000           -- large instalments only
ORDER BY LoanID,
         DueDate;

-- Step 3: the mortgages seriously behind.

SELECT LoanID,
       CustomerID,
       ProductCode,
       LoanStatus,
       OutstandingBalance
FROM dbo.Loan
WHERE LoanStatus IN (N'Arrears', N'Default')
  AND ProductCode LIKE 'MTG%'          -- every mortgage product
  AND OutstandingBalance >= 100000
ORDER BY OutstandingBalance DESC;
