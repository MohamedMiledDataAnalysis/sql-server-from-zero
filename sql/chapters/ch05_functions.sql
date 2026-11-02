/* SQL Server from Zero — Volume 1
   Chapter 05: Functions, CASE and data types in queries
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- 1. Data types

SELECT TOP (3)
       LoanID,
       Principal,                        -- DECIMAL(12,2)
       InterestRate,                     -- DECIMAL(5,2)
       Principal * InterestRate AS RateTimesPrincipal,
       17 / 5.0 AS DecimalDivision       -- DECIMAL(2,0) / DECIMAL(2,1)
FROM dbo.Loan
ORDER BY LoanID;

-- 2. CAST, CONVERT and TRY_CAST

SELECT TOP (3)
       LoanID,
       InterestRate,
       CAST(InterestRate AS INT)          AS RateAsInt,     -- cuts
       CAST(InterestRate AS DECIMAL(4,1)) AS RateOneDecimal,-- rounds
       CAST(Principal * InterestRate / 100
            AS DECIMAL(12,2))             AS AnnualInterest
FROM dbo.Loan
ORDER BY LoanID;

SELECT TOP (3)
       LoanID,
       OriginationDate,
       CONVERT(VARCHAR(10), OriginationDate, 103) AS UkStyle,
       CONVERT(VARCHAR(8),  OriginationDate, 112) AS Compact,
       CAST(LoanID AS VARCHAR(10)) + '-'
           + ProductCode AS LoanRef
FROM dbo.Loan
ORDER BY LoanID;

SELECT TRY_CAST(N'12A'        AS INT)  AS BadNumber,
       TRY_CAST(N'0042'       AS INT)  AS GoodNumber,
       TRY_CAST(N'2026-02-30' AS DATE) AS BadDate,
       TRY_CAST(N'2026-02-28' AS DATE) AS GoodDate;

-- 3. String functions

SELECT TOP (5)
       CustomerID,
       Postcode,
       CHARINDEX(' ', Postcode) AS SpaceAt,       -- position of space
       LEFT(Postcode, CHARINDEX(' ', Postcode) - 1)
           AS OutwardCode,                        -- text before it
       REPLACE(Phone, ' ', '') AS PhoneDigits     -- remove spaces
FROM dbo.Customer
ORDER BY CustomerID;

SELECT TOP (3)
       LoanID,
       FORMAT(Principal, 'N2', 'en-GB')       AS WithSeparators,
       FORMAT(Principal, 'C0', 'en-GB')       AS Currency,
       FORMAT(OriginationDate, 'dd MMMM yyyy', 'en-GB') AS LongDate
FROM dbo.Loan
ORDER BY LoanID;

-- 4. Numeric functions

SELECT LoanID,
       OutstandingBalance,
       ROUND(OutstandingBalance, 1)  AS RoundOne,
       ROUND(OutstandingBalance, 0)  AS RoundZero,
       ROUND(OutstandingBalance, -3) AS RoundThousand,
       CEILING(OutstandingBalance)   AS Ceil,
       FLOOR(OutstandingBalance)     AS Flr
FROM dbo.Loan
WHERE LoanID = 10001;

SELECT TOP (3)
       LoanID,
       MonthlyPayment,
       CAST(Principal * (CAST(InterestRate AS FLOAT) / 1200)
            / (1 - POWER(1 + CAST(InterestRate AS FLOAT) / 1200,
                         -TermMonths))
            AS DECIMAL(12,2)) AS Recomputed
FROM dbo.Loan
ORDER BY LoanID;

-- 5. Date functions

SELECT LoanID,
       OriginationDate,
       YEAR(OriginationDate)              AS OrigYear,
       DATEPART(quarter, OriginationDate) AS OrigQuarter,
       DATEADD(month, TermMonths, OriginationDate) AS CalcMaturity,
       MaturityDate
FROM dbo.Loan
WHERE LoanID BETWEEN 10001 AND 10004
ORDER BY LoanID;

SELECT DATEDIFF(day,   '2026-09-01', '2026-09-30') AS DaysApart,
       DATEDIFF(month, '2026-01-31', '2026-02-01') AS MonthsApart,
       DATEDIFF(year,  '2025-12-31', '2026-01-01') AS YearsApart,
       EOMONTH('2026-02-10')                       AS EndOfFebruary,
       DATEADD(month, 1, DATEFROMPARTS(2026, 1, 31)) AS OneMonthLater;

-- 6. Missing values: ISNULL, COALESCE and NULLIF

SELECT CustomerID,
       ISNULL(Email, N'(no email)')     AS EmailShown,
       COALESCE(Email, Phone,
                N'no contact details')  AS BestContact
FROM dbo.Customer
WHERE CustomerID IN (1, 2, 7, 245)
ORDER BY CustomerID;

SELECT CustomerID,
       ISNULL(Phone, 'no phone number on record')   AS WithIsnull,
       COALESCE(Phone, 'no phone number on record') AS WithCoalesce
FROM dbo.Customer
WHERE CustomerID = 2;

SELECT TOP (3)
       LoanID,
       Principal,
       OutstandingBalance,
       CAST(100.0 * (Principal - OutstandingBalance)
            / NULLIF(Principal, 0) AS DECIMAL(5,2)) AS PctRepaid
FROM dbo.Loan
ORDER BY LoanID;

-- 7. IIF and CASE

SELECT ProductCode,
       ProductType,
       IIF(IsSecured = 1, N'Secured', N'Unsecured') AS Security
FROM dbo.Product
ORDER BY ProductCode;

SELECT CustomerID,
       FirstName,
       CreditScore,
       CASE
           WHEN CreditScore >= 850 THEN 'A'
           WHEN CreditScore >= 750 THEN 'B'   -- 750 to 849
           WHEN CreditScore >= 650 THEN 'C'   -- 650 to 749
           WHEN CreditScore >= 550 THEN 'D'   -- 550 to 649
           ELSE 'E'                           -- below 550
       END AS Grade
FROM dbo.Customer
WHERE CustomerID BETWEEN 1 AND 6
ORDER BY CustomerID;


-- Applied example

-- Step 1: grade and income band.

SELECT CustomerID,
       CreditScore,
       CASE
           WHEN CreditScore >= 850 THEN 'A'
           WHEN CreditScore >= 750 THEN 'B'
           WHEN CreditScore >= 650 THEN 'C'
           WHEN CreditScore >= 550 THEN 'D'
           ELSE 'E'
       END AS Grade,
       CASE
           WHEN AnnualIncome < 20000 THEN N'Low'
           WHEN AnnualIncome < 40000 THEN N'Middle'
           ELSE N'Higher'
       END AS IncomeBand,
       FORMAT(AnnualIncome, 'C0', 'en-GB') AS Income
FROM dbo.Customer
WHERE HomeBranchID = 6
  AND CreditScore < 600
ORDER BY CreditScore,
         CustomerID;

-- Step 2: the final sheet, with the exact age.

SELECT CONCAT(UPPER(LastName), N', ', FirstName) AS CustomerName,
       DATEDIFF(year, DateOfBirth, '2026-09-30')
         - CASE
               WHEN DATEADD(year,
                            DATEDIFF(year, DateOfBirth, '2026-09-30'),
                            DateOfBirth) > '2026-09-30'
               THEN 1 ELSE 0      -- birthday still to come
           END AS Age,
       CASE
           WHEN CreditScore >= 550 THEN 'D'
           ELSE 'E'
       END AS Grade,                -- every score here is below 650
       FORMAT(AnnualIncome, 'C0', 'en-GB') AS Income,
       DATEDIFF(month, JoinedDate, '2026-09-30') AS MonthsAsCustomer,
       COALESCE(Email, Phone, N'no contact details') AS Contact
FROM dbo.Customer
WHERE HomeBranchID = 6
  AND CreditScore < 600
ORDER BY CreditScore,
         CustomerID;
