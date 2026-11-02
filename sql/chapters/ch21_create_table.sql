/* SQL Server from Zero — Volume 1
   Chapter 21: Creating tables properly
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- ------------------------------------------------------------------
-- Before you start
-- ------------------------------------------------------------------
USE NorthbridgeLending;

-- CREATE SCHEMA must be alone in its batch, hence EXEC (chapter 18).
IF SCHEMA_ID(N'risk') IS NULL
    EXEC (N'CREATE SCHEMA risk;');

-- Children first, parents last: a parent cannot be dropped
-- while a foreign key still points at it.
DROP TABLE IF EXISTS risk.CaseNote, risk.ReviewCase,
    risk.LoanWatchlist, risk.ExposureCheck, risk.ReviewTeam,
    risk.BranchExposure, risk.ScoreBand;   -- chapter 22
GO


-- ------------------------------------------------------------------
-- 1. Choosing data types deliberately
-- ------------------------------------------------------------------
SELECT
    MAX(Principal)          AS MaxPrincipal,
    MAX(OutstandingBalance) AS MaxBalance,
    MAX(MonthlyPayment)     AS MaxPayment,
    MAX(TermMonths)         AS MaxTerm,
    MAX(InterestRate)       AS MaxRate,
    MIN(InterestRate)       AS MinRate
FROM dbo.Loan;
GO

CREATE TABLE risk.ScoreBand
(
    Grade                CHAR(1)       NOT NULL,  -- always 1 letter
    MinScore             SMALLINT      NOT NULL,  -- 300 to 999
    MaxScore             SMALLINT      NOT NULL,
    ProbabilityOfDefault DECIMAL(6,4)  NOT NULL,  -- e.g. 0.0280
    BandLabel            NVARCHAR(30)  NOT NULL   -- free text
);
GO


-- ------------------------------------------------------------------
-- 2. NULL and NOT NULL
-- ------------------------------------------------------------------
-- Fails on purpose with Msg 515: BandLabel does not accept NULL.
-- INSERT INTO risk.ScoreBand
--     (Grade, MinScore, MaxScore, ProbabilityOfDefault, BandLabel)
-- VALUES
--     ('F', 200, 299, 0.4000, NULL);
GO


-- ------------------------------------------------------------------
-- 3. PRIMARY KEY and constraint names
-- ------------------------------------------------------------------
DROP TABLE IF EXISTS risk.ScoreBand;

CREATE TABLE risk.ScoreBand
(
    Grade                CHAR(1)       NOT NULL
        CONSTRAINT PK_ScoreBand PRIMARY KEY,  -- column constraint
    MinScore             SMALLINT      NOT NULL,
    MaxScore             SMALLINT      NOT NULL,
    ProbabilityOfDefault DECIMAL(6,4)  NOT NULL,
    BandLabel            NVARCHAR(30)  NOT NULL
);

INSERT INTO risk.ScoreBand
    (Grade, MinScore, MaxScore, ProbabilityOfDefault, BandLabel)
VALUES
    ('A', 850, 999, 0.0040, N'Very low risk'),
    ('B', 750, 849, 0.0110, N'Low risk'),
    ('C', 650, 749, 0.0280, N'Moderate risk'),
    ('D', 550, 649, 0.0750, N'High risk'),
    ('E', 300, 549, 0.1900, N'Very high risk');

-- Fails on purpose with Msg 2627: grade C already exists (PK_ScoreBand).
-- INSERT INTO risk.ScoreBand
--     (Grade, MinScore, MaxScore, ProbabilityOfDefault, BandLabel)
-- VALUES
--     ('C', 600, 700, 0.0300, N'Duplicate grade');
GO

CREATE TABLE risk.BranchExposure
(
    BranchID          INT            NOT NULL,
    MonthEnd          DATE           NOT NULL,
    LoansOutstanding  INT            NOT NULL,
    Exposure          DECIMAL(14,2)  NOT NULL,
    CONSTRAINT PK_BranchExposure
        PRIMARY KEY (BranchID, MonthEnd)  -- table constraint
);
GO


-- ------------------------------------------------------------------
-- 4. UNIQUE and CHECK
-- ------------------------------------------------------------------
CREATE TABLE risk.ReviewTeam
(
    TeamID        INT           NOT NULL
        CONSTRAINT PK_ReviewTeam PRIMARY KEY,
    TeamCode      VARCHAR(10)   NOT NULL
        CONSTRAINT UQ_ReviewTeam_TeamCode UNIQUE,
    TeamName      NVARCHAR(60)  NOT NULL,
    MaxOpenCases  SMALLINT      NOT NULL
        CONSTRAINT CK_ReviewTeam_MaxOpenCases
            CHECK (MaxOpenCases BETWEEN 1 AND 200)
);

INSERT INTO risk.ReviewTeam (TeamID, TeamCode, TeamName, MaxOpenCases)
VALUES
    (1, 'RET', N'Retail Credit Review', 40),
    (2, 'MTG', N'Mortgage Review', 25);

-- Fails on purpose with Msg 2627: team code MTG already exists (UQ_ReviewTeam_TeamCode).
-- INSERT INTO risk.ReviewTeam (TeamID, TeamCode, TeamName, MaxOpenCases)
-- VALUES (3, 'MTG', N'Second mortgage team', 25);

-- Fails on purpose with Msg 547: 500 breaks CK_ReviewTeam_MaxOpenCases.
-- INSERT INTO risk.ReviewTeam (TeamID, TeamCode, TeamName, MaxOpenCases)
-- VALUES (3, 'COLL', N'Collections', 500);
GO


-- ------------------------------------------------------------------
-- 5. DEFAULT
-- ------------------------------------------------------------------
DROP TABLE IF EXISTS risk.ReviewTeam;

CREATE TABLE risk.ReviewTeam
(
    TeamID        INT           NOT NULL
        CONSTRAINT PK_ReviewTeam PRIMARY KEY,
    TeamCode      VARCHAR(10)   NOT NULL
        CONSTRAINT UQ_ReviewTeam_TeamCode UNIQUE,
    TeamName      NVARCHAR(60)  NOT NULL,
    MaxOpenCases  SMALLINT      NOT NULL
        CONSTRAINT DF_ReviewTeam_MaxOpenCases DEFAULT (25)
        CONSTRAINT CK_ReviewTeam_MaxOpenCases
            CHECK (MaxOpenCases BETWEEN 1 AND 200),
    IsActive      BIT           NOT NULL
        CONSTRAINT DF_ReviewTeam_IsActive DEFAULT (1)
);
GO   -- the new table must exist before the INSERTs are compiled

INSERT INTO risk.ReviewTeam (TeamID, TeamCode, TeamName)
VALUES (1, 'RET', N'Retail Credit Review');      -- both omitted

INSERT INTO risk.ReviewTeam
    (TeamID, TeamCode, TeamName, MaxOpenCases, IsActive)
VALUES (2, 'MTG', N'Mortgage Review', 30, DEFAULT);  -- keyword

INSERT INTO risk.ReviewTeam
    (TeamID, TeamCode, TeamName, MaxOpenCases, IsActive)
VALUES (3, 'SME', N'Business Banking Review', DEFAULT, 0);

SELECT TeamID, TeamCode, TeamName, MaxOpenCases, IsActive
FROM risk.ReviewTeam
ORDER BY TeamID;
GO


-- ------------------------------------------------------------------
-- 6. IDENTITY
-- ------------------------------------------------------------------
-- Section 6 version of the team table: TeamID is now an IDENTITY.
DROP TABLE IF EXISTS risk.ReviewTeam;

CREATE TABLE risk.ReviewTeam
(
    TeamID        INT           NOT NULL IDENTITY(1, 1)
        CONSTRAINT PK_ReviewTeam PRIMARY KEY,
    TeamCode      VARCHAR(10)   NOT NULL
        CONSTRAINT UQ_ReviewTeam_TeamCode UNIQUE,
    TeamName      NVARCHAR(60)  NOT NULL,
    MaxOpenCases  SMALLINT      NOT NULL
        CONSTRAINT DF_ReviewTeam_MaxOpenCases DEFAULT (25)
        CONSTRAINT CK_ReviewTeam_MaxOpenCases
            CHECK (MaxOpenCases BETWEEN 1 AND 200),
    IsActive      BIT           NOT NULL
        CONSTRAINT DF_ReviewTeam_IsActive DEFAULT (1)
);
GO

INSERT INTO risk.ReviewTeam (TeamCode, TeamName, MaxOpenCases)
VALUES
    ('RET', N'Retail Credit Review', 40),
    ('MTG', N'Mortgage Review', 25),
    ('SME', N'Business Banking Review', 20);

SELECT SCOPE_IDENTITY() AS LastTeamID;
GO

-- Fails: MTG already exists (error 2627 on UQ_ReviewTeam_TeamCode).
-- Kept active: the failed insert consumes identity value 4.
INSERT INTO risk.ReviewTeam (TeamCode, TeamName)
VALUES ('MTG', N'Second mortgage team');
GO

-- Succeeds.
INSERT INTO risk.ReviewTeam (TeamCode, TeamName, MaxOpenCases)
VALUES ('COLL', N'Collections and Recovery', 60);

SELECT TeamID, TeamCode, TeamName, MaxOpenCases, IsActive
FROM risk.ReviewTeam
ORDER BY TeamID;
GO

SET IDENTITY_INSERT risk.ReviewTeam ON;

INSERT INTO risk.ReviewTeam (TeamID, TeamCode, TeamName, MaxOpenCases)
VALUES (4, 'WOFF', N'Write-off Committee', 10);

SET IDENTITY_INSERT risk.ReviewTeam OFF;

SELECT IDENT_CURRENT(N'risk.ReviewTeam') AS CurrentIdentity;
GO


-- ------------------------------------------------------------------
-- 7. FOREIGN KEY and referential actions
-- ------------------------------------------------------------------
CREATE TABLE risk.ReviewCase
(
    CaseID      INT   NOT NULL IDENTITY(1, 1)
        CONSTRAINT PK_ReviewCase PRIMARY KEY,
    LoanID      INT   NOT NULL
        CONSTRAINT FK_ReviewCase_Loan
            REFERENCES dbo.Loan (LoanID),           -- NO ACTION
    TeamID      INT   NOT NULL
        CONSTRAINT FK_ReviewCase_ReviewTeam
            REFERENCES risk.ReviewTeam (TeamID),    -- NO ACTION
    OpenedDate  DATE  NOT NULL
);

CREATE TABLE risk.CaseNote
(
    NoteID    INT            NOT NULL IDENTITY(1, 1)
        CONSTRAINT PK_CaseNote PRIMARY KEY,
    CaseID    INT            NOT NULL,
    NoteText  NVARCHAR(200)  NOT NULL,
    CONSTRAINT FK_CaseNote_ReviewCase
        FOREIGN KEY (CaseID)
        REFERENCES risk.ReviewCase (CaseID)
        ON DELETE CASCADE                          -- notes follow
);

INSERT INTO risk.ReviewCase (LoanID, TeamID, OpenedDate)
VALUES
    (10041, 2, '2026-09-30'),
    (10086, 3, '2026-09-30'),
    (10002, 1, '2026-09-30'),
    (10445, 2, '2026-09-30');

INSERT INTO risk.CaseNote (CaseID, NoteText)
VALUES
    (1, N'Loan in default; borrower contacted.'),
    (1, N'Valuation of the property requested.'),
    (2, N'Director guarantee under review.'),
    (4, N'Payment plan proposed to the borrower.');
GO

-- Fails on purpose with Msg 547: review cases still reference team MTG.
-- DELETE FROM risk.ReviewTeam
-- WHERE TeamCode = 'MTG';
GO

DELETE FROM risk.ReviewCase
WHERE CaseID = 1;

SELECT NoteID, CaseID, NoteText
FROM risk.CaseNote
ORDER BY NoteID;
GO


-- ------------------------------------------------------------------
-- 8. Computed columns
-- ------------------------------------------------------------------
CREATE TABLE risk.ExposureCheck
(
    LoanID           INT            NOT NULL
        CONSTRAINT PK_ExposureCheck PRIMARY KEY,
    Balance          DECIMAL(12,2)  NOT NULL,
    PD               DECIMAL(6,4)   NOT NULL,
    LGD              DECIMAL(5,4)   NOT NULL,
    ExpectedLoss     AS CAST(Balance * PD * LGD AS DECIMAL(12,2))
                     PERSISTED,
    PDPercent        AS (PD * 100)              -- not persisted
);

INSERT INTO risk.ExposureCheck (LoanID, Balance, PD, LGD)
VALUES
    (10002,   1963.72, 0.1900, 0.4500),
    (10041, 433492.36, 0.0750, 0.2500),
    (10445, 437580.99, 0.1900, 0.2500);

SELECT LoanID, Balance, PD, LGD, ExpectedLoss, PDPercent
FROM risk.ExposureCheck
ORDER BY LoanID;
GO


-- ------------------------------------------------------------------
-- Applied example
-- ------------------------------------------------------------------

-- ------------------------------------------------------------------
-- Applied example, Step 1. Rebuild the team table.
-- ------------------------------------------------------------------
DROP TABLE IF EXISTS risk.CaseNote, risk.ReviewCase,
    risk.LoanWatchlist, risk.ReviewTeam;

CREATE TABLE risk.ReviewTeam
(
    TeamID        INT           NOT NULL IDENTITY(1, 1)
        CONSTRAINT PK_ReviewTeam PRIMARY KEY,
    TeamCode      VARCHAR(10)   NOT NULL
        CONSTRAINT UQ_ReviewTeam_TeamCode UNIQUE,
    TeamName      NVARCHAR(60)  NOT NULL,
    MaxOpenCases  SMALLINT      NOT NULL
        CONSTRAINT DF_ReviewTeam_MaxOpenCases DEFAULT (25)
        CONSTRAINT CK_ReviewTeam_MaxOpenCases
            CHECK (MaxOpenCases BETWEEN 1 AND 200),
    IsActive      BIT           NOT NULL
        CONSTRAINT DF_ReviewTeam_IsActive DEFAULT (1)
);

INSERT INTO risk.ReviewTeam (TeamCode, TeamName, MaxOpenCases)
VALUES
    ('RET',  N'Retail Credit Review',    40),
    ('MTG',  N'Mortgage Review',         25),
    ('SME',  N'Business Banking Review', 20),
    ('WOFF', N'Write-off Committee',     10);
GO


-- ------------------------------------------------------------------
-- Applied example, Step 2. Create the watchlist.
-- ------------------------------------------------------------------
CREATE TABLE risk.LoanWatchlist
(
    WatchlistID       INT            NOT NULL IDENTITY(1000, 1)
        CONSTRAINT PK_LoanWatchlist PRIMARY KEY,
    LoanID            INT            NOT NULL
        CONSTRAINT FK_LoanWatchlist_Loan
            REFERENCES dbo.Loan (LoanID)
        CONSTRAINT UQ_LoanWatchlist_LoanID UNIQUE,
    TeamID            INT            NULL
        CONSTRAINT FK_LoanWatchlist_ReviewTeam
            REFERENCES risk.ReviewTeam (TeamID)
            ON DELETE SET NULL,
    AddedDate         DATE           NOT NULL,
    ReviewDueDate     DATE           NOT NULL,
    RiskLevel         TINYINT        NOT NULL
        CONSTRAINT CK_LoanWatchlist_RiskLevel
            CHECK (RiskLevel BETWEEN 1 AND 5),
    Reason            NVARCHAR(200)  NOT NULL,
    BalanceAtEntry    DECIMAL(12,2)  NOT NULL
        CONSTRAINT CK_LoanWatchlist_Balance
            CHECK (BalanceAtEntry >= 0),
    ProbabilityOfDefault DECIMAL(6,4) NOT NULL
        CONSTRAINT CK_LoanWatchlist_PD
            CHECK (ProbabilityOfDefault > 0
               AND ProbabilityOfDefault < 1),
    LossGivenDefault  DECIMAL(5,4)   NOT NULL
        CONSTRAINT DF_LoanWatchlist_LGD DEFAULT (0.4500)
        CONSTRAINT CK_LoanWatchlist_LGD
            CHECK (LossGivenDefault BETWEEN 0 AND 1),
    ExpectedLoss      AS CAST(BalanceAtEntry * ProbabilityOfDefault
                              * LossGivenDefault AS DECIMAL(12,2))
                      PERSISTED,
    ReviewStatus      NVARCHAR(20)   NOT NULL
        CONSTRAINT DF_LoanWatchlist_ReviewStatus DEFAULT (N'Open')
        CONSTRAINT CK_LoanWatchlist_ReviewStatus
            CHECK (ReviewStatus IN (N'Open', N'In review', N'Closed')),
    CreatedAt         DATETIME2(0)   NOT NULL
        CONSTRAINT DF_LoanWatchlist_CreatedAt DEFAULT (SYSDATETIME()),
    CONSTRAINT CK_LoanWatchlist_Dates
        CHECK (ReviewDueDate >= AddedDate)
);
GO


-- ------------------------------------------------------------------
-- Applied example, Step 3. Load the 48 loans.
-- ------------------------------------------------------------------
DECLARE @AsOfDate DATE = '2026-09-30';

INSERT INTO risk.LoanWatchlist
    (LoanID, TeamID, AddedDate, ReviewDueDate, RiskLevel, Reason,
     BalanceAtEntry, ProbabilityOfDefault, LossGivenDefault)
SELECT
    l.LoanID,
    t.TeamID,
    @AsOfDate,
    DATEADD(DAY,
        CASE WHEN l.LoanStatus = N'Default' THEN 30 ELSE 60 END,
        @AsOfDate),
    CASE WHEN l.LoanStatus = N'Default' THEN 5 ELSE 3 END,
    CONCAT(N'Loan status ', l.LoanStatus, N' at snapshot'),
    l.OutstandingBalance,
    sb.ProbabilityOfDefault,
    CASE WHEN p.IsSecured = 1 THEN 0.2500 ELSE 0.4500 END
FROM dbo.Loan AS l
INNER JOIN dbo.Product AS p
    ON p.ProductCode = l.ProductCode
INNER JOIN dbo.Customer AS c
    ON c.CustomerID = l.CustomerID
INNER JOIN risk.ScoreBand AS sb
    ON c.CreditScore BETWEEN sb.MinScore AND sb.MaxScore
INNER JOIN risk.ReviewTeam AS t
    ON t.TeamCode =
        CASE
            WHEN l.LoanStatus = N'Default'
             AND l.OutstandingBalance >= 400000 THEN 'WOFF'
            WHEN p.ProductType IN (N'Personal', N'Auto') THEN 'RET'
            WHEN p.ProductType = N'Mortgage' THEN 'MTG'
            ELSE 'SME'
        END
WHERE l.LoanStatus IN (N'Arrears', N'Default')
ORDER BY l.LoanID;   -- identity values follow this order
GO


-- ------------------------------------------------------------------
-- Applied example, Step 4. Prove that the table defends itself.
-- ------------------------------------------------------------------
-- Fails on purpose with Msg 547: ReviewDueDate before AddedDate breaks CK_LoanWatchlist_Dates.
-- INSERT INTO risk.LoanWatchlist
--     (LoanID, TeamID, AddedDate, ReviewDueDate, RiskLevel, Reason,
--      BalanceAtEntry, ProbabilityOfDefault)
-- VALUES (10001, 1, '2026-09-30', '2026-09-01', 2, N'Manual entry',
--         5000.00, 0.0280);
GO


-- ------------------------------------------------------------------
-- Applied example, Step 5. Close a team.
-- ------------------------------------------------------------------
DELETE FROM risk.ReviewTeam
WHERE TeamCode = 'WOFF';

SELECT WatchlistID, LoanID, TeamID, BalanceAtEntry
FROM risk.LoanWatchlist
WHERE TeamID IS NULL
ORDER BY WatchlistID;
GO


-- ------------------------------------------------------------------
-- Clean-up (optional). The base tables are never changed by this
-- script; the practice tables can stay or be removed:
-- uncomment to remove everything this chapter created.
-- ------------------------------------------------------------------
-- DROP TABLE IF EXISTS risk.CaseNote, risk.ReviewCase,
--     risk.LoanWatchlist, risk.ExposureCheck, risk.ReviewTeam,
--     risk.BranchExposure, risk.ScoreBand;
-- GO
