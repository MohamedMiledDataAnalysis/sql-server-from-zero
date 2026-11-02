/* SQL Server from Zero — Volume 1
   Chapter 07: Joining tables
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- Correction 07.1

SELECT l.LoanID,
       p.ProductName,
       l.OriginationDate,
       l.Principal,
       l.LoanStatus
FROM dbo.Loan AS l
JOIN dbo.Product AS p ON p.ProductCode = l.ProductCode  -- the name
WHERE l.CustomerID = 143
ORDER BY l.OriginationDate;


-- Correction 07.2

SELECT b.BranchName,
       COUNT(*) AS Customers
FROM dbo.Customer AS c
JOIN dbo.Branch AS b ON b.BranchID = c.HomeBranchID
GROUP BY b.BranchName
ORDER BY Customers DESC, b.BranchName;


-- Correction 07.3

SELECT o.OfficerID,
       o.FirstName,
       o.LastName,
       b.BranchName,
       b.Region
FROM dbo.LoanOfficer AS o
JOIN dbo.Branch AS b ON b.BranchID = o.BranchID
WHERE b.Region IN (N'Scotland', N'Wales')   -- filter on the parent
ORDER BY b.BranchName, o.LastName;


-- Correction 07.4

SELECT b.Region,
       COUNT(*)                  AS Loans,
       SUM(l.OutstandingBalance) AS Outstanding
FROM dbo.Loan AS l
JOIN dbo.Branch AS b ON b.BranchID = l.BranchID
WHERE l.LoanStatus = N'Active'
GROUP BY b.Region
ORDER BY Outstanding DESC;


-- Correction 07.5

SELECT c.EmploymentStatus,
       COUNT(*) AS CustomersWithoutLoan
FROM dbo.Customer AS c
LEFT JOIN dbo.Loan AS l ON l.CustomerID = c.CustomerID
WHERE l.LoanID IS NULL               -- no loan found
GROUP BY c.EmploymentStatus
ORDER BY CustomersWithoutLoan DESC;


-- Correction 07.6

-- Step A: the loans with 12 or more missed instalments, with status
SELECT l.LoanID,
       l.LoanStatus,
       COUNT(*) - COUNT(p.PaidDate) AS Missed
FROM dbo.Loan AS l
JOIN dbo.Payment AS p ON p.LoanID = l.LoanID
GROUP BY l.LoanID, l.LoanStatus
HAVING COUNT(*) - COUNT(p.PaidDate) >= 12
ORDER BY Missed DESC, l.LoanID;

-- Step B: how many loans are written off in total?
SELECT COUNT(*) AS WrittenOffLoans
FROM dbo.Loan
WHERE LoanStatus = N'Written Off';


-- Correction 07.7

SELECT p.ProductCode,
       p.ProductName,
       COUNT(l.LoanID) AS Loans2026
FROM dbo.Product AS p
LEFT JOIN dbo.Loan AS l
    ON  l.ProductCode     = p.ProductCode
    AND l.BranchID        = 1               -- London City
    AND l.OriginationDate >= '2026-01-01'   -- 2026 only
GROUP BY p.ProductCode, p.ProductName
ORDER BY p.ProductCode;


-- Correction 07.8

SELECT b.BranchName,
       x.LoanID,
       x.ProductCode,
       x.Principal,
       x.OriginationDate
FROM dbo.Branch AS b
CROSS APPLY (
    SELECT TOP (1) l.LoanID, l.ProductCode,
                   l.Principal, l.OriginationDate
    FROM dbo.Loan AS l
    WHERE l.BranchID = b.BranchID           -- this branch
      AND l.OriginationDate >= '2026-01-01' -- 2026 only
    ORDER BY l.Principal DESC, l.LoanID     -- largest, then lowest ID
) AS x
ORDER BY b.BranchID;

