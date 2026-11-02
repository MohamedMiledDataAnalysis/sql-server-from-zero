/* SQL Server from Zero — Volume 1
   Chapter 8: Subqueries, CTEs and set operators
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- Solutions to the exercises of chapter 8

-- Correction 08.1

SELECT TOP (5)
       LoanID,
       ProductCode,
       InterestRate
FROM dbo.Loan
WHERE InterestRate > (SELECT AVG(InterestRate) FROM dbo.Loan)
ORDER BY InterestRate DESC, LoanID;

SELECT COUNT(*) AS LoansAboveAvgRate
FROM dbo.Loan
WHERE InterestRate > (SELECT AVG(InterestRate) FROM dbo.Loan);


-- Correction 08.2

SELECT COUNT(*) AS UnsecuredLoans
FROM dbo.Loan
WHERE ProductCode IN (SELECT ProductCode
                      FROM dbo.Product
                      WHERE IsSecured = 0);   -- PL-STD, PL-CONS


-- Correction 08.3

SELECT b.BranchID,
       b.BranchName
FROM dbo.Branch AS b
WHERE NOT EXISTS (SELECT 1
                  FROM dbo.Loan AS l
                  WHERE l.BranchID   = b.BranchID     -- this branch
                    AND l.LoanStatus = N'Arrears')
ORDER BY b.BranchID;


-- Correction 08.4

-- The colleague's query
SELECT COUNT(*) AS Customers
FROM dbo.Customer
WHERE Email NOT IN (SELECT Email FROM dbo.LoanOfficer);

-- The intended question, stated precisely
SELECT COUNT(*) AS CustomersWithOwnEmail
FROM dbo.Customer AS c
WHERE c.Email IS NOT NULL                       -- has an address
  AND NOT EXISTS (SELECT 1
                  FROM dbo.LoanOfficer AS o
                  WHERE o.Email = c.Email);     -- not an officer's


-- Correction 08.5

SELECT t.LoansHeld,
       COUNT(*) AS Borrowers
FROM (SELECT CustomerID,
             COUNT(*) AS LoansHeld          -- per customer
      FROM dbo.Loan
      GROUP BY CustomerID) AS t
GROUP BY t.LoansHeld                        -- per number of loans
ORDER BY t.LoansHeld;


-- Correction 08.6

WITH OfficerBook AS
(
    SELECT OfficerID,
           SUM(OutstandingBalance) AS Outstanding
    FROM dbo.Loan
    WHERE LoanStatus <> N'Repaid'
    GROUP BY OfficerID
)
SELECT ob.OfficerID,
       o.LastName,
       ob.Outstanding
FROM OfficerBook AS ob
JOIN dbo.LoanOfficer AS o ON o.OfficerID = ob.OfficerID
WHERE ob.Outstanding > 5000000          -- WHERE on the CTE column
ORDER BY ob.Outstanding DESC;


-- Correction 08.7

WITH Schedule AS
(
    SELECT 0                                  AS InstalmentNumber,
           l.OriginationDate                  AS DueDate,
           CAST(0 AS DECIMAL(12,2))           AS Interest,
           CAST(l.Principal AS DECIMAL(12,2)) AS Balance
    FROM dbo.Loan AS l
    WHERE l.LoanID = 10031
    UNION ALL
    SELECT s.InstalmentNumber + 1,
           DATEADD(month, s.InstalmentNumber + 1,
                   l.OriginationDate),
           CAST(ROUND(s.Balance * l.InterestRate / 1200, 2)
                AS DECIMAL(12,2)),
           CAST(s.Balance
                + ROUND(s.Balance * l.InterestRate / 1200, 2)
                - l.MonthlyPayment AS DECIMAL(12,2))
    FROM Schedule AS s
    JOIN dbo.Loan AS l ON l.LoanID = 10031
    WHERE s.InstalmentNumber < 6            -- first six only
)
SELECT InstalmentNumber, DueDate, Interest, Balance
FROM Schedule
WHERE InstalmentNumber >= 1
ORDER BY InstalmentNumber;


-- Correction 08.8

WITH LatestRating AS
(
    SELECT r.CustomerID, r.Grade
    FROM dbo.CreditRating AS r
    WHERE r.RatingDate = (SELECT MAX(x.RatingDate)
                          FROM dbo.CreditRating AS x
                          WHERE x.CustomerID = r.CustomerID)
),
Mismatch AS
(
    SELECT CustomerID FROM dbo.Loan
    WHERE LoanStatus IN (N'Default', N'Written Off')
    EXCEPT
    SELECT CustomerID FROM LatestRating
    WHERE Grade IN ('D', 'E')
)
SELECT m.CustomerID,
       lr.Grade
FROM Mismatch AS m
JOIN LatestRating AS lr ON lr.CustomerID = m.CustomerID
ORDER BY lr.Grade, m.CustomerID;


