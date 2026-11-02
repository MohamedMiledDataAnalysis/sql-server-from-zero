/* SQL Server from Zero — Volume 1
   Chapter 05: Functions, CASE and data types in queries
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- Correction 05.1

SELECT OfficerID,
       UPPER(LastName)    AS LastNameUpper,
       LEFT(FirstName, 1) AS Initial,       -- first character
       LEN(Email)         AS EmailLength
FROM dbo.LoanOfficer
WHERE BranchID = 1
ORDER BY OfficerID;


-- Correction 05.2

SELECT LoanID,
       OriginationDate,
       YEAR(OriginationDate)    AS OrigYear,
       MONTH(OriginationDate)   AS OrigMonth,
       EOMONTH(OriginationDate) AS MonthEnd    -- last day of month
FROM dbo.Loan
WHERE LoanID BETWEEN 10001 AND 10005
ORDER BY LoanID;


-- Correction 05.3

SELECT CustomerID,
       FirstName,
       COALESCE(Phone, 'no phone') AS PhoneShown  -- NULL replaced
FROM dbo.Customer
WHERE CustomerID BETWEEN 1 AND 8
ORDER BY CustomerID;


-- Correction 05.4

SELECT TOP (8)
       CustomerID,
       LastName,
       Postcode,
       LEFT(Postcode, CHARINDEX(' ', Postcode) - 1) AS OutwardCode
FROM dbo.Customer
WHERE City = N'Bristol'
ORDER BY CustomerID;


-- Correction 05.5

SELECT InstalmentNumber,
       DueDate,
       PaidDate,
       DaysLate,
       IIF(DATEDIFF(day, DueDate, PaidDate) < 0,
           0,                                    -- early counts as 0
           DATEDIFF(day, DueDate, PaidDate)) AS Recomputed
FROM dbo.Payment
WHERE LoanID = 10002
  AND InstalmentNumber BETWEEN 1 AND 8
ORDER BY InstalmentNumber;


-- Correction 05.6

SELECT LoanID,
       Principal,
       CASE
           WHEN Principal < 25000  THEN N'Small'
           WHEN Principal < 150000 THEN N'Medium'  -- 25,000 up to 149,999.99
           ELSE N'Large'                           -- 150,000 and above
       END AS SizeBand
FROM dbo.Loan
WHERE LoanID BETWEEN 10001 AND 10008
ORDER BY LoanID;


-- Correction 05.7

SELECT TOP (8)
       CustomerID,
       FirstName,
       DateOfBirth,
       DATEDIFF(year, DateOfBirth, '2026-09-30') AS NaiveAge,
       DATEDIFF(year, DateOfBirth, '2026-09-30')
         - CASE
               WHEN DATEADD(year,
                            DATEDIFF(year, DateOfBirth, '2026-09-30'),
                            DateOfBirth) > '2026-09-30'
               THEN 1 ELSE 0
           END AS ExactAge
FROM dbo.Customer
WHERE DATEADD(year,                       -- birthday of 2026 ...
              DATEDIFF(year, DateOfBirth, '2026-09-30'),
              DateOfBirth) > '2026-09-30' -- ... still to come
ORDER BY CustomerID;


-- Correction 05.8

SELECT TOP (5)
       LoanID,
       LoanStatus,
       OutstandingBalance,
       CASE LoanStatus
           WHEN N'Default'     THEN 1
           WHEN N'Arrears'     THEN 2
           WHEN N'Written Off' THEN 3
       END AS SeverityRank
FROM dbo.Loan
WHERE LoanStatus IN (N'Arrears', N'Default', N'Written Off')
ORDER BY SeverityRank,            -- the alias of the CASE
         OutstandingBalance,      -- smallest balance first
         LoanID;

