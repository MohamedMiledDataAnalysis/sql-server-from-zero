/* SQL Server from Zero — Volume 1
   Chapter 10: Variables, PRINT and session settings
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- 1. DECLARE and SET: creating a variable and giving it a value

DECLARE @AsOfDate DATE = '2026-09-30';   -- declared with a value
DECLARE @MinScore SMALLINT;              -- declared, value NULL

SET @MinScore = 850;                     -- value given later

SELECT @AsOfDate AS AsOfDate, @MinScore AS MinScore;
GO

DECLARE @MinScore SMALLINT = 850;

SELECT COUNT(*) AS GradeACustomers
FROM dbo.Customer
WHERE CreditScore >= @MinScore;          -- the variable replaces 850
GO

DECLARE @AsOfDate DATE = '2026-09-30';
GO
/* This batch fails on purpose with Msg 137 (variable not declared).
   Remove the comment markers to see the error.
SELECT @AsOfDate AS AsOfDate;
*/
GO


-- 2. Assigning with SELECT, and its two traps

DECLARE @FirstName NVARCHAR(40),
        @LastName  NVARCHAR(40),
        @Score     SMALLINT;

SELECT @FirstName = FirstName,
       @LastName  = LastName,
       @Score     = CreditScore
FROM dbo.Customer
WHERE CustomerID = 42;                   -- exactly one row

SELECT @FirstName AS FirstName, @LastName AS LastName,
       @Score AS CreditScore;
GO


DECLARE @LastName NVARCHAR(40);

SELECT @LastName = LastName
FROM dbo.Customer
WHERE City = N'London';                  -- many customers match

SELECT @LastName AS SomeLondoner;        -- one of them, unpredictable
GO

DECLARE @LastName NVARCHAR(40);

SELECT TOP (1) @LastName = LastName
FROM dbo.Customer
WHERE City = N'London'
ORDER BY CreditScore DESC, CustomerID;   -- the best score, defined

SELECT @LastName AS BestLondoner;
GO

DECLARE @LastName NVARCHAR(40) = N'Young';   -- from an earlier lookup

SELECT @LastName = LastName
FROM dbo.Customer
WHERE CustomerID = 9999;                 -- no such customer

SELECT @LastName AS LookupResult;
GO

DECLARE @LastName NVARCHAR(40) = N'Young';

SET @LastName = (SELECT LastName
                 FROM dbo.Customer
                 WHERE CustomerID = 9999);

SELECT @LastName AS LookupResult;
GO

DECLARE @LastName NVARCHAR(40);

-- Fails on purpose with Msg 512: the subquery returns several rows.
-- SET @LastName = (SELECT LastName
--                  FROM dbo.Customer
--                  WHERE City = N'London');
GO


-- 3. PRINT: writing messages

DECLARE @Loans INT = 25;

-- Fails on purpose with Msg 245: the text cannot be converted to INT.
-- PRINT 'Loans in arrears: ' + @Loans;
GO

DECLARE @Loans INT = 25;
DECLARE @Balance DECIMAL(12,2) = 2770913.59;
DECLARE @AsOfDate DATE = '2026-09-30';

PRINT 'Loans in arrears: ' + CAST(@Loans AS VARCHAR(10));
PRINT CONCAT('Arrears balance (GBP): ', @Balance);
PRINT CONCAT('As at ', CONVERT(VARCHAR(10), @AsOfDate, 103));
GO


-- 4. Table variables: a table that lives in a batch

DECLARE @Arrears TABLE
(
    LoanID             INT           NOT NULL PRIMARY KEY,
    BranchID           INT           NOT NULL,
    OutstandingBalance DECIMAL(12,2) NOT NULL
);

INSERT INTO @Arrears (LoanID, BranchID, OutstandingBalance)
SELECT LoanID, BranchID, OutstandingBalance
FROM dbo.Loan
WHERE LoanStatus = N'Arrears';

SELECT
    BranchID,
    COUNT(*)                AS Loans,
    SUM(OutstandingBalance) AS Balance
FROM @Arrears                            -- used like a table
GROUP BY BranchID
ORDER BY BranchID;
GO


-- 5. @@ROWCOUNT and SET NOCOUNT

DECLARE @Rows INT;

SELECT LoanID
FROM dbo.Loan
WHERE LoanStatus = N'Default';

PRINT 'Defaulted loans listed.';         -- resets @@ROWCOUNT to 0

SET @Rows = @@ROWCOUNT;
SELECT @Rows AS RowsAfterPrint;
GO

SET NOCOUNT ON;

SELECT LoanID
FROM dbo.Loan
WHERE LoanStatus = N'Default';

PRINT CONCAT('Rows counted: ', @@ROWCOUNT);

SET NOCOUNT OFF;
GO


-- 6. Session settings: USE, ANSI_NULLS and QUOTED_IDENTIFIER

USE NorthbridgeLending;

SELECT DB_NAME() AS CurrentDatabase;
GO

SET ANSI_NULLS OFF;
SELECT COUNT(*) AS NoEmailOff
FROM dbo.Customer
WHERE Email = NULL;

SET ANSI_NULLS ON;
SELECT COUNT(*) AS NoEmailOn
FROM dbo.Customer
WHERE Email = NULL;
GO

SET QUOTED_IDENTIFIER OFF;
GO
SELECT "Northbridge" AS Lender;          -- a string literal
GO
SET QUOTED_IDENTIFIER ON;
GO
/* This statement fails on purpose with Msg 207.
   Remove the comment markers to see the error.
SELECT "Northbridge" AS Lender;          -- a column name
*/
GO


-- 7. Dates and language: DATEFORMAT, LANGUAGE and DATEFIRST

SET DATEFORMAT dmy;
SELECT CAST('03/04/2026' AS DATE) AS ReadAsDmy;

SET DATEFORMAT mdy;
SELECT CAST('03/04/2026' AS DATE) AS ReadAsMdy;
GO

SET DATEFORMAT dmy;
SELECT
    CAST('2026-04-03' AS DATETIME) AS AsDatetime,
    CAST('2026-04-03' AS DATE)     AS AsDate,
    CAST('20260403' AS DATETIME)   AS CompactDatetime;
SET DATEFORMAT mdy;
GO

DECLARE @d DATE = '2026-09-30';

SET LANGUAGE British;
SELECT @@LANGUAGE AS LanguageName,
       DATENAME(month, @d)   AS MonthName,
       DATENAME(weekday, @d) AS DayName;

SET LANGUAGE French;
SELECT @@LANGUAGE AS LanguageName,
       DATENAME(month, @d)   AS MonthName,
       DATENAME(weekday, @d) AS DayName;

SET LANGUAGE us_english;
GO

DECLARE @d DATE = '2026-09-30';          -- a Wednesday

SET DATEFIRST 7;                         -- week starts on Sunday
SELECT @@DATEFIRST AS FirstDay, DATEPART(weekday, @d) AS WeekdayNo;

SET DATEFIRST 1;                         -- week starts on Monday
SELECT @@DATEFIRST AS FirstDay, DATEPART(weekday, @d) AS WeekdayNo;

SET DATEFIRST 7;
GO


-- 8. Temporary tables: a preview of SELECT … INTO #table

DROP TABLE IF EXISTS #DefaultLoans;      -- safe on the first run

SELECT LoanID, CustomerID, ProductCode, OutstandingBalance
INTO #DefaultLoans
FROM dbo.Loan
WHERE LoanStatus = N'Default';
GO

SELECT TOP (5) LoanID, CustomerID, ProductCode, OutstandingBalance
FROM #DefaultLoans                       -- still here after GO
ORDER BY OutstandingBalance DESC;
GO


-- Applied example (steps run together as one batch)


-- Step 1. Parameters and the set of loans.

SET NOCOUNT ON;

DECLARE @AsOfDate DATE = '2026-09-30';               -- change monthly
DECLARE @FromDate DATE = DATEADD(DAY, -90, @AsOfDate);
DECLARE @Loans INT, @Instalments INT,
        @Total DECIMAL(12,2), @Largest DECIMAL(12,2);

DECLARE @Missed TABLE
(
    LoanID            INT           NOT NULL PRIMARY KEY,
    MissedInstalments INT           NOT NULL,
    AmountMissed      DECIMAL(12,2) NOT NULL
);

INSERT INTO @Missed (LoanID, MissedInstalments, AmountMissed)
SELECT LoanID, COUNT(*), SUM(AmountDue)
FROM dbo.Payment
WHERE PaidDate IS NULL                     -- missed instalments
  AND DueDate >  @FromDate                 -- after 2 July 2026
  AND DueDate <= @AsOfDate                 -- up to the snapshot
GROUP BY LoanID;

SET @Loans = @@ROWCOUNT;                   -- read immediately


-- Step 2. The summary.

SELECT @Instalments = SUM(MissedInstalments),
       @Total       = SUM(AmountMissed),
       @Largest     = MAX(AmountMissed)
FROM @Missed;

PRINT CONCAT('Collections note as at ',
             CONVERT(VARCHAR(10), @AsOfDate, 103));
PRINT CONCAT('Due dates from ',
             CONVERT(VARCHAR(10), DATEADD(DAY, 1, @FromDate), 103),
             ' to ', CONVERT(VARCHAR(10), @AsOfDate, 103));
PRINT CONCAT('Loans with a missed instalment: ', @Loans);
PRINT CONCAT('Missed instalments: ', @Instalments);
PRINT CONCAT('Amount missed (GBP): ', @Total);
PRINT CONCAT('Largest shortfall on one loan (GBP): ', @Largest);


-- Step 3. Breakdown by loan status.

SELECT
    l.LoanStatus,
    COUNT(*)            AS Loans,
    SUM(m.AmountMissed) AS AmountMissed
FROM @Missed AS m                          -- alias for the table variable
INNER JOIN dbo.Loan AS l
    ON l.LoanID = m.LoanID
GROUP BY l.LoanStatus
ORDER BY l.LoanStatus;


-- Step 4. The five largest shortfalls.

SELECT TOP (5)
    m.LoanID,
    l.LoanStatus,
    m.MissedInstalments,
    m.AmountMissed
FROM @Missed AS m
INNER JOIN dbo.Loan AS l
    ON l.LoanID = m.LoanID
ORDER BY m.AmountMissed DESC, m.LoanID;

SET NOCOUNT OFF;

GO

-- Clean-up: restore the default session settings
SET NOCOUNT OFF;
SET LANGUAGE us_english;
SET DATEFORMAT mdy;
SET DATEFIRST 7;
DROP TABLE IF EXISTS #DefaultLoans;
GO
