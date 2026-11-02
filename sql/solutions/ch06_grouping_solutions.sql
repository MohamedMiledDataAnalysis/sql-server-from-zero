/* SQL Server from Zero — Volume 1
   Chapter 06: Summarising with GROUP BY and HAVING
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- Correction 06.1

SELECT COUNT(*)                     AS Customers,     -- all rows
       COUNT(DISTINCT HomeBranchID) AS HomeBranches,  -- distinct
       MIN(JoinedDate)              AS FirstJoined,   -- earliest date
       MAX(JoinedDate)              AS LastJoined     -- latest date
FROM dbo.Customer;


-- Correction 06.2

SELECT EmploymentStatus,
       COUNT(*) AS Customers
FROM dbo.Customer
GROUP BY EmploymentStatus      -- one row per status
ORDER BY Customers DESC;       -- alias allowed in ORDER BY


-- Correction 06.3

SELECT ProductCode,
       COUNT(*)                AS Loans,
       SUM(OutstandingBalance) AS Outstanding
FROM dbo.Loan
WHERE LoanStatus = N'Active'       -- row filter, before grouping
GROUP BY ProductCode
ORDER BY Outstanding DESC;


-- Correction 06.4

SELECT AVG(InterestRate)                       AS AvgRate,
       CAST(AVG(InterestRate) AS DECIMAL(5,2)) AS AvgRateTwoDp,
       MIN(InterestRate)                       AS MinRate,
       MAX(InterestRate)                       AS MaxRate
FROM dbo.Loan;


-- Correction 06.5

SELECT CustomerID,
       COUNT(*)       AS Loans,
       SUM(Principal) AS TotalPrincipal
FROM dbo.Loan
GROUP BY CustomerID
HAVING COUNT(*) >= 6
ORDER BY Loans DESC, CustomerID;


-- Correction 06.6

SELECT LoanID,
       COUNT(*) - COUNT(PaidDate)    AS MissedInstalments,
       SUM(AmountDue - AmountPaid)   AS Unpaid    -- 0 when paid
FROM dbo.Payment
GROUP BY LoanID
HAVING COUNT(*) - COUNT(PaidDate) >= 12
ORDER BY MissedInstalments DESC, LoanID;


-- Correction 06.7

SELECT CASE WHEN GROUPING(Grade) = 1 THEN 'All'
            ELSE Grade END                         AS GradeLabel,
       COUNT(*)                                    AS Ratings,
       CAST(AVG(ProbabilityOfDefault)
            AS DECIMAL(6,4))                       AS AvgPD,
       MIN(CreditScore)                            AS MinScore,
       MAX(CreditScore)                            AS MaxScore
FROM dbo.CreditRating
WHERE RatingDate = '2026-07-01'       -- one rating date only
GROUP BY ROLLUP (Grade)
ORDER BY GROUPING(Grade), Grade;


-- Correction 06.8

SELECT CASE WHEN GROUPING(CollateralType) = 1 THEN N'All types'
            ELSE CollateralType END                AS TypeLabel,
       CASE WHEN GROUPING(YEAR(ValuationDate)) = 1 THEN N'All years'
            ELSE CAST(YEAR(ValuationDate) AS NVARCHAR(4))
       END                                         AS YearLabel,
       COUNT(*)                                    AS Items,
       SUM(ValuationAmount)                        AS TotalValuation
FROM dbo.Collateral
WHERE ValuationDate >= '2025-01-01'
GROUP BY GROUPING SETS ((CollateralType),
                        (YEAR(ValuationDate)),
                        ())
ORDER BY GROUPING(CollateralType), CollateralType,
         GROUPING(YEAR(ValuationDate)), YEAR(ValuationDate);

