/* SQL Server from Zero — Volume 1
   Chapter 8: Subqueries, CTEs and set operators
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- ------------------------------------------------------------
-- 1. Scalar subqueries: a query that returns one value
-- ------------------------------------------------------------

SELECT COUNT(*) AS LoansAboveAverage
FROM dbo.Loan
WHERE Principal > (SELECT AVG(Principal)   -- one value: 120933.000000
                   FROM dbo.Loan);

-- Scalar subquery in the SELECT list (described in the text)
SELECT ProductCode,
       SUM(OutstandingBalance) AS Outstanding,
       CAST(100.0 * SUM(OutstandingBalance)
            / (SELECT SUM(OutstandingBalance) FROM dbo.Loan)  -- total
            AS DECIMAL(5,2)) AS SharePct
FROM dbo.Loan
GROUP BY ProductCode
ORDER BY Outstanding DESC;


-- The next statement fails on purpose (see the book). Remove the
-- comment marks to see the error message.
-- SELECT LoanID
-- FROM dbo.Loan
-- WHERE Principal > (SELECT AVG(Principal)
--                    FROM dbo.Loan
--                    GROUP BY ProductCode);   -- eight values


-- ------------------------------------------------------------
-- 2. Multi-row subqueries with IN and NOT IN
-- ------------------------------------------------------------

SELECT CustomerID,
       FirstName,
       LastName
FROM dbo.Customer
WHERE CustomerID IN (SELECT CustomerID          -- a list of IDs
                     FROM dbo.Loan
                     WHERE LoanStatus = N'Arrears')
ORDER BY CustomerID;


-- ------------------------------------------------------------
-- 3. EXISTS, NOT EXISTS and the NOT IN trap
-- ------------------------------------------------------------

SELECT COUNT(*) AS CustomersWithRecentMiss
FROM dbo.Customer AS c
WHERE EXISTS (SELECT 1
              FROM dbo.Loan AS l
              JOIN dbo.Payment AS p ON p.LoanID = l.LoanID
              WHERE l.CustomerID = c.CustomerID     -- this customer
                AND p.PaidDate IS NULL              -- missed
                AND p.DueDate >= '2026-07-01');     -- recently


SELECT COUNT(*) AS OfficersNotCustomers
FROM dbo.LoanOfficer
WHERE Email NOT IN (SELECT Email FROM dbo.Customer);  -- has NULLs

-- Version 1: remove the NULLs from the list
SELECT COUNT(*) AS OfficersNotCustomers
FROM dbo.LoanOfficer
WHERE Email NOT IN (SELECT Email
                    FROM dbo.Customer
                    WHERE Email IS NOT NULL);

-- Version 2: NOT EXISTS, which is not affected by NULLs
SELECT COUNT(*) AS OfficersNotCustomers
FROM dbo.LoanOfficer AS o
WHERE NOT EXISTS (SELECT 1
                  FROM dbo.Customer AS c
                  WHERE c.Email = o.Email);


-- ------------------------------------------------------------
-- 4. Correlated subqueries
-- ------------------------------------------------------------


SELECT TOP (5)
       c.CustomerID,
       c.LastName,
       r.RatingDate,
       r.Grade,
       r.ProbabilityOfDefault
FROM dbo.Customer AS c
JOIN dbo.CreditRating AS r ON r.CustomerID = c.CustomerID
WHERE r.RatingDate = (SELECT MAX(x.RatingDate)       -- latest date
                      FROM dbo.CreditRating AS x
                      WHERE x.CustomerID = c.CustomerID)
ORDER BY c.CustomerID;


-- ------------------------------------------------------------
-- 5. Derived tables: a query in the FROM clause
-- ------------------------------------------------------------

SELECT t.LoanStatus,
       COUNT(*) AS LoansWithMisses
FROM (SELECT l.LoanID,
             l.LoanStatus,
             COUNT(*) - COUNT(p.PaidDate) AS Missed   -- per loan
      FROM dbo.Loan AS l
      JOIN dbo.Payment AS p ON p.LoanID = l.LoanID
      GROUP BY l.LoanID, l.LoanStatus
      HAVING COUNT(*) - COUNT(p.PaidDate) >= 1) AS t
GROUP BY t.LoanStatus                                 -- per status
ORDER BY t.LoanStatus;


-- ------------------------------------------------------------
-- 6. Common table expressions with WITH
-- ------------------------------------------------------------

WITH CustomerExposure AS
(
    SELECT CustomerID,
           COUNT(*)                AS Loans,
           SUM(OutstandingBalance) AS Exposure
    FROM dbo.Loan
    WHERE LoanStatus <> N'Repaid'          -- loans still owed
    GROUP BY CustomerID
)
SELECT TOP (5)
       e.CustomerID,
       c.FirstName,
       c.LastName,
       e.Loans,
       e.Exposure
FROM CustomerExposure AS e
JOIN dbo.Customer AS c ON c.CustomerID = e.CustomerID
ORDER BY e.Exposure DESC;


-- ------------------------------------------------------------
-- 7. Set operators: UNION, UNION ALL, INTERSECT and EXCEPT
-- ------------------------------------------------------------

SELECT N'Customer' AS ContactType, FirstName, LastName, Email
FROM dbo.Customer
WHERE City = N'Cardiff'
  AND JoinedDate >= '2026-01-01'
UNION ALL
SELECT N'Officer', FirstName, LastName, Email
FROM dbo.LoanOfficer
WHERE BranchID = 7                       -- Cardiff Bay
ORDER BY ContactType, LastName, FirstName;

SELECT CustomerID FROM dbo.Loan WHERE ProductCode LIKE 'MTG%'
INTERSECT
SELECT CustomerID FROM dbo.Loan WHERE ProductCode LIKE 'PL%'
ORDER BY CustomerID;

SELECT COUNT(*) AS NeverMissed
FROM (SELECT CustomerID FROM dbo.Loan          -- all borrowers
      EXCEPT
      SELECT l.CustomerID                      -- with a miss
      FROM dbo.Loan AS l
      JOIN dbo.Payment AS p ON p.LoanID = l.LoanID
      WHERE p.PaidDate IS NULL) AS t;


-- ------------------------------------------------------------
-- 8. Recursive CTEs: generating an instalment schedule
-- ------------------------------------------------------------

WITH Schedule AS
(
    -- Anchor: instalment 0 is the day the loan is paid out
    SELECT 0                                AS InstalmentNumber,
           l.OriginationDate                AS DueDate,
           CAST(0 AS DECIMAL(12,2))         AS Interest,
           CAST(l.Principal AS DECIMAL(12,2)) AS Balance
    FROM dbo.Loan AS l
    WHERE l.LoanID = 10016

    UNION ALL

    -- Recursive member: next instalment from the previous one
    SELECT s.InstalmentNumber + 1,
           DATEADD(month, s.InstalmentNumber + 1,
                   l.OriginationDate),
           CAST(ROUND(s.Balance * l.InterestRate / 1200, 2)
                AS DECIMAL(12,2)),
           CAST(s.Balance
                + ROUND(s.Balance * l.InterestRate / 1200, 2)
                - l.MonthlyPayment AS DECIMAL(12,2))
    FROM Schedule AS s
    JOIN dbo.Loan AS l ON l.LoanID = 10016
    WHERE s.InstalmentNumber < l.TermMonths     -- stop at 24
)
SELECT InstalmentNumber, DueDate, Interest, Balance
FROM Schedule
WHERE InstalmentNumber BETWEEN 1 AND 3
   OR InstalmentNumber >= 23
ORDER BY InstalmentNumber;


WITH Schedule AS
(
    SELECT 0 AS InstalmentNumber, l.OriginationDate AS DueDate
    FROM dbo.Loan AS l
    WHERE l.LoanID = 10009
    UNION ALL
    SELECT s.InstalmentNumber + 1,
           DATEADD(month, s.InstalmentNumber + 1, l.OriginationDate)
    FROM Schedule AS s
    JOIN dbo.Loan AS l ON l.LoanID = 10009
    WHERE s.InstalmentNumber < l.TermMonths
)
SELECT COUNT(*) AS ScheduleRows
FROM Schedule
OPTION (MAXRECURSION 400);       -- allow up to 400 steps


-- ------------------------------------------------------------
-- Applied example
-- ------------------------------------------------------------


-- Step 1 — The latest rating of each customer, as a CTE

WITH LatestRating AS
(
    SELECT r.CustomerID, r.Grade, r.ProbabilityOfDefault
    FROM dbo.CreditRating AS r
    WHERE r.RatingDate = (SELECT MAX(x.RatingDate)
                          FROM dbo.CreditRating AS x
                          WHERE x.CustomerID = r.CustomerID)
)
SELECT Grade, COUNT(*) AS Customers
FROM LatestRating
GROUP BY Grade
ORDER BY Grade;


-- Step 2 — Build the watch list and add the exposure

WITH LatestRating AS
(
    SELECT r.CustomerID, r.Grade, r.ProbabilityOfDefault
    FROM dbo.CreditRating AS r
    WHERE r.RatingDate = (SELECT MAX(x.RatingDate)
                          FROM dbo.CreditRating AS x
                          WHERE x.CustomerID = r.CustomerID)
),
RecentMiss AS
(
    SELECT DISTINCT l.CustomerID
    FROM dbo.Loan AS l
    JOIN dbo.Payment AS p ON p.LoanID = l.LoanID
    WHERE p.PaidDate IS NULL
      AND p.DueDate >= '2026-07-01'
),
WatchList AS
(
    SELECT CustomerID FROM LatestRating WHERE Grade IN ('D', 'E')
    INTERSECT
    SELECT CustomerID FROM RecentMiss
)
SELECT w.CustomerID,
       c.LastName,
       lr.Grade,
       COUNT(*)                  AS OpenLoans,
       SUM(l.OutstandingBalance) AS Exposure,
       CAST(SUM(l.OutstandingBalance * lr.ProbabilityOfDefault)
            AS DECIMAL(12,2))    AS ExpectedLoss
FROM WatchList AS w
JOIN dbo.Customer AS c   ON c.CustomerID  = w.CustomerID
JOIN LatestRating AS lr  ON lr.CustomerID = w.CustomerID
JOIN dbo.Loan AS l       ON l.CustomerID  = w.CustomerID
                        AND l.LoanStatus <> N'Repaid'
GROUP BY w.CustomerID, c.LastName, lr.Grade
ORDER BY ExpectedLoss DESC, w.CustomerID;


-- Step 3 — The total for the cover note

-- The three CTEs of step 2, repeated: a CTE lives for one statement.
WITH LatestRating AS
(
    SELECT r.CustomerID, r.Grade, r.ProbabilityOfDefault
    FROM dbo.CreditRating AS r
    WHERE r.RatingDate = (SELECT MAX(x.RatingDate)
                          FROM dbo.CreditRating AS x
                          WHERE x.CustomerID = r.CustomerID)
),
RecentMiss AS
(
    SELECT DISTINCT l.CustomerID
    FROM dbo.Loan AS l
    JOIN dbo.Payment AS p ON p.LoanID = l.LoanID
    WHERE p.PaidDate IS NULL
      AND p.DueDate >= '2026-07-01'
),
WatchList AS
(
    SELECT CustomerID FROM LatestRating WHERE Grade IN ('D', 'E')
    INTERSECT
    SELECT CustomerID FROM RecentMiss
)
SELECT COUNT(DISTINCT w.CustomerID) AS Customers,
       COUNT(*)                     AS OpenLoans,
       SUM(l.OutstandingBalance)    AS Exposure,
       CAST(SUM(l.OutstandingBalance * lr.ProbabilityOfDefault)
            AS DECIMAL(12,2))       AS ExpectedLoss
FROM WatchList AS w
JOIN LatestRating AS lr  ON lr.CustomerID = w.CustomerID
JOIN dbo.Loan AS l       ON l.CustomerID  = w.CustomerID
                        AND l.LoanStatus <> N'Repaid';
