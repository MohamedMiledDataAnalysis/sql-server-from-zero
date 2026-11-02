/* SQL Server from Zero — Volume 1
   Chapter 21: Creating tables properly
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- Works on its own: create the schema if the chapter script has not been run.
IF SCHEMA_ID(N'risk') IS NULL
    EXEC (N'CREATE SCHEMA risk AUTHORIZATION dbo;');
GO

-- ------------------------------------------------------------------
-- Correction 21.1
-- ------------------------------------------------------------------
DROP TABLE IF EXISTS risk.ProductLimit;

CREATE TABLE risk.ProductLimit
(
    ProductCode     VARCHAR(10)    NOT NULL
        CONSTRAINT PK_ProductLimit PRIMARY KEY      -- one row per product
        CONSTRAINT FK_ProductLimit_Product
            REFERENCES dbo.Product (ProductCode),   -- must exist
    MaxPrincipal    DECIMAL(12,2)  NOT NULL,         -- same type as Principal
    MinCreditScore  SMALLINT       NOT NULL
        CONSTRAINT CK_ProductLimit_MinCreditScore
            CHECK (MinCreditScore BETWEEN 300 AND 999)
);

SELECT CONSTRAINT_NAME, CONSTRAINT_TYPE
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
WHERE TABLE_SCHEMA = N'risk'
  AND TABLE_NAME = N'ProductLimit'
ORDER BY CONSTRAINT_NAME;
GO


-- ------------------------------------------------------------------
-- Correction 21.2
-- ------------------------------------------------------------------
INSERT INTO risk.ProductLimit
    (ProductCode, MaxPrincipal, MinCreditScore)
SELECT
    l.ProductCode,
    MAX(l.Principal),        -- largest loan on the product
    MIN(c.CreditScore)       -- weakest borrower on the product
FROM dbo.Loan AS l
INNER JOIN dbo.Customer AS c
    ON c.CustomerID = l.CustomerID
GROUP BY l.ProductCode;

SELECT ProductCode, MaxPrincipal, MinCreditScore
FROM risk.ProductLimit
ORDER BY ProductCode;
GO


-- ------------------------------------------------------------------
-- Correction 21.3
-- ------------------------------------------------------------------
-- 1) 'MTG-OFF' is not in dbo.Product: error 547, FK_ProductLimit_Product.
INSERT INTO risk.ProductLimit (ProductCode, MaxPrincipal,
    MinCreditScore)
VALUES ('MTG-OFF', 500000.00, 700);
GO

-- 2) 250 is below 300: error 547, CK_ProductLimit_MinCreditScore.
UPDATE risk.ProductLimit
SET MinCreditScore = 250
WHERE ProductCode = 'PL-STD';
GO

-- 3) NULL into a NOT NULL column: error 515 on MaxPrincipal.
UPDATE risk.ProductLimit
SET MaxPrincipal = NULL
WHERE ProductCode = 'PL-STD';
GO

-- Proof that nothing changed.
SELECT ProductCode, MaxPrincipal, MinCreditScore
FROM risk.ProductLimit
WHERE ProductCode = 'PL-STD';
GO


-- ------------------------------------------------------------------
-- Correction 21.4
-- ------------------------------------------------------------------
DROP TABLE IF EXISTS risk.RatingOverride;

CREATE TABLE risk.RatingOverride
(
    OverrideID     INT            NOT NULL IDENTITY(500, 5)
        CONSTRAINT PK_RatingOverride PRIMARY KEY,
    CustomerID     INT            NOT NULL
        CONSTRAINT FK_RatingOverride_Customer
            REFERENCES dbo.Customer (CustomerID),
    OverrideGrade  CHAR(1)        NOT NULL
        CONSTRAINT CK_RatingOverride_Grade
            CHECK (OverrideGrade IN ('A', 'B', 'C', 'D', 'E')),
    Comment        NVARCHAR(200)  NULL              -- optional
);
GO

-- Run these two statements together (same scope).
INSERT INTO risk.RatingOverride (CustomerID, OverrideGrade, Comment)
VALUES
    (9,   'E', N'Mortgage in default'),
    (54,  'E', N'Mortgage in default'),
    (433, 'D', N'Tracker mortgage in arrears');

SELECT SCOPE_IDENTITY() AS LastOverrideID;

SELECT OverrideID, CustomerID, OverrideGrade, Comment
FROM risk.RatingOverride
ORDER BY OverrideID;
GO


-- ------------------------------------------------------------------
-- Correction 21.5
-- ------------------------------------------------------------------
DROP TABLE IF EXISTS risk.OfficerDesk;

CREATE TABLE risk.OfficerDesk
(
    OfficerID  INT          NOT NULL
        CONSTRAINT PK_OfficerDesk PRIMARY KEY
        CONSTRAINT FK_OfficerDesk_LoanOfficer
            REFERENCES dbo.LoanOfficer (OfficerID),
    DeskPhone  VARCHAR(20)  NULL
        CONSTRAINT UQ_OfficerDesk_DeskPhone UNIQUE
);

GO

-- Fails: the second NULL is a duplicate of the first.
INSERT INTO risk.OfficerDesk (OfficerID, DeskPhone)
VALUES (101, NULL), (102, NULL);
GO

-- Works: only one NULL remains.
INSERT INTO risk.OfficerDesk (OfficerID, DeskPhone)
VALUES (101, '020 7946 0101'), (102, NULL);

SELECT OfficerID, DeskPhone
FROM risk.OfficerDesk
ORDER BY OfficerID;
GO


-- ------------------------------------------------------------------
-- Correction 21.6
-- ------------------------------------------------------------------
DROP TABLE IF EXISTS risk.Affordability;

CREATE TABLE risk.Affordability
(
    LoanID              INT            NOT NULL
        CONSTRAINT PK_Affordability PRIMARY KEY
        CONSTRAINT FK_Affordability_Loan
            REFERENCES dbo.Loan (LoanID),
    MonthlyPayment      DECIMAL(12,2)  NOT NULL,
    AnnualIncome        DECIMAL(12,2)  NOT NULL
        CONSTRAINT CK_Affordability_Income
            CHECK (AnnualIncome > 0),          -- avoids division by 0
    MonthlyIncome       AS CAST(AnnualIncome / 12 AS DECIMAL(12,2)),
    PaymentToIncomePct  AS CAST(MonthlyPayment * 1200 / AnnualIncome
                                AS DECIMAL(6,2)) PERSISTED
);

INSERT INTO risk.Affordability
    (LoanID, MonthlyPayment, AnnualIncome)
SELECT TOP (5)
    l.LoanID, l.MonthlyPayment, c.AnnualIncome
FROM dbo.Loan AS l
INNER JOIN dbo.Customer AS c
    ON c.CustomerID = l.CustomerID
ORDER BY l.MonthlyPayment DESC, l.LoanID;

SELECT LoanID, MonthlyPayment, AnnualIncome,
       MonthlyIncome, PaymentToIncomePct
FROM risk.Affordability
ORDER BY PaymentToIncomePct DESC;
GO


-- ------------------------------------------------------------------
-- Correction 21.7
-- ------------------------------------------------------------------
DROP TABLE IF EXISTS risk.CollateralReviewDoc, risk.CollateralReview;

CREATE TABLE risk.CollateralReview
(
    ReviewID      INT            NOT NULL IDENTITY(1, 1)
        CONSTRAINT PK_CollateralReview PRIMARY KEY,
    CollateralID  INT            NOT NULL
        CONSTRAINT FK_CollateralReview_Collateral
            REFERENCES dbo.Collateral (CollateralID)   -- NO ACTION
        CONSTRAINT UQ_CollateralReview_CollateralID UNIQUE,
    ReviewDate    DATE           NOT NULL,
    RevisedValue  DECIMAL(12,2)  NOT NULL
        CONSTRAINT CK_CollateralReview_RevisedValue
            CHECK (RevisedValue >= 0)
);

CREATE TABLE risk.CollateralReviewDoc
(
    DocID     INT            NOT NULL IDENTITY(1, 1)
        CONSTRAINT PK_CollateralReviewDoc PRIMARY KEY,
    ReviewID  INT            NOT NULL
        CONSTRAINT FK_CollateralReviewDoc_CollateralReview
            REFERENCES risk.CollateralReview (ReviewID)
            ON DELETE CASCADE,                        -- docs follow
    FileName  NVARCHAR(100)  NOT NULL
);

INSERT INTO risk.CollateralReview
    (CollateralID, ReviewDate, RevisedValue)
VALUES (1, '2026-09-30', 250000.00),
       (2, '2026-09-30', 228000.00);

INSERT INTO risk.CollateralReviewDoc (ReviewID, FileName)
VALUES (1, N'valuation_report.pdf'),
       (1, N'site_photos.zip'),
       (2, N'lease_valuation.pdf');

DELETE FROM risk.CollateralReview
WHERE ReviewID = 1;

SELECT ReviewID, CollateralID, RevisedValue
FROM risk.CollateralReview
ORDER BY ReviewID;

SELECT DocID, ReviewID, FileName
FROM risk.CollateralReviewDoc
ORDER BY DocID;
GO


-- ------------------------------------------------------------------
-- Correction 21.8
-- ------------------------------------------------------------------
DROP TABLE IF EXISTS risk.ArrearsCase;

CREATE TABLE risk.ArrearsCase
(
    ArrearsCaseID      INT            NOT NULL IDENTITY(1, 1)
        CONSTRAINT PK_ArrearsCase PRIMARY KEY,
    LoanID             INT            NOT NULL
        CONSTRAINT FK_ArrearsCase_Loan REFERENCES dbo.Loan (LoanID)
        CONSTRAINT UQ_ArrearsCase_LoanID UNIQUE,
    BranchID           INT            NOT NULL
        CONSTRAINT FK_ArrearsCase_Branch
            REFERENCES dbo.Branch (BranchID),
    Balance            DECIMAL(12,2)  NOT NULL
        CONSTRAINT CK_ArrearsCase_Balance CHECK (Balance >= 0),
    MissedInstalments  TINYINT        NOT NULL
        CONSTRAINT CK_ArrearsCase_Missed
            CHECK (MissedInstalments BETWEEN 2 AND 5),
    FirstMissedDate    DATE           NOT NULL,
    SnapshotDate       DATE           NOT NULL
        CONSTRAINT DF_ArrearsCase_SnapshotDate DEFAULT ('2026-09-30'),
    DaysSinceFirstMiss AS DATEDIFF(DAY, FirstMissedDate, SnapshotDate)
                       PERSISTED,                  -- deterministic
    CONSTRAINT CK_ArrearsCase_Dates
        CHECK (FirstMissedDate <= SnapshotDate)
);

INSERT INTO risk.ArrearsCase
    (LoanID, BranchID, Balance, MissedInstalments, FirstMissedDate)
SELECT
    l.LoanID,
    l.BranchID,
    l.OutstandingBalance,
    COUNT(*),                  -- rows kept by WHERE = missed ones
    MIN(p.DueDate)             -- earliest missed due date
FROM dbo.Loan AS l
INNER JOIN dbo.Payment AS p
    ON p.LoanID = l.LoanID
WHERE l.LoanStatus = N'Arrears'
  AND p.PaidDate IS NULL       -- NULL PaidDate = missed instalment
GROUP BY l.LoanID, l.BranchID, l.OutstandingBalance
ORDER BY l.LoanID;

SELECT
    b.BranchName,
    COUNT(*)                  AS Cases,
    SUM(a.Balance)            AS Balance,
    MAX(a.DaysSinceFirstMiss) AS LongestDays
FROM risk.ArrearsCase AS a
INNER JOIN dbo.Branch AS b
    ON b.BranchID = a.BranchID
GROUP BY b.BranchID, b.BranchName
ORDER BY b.BranchID;
GO

