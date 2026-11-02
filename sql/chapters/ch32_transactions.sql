/* SQL Server from Zero — Volume 2
   Chapter 32: BEGIN TRANSACTION, COMMIT and ROLLBACK
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022).
   Every change to a base table is rolled back or reversed by a compensating
   transaction: the script leaves the dataset exactly as the setup scripts loaded it.
   Two errors are raised on purpose, each in its own batch: 8115 (section 1)
   and 547 (section 6). */
USE NorthbridgeLending;
GO

-- Start clean: no transaction left open, autocommit mode, no temporary table.
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
SET IMPLICIT_TRANSACTIONS OFF;
DROP TABLE IF EXISTS #Postings;
GO

-- ============================================================
-- 1. What a transaction is, and autocommit mode
-- ============================================================
SELECT @@TRANCOUNT AS OpenTransactions;
GO
-- Fails on purpose with Msg 8115: loan 10445 overflows DECIMAL(12,2).
-- Autocommit undoes every row the statement had already changed.
UPDATE dbo.Loan
SET OutstandingBalance = OutstandingBalance * 30000
WHERE LoanStatus = N'Arrears';
GO
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO
SELECT COUNT(*)                AS ArrearsLoans,
       SUM(OutstandingBalance) AS ArrearsBalance
FROM dbo.Loan
WHERE LoanStatus = N'Arrears';
GO

-- ============================================================
-- 2. BEGIN TRANSACTION and COMMIT
-- ============================================================
BEGIN TRANSACTION;

UPDATE dbo.Payment
SET PaidDate   = '2026-09-30',
    AmountPaid = AmountDue,
    DaysLate   = DATEDIFF(day, DueDate, '2026-09-30')
WHERE PaymentID = 4474
  AND PaidDate IS NULL;                  -- only if still unpaid

UPDATE dbo.Loan
SET OutstandingBalance = OutstandingBalance - 517.14
WHERE LoanID = 10196;

SELECT @@TRANCOUNT AS OpenTransactions;
GO
-- The transaction is still open: check before committing.
SELECT p.PaymentID, p.PaidDate, p.AmountPaid, p.DaysLate,
       l.OutstandingBalance
FROM dbo.Payment AS p
INNER JOIN dbo.Loan AS l
    ON l.LoanID = p.LoanID
WHERE p.PaymentID = 4474;
GO
COMMIT TRANSACTION;

SELECT @@TRANCOUNT AS OpenTransactions;
GO
-- COMMIT is final: reverse the posting with a compensating transaction.
BEGIN TRANSACTION;

UPDATE dbo.Payment
SET PaidDate   = NULL,
    AmountPaid = 0.00,
    DaysLate   = NULL
WHERE PaymentID = 4474;

UPDATE dbo.Loan
SET OutstandingBalance = OutstandingBalance + 517.14
WHERE LoanID = 10196;

COMMIT TRANSACTION;

SELECT p.PaymentID, p.PaidDate, p.AmountPaid, p.DaysLate,
       l.OutstandingBalance
FROM dbo.Payment AS p
INNER JOIN dbo.Loan AS l
    ON l.LoanID = p.LoanID
WHERE p.PaymentID = 4474;
GO

-- ============================================================
-- 3. ROLLBACK: changing real tables safely
-- ============================================================
BEGIN TRANSACTION;

UPDATE dbo.Customer
SET City = N'London';                    -- no WHERE: every customer

SELECT COUNT(*) AS LondonCustomers
FROM dbo.Customer
WHERE City = N'London';
GO
ROLLBACK TRANSACTION;

SELECT COUNT(*) AS LondonCustomers
FROM dbo.Customer
WHERE City = N'London';
GO
-- The SELECT-check-then-COMMIT habit: change, check and decide in one batch.
DECLARE @Changed INT;

BEGIN TRANSACTION;

UPDATE dbo.Customer
SET Phone = '07700 900123'
WHERE LastName = N'Edwards';             -- wrong filter: a surname

SET @Changed = @@ROWCOUNT;               -- capture at once

IF @Changed = 1
BEGIN
    COMMIT TRANSACTION;
    PRINT N'Committed: one customer updated.';
END
ELSE
BEGIN
    ROLLBACK TRANSACTION;
    PRINT CONCAT(N'Rolled back: ', @Changed,
                 N' customers matched instead of 1.');
END;
GO

-- ============================================================
-- 4. Named transactions, WITH MARK, and WORK
-- ============================================================
BEGIN TRANSACTION TrackerRise
    WITH MARK 'Tracker rate +0.25, September 2026';

UPDATE dbo.Loan
SET InterestRate = InterestRate + 0.25
WHERE ProductCode = 'MTG-TRK'
  AND LoanStatus = N'Active';

SELECT TOP (3) LoanID, InterestRate
FROM dbo.Loan
WHERE ProductCode = 'MTG-TRK'
  AND LoanStatus = N'Active'
ORDER BY LoanID;
GO
ROLLBACK TRANSACTION TrackerRise;

SELECT TOP (3) LoanID, InterestRate
FROM dbo.Loan
WHERE ProductCode = 'MTG-TRK'
  AND LoanStatus = N'Active'
ORDER BY LoanID;
GO

-- ============================================================
-- 5. SET IMPLICIT_TRANSACTIONS
-- ============================================================
SET IMPLICIT_TRANSACTIONS ON;

SELECT COUNT(*) AS Branches
FROM dbo.Branch;                         -- reads a table

SELECT @@TRANCOUNT AS OpenTransactions;

COMMIT TRANSACTION;                      -- closes the implicit one

SET IMPLICIT_TRANSACTIONS OFF;
GO

-- ============================================================
-- 6. What an error does and does not undo
-- ============================================================
-- Fails on purpose with Msg 547 (loan 99999 does not exist); the batch
-- continues and the transaction stays open.
BEGIN TRANSACTION;

UPDATE dbo.Payment                       -- succeeds
SET PaidDate   = '2026-09-30',
    AmountPaid = AmountDue,
    DaysLate   = DATEDIFF(day, DueDate, '2026-09-30')
WHERE PaymentID = 4474
  AND PaidDate IS NULL;

INSERT INTO dbo.Payment                  -- fails: loan 99999
    (PaymentID, LoanID, InstalmentNumber, DueDate, AmountDue,
     PaidDate, AmountPaid, DaysLate)
VALUES (18419, 99999, 1, '2026-09-30', 517.14,
        '2026-09-30', 517.14, 0);

UPDATE dbo.Loan                          -- runs anyway
SET OutstandingBalance = OutstandingBalance - 517.14
WHERE LoanID = 10196;

PRINT CONCAT(N'Open transactions: ', @@TRANCOUNT);
GO
SELECT p.PaymentID, p.PaidDate, l.OutstandingBalance
FROM dbo.Payment AS p
INNER JOIN dbo.Loan AS l
    ON l.LoanID = p.LoanID
WHERE p.PaymentID = 4474;

IF @@TRANCOUNT > 0
    ROLLBACK TRANSACTION;

SELECT p.PaymentID, p.PaidDate, l.OutstandingBalance
FROM dbo.Payment AS p
INNER JOIN dbo.Loan AS l
    ON l.LoanID = p.LoanID
WHERE p.PaymentID = 4474;
GO

-- ============================================================
-- 7. Watching open transactions: @@TRANCOUNT, DMVs and DBCC OPENTRAN
-- ============================================================
BEGIN TRANSACTION PostingCheck;

UPDATE dbo.Loan
SET OutstandingBalance = OutstandingBalance - 517.14
WHERE LoanID = 10196;

SELECT at.name              AS TranName,
       at.transaction_type  AS TranType,
       at.transaction_state AS TranState
FROM sys.dm_tran_session_transactions AS st
INNER JOIN sys.dm_tran_active_transactions AS at
    ON at.transaction_id = st.transaction_id
WHERE st.session_id = @@SPID;            -- my session only
GO
-- SPID, LSN, start time and SID differ on every server.
DBCC OPENTRAN;
GO
ROLLBACK TRANSACTION PostingCheck;

DBCC OPENTRAN;
GO

-- ============================================================
-- Applied example
-- ============================================================

-- ============================================================
-- Step 1. Load the file into a temporary table.
-- ============================================================
DROP TABLE IF EXISTS #Postings;

CREATE TABLE #Postings (
    PostingNo INT           NOT NULL PRIMARY KEY,
    LoanID    INT           NOT NULL,
    PaymentID INT           NOT NULL,
    Amount    DECIMAL(12,2) NOT NULL,
    Outcome   NVARCHAR(20)  NULL           -- filled by step 3
);

INSERT INTO #Postings (PostingNo, LoanID, PaymentID, Amount)
VALUES (1, 10183,  4246, 776.21),
       (2, 10322,  7113, 403.64),
       (3, 10430,  9528, 784.33),
       (4, 10794, 18256, 215.92);
GO

-- ============================================================
-- Step 2. SELECT first: what does each posting find?
-- ============================================================
SELECT t.PostingNo, t.LoanID, t.PaymentID, p.AmountDue, p.PaidDate
FROM #Postings AS t
INNER JOIN dbo.Payment AS p
    ON p.PaymentID = t.PaymentID
ORDER BY t.PostingNo;
GO

-- ============================================================
-- Step 3. Post each payment in its own transaction.
-- ============================================================
SET NOCOUNT ON;

DECLARE @No INT = 1, @MaxNo INT, @LoanID INT, @PaymentID INT,
        @Amount DECIMAL(12,2), @PayRows INT, @LoanRows INT;

SELECT @MaxNo = MAX(PostingNo) FROM #Postings;

WHILE @No <= @MaxNo
BEGIN
    SELECT @LoanID = LoanID, @PaymentID = PaymentID, @Amount = Amount
    FROM #Postings
    WHERE PostingNo = @No;

    BEGIN TRANSACTION;

    UPDATE dbo.Payment
    SET PaidDate   = '2026-09-30',
        AmountPaid = @Amount,
        DaysLate   = DATEDIFF(day, DueDate, '2026-09-30')
    WHERE PaymentID = @PaymentID
      AND LoanID    = @LoanID
      AND PaidDate IS NULL                -- still unpaid
      AND AmountDue = @Amount;            -- the expected amount
    SET @PayRows = @@ROWCOUNT;

    UPDATE dbo.Loan
    SET OutstandingBalance = OutstandingBalance - @Amount
    WHERE LoanID = @LoanID;
    SET @LoanRows = @@ROWCOUNT;

    IF @PayRows = 1 AND @LoanRows = 1
    BEGIN
        COMMIT TRANSACTION;
        UPDATE #Postings SET Outcome = N'Committed'
        WHERE PostingNo = @No;
        PRINT CONCAT(N'Posting ', @No, N', loan ', @LoanID,
                     N': committed.');
    END
    ELSE
    BEGIN
        ROLLBACK TRANSACTION;
        UPDATE #Postings SET Outcome = N'Rolled back'
        WHERE PostingNo = @No;
        PRINT CONCAT(N'Posting ', @No, N', loan ', @LoanID,
                     N': rolled back (payment rows ', @PayRows,
                     N', loan rows ', @LoanRows, N').');
    END;

    SET @No = @No + 1;
END;

SET NOCOUNT OFF;
GO

-- ============================================================
-- Step 4. Prove the result.
-- ============================================================
SELECT t.PostingNo, t.Outcome, l.LoanID, l.OutstandingBalance
FROM #Postings AS t
INNER JOIN dbo.Loan AS l
    ON l.LoanID = t.LoanID
ORDER BY t.PostingNo;

SELECT COUNT(*) - COUNT(PaidDate) AS MissedInstalments
FROM dbo.Payment;
GO

-- ============================================================
-- Step 5. Reverse the committed postings with a compensating transaction.
-- ============================================================
DECLARE @PayRows INT, @LoanRows INT;

BEGIN TRANSACTION;

UPDATE p
SET PaidDate = NULL, AmountPaid = 0.00, DaysLate = NULL
FROM dbo.Payment AS p
INNER JOIN #Postings AS t
    ON t.PaymentID = p.PaymentID
WHERE t.Outcome = N'Committed';
SET @PayRows = @@ROWCOUNT;

UPDATE l
SET OutstandingBalance = l.OutstandingBalance + t.Amount
FROM dbo.Loan AS l
INNER JOIN #Postings AS t
    ON t.LoanID = l.LoanID
WHERE t.Outcome = N'Committed';
SET @LoanRows = @@ROWCOUNT;

IF @PayRows = 3 AND @LoanRows = 3
BEGIN
    COMMIT TRANSACTION;
    PRINT N'Reversal committed.';
END
ELSE
BEGIN
    ROLLBACK TRANSACTION;
    PRINT N'Reversal rolled back: counts do not match.';
END;

SELECT COUNT(*) - COUNT(PaidDate) AS MissedInstalments
FROM dbo.Payment;

SELECT SUM(OutstandingBalance) AS TotalOutstanding
FROM dbo.Loan;

DROP TABLE IF EXISTS #Postings;
GO

-- ============================================================
-- Clean-up: no transaction may stay open, and the session returns to
-- autocommit mode. The base tables are as loaded: every change above was
-- rolled back or reversed.
-- ============================================================
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
SET IMPLICIT_TRANSACTIONS OFF;
DROP TABLE IF EXISTS #Postings;
GO
