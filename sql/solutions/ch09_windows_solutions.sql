/* SQL Server from Zero — Volume 1
   Chapter 09: Window functions
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- Correction 09.1

SELECT
    ProductCode,
    ProductName,
    BaseRate,
    ROW_NUMBER() OVER (ORDER BY BaseRate DESC) AS RateOrder
FROM dbo.Product
ORDER BY RateOrder;                -- the alias is visible here
GO


-- Correction 09.2

SELECT
    ProductCode,
    BaseRate,
    AVG(BaseRate) OVER () AS AvgRate,           -- same on every row
    BaseRate - AVG(BaseRate) OVER () AS DiffFromAvg
FROM dbo.Product
ORDER BY ProductCode;
GO


-- Correction 09.3

SELECT
    BranchID,
    COUNT(*) AS Loans,
    RANK()       OVER (ORDER BY COUNT(*) DESC) AS RankNo,
    DENSE_RANK() OVER (ORDER BY COUNT(*) DESC) AS DenseRankNo
FROM dbo.Loan
GROUP BY BranchID                   -- 8 rows reach the window
ORDER BY DenseRankNo, BranchID;
GO


-- Correction 09.4

WITH Ranked AS
(
    SELECT
        ProductCode,
        LoanID,
        Principal,
        ROW_NUMBER() OVER (PARTITION BY ProductCode
                           ORDER BY Principal DESC,
                                    LoanID ASC) AS RowNum
    FROM dbo.Loan
)
SELECT ProductCode, LoanID, Principal
FROM Ranked
WHERE RowNum = 1                    -- one row per product
ORDER BY ProductCode;
GO


-- Correction 09.5

SELECT
    MONTH(DueDate)  AS DueMonth,
    SUM(AmountPaid) AS MonthPaid,             -- group aggregate
    SUM(SUM(AmountPaid)) OVER (               -- window over groups
        ORDER BY MONTH(DueDate)
        ROWS BETWEEN UNBOUNDED PRECEDING
                 AND CURRENT ROW) AS YtdPaid
FROM dbo.Payment
WHERE DueDate BETWEEN '2026-01-01' AND '2026-08-31'
GROUP BY MONTH(DueDate)
ORDER BY DueMonth;
GO


-- Correction 09.6

WITH Changes AS
(
    SELECT
        RatingDate,
        CreditScore,
        Grade,
        CreditScore - LAG(CreditScore)
            OVER (ORDER BY RatingDate) AS Change,
        LAG(Grade) OVER (ORDER BY RatingDate) AS PrevGrade
    FROM dbo.CreditRating
    WHERE CustomerID = 4             -- all ten ratings
)
SELECT RatingDate, CreditScore, Grade, Change, PrevGrade
FROM Changes
WHERE RatingDate >= '2023-01-01'     -- filter after LAG
ORDER BY RatingDate;
GO


-- Correction 09.7

WITH OfficerTotals AS
(
    SELECT
        BranchID,
        OfficerID,
        COUNT(*)       AS Loans,
        SUM(Principal) AS TotalPrincipal,
        RANK() OVER (PARTITION BY BranchID
                     ORDER BY SUM(Principal) DESC) AS RankNo
    FROM dbo.Loan
    GROUP BY BranchID, OfficerID     -- one row per officer
)
SELECT
    t.BranchID,
    t.OfficerID,
    o.FirstName,
    o.LastName,
    t.Loans,
    t.TotalPrincipal
FROM OfficerTotals AS t
INNER JOIN dbo.LoanOfficer AS o
    ON o.OfficerID = t.OfficerID
WHERE t.RankNo = 1                   -- top officer(s) of each branch
ORDER BY t.BranchID;
GO


-- Correction 09.8

WITH Frames AS
(
    SELECT
        LoanID,
        SUM(AmountPaid) OVER (PARTITION BY LoanID
            ORDER BY InstalmentNumber
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS PaidLast3,
        COUNT(*) OVER (PARTITION BY LoanID
            ORDER BY InstalmentNumber
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS RowsLast3,
        ROW_NUMBER() OVER (PARTITION BY LoanID
            ORDER BY InstalmentNumber DESC) AS RowNum
    FROM dbo.Payment
)
SELECT
    l.LoanStatus,
    COUNT(*) AS FlaggedLoans
FROM Frames AS f
INNER JOIN dbo.Loan AS l
    ON l.LoanID = f.LoanID
WHERE f.RowNum = 1                   -- latest instalment of each loan
  AND f.RowsLast3 = 3                -- three instalments in the frame
  AND f.PaidLast3 = 0                -- all three missed
GROUP BY l.LoanStatus
ORDER BY l.LoanStatus;
GO
