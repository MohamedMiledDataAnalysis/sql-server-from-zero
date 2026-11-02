/* SQL Server from Zero — Volume 1
   Chapter 06: Summarising with GROUP BY and HAVING
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- 1. Counting rows and values with COUNT

SELECT COUNT(*)             AS Customers,   -- every row
       COUNT(Email)         AS WithEmail,   -- Email is not NULL
       COUNT(Phone)         AS WithPhone,   -- Phone is not NULL
       COUNT(DISTINCT City) AS Cities       -- different cities
FROM dbo.Customer;

-- 2. SUM, AVG, MIN and MAX — and the integer trap

SELECT COUNT(*)                AS Loans,
       SUM(Principal)          AS TotalPrincipal,    -- amount lent
       SUM(OutstandingBalance) AS TotalOutstanding,  -- still owed
       MIN(Principal)          AS SmallestLoan,
       MAX(Principal)          AS LargestLoan,
       MIN(OriginationDate)    AS FirstLoan,         -- earliest date
       MAX(OriginationDate)    AS LastLoan           -- latest date
FROM dbo.Loan;

SELECT AVG(CreditScore)       AS AvgInt,     -- SMALLINT column
       AVG(CreditScore * 1.0) AS AvgExact,   -- decimal average
       CAST(AVG(CreditScore * 1.0) AS DECIMAL(6,2)) AS AvgTwoDp
FROM dbo.Customer;

SELECT COUNT(*)                     AS Instalments,
       COUNT(DaysLate)              AS PaidInstalments,
       AVG(DaysLate)                AS AvgDaysLateInt,
       CAST(AVG(DaysLate * 1.0) AS DECIMAL(6,2))          AS AvgPaid,
       CAST(AVG(ISNULL(DaysLate, 0) * 1.0) AS DECIMAL(6,2)) AS AvgAll
FROM dbo.Payment;

-- 3. GROUP BY: one summary row per group

SELECT LoanStatus,
       COUNT(*)                AS Loans,
       SUM(Principal)          AS TotalPrincipal,
       SUM(OutstandingBalance) AS TotalOutstanding
FROM dbo.Loan
GROUP BY LoanStatus      -- one group per status
ORDER BY LoanStatus;

-- The next statement fails on purpose (see the book). Remove the
-- comment marks to see the error message.
-- SELECT LoanStatus,
--        LoanID,            -- not grouped, not aggregated
--        COUNT(*) AS Loans
-- FROM dbo.Loan
-- GROUP BY LoanStatus;

-- 4. Grouping on several columns and on expressions

SELECT ProductCode,
       LoanStatus,
       COUNT(*) AS Loans
FROM dbo.Loan
WHERE ProductCode IN ('MTG-FIX2', 'MTG-FIX5')
  AND LoanStatus IN (N'Arrears', N'Default', N'Written Off')
GROUP BY ProductCode, LoanStatus      -- one group per combination
ORDER BY ProductCode, LoanStatus;

SELECT YEAR(OriginationDate) AS OriginationYear,
       COUNT(*)              AS Loans,
       SUM(Principal)        AS TotalPrincipal
FROM dbo.Loan
GROUP BY YEAR(OriginationDate)   -- the expression, not the alias
ORDER BY OriginationYear;

-- 5. HAVING: filtering groups, and the logical order of the clauses

SELECT OfficerID,
       COUNT(*)       AS Loans,
       SUM(Principal) AS TotalPrincipal
FROM dbo.Loan
GROUP BY OfficerID
HAVING COUNT(*) > 40           -- keep only the large portfolios
ORDER BY Loans DESC, OfficerID;

-- The next statement fails on purpose (see the book). Remove the
-- comment marks to see the error message.
-- SELECT OfficerID, COUNT(*) AS Loans
-- FROM dbo.Loan
-- WHERE COUNT(*) > 40            -- not allowed
-- GROUP BY OfficerID;

SELECT OfficerID,
       COUNT(*) AS ProblemLoans
FROM dbo.Loan
WHERE LoanStatus IN (N'Arrears', N'Default', N'Written Off') -- rows
GROUP BY OfficerID
HAVING COUNT(*) >= 5                                       -- groups
ORDER BY ProblemLoans DESC, OfficerID;

-- 6. ROLLUP: subtotals and a grand total

SELECT ProductCode,
       LoanStatus,
       COUNT(*)                AS Loans,
       SUM(OutstandingBalance) AS Outstanding
FROM dbo.Loan
WHERE ProductCode IN ('AUTO-NEW', 'AUTO-USD')
  AND LoanStatus IN (N'Default', N'Written Off')
GROUP BY ROLLUP (ProductCode, LoanStatus)
ORDER BY GROUPING(ProductCode), ProductCode,
         GROUPING(LoanStatus), LoanStatus;

-- 7. CUBE, GROUPING SETS and the GROUPING() function

SELECT ProductCode,
       LoanStatus,
       COUNT(*)                AS Loans,
       SUM(OutstandingBalance) AS Outstanding
FROM dbo.Loan
WHERE ProductCode IN ('AUTO-NEW', 'AUTO-USD')
  AND LoanStatus IN (N'Default', N'Written Off')
GROUP BY CUBE (ProductCode, LoanStatus)
ORDER BY GROUPING(ProductCode), ProductCode,
         GROUPING(LoanStatus), LoanStatus;

SELECT ProductCode,
       LoanStatus,
       COUNT(*)                AS Loans,
       SUM(OutstandingBalance) AS Outstanding
FROM dbo.Loan
WHERE ProductCode IN ('AUTO-NEW', 'AUTO-USD')
  AND LoanStatus IN (N'Default', N'Written Off')
GROUP BY GROUPING SETS ((ProductCode), (LoanStatus), ())
ORDER BY GROUPING(ProductCode), ProductCode,
         GROUPING(LoanStatus), LoanStatus;

SELECT YEAR(PaidDate)            AS PaidYear,
       GROUPING(YEAR(PaidDate))  AS IsTotal,  -- 1 on the total row
       COUNT(*)                  AS Instalments
FROM dbo.Payment
GROUP BY ROLLUP (YEAR(PaidDate))
ORDER BY IsTotal, PaidYear;


-- Applied example

-- Step 1 — Check the raw totals for 2026.

SELECT COUNT(*)                  AS Instalments,
       COUNT(*) - COUNT(PaidDate) AS Missed,      -- NULL PaidDate
       SUM(AmountDue)            AS AmountDue,
       SUM(AmountPaid)           AS AmountPaid
FROM dbo.Payment
WHERE DueDate >= '2026-01-01';

-- Step 2 — Find the weak months with HAVING.

SELECT MONTH(DueDate)              AS DueMonth,
       COUNT(*) - COUNT(PaidDate)  AS Missed,
       CAST(100.0 * SUM(AmountPaid) / SUM(AmountDue)
            AS DECIMAL(5,2))       AS CollectionRatePct
FROM dbo.Payment
WHERE DueDate >= '2026-01-01'
GROUP BY MONTH(DueDate)
HAVING 100.0 * SUM(AmountPaid) / SUM(AmountDue) < 92
ORDER BY DueMonth;

-- Step 3 — Produce the quarterly table with a labelled total.

SELECT CASE WHEN GROUPING(DATEPART(quarter, DueDate)) = 1
            THEN 'Total 2026'
            ELSE CONCAT('Q', DATEPART(quarter, DueDate))
       END                         AS Period,
       COUNT(*)                    AS Instalments,
       COUNT(*) - COUNT(PaidDate)  AS Missed,
       SUM(AmountDue)              AS AmountDue,
       SUM(AmountPaid)             AS AmountPaid,
       CAST(100.0 * SUM(AmountPaid) / SUM(AmountDue)
            AS DECIMAL(5,2))       AS RatePct
FROM dbo.Payment
WHERE DueDate >= '2026-01-01'
GROUP BY ROLLUP (DATEPART(quarter, DueDate))
ORDER BY GROUPING(DATEPART(quarter, DueDate)),
         DATEPART(quarter, DueDate);
