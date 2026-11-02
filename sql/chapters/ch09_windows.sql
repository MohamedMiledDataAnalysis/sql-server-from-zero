/* SQL Server from Zero — Volume 1
   Chapter 09: Window functions
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- 1. The OVER clause: aggregates that keep every row

SELECT TOP (8)
    LoanID,
    BranchID,
    OutstandingBalance,
    COUNT(*) OVER () AS LoansInList,            -- rows in the result
    SUM(OutstandingBalance) OVER () AS TotalArrears
FROM dbo.Loan
WHERE LoanStatus = N'Arrears'
ORDER BY LoanID;
GO


-- Share of each loan in the arrears book (described in the text)
SELECT
    LoanID,
    OutstandingBalance,
    CAST(100.0 * OutstandingBalance
         / SUM(OutstandingBalance) OVER () AS DECIMAL(5,2)) AS SharePct
FROM dbo.Loan
WHERE LoanStatus = N'Arrears'
ORDER BY SharePct DESC;
GO

-- 2. PARTITION BY: one window per group

SELECT TOP (8)
    BranchID,
    LoanID,
    OutstandingBalance,
    COUNT(*) OVER (PARTITION BY BranchID) AS BranchLoans,
    SUM(OutstandingBalance)
        OVER (PARTITION BY BranchID) AS BranchArrears
FROM dbo.Loan
WHERE LoanStatus = N'Arrears'
ORDER BY BranchID, LoanID;
GO


-- 3. ROW_NUMBER, RANK and DENSE_RANK

SELECT TOP (8)
    CustomerID,
    LastName,
    CreditScore,
    ROW_NUMBER() OVER (ORDER BY CreditScore DESC,
                                CustomerID) AS RowNum,
    RANK()       OVER (ORDER BY CreditScore DESC) AS RankNo,
    DENSE_RANK() OVER (ORDER BY CreditScore DESC) AS DenseRankNo
FROM dbo.Customer
ORDER BY CreditScore DESC, CustomerID;
GO


-- Top two customers of each home branch (described in the text;
-- the filter on RowNum needs a CTE, see section 8)
WITH Ranked AS
(
    SELECT
        HomeBranchID,
        CustomerID,
        LastName,
        CreditScore,
        ROW_NUMBER() OVER (PARTITION BY HomeBranchID
                           ORDER BY CreditScore DESC,
                                    CustomerID) AS RowNum
    FROM dbo.Customer
)
SELECT HomeBranchID, CustomerID, LastName, CreditScore, RowNum
FROM Ranked
WHERE RowNum <= 2
ORDER BY HomeBranchID, RowNum;
GO

-- 4. NTILE: splitting rows into equal buckets

WITH Quartiles AS
(
    SELECT
        CustomerID,
        CreditScore,
        NTILE(4) OVER (ORDER BY CreditScore DESC,
                                CustomerID) AS Quartile
    FROM dbo.Customer
)
SELECT
    Quartile,
    COUNT(*)         AS Customers,
    MIN(CreditScore) AS LowestScore,
    MAX(CreditScore) AS HighestScore
FROM Quartiles
GROUP BY Quartile
ORDER BY Quartile;
GO


-- 5. Running totals, moving sums and window frames

WITH Schedule AS
(
    SELECT
        InstalmentNumber,
        DueDate,
        AmountPaid,
        SUM(AmountDue) OVER (ORDER BY InstalmentNumber
            ROWS BETWEEN UNBOUNDED PRECEDING
                     AND CURRENT ROW) AS CumDue,
        SUM(AmountPaid) OVER (ORDER BY InstalmentNumber
            ROWS BETWEEN UNBOUNDED PRECEDING
                     AND CURRENT ROW) AS CumPaid
    FROM dbo.Payment
    WHERE LoanID = 10430
)
SELECT
    InstalmentNumber,
    DueDate,
    AmountPaid,
    CumDue,
    CumPaid,
    CumDue - CumPaid AS Shortfall
FROM Schedule
WHERE InstalmentNumber >= 6       -- display from instalment 6
ORDER BY InstalmentNumber;
GO


-- Moving sum over the last three instalments (described in the text)
WITH Moving AS
(
    SELECT
        InstalmentNumber,
        DueDate,
        AmountPaid,
        SUM(AmountPaid) OVER (ORDER BY InstalmentNumber
            ROWS BETWEEN 2 PRECEDING
                     AND CURRENT ROW) AS PaidLast3
    FROM dbo.Payment
    WHERE LoanID = 10430
)
SELECT InstalmentNumber, DueDate, AmountPaid, PaidLast3
FROM Moving
WHERE InstalmentNumber >= 6
ORDER BY InstalmentNumber;
GO

SELECT
    LoanID,
    OriginationDate,
    Principal,
    SUM(Principal) OVER (ORDER BY OriginationDate)
        AS DefaultFrame,                      -- RANGE by default
    SUM(Principal) OVER (ORDER BY OriginationDate, LoanID
        ROWS BETWEEN UNBOUNDED PRECEDING
                 AND CURRENT ROW) AS RowsFrame
FROM dbo.Loan
WHERE OriginationDate BETWEEN '2021-12-07' AND '2021-12-29'
ORDER BY OriginationDate, LoanID;
GO


-- 6. LAG and LEAD: the previous and the next row

SELECT
    RatingDate,
    CreditScore,
    Grade,
    LAG(CreditScore) OVER (ORDER BY RatingDate) AS PrevScore,
    CreditScore
        - LAG(CreditScore) OVER (ORDER BY RatingDate) AS Change,
    LEAD(RatingDate) OVER (ORDER BY RatingDate) AS NextRating
FROM dbo.CreditRating
WHERE CustomerID = 1
ORDER BY RatingDate;
GO


-- 7. FIRST_VALUE, LAST_VALUE and PERCENT_RANK

SELECT
    RatingDate,
    CreditScore,
    FIRST_VALUE(RatingDate) OVER (ORDER BY RatingDate)
        AS FirstRating,
    LAST_VALUE(RatingDate) OVER (ORDER BY RatingDate)
        AS LastRatingWrong,               -- default frame
    LAST_VALUE(RatingDate) OVER (ORDER BY RatingDate
        ROWS BETWEEN UNBOUNDED PRECEDING
                 AND UNBOUNDED FOLLOWING) AS LastRating
FROM dbo.CreditRating
WHERE CustomerID = 1
ORDER BY RatingDate;
GO

SELECT
    BranchID,
    SUM(Principal) AS TotalPrincipal,
    CAST(PERCENT_RANK() OVER (ORDER BY SUM(Principal))
         AS DECIMAL(5,4)) AS PctRank
FROM dbo.Loan
GROUP BY BranchID
ORDER BY TotalPrincipal;
GO


-- 8. The latest rating of each customer

-- Fails on purpose with Msg 4108: a window function cannot appear in WHERE.
-- SELECT CustomerID, RatingDate, Grade
-- FROM dbo.CreditRating
-- WHERE ROW_NUMBER() OVER (PARTITION BY CustomerID
--                          ORDER BY RatingDate DESC) = 1;
GO

WITH LatestFirst AS
(
    SELECT
        CustomerID,
        RatingDate,
        CreditScore,
        Grade,
        ROW_NUMBER() OVER (PARTITION BY CustomerID
                           ORDER BY RatingDate DESC) AS RowNum
    FROM dbo.CreditRating
)
SELECT TOP (8) CustomerID, RatingDate, CreditScore, Grade
FROM LatestFirst
WHERE RowNum = 1                  -- the most recent rating
ORDER BY CustomerID;
GO


-- Applied example (steps run together as one batch)


-- Step 1. Attach the previous rating to every rating row.

WITH History AS
(
    SELECT
        CustomerID,
        RatingDate,
        CreditScore,
        Grade,
        LAG(CreditScore) OVER (PARTITION BY CustomerID
                               ORDER BY RatingDate) AS PrevScore,
        LAG(Grade) OVER (PARTITION BY CustomerID
                         ORDER BY RatingDate) AS PrevGrade,
        ROW_NUMBER() OVER (PARTITION BY CustomerID
                           ORDER BY RatingDate DESC) AS RowNum
    FROM dbo.CreditRating
)
SELECT TOP (5)
    CustomerID, RatingDate, CreditScore, Grade, PrevScore, PrevGrade
FROM History
WHERE RowNum = 1
ORDER BY CustomerID;


-- Step 2. Classify each movement.

WITH History AS
(
    SELECT
        CustomerID,
        Grade,
        LAG(Grade) OVER (PARTITION BY CustomerID
                         ORDER BY RatingDate) AS PrevGrade,
        ROW_NUMBER() OVER (PARTITION BY CustomerID
                           ORDER BY RatingDate DESC) AS RowNum
    FROM dbo.CreditRating
)
SELECT
    CASE
        WHEN Grade > PrevGrade THEN N'Downgrade'
        WHEN Grade < PrevGrade THEN N'Upgrade'
        ELSE N'Unchanged'
    END AS Movement,
    COUNT(*) AS Customers
FROM History
WHERE RowNum = 1
GROUP BY
    CASE
        WHEN Grade > PrevGrade THEN N'Downgrade'
        WHEN Grade < PrevGrade THEN N'Upgrade'
        ELSE N'Unchanged'
    END
ORDER BY Movement;


-- Step 3. Rank the largest falls in score.

WITH History AS
(
    SELECT
        CustomerID,
        CreditScore,
        LAG(CreditScore) OVER (PARTITION BY CustomerID
                               ORDER BY RatingDate) AS PrevScore,
        ROW_NUMBER() OVER (PARTITION BY CustomerID
                           ORDER BY RatingDate DESC) AS RowNum
    FROM dbo.CreditRating
),
Falls AS
(
    SELECT
        h.CustomerID,
        c.HomeBranchID,
        h.PrevScore,
        h.CreditScore,
        h.CreditScore - h.PrevScore AS Change,
        RANK() OVER (ORDER BY h.CreditScore - h.PrevScore)
            AS FallRank
    FROM History AS h
    INNER JOIN dbo.Customer AS c
        ON c.CustomerID = h.CustomerID
    WHERE h.RowNum = 1
)
SELECT CustomerID, HomeBranchID, PrevScore, CreditScore, Change, FallRank
FROM Falls
WHERE FallRank <= 5
ORDER BY FallRank, CustomerID;

GO
