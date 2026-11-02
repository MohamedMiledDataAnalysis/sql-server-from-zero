/* SQL Server from Zero — Volume 1
   Chapter 14: MERGE and OUTPUT
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022).
   Each example ends with GO so that the deliberate errors of the chapter
   stop only their own batch. Run the script statement by statement (F5 on a selection). */
USE NorthbridgeLending;
GO

-- Start clean: remove practice tables left by an earlier run.
DROP TABLE IF EXISTS dbo.Practice_Product;
DROP TABLE IF EXISTS dbo.Practice_ProductFeed;
DROP TABLE IF EXISTS dbo.Practice_Branch;
DROP TABLE IF EXISTS dbo.Practice_BranchFeed;
DROP TABLE IF EXISTS dbo.Practice_Loan;
DROP TABLE IF EXISTS dbo.Practice_Payment;
DROP TABLE IF EXISTS dbo.Practice_PaymentArchive;
DROP TABLE IF EXISTS dbo.Practice_ProductAudit;
DROP TABLE IF EXISTS dbo.Practice_RateAudit;
DROP TABLE IF EXISTS dbo.Practice_MortgageFeed;
DROP TABLE IF EXISTS dbo.Practice_CustomerScore;
DROP TABLE IF EXISTS dbo.Practice_ScoreAudit;
DROP TABLE IF EXISTS dbo.Practice_LoanOfficer;
DROP TABLE IF EXISTS dbo.Practice_Customer;
DROP TABLE IF EXISTS dbo.Practice_Watchlist;
GO

-- ============================================================
-- 1. The upsert problem
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Product;
DROP TABLE IF EXISTS dbo.Practice_ProductFeed;

SELECT * INTO dbo.Practice_Product FROM dbo.Product;   -- target

SELECT *
INTO dbo.Practice_ProductFeed                          -- source
FROM dbo.Product
WHERE 1 = 0;                                           -- no rows

INSERT INTO dbo.Practice_ProductFeed
    (ProductCode, ProductName, ProductType, BaseRate,
     MaxTermMonths, IsSecured)
VALUES
    ('AUTO-NEW', N'New Car Loan', N'Auto',
     6.70, 60, 1),
    ('AUTO-USD', N'Used Car Loan', N'Auto',
     8.45, 48, 1),
    ('MTG-FIX2', N'Fixed-Rate Mortgage 2 Years', N'Mortgage',
     4.89, 360, 1),
    ('MTG-FIX5', N'Fixed-Rate Mortgage 5 Years', N'Mortgage',
     4.49, 360, 1),
    ('MTG-TRK', N'Tracker Mortgage', N'Mortgage',
     5.49, 300, 1),
    ('PL-CONS', N'Debt Consolidation Loan', N'Personal',
     9.40, 84, 0),
    ('PL-STD', N'Personal Loan', N'Personal',
     7.90, 60, 0),
    ('MTG-FIX10', N'Fixed-Rate Mortgage 10 Years', N'Mortgage',
     5.15, 360, 1),
    ('PL-GREEN', N'Green Home Improvement Loan', N'Personal',
     6.95, 84, 0);
GO
SELECT COALESCE(s.ProductCode, t.ProductCode) AS Code,
       t.BaseRate AS CurrentRate,
       s.BaseRate AS FeedRate
FROM dbo.Practice_Product AS t
FULL OUTER JOIN dbo.Practice_ProductFeed AS s
    ON s.ProductCode = t.ProductCode
ORDER BY Code;
GO

-- ============================================================
-- 2. MERGE: WHEN MATCHED and WHEN NOT MATCHED BY TARGET
-- ============================================================
MERGE INTO dbo.Practice_Product AS t
USING dbo.Practice_ProductFeed AS s
    ON t.ProductCode = s.ProductCode       -- match on the key
WHEN MATCHED THEN                          -- in both tables
    UPDATE SET ProductName   = s.ProductName,
               ProductType   = s.ProductType,
               BaseRate      = s.BaseRate,
               MaxTermMonths = s.MaxTermMonths,
               IsSecured     = s.IsSecured
WHEN NOT MATCHED BY TARGET THEN            -- in the source only
    INSERT (ProductCode, ProductName, ProductType, BaseRate,
            MaxTermMonths, IsSecured)
    VALUES (s.ProductCode, s.ProductName, s.ProductType,
            s.BaseRate, s.MaxTermMonths, s.IsSecured);
GO

-- ============================================================
-- 3. Extra conditions: WHEN MATCHED AND …
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Product;
SELECT * INTO dbo.Practice_Product FROM dbo.Product;

MERGE INTO dbo.Practice_Product AS t
USING dbo.Practice_ProductFeed AS s
    ON t.ProductCode = s.ProductCode
WHEN MATCHED AND (t.ProductName   <> s.ProductName
               OR t.ProductType   <> s.ProductType
               OR t.BaseRate      <> s.BaseRate
               OR t.MaxTermMonths <> s.MaxTermMonths
               OR t.IsSecured     <> s.IsSecured) THEN
    UPDATE SET ProductName   = s.ProductName,
               ProductType   = s.ProductType,
               BaseRate      = s.BaseRate,
               MaxTermMonths = s.MaxTermMonths,
               IsSecured     = s.IsSecured
WHEN NOT MATCHED BY TARGET THEN
    INSERT (ProductCode, ProductName, ProductType, BaseRate,
            MaxTermMonths, IsSecured)
    VALUES (s.ProductCode, s.ProductName, s.ProductType,
            s.BaseRate, s.MaxTermMonths, s.IsSecured);
GO

-- ============================================================
-- 4. WHEN NOT MATCHED BY SOURCE
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Product;
SELECT * INTO dbo.Practice_Product FROM dbo.Product;

MERGE INTO dbo.Practice_Product AS t
USING dbo.Practice_ProductFeed AS s
    ON t.ProductCode = s.ProductCode
WHEN MATCHED AND (t.ProductName   <> s.ProductName
               OR t.ProductType   <> s.ProductType
               OR t.BaseRate      <> s.BaseRate
               OR t.MaxTermMonths <> s.MaxTermMonths
               OR t.IsSecured     <> s.IsSecured) THEN
    UPDATE SET ProductName   = s.ProductName,
               ProductType   = s.ProductType,
               BaseRate      = s.BaseRate,
               MaxTermMonths = s.MaxTermMonths,
               IsSecured     = s.IsSecured
WHEN NOT MATCHED BY TARGET THEN
    INSERT (ProductCode, ProductName, ProductType, BaseRate,
            MaxTermMonths, IsSecured)
    VALUES (s.ProductCode, s.ProductName, s.ProductType,
            s.BaseRate, s.MaxTermMonths, s.IsSecured)
WHEN NOT MATCHED BY SOURCE THEN            -- in the target only
    DELETE;
GO

-- ============================================================
-- 5. Known pitfalls of MERGE
-- ============================================================
SELECT ProductCode, COUNT(*) AS Occurrences
FROM dbo.Practice_ProductFeed
GROUP BY ProductCode
HAVING COUNT(*) > 1;                    -- must return no row
GO
MERGE INTO dbo.Practice_Product WITH (HOLDLOCK) AS t
USING dbo.Practice_ProductFeed AS s
    ON t.ProductCode = s.ProductCode
WHEN NOT MATCHED BY TARGET THEN
    INSERT (ProductCode, ProductName, ProductType, BaseRate,
            MaxTermMonths, IsSecured)
    VALUES (s.ProductCode, s.ProductName, s.ProductType,
            s.BaseRate, s.MaxTermMonths, s.IsSecured);
GO

-- ============================================================
-- 6. OUTPUT: seeing the rows a statement changed
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Branch;
SELECT * INTO dbo.Practice_Branch FROM dbo.Branch;

INSERT INTO dbo.Practice_Branch
    (BranchID, BranchName, City, Region, OpenedDate)
OUTPUT inserted.BranchID, inserted.BranchName, inserted.OpenedDate
VALUES
    (9, N'Edinburgh Princes Street', N'Edinburgh', N'Scotland',
     '2026-10-05');
GO
DROP TABLE IF EXISTS dbo.Practice_Loan;
SELECT * INTO dbo.Practice_Loan FROM dbo.Loan;

UPDATE dbo.Practice_Loan
SET InterestRate = InterestRate + 0.25
OUTPUT inserted.LoanID,
       deleted.InterestRate  AS OldRate,      -- before
       inserted.InterestRate AS NewRate       -- after
WHERE LoanID IN (10009, 10045, 10052);
GO
DROP TABLE IF EXISTS dbo.Practice_Payment;
SELECT * INTO dbo.Practice_Payment FROM dbo.Payment;

DELETE FROM dbo.Practice_Payment
OUTPUT deleted.PaymentID, deleted.InstalmentNumber,
       deleted.DueDate, deleted.AmountDue
WHERE LoanID = 10002
  AND PaidDate IS NULL;
GO

-- ============================================================
-- 7. OUTPUT in MERGE: $action
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Product;
SELECT * INTO dbo.Practice_Product FROM dbo.Product;

MERGE INTO dbo.Practice_Product AS t
USING dbo.Practice_ProductFeed AS s
    ON t.ProductCode = s.ProductCode
WHEN MATCHED AND t.BaseRate <> s.BaseRate THEN
    UPDATE SET BaseRate = s.BaseRate
WHEN NOT MATCHED BY TARGET THEN
    INSERT (ProductCode, ProductName, ProductType, BaseRate,
            MaxTermMonths, IsSecured)
    VALUES (s.ProductCode, s.ProductName, s.ProductType,
            s.BaseRate, s.MaxTermMonths, s.IsSecured)
WHEN NOT MATCHED BY SOURCE THEN
    DELETE
OUTPUT $action                                    AS ActionTaken,
       COALESCE(inserted.ProductCode,
                deleted.ProductCode)              AS ProductCode,
       deleted.BaseRate                           AS OldRate,
       inserted.BaseRate                          AS NewRate;
GO

-- ============================================================
-- 8. OUTPUT INTO: keeping an audit trail
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_ProductAudit;

SELECT CAST(N'' AS NVARCHAR(10))    AS ActionTaken,
       CAST('' AS VARCHAR(10))      AS ProductCode,
       CAST(NULL AS DECIMAL(5,2))   AS OldRate,
       CAST(NULL AS DECIMAL(5,2))   AS NewRate,
       CAST(NULL AS DATE)           AS ChangeDate
INTO dbo.Practice_ProductAudit
FROM dbo.Branch
WHERE 1 = 0;                                   -- structure only
GO
DROP TABLE IF EXISTS dbo.Practice_Product;
SELECT * INTO dbo.Practice_Product FROM dbo.Product;

DECLARE @AsOfDate DATE = '2026-09-30';

MERGE INTO dbo.Practice_Product WITH (HOLDLOCK) AS t
USING dbo.Practice_ProductFeed AS s
    ON t.ProductCode = s.ProductCode
WHEN MATCHED AND t.BaseRate <> s.BaseRate THEN
    UPDATE SET BaseRate = s.BaseRate
WHEN NOT MATCHED BY TARGET THEN
    INSERT (ProductCode, ProductName, ProductType, BaseRate,
            MaxTermMonths, IsSecured)
    VALUES (s.ProductCode, s.ProductName, s.ProductType,
            s.BaseRate, s.MaxTermMonths, s.IsSecured)
WHEN NOT MATCHED BY SOURCE THEN
    DELETE
OUTPUT $action,
       COALESCE(inserted.ProductCode, deleted.ProductCode),
       deleted.BaseRate,
       inserted.BaseRate,
       @AsOfDate                     -- same date on every row
INTO dbo.Practice_ProductAudit
     (ActionTaken, ProductCode, OldRate, NewRate, ChangeDate);
GO
SELECT ActionTaken, ProductCode, OldRate, NewRate, ChangeDate
FROM dbo.Practice_ProductAudit
ORDER BY ActionTaken, ProductCode;
GO
DECLARE @Removed TABLE (PaymentID INT, AmountDue DECIMAL(12,2));

DELETE FROM dbo.Practice_Payment
OUTPUT deleted.PaymentID, deleted.AmountDue
INTO @Removed (PaymentID, AmountDue)
WHERE LoanID = 10019
  AND PaidDate IS NULL;

SELECT COUNT(*) AS RowsRemoved, SUM(AmountDue) AS AmountRemoved
FROM @Removed;
GO

-- ============================================================
-- Applied example
-- ============================================================

-- ============================================================
-- Step 1. Build the target as it stood at the review.
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_CustomerScore;

WITH RatingAtReview AS
(
    SELECT CustomerID, CreditScore, Grade, RatingDate,
           ROW_NUMBER() OVER (PARTITION BY CustomerID
                              ORDER BY RatingDate DESC) AS rn
    FROM dbo.CreditRating
    WHERE RatingDate <= '2025-10-01'       -- known at the review
)
SELECT CustomerID, CreditScore, Grade, RatingDate
INTO dbo.Practice_CustomerScore
FROM RatingAtReview
WHERE rn = 1;                   -- latest rating per customer
GO

-- ============================================================
-- Step 2. Create the audit table.
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_ScoreAudit;

SELECT CAST(N'' AS NVARCHAR(10))   AS ActionTaken,
       CAST(0 AS INT)              AS CustomerID,
       CAST(NULL AS SMALLINT)      AS OldScore,
       CAST(NULL AS SMALLINT)      AS NewScore,
       CAST(NULL AS CHAR(1))       AS OldGrade,
       CAST(NULL AS CHAR(1))       AS NewGrade
INTO dbo.Practice_ScoreAudit
FROM dbo.Branch
WHERE 1 = 0;
GO

-- ============================================================
-- Step 3. MERGE with OUTPUT INTO.
-- ============================================================
WITH LatestRating AS
(
    SELECT CustomerID, CreditScore, Grade, RatingDate,
           ROW_NUMBER() OVER (PARTITION BY CustomerID
                              ORDER BY RatingDate DESC) AS rn
    FROM dbo.CreditRating
)
MERGE INTO dbo.Practice_CustomerScore WITH (HOLDLOCK) AS t
USING (SELECT CustomerID, CreditScore, Grade, RatingDate
       FROM LatestRating
       WHERE rn = 1) AS s                  -- one row per customer
    ON t.CustomerID = s.CustomerID
WHEN MATCHED AND t.RatingDate <> s.RatingDate THEN   -- newer rating
    UPDATE SET CreditScore = s.CreditScore,
               Grade       = s.Grade,
               RatingDate  = s.RatingDate
WHEN NOT MATCHED BY TARGET THEN                      -- new customer
    INSERT (CustomerID, CreditScore, Grade, RatingDate)
    VALUES (s.CustomerID, s.CreditScore, s.Grade, s.RatingDate)
OUTPUT $action, s.CustomerID,
       deleted.CreditScore, inserted.CreditScore,
       deleted.Grade, inserted.Grade
INTO dbo.Practice_ScoreAudit
     (ActionTaken, CustomerID, OldScore, NewScore,
      OldGrade, NewGrade);
GO
-- ============================================================
-- Step 4. Report the grade migrations.
-- ============================================================
SELECT CASE
           WHEN NewGrade < OldGrade THEN N'Upgrade'
           WHEN NewGrade > OldGrade THEN N'Downgrade'
           ELSE N'Same grade'
       END      AS Migration,
       COUNT(*) AS Customers
FROM dbo.Practice_ScoreAudit
WHERE ActionTaken = N'UPDATE'
GROUP BY CASE
             WHEN NewGrade < OldGrade THEN N'Upgrade'
             WHEN NewGrade > OldGrade THEN N'Downgrade'
             ELSE N'Same grade'
         END
ORDER BY Migration;
GO

-- ============================================================
-- Step 5. List the five largest score falls.
-- ============================================================
SELECT TOP (5) CustomerID, OldScore, NewScore,
       NewScore - OldScore AS Change,
       OldGrade, NewGrade
FROM dbo.Practice_ScoreAudit
WHERE ActionTaken = N'UPDATE'
ORDER BY Change, CustomerID;
GO

-- ============================================================
-- Clean-up: remove every practice table created in this chapter.
-- The base tables were not changed.
-- ============================================================
DROP TABLE IF EXISTS dbo.Practice_Product;
DROP TABLE IF EXISTS dbo.Practice_ProductFeed;
DROP TABLE IF EXISTS dbo.Practice_Branch;
DROP TABLE IF EXISTS dbo.Practice_BranchFeed;
DROP TABLE IF EXISTS dbo.Practice_Loan;
DROP TABLE IF EXISTS dbo.Practice_Payment;
DROP TABLE IF EXISTS dbo.Practice_PaymentArchive;
DROP TABLE IF EXISTS dbo.Practice_ProductAudit;
DROP TABLE IF EXISTS dbo.Practice_RateAudit;
DROP TABLE IF EXISTS dbo.Practice_MortgageFeed;
DROP TABLE IF EXISTS dbo.Practice_CustomerScore;
DROP TABLE IF EXISTS dbo.Practice_ScoreAudit;
DROP TABLE IF EXISTS dbo.Practice_LoanOfficer;
DROP TABLE IF EXISTS dbo.Practice_Customer;
DROP TABLE IF EXISTS dbo.Practice_Watchlist;
GO
