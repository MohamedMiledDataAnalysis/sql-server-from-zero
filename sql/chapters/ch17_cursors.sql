/* SQL Server from Zero — Volume 1
   Chapter 17: Cursors
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

/* Section 4 creates the practice copy dbo.Practice_Branch; no base table
   is changed. Run the batches one at a time, in order. */

-- 2. Your first cursor
DECLARE @BranchID   INT;
DECLARE @BranchName NVARCHAR(60);
DECLARE @Loans      INT;

DECLARE BranchCursor CURSOR LOCAL FAST_FORWARD
FOR
    SELECT
        b.BranchID,
        b.BranchName,
        COUNT(l.LoanID)
    FROM dbo.Branch AS b
    LEFT JOIN dbo.Loan AS l
        ON l.BranchID = b.BranchID
    GROUP BY b.BranchID, b.BranchName
    ORDER BY b.BranchID;

OPEN BranchCursor;

FETCH NEXT FROM BranchCursor
INTO @BranchID, @BranchName, @Loans;      -- first row

WHILE @@FETCH_STATUS = 0                  -- 0 = a row was fetched
BEGIN
    PRINT CONCAT(@BranchID, N' ', @BranchName, N': ',
                 @Loans, N' loans');

    FETCH NEXT FROM BranchCursor
    INTO @BranchID, @BranchName, @Loans;  -- next row
END;

CLOSE BranchCursor;
DEALLOCATE BranchCursor;
GO

-- 3. The fetch loop and its traps
/* Not run on purpose (see the book): this loop never ends.
-- DO NOT RUN: this loop never ends.
WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT CONCAT(@BranchID, N' ', @BranchName);
END;
*/
-- Fails on purpose with Msg 16924: one variable in INTO for two columns.
-- DECLARE @BranchID INT;
--
-- DECLARE TwoColumns CURSOR LOCAL FAST_FORWARD
-- FOR
--     SELECT BranchID, BranchName
--     FROM dbo.Branch
--     ORDER BY BranchID;
--
-- OPEN TwoColumns;
-- FETCH NEXT FROM TwoColumns INTO @BranchID;   -- 1 variable, 2 columns
-- CLOSE TwoColumns;
-- DEALLOCATE TwoColumns;

-- 4. Cursor options
DROP TABLE IF EXISTS dbo.Practice_Branch;

SELECT *
INTO dbo.Practice_Branch
FROM dbo.Branch;
GO
SET NOCOUNT ON;
DECLARE @BranchID INT, @BranchName NVARCHAR(60);

DECLARE SnapCursor CURSOR LOCAL STATIC READ_ONLY
FOR
    SELECT BranchID, BranchName
    FROM dbo.Practice_Branch
    WHERE BranchID <= 3
    ORDER BY BranchID;

OPEN SnapCursor;                          -- snapshot taken here

UPDATE dbo.Practice_Branch                -- change after OPEN
SET BranchName = N'London Bishopsgate'
WHERE BranchID = 1;

FETCH NEXT FROM SnapCursor INTO @BranchID, @BranchName;
WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT CONCAT(@BranchID, N' ', @BranchName);
    FETCH NEXT FROM SnapCursor INTO @BranchID, @BranchName;
END;

CLOSE SnapCursor;
DEALLOCATE SnapCursor;

SELECT BranchID, BranchName
FROM dbo.Practice_Branch
WHERE BranchID <= 3
ORDER BY BranchID;
GO

-- 5. SCROLL cursors: moving in every direction
DECLARE @Code VARCHAR(10), @Rate DECIMAL(5,2);

DECLARE RateCursor CURSOR LOCAL SCROLL STATIC READ_ONLY
FOR
    SELECT ProductCode, BaseRate
    FROM dbo.Product
    ORDER BY BaseRate DESC;

OPEN RateCursor;

FETCH LAST FROM RateCursor INTO @Code, @Rate;
PRINT CONCAT(N'LAST        : ', @Code, N' ', @Rate);

FETCH PRIOR FROM RateCursor INTO @Code, @Rate;
PRINT CONCAT(N'PRIOR       : ', @Code, N' ', @Rate);

FETCH FIRST FROM RateCursor INTO @Code, @Rate;
PRINT CONCAT(N'FIRST       : ', @Code, N' ', @Rate);

FETCH ABSOLUTE 3 FROM RateCursor INTO @Code, @Rate;
PRINT CONCAT(N'ABSOLUTE 3  : ', @Code, N' ', @Rate);

FETCH RELATIVE 2 FROM RateCursor INTO @Code, @Rate;
PRINT CONCAT(N'RELATIVE 2  : ', @Code, N' ', @Rate);

FETCH ABSOLUTE -2 FROM RateCursor INTO @Code, @Rate;
PRINT CONCAT(N'ABSOLUTE -2 : ', @Code, N' ', @Rate);

FETCH RELATIVE -6 FROM RateCursor INTO @Code, @Rate;
PRINT CONCAT(N'RELATIVE -6 : ', @Code, N' ', @Rate);

FETCH PRIOR FROM RateCursor INTO @Code, @Rate;
PRINT CONCAT(N'PRIOR       : status ', @@FETCH_STATUS);

CLOSE RateCursor;
DEALLOCATE RateCursor;
GO

-- 7. Cursor versus set-based: a timing comparison
SET NOCOUNT ON;   -- hide 800 "(1 row affected)" messages

DECLARE @ByCursor TABLE (
    LoanID INT PRIMARY KEY, Missed INT, MissedAmount DECIMAL(12,2));
DECLARE @BySet TABLE (
    LoanID INT PRIMARY KEY, Missed INT, MissedAmount DECIMAL(12,2));

DECLARE @LoanID INT, @Missed INT, @Amount DECIMAL(12,2);
DECLARE @Start DATETIME2 = SYSDATETIME();

-- Version 1: a cursor, one query per loan.
DECLARE LoanCursor CURSOR LOCAL FAST_FORWARD
FOR
    SELECT LoanID FROM dbo.Loan ORDER BY LoanID;

OPEN LoanCursor;
FETCH NEXT FROM LoanCursor INTO @LoanID;
WHILE @@FETCH_STATUS = 0
BEGIN
    SELECT
        @Missed = COUNT(*),
        @Amount = ISNULL(SUM(AmountDue), 0)
    FROM dbo.Payment
    WHERE LoanID = @LoanID
      AND PaidDate IS NULL;

    INSERT INTO @ByCursor VALUES (@LoanID, @Missed, @Amount);

    FETCH NEXT FROM LoanCursor INTO @LoanID;
END;
CLOSE LoanCursor;
DEALLOCATE LoanCursor;

PRINT CONCAT(N'Cursor    : ',
             DATEDIFF(MILLISECOND, @Start, SYSDATETIME()), N' ms');

-- Version 2: one set-based statement.
SET @Start = SYSDATETIME();

INSERT INTO @BySet (LoanID, Missed, MissedAmount)
SELECT
    l.LoanID,
    COUNT(p.PaymentID),
    ISNULL(SUM(p.AmountDue), 0)
FROM dbo.Loan AS l
LEFT JOIN dbo.Payment AS p
    ON p.LoanID = l.LoanID
   AND p.PaidDate IS NULL
GROUP BY l.LoanID;

PRINT CONCAT(N'Set-based : ',
             DATEDIFF(MILLISECOND, @Start, SYSDATETIME()), N' ms');

-- Same answer?
SELECT
    (SELECT COUNT(*) FROM @ByCursor)                  AS CursorRows,
    (SELECT SUM(MissedAmount) FROM @ByCursor)         AS CursorAmount,
    (SELECT SUM(MissedAmount) FROM @BySet)            AS SetAmount,
    (SELECT COUNT(*)
     FROM (SELECT * FROM @ByCursor
           EXCEPT
           SELECT * FROM @BySet) AS d)               AS Differences;
GO

-- 8. When a cursor is the right tool
SET NOCOUNT ON;

DECLARE @Remaining DECIMAL(12,2) = 1000.00;    -- the recovery
DECLARE @Instalment SMALLINT, @Due DATE;
DECLARE @AmountDue DECIMAL(12,2), @Allocated DECIMAL(12,2);

DECLARE @Allocation TABLE (
    InstalmentNumber SMALLINT,
    DueDate          DATE,
    AmountDue        DECIMAL(12,2),
    Allocated        DECIMAL(12,2),
    LeftToAllocate   DECIMAL(12,2));

DECLARE MissedCursor CURSOR LOCAL FAST_FORWARD
FOR
    SELECT InstalmentNumber, DueDate, AmountDue
    FROM dbo.Payment
    WHERE LoanID = 10002
      AND PaidDate IS NULL
    ORDER BY DueDate;                           -- oldest first

OPEN MissedCursor;
FETCH NEXT FROM MissedCursor INTO @Instalment, @Due, @AmountDue;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Pay the instalment in full, or with what is left.
    SET @Allocated = CASE WHEN @Remaining >= @AmountDue
                          THEN @AmountDue
                          ELSE @Remaining END;
    SET @Remaining = @Remaining - @Allocated;

    INSERT INTO @Allocation
    VALUES (@Instalment, @Due, @AmountDue, @Allocated, @Remaining);

    IF @Remaining = 0
        BREAK;                                  -- money used up

    FETCH NEXT FROM MissedCursor INTO @Instalment, @Due, @AmountDue;
END;

CLOSE MissedCursor;
DEALLOCATE MissedCursor;

SELECT *
FROM @Allocation
ORDER BY DueDate;
GO

-- Applied example, Step 1. Look at the set before writing the loop.
SELECT
    COUNT(*)                AS LoansInArrears,
    SUM(OutstandingBalance) AS TotalOutstanding
FROM dbo.Loan
WHERE LoanStatus = N'Arrears';
GO

-- Applied example, Step 2. Create the log.
DROP TABLE IF EXISTS #NoticeLog;

CREATE TABLE #NoticeLog (
    NoticeNumber INT           NOT NULL,
    LoanID       INT           NOT NULL,
    Missed       INT           NOT NULL,
    MissedAmount DECIMAL(12,2) NOT NULL
);
GO

-- Applied example, Step 3. Run the notice loop.
SET NOCOUNT ON;

DECLARE @LoanID INT, @Balance DECIMAL(12,2);
DECLARE @Missed INT, @Amount DECIMAL(12,2);
DECLARE @Notice INT = 0;                       -- notice counter

DECLARE ArrearsCursor CURSOR LOCAL FAST_FORWARD
FOR
    SELECT LoanID, OutstandingBalance
    FROM dbo.Loan
    WHERE LoanStatus = N'Arrears'
    ORDER BY OutstandingBalance DESC;          -- largest first

OPEN ArrearsCursor;
FETCH NEXT FROM ArrearsCursor INTO @LoanID, @Balance;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @Notice = @Notice + 1;

    SELECT
        @Missed = COUNT(*),
        @Amount = SUM(AmountDue)
    FROM dbo.Payment
    WHERE LoanID = @LoanID
      AND PaidDate IS NULL;

    INSERT INTO #NoticeLog (NoticeNumber, LoanID, Missed, MissedAmount)
    VALUES (@Notice, @LoanID, @Missed, @Amount);

    PRINT CONCAT(N'Notice ', @Notice, N': loan ', @LoanID,
                 N', ', @Missed, N' missed, GBP ', @Amount);

    FETCH NEXT FROM ArrearsCursor INTO @LoanID, @Balance;
END;

CLOSE ArrearsCursor;
DEALLOCATE ArrearsCursor;
GO

-- Applied example, Step 4. Check the log.
SELECT
    COUNT(*)          AS Notices,
    MIN(NoticeNumber) AS FirstNumber,
    MAX(NoticeNumber) AS LastNumber,
    SUM(Missed)       AS MissedInstalments,
    SUM(MissedAmount) AS MissedAmount
FROM #NoticeLog;
GO

-- Applied example, Step 5. Prove the log with a set-based query.
SELECT COUNT(*) AS Differences
FROM (
    SELECT NoticeNumber, LoanID, Missed, MissedAmount
    FROM #NoticeLog
    EXCEPT
    SELECT
        ROW_NUMBER() OVER (ORDER BY l.OutstandingBalance DESC),
        l.LoanID,
        COUNT(*),
        SUM(p.AmountDue)
    FROM dbo.Loan AS l
    INNER JOIN dbo.Payment AS p
        ON p.LoanID = l.LoanID
       AND p.PaidDate IS NULL
    WHERE l.LoanStatus = N'Arrears'
    GROUP BY l.LoanID, l.OutstandingBalance
) AS d;
GO

-- Clean-up: remove the practice copy and the temporary log.
-- The base tables were not changed.
DROP TABLE IF EXISTS dbo.Practice_Branch;
DROP TABLE IF EXISTS #NoticeLog;
GO
