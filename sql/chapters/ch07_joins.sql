/* SQL Server from Zero — Volume 1
   Chapter 07: Joining tables
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- 1. INNER JOIN: matching rows of two tables

SELECT TOP (5)
       l.LoanID,
       l.CustomerID,
       c.FirstName,             -- from dbo.Customer
       c.LastName,
       l.Principal              -- from dbo.Loan
FROM dbo.Loan AS l
JOIN dbo.Customer AS c
    ON c.CustomerID = l.CustomerID   -- the join condition
ORDER BY l.LoanID;

-- The next statement fails on purpose (see the book). Remove the
-- comment marks to see the error message.
-- SELECT TOP (5) LoanID, CustomerID, LastName  -- which CustomerID?
-- FROM dbo.Loan AS l
-- JOIN dbo.Customer AS c
--     ON c.CustomerID = l.CustomerID
-- ORDER BY LoanID;

-- 2. Joining three or more tables

SELECT TOP (5)
       l.LoanID,
       c.LastName      AS Customer,
       p.ProductName,
       b.BranchName,
       o.LastName      AS Officer
FROM dbo.Loan AS l
JOIN dbo.Customer    AS c ON c.CustomerID  = l.CustomerID
JOIN dbo.Product     AS p ON p.ProductCode = l.ProductCode
JOIN dbo.Branch      AS b ON b.BranchID    = l.BranchID
JOIN dbo.LoanOfficer AS o ON o.OfficerID   = l.OfficerID
ORDER BY l.LoanID;

SELECT p.ProductType,
       COUNT(*)                  AS Loans,
       SUM(l.OutstandingBalance) AS Outstanding
FROM dbo.Loan AS l
JOIN dbo.Product AS p ON p.ProductCode = l.ProductCode
GROUP BY p.ProductType
ORDER BY Outstanding DESC;

-- 3. LEFT OUTER JOIN and finding unmatched rows

SELECT TOP (8)
       c.CustomerID,
       c.LastName,
       l.LoanID                 -- NULL when the customer has no loan
FROM dbo.Customer AS c
LEFT JOIN dbo.Loan AS l
    ON l.CustomerID = c.CustomerID
ORDER BY c.CustomerID, l.LoanID;

SELECT c.CustomerID,
       c.FirstName,
       c.LastName,
       c.JoinedDate
FROM dbo.Customer AS c
LEFT JOIN dbo.Loan AS l
    ON l.CustomerID = c.CustomerID
WHERE l.LoanID IS NULL           -- no matching loan
ORDER BY c.CustomerID;

SELECT c.CustomerID,
       c.LastName,
       COUNT(*)        AS RowsInJoin,   -- counts the NULL row too
       COUNT(l.LoanID) AS Loans         -- counts real loans only
FROM dbo.Customer AS c
LEFT JOIN dbo.Loan AS l
    ON l.CustomerID = c.CustomerID
WHERE c.CustomerID BETWEEN 1 AND 5
GROUP BY c.CustomerID, c.LastName
ORDER BY c.CustomerID;

-- 4. RIGHT OUTER JOIN and FULL OUTER JOIN

SELECT COUNT(*) AS RowsInJoin
FROM dbo.Loan AS l
RIGHT JOIN dbo.Customer AS c          -- keep every customer
    ON l.CustomerID = c.CustomerID;

SELECT CASE
           WHEN c.CustomerID IS NOT NULL
            AND o.OfficerID IS NOT NULL THEN 'Customer and officer'
           WHEN c.CustomerID IS NOT NULL THEN 'Customer only'
           ELSE 'Officer only'
       END      AS PersonType,
       COUNT(*) AS People
FROM dbo.Customer AS c
FULL OUTER JOIN dbo.LoanOfficer AS o
    ON  o.FirstName = c.FirstName     -- condition on two columns
    AND o.LastName  = c.LastName
GROUP BY CASE
             WHEN c.CustomerID IS NOT NULL
              AND o.OfficerID IS NOT NULL THEN 'Customer and officer'
             WHEN c.CustomerID IS NOT NULL THEN 'Customer only'
             ELSE 'Officer only'
         END
ORDER BY PersonType;

-- 5. CROSS JOIN: every combination

SELECT TOP (8)
       b.BranchID,
       b.BranchName,
       p.ProductCode
FROM dbo.Branch AS b
CROSS JOIN dbo.Product AS p       -- 8 branches x 8 products
ORDER BY b.BranchID, p.ProductCode;

SELECT b.BranchName,
       p.ProductCode,
       COUNT(l.LoanID) AS Loans2026
FROM dbo.Branch AS b
CROSS JOIN dbo.Product AS p                 -- the full grid
LEFT JOIN dbo.Loan AS l
    ON  l.BranchID    = b.BranchID          -- same branch
    AND l.ProductCode = p.ProductCode       -- and same product
    AND l.OriginationDate >= '2026-01-01'   -- 2026 loans only
GROUP BY b.BranchID, b.BranchName, p.ProductCode
HAVING COUNT(l.LoanID) = 0                  -- the empty cells
ORDER BY b.BranchID, p.ProductCode;

-- 6. Self-joins and conditions on several columns

SELECT r1.CustomerID,
       r1.CreditScore AS ScoreJan,
       r1.Grade       AS GradeJan,
       r2.CreditScore AS ScoreJul,
       r2.Grade       AS GradeJul,
       r2.CreditScore - r1.CreditScore AS Change
FROM dbo.CreditRating AS r1                       -- earlier rating
JOIN dbo.CreditRating AS r2                       -- next rating
    ON  r2.CustomerID = r1.CustomerID             -- same customer
    AND r2.RatingDate = DATEADD(month, 6, r1.RatingDate)
WHERE r1.RatingDate = '2026-01-01'
  AND r2.CreditScore - r1.CreditScore <= -100
ORDER BY Change, r1.CustomerID;

-- 7. CROSS APPLY and OUTER APPLY

SELECT TOP (5)
       c.CustomerID,
       c.LastName,
       r.RatingDate,
       r.CreditScore,
       r.Grade
FROM dbo.Customer AS c
CROSS APPLY (
    SELECT TOP (1) cr.RatingDate, cr.CreditScore, cr.Grade
    FROM dbo.CreditRating AS cr
    WHERE cr.CustomerID = c.CustomerID   -- this customer only
    ORDER BY cr.RatingDate DESC          -- latest first
) AS r
ORDER BY c.CustomerID;

SELECT c.CustomerID,
       c.LastName,
       x.LoanID,
       x.OriginationDate,
       x.Principal
FROM dbo.Customer AS c
OUTER APPLY (
    SELECT TOP (1) l.LoanID, l.OriginationDate, l.Principal
    FROM dbo.Loan AS l
    WHERE l.CustomerID = c.CustomerID
    ORDER BY l.OriginationDate DESC, l.LoanID DESC
) AS x
WHERE c.CustomerID <= 5
ORDER BY c.CustomerID;


-- Applied example

-- Step 1 — The loans in arrears with contact, product, branch and officer.

SELECT TOP (5)
       l.LoanID,
       c.LastName                            AS Customer,
       c.Phone,
       p.ProductName,
       b.BranchName,
       CONCAT(o.FirstName, ' ', o.LastName)  AS Officer
FROM dbo.Loan AS l
JOIN dbo.Customer    AS c ON c.CustomerID  = l.CustomerID
JOIN dbo.Product     AS p ON p.ProductCode = l.ProductCode
JOIN dbo.Branch      AS b ON b.BranchID    = l.BranchID
JOIN dbo.LoanOfficer AS o ON o.OfficerID   = l.OfficerID
WHERE l.LoanStatus = N'Arrears'
ORDER BY l.OutstandingBalance DESC;

-- Step 2 — Security and missed instalments.

SELECT TOP (5)
       l.LoanID,
       l.ProductCode,
       l.OutstandingBalance,
       k.CollateralType,                   -- NULL for unsecured loans
       COUNT(*) - COUNT(p.PaidDate)    AS Missed,
       SUM(p.AmountDue - p.AmountPaid) AS UnpaidAmount
FROM dbo.Loan AS l
LEFT JOIN dbo.Collateral AS k ON k.LoanID = l.LoanID
JOIN dbo.Payment AS p         ON p.LoanID = l.LoanID
WHERE l.LoanStatus = N'Arrears'
GROUP BY l.LoanID, l.ProductCode, l.OutstandingBalance,
         k.CollateralType
ORDER BY l.OutstandingBalance, l.LoanID;

-- Step 3 — The summary per branch, every branch included.

SELECT b.BranchName,
       COUNT(l.LoanID)                      AS LoansInArrears,
       COUNT(k.CollateralID)                AS Secured,
       ISNULL(SUM(l.OutstandingBalance), 0) AS Outstanding
FROM dbo.Branch AS b
LEFT JOIN dbo.Loan AS l
    ON  l.BranchID   = b.BranchID
    AND l.LoanStatus = N'Arrears'          -- in ON, not in WHERE
LEFT JOIN dbo.Collateral AS k
    ON  k.LoanID = l.LoanID
GROUP BY b.BranchID, b.BranchName
ORDER BY Outstanding DESC;
