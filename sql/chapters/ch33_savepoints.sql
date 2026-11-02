/* SQL Server from Zero — Volume 2
   Chapter 33: SAVE TRANSACTION, @@TRANCOUNT and nested transactions
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022).
   Every change to a base table is rolled back or reversed: the script leaves the
   dataset as loaded. Errors raised on purpose, each in its own batch and followed
   by a guarded ROLLBACK: 3902 and 3903 (section 2), 6401 (section 3), 266 twice
   (section 5). */
USE NorthbridgeLending;
GO

-- Start clean: no transaction open, no object left by an earlier run.
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
SET IMPLICIT_TRANSACTIONS OFF;
DROP PROCEDURE IF EXISTS dbo.usp_PostInstalment;
DROP PROCEDURE IF EXISTS dbo.usp_Bad_LeaveOpen;
DROP PROCEDURE IF EXISTS dbo.usp_Bad_RollbackAll;
DROP TABLE IF EXISTS dbo.PostingLog;
GO

-- ============================================================
-- 1. Nested BEGIN TRANSACTION: a counter, not a second transaction
-- ============================================================
BEGIN TRANSACTION;                               -- outer
PRINT CONCAT(N'After outer BEGIN: ', @@TRANCOUNT);

UPDATE dbo.Loan
SET LoanStatus = N'Default'
WHERE LoanID = 10196;                            -- was Arrears

BEGIN TRANSACTION;                               -- inner
PRINT CONCAT(N'After inner BEGIN: ', @@TRANCOUNT);

UPDATE dbo.Payment
SET PaidDate = '2026-09-30', AmountPaid = AmountDue, DaysLate = 119
WHERE PaymentID = 4474;

COMMIT TRANSACTION;                              -- inner COMMIT
PRINT CONCAT(N'After inner COMMIT: ', @@TRANCOUNT);

ROLLBACK TRANSACTION;                            -- outer ROLLBACK
PRINT CONCAT(N'After ROLLBACK: ', @@TRANCOUNT);

SELECT l.LoanID, l.LoanStatus, p.PaymentID, p.PaidDate
FROM dbo.Loan AS l
INNER JOIN dbo.Payment AS p
    ON p.LoanID = l.LoanID
WHERE p.PaymentID = 4474;
GO

-- ============================================================
-- 2. Any ROLLBACK undoes everything: errors 3902 and 3903
-- ============================================================
-- Fails on purpose with Msg 3902 at the last line.
BEGIN TRANSACTION;                               -- outer
UPDATE dbo.Loan
SET LoanStatus = N'Default'
WHERE LoanID = 10196;

BEGIN TRANSACTION;                               -- inner
UPDATE dbo.Payment
SET PaidDate = '2026-09-30', AmountPaid = AmountDue, DaysLate = 119
WHERE PaymentID = 4474;

ROLLBACK TRANSACTION;                            -- for the inner
PRINT CONCAT(N'After ROLLBACK: ', @@TRANCOUNT);

COMMIT TRANSACTION;                              -- for the outer
GO
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO
-- Fails on purpose with Msg 3903: no transaction is open.
ROLLBACK TRANSACTION;
GO
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO

-- ============================================================
-- 3. Names in nested transactions: error 6401
-- ============================================================
-- Fails on purpose with Msg 6401: only the outermost name is registered.
BEGIN TRANSACTION OuterPosting;
UPDATE dbo.Loan
SET LoanStatus = N'Default'
WHERE LoanID = 10196;

BEGIN TRANSACTION InnerPosting;
UPDATE dbo.Payment
SET PaidDate = '2026-09-30', AmountPaid = AmountDue, DaysLate = 119
WHERE PaymentID = 4474;

ROLLBACK TRANSACTION InnerPosting;               -- not registered
PRINT CONCAT(N'Open transactions: ', @@TRANCOUNT);
GO
ROLLBACK TRANSACTION OuterPosting;               -- registered name
PRINT CONCAT(N'Open transactions: ', @@TRANCOUNT);
GO
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO

-- ============================================================
-- 4. SAVE TRANSACTION: undoing part of a transaction
-- ============================================================
BEGIN TRANSACTION;

UPDATE dbo.Loan
SET OutstandingBalance = OutstandingBalance - 776.21
WHERE LoanID = 10183;                            -- adjustment 1

SAVE TRANSACTION AfterLoan10183;                 -- the savepoint

UPDATE dbo.Loan
SET OutstandingBalance = OutstandingBalance - 403.64
WHERE LoanID = 10322;                            -- adjustment 2

ROLLBACK TRANSACTION AfterLoan10183;             -- undo adjustment 2
PRINT CONCAT(N'Open transactions: ', @@TRANCOUNT);

SELECT LoanID, OutstandingBalance
FROM dbo.Loan
WHERE LoanID IN (10183, 10322)
ORDER BY LoanID;
GO
ROLLBACK TRANSACTION;

SELECT LoanID, OutstandingBalance
FROM dbo.Loan
WHERE LoanID IN (10183, 10322)
ORDER BY LoanID;
GO

-- ============================================================
-- 5. Procedures and @@TRANCOUNT: error 266
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.usp_Bad_LeaveOpen
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRANSACTION;
    UPDATE dbo.Loan
    SET LoanStatus = N'Default'
    WHERE LoanID = 10196;
    -- no COMMIT: the transaction leaves with the procedure
END;
GO

-- Fails on purpose with Msg 266 (Previous count = 0, current count = 1).
EXEC dbo.usp_Bad_LeaveOpen;
PRINT CONCAT(N'Open transactions: ', @@TRANCOUNT);
GO
IF @@TRANCOUNT > 0
    ROLLBACK TRANSACTION;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Bad_RollbackAll
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRANSACTION;
    UPDATE dbo.Loan
    SET LoanStatus = N'Default'
    WHERE LoanID = 10430;
    ROLLBACK TRANSACTION;                -- undoes the caller's too
END;
GO

-- Fails on purpose with Msg 266 (Previous count = 1, current count = 0).
BEGIN TRANSACTION;                       -- the caller's transaction
UPDATE dbo.Loan
SET LoanStatus = N'Default'
WHERE LoanID = 10196;

EXEC dbo.usp_Bad_RollbackAll;
PRINT CONCAT(N'Open transactions: ', @@TRANCOUNT);

SELECT LoanID, LoanStatus
FROM dbo.Loan
WHERE LoanID = 10196;
GO
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO

-- ============================================================
-- 6. A procedure that works with or without its caller's transaction
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.usp_PostInstalment
    @LoanID    INT,
    @PaymentID INT,
    @Amount    DECIMAL(12,2),
    @PaidDate  DATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @TranCount INT = @@TRANCOUNT;  -- 0: called alone
    DECLARE @PayRows INT, @LoanRows INT;

    IF @TranCount = 0
        BEGIN TRANSACTION;                 -- my own transaction
    ELSE
        SAVE TRANSACTION PostInstalment;   -- a point in the caller's

    UPDATE dbo.Payment
    SET PaidDate   = @PaidDate,
        AmountPaid = @Amount,
        DaysLate   = DATEDIFF(day, DueDate, @PaidDate)
    WHERE PaymentID = @PaymentID
      AND LoanID    = @LoanID
      AND PaidDate IS NULL
      AND AmountDue = @Amount;
    SET @PayRows = @@ROWCOUNT;

    UPDATE dbo.Loan
    SET OutstandingBalance = OutstandingBalance - @Amount
    WHERE LoanID = @LoanID;
    SET @LoanRows = @@ROWCOUNT;

    IF @PayRows = 1 AND @LoanRows = 1
    BEGIN
        IF @TranCount = 0
            COMMIT TRANSACTION;            -- only what I began
        RETURN 0;
    END;

    IF @TranCount = 0
        ROLLBACK TRANSACTION;              -- all of my transaction
    ELSE
        ROLLBACK TRANSACTION PostInstalment;   -- my part only
    PRINT CONCAT(N'Refused: payment ', @PaymentID, N' of loan ',
                 @LoanID, N' is not unpaid at ', @Amount, N'.');
    RETURN 1;
END;
GO
-- Test 1: called alone, with the wrong instalment of loan 10430
DECLARE @rc INT;

EXEC @rc = dbo.usp_PostInstalment
    @LoanID = 10430, @PaymentID = 9528,
    @Amount = 784.33, @PaidDate = '2026-09-30';

PRINT CONCAT(N'Return code: ', @rc,
             N'; open transactions: ', @@TRANCOUNT);
GO
-- Test 2: called twice inside the caller's transaction
DECLARE @rc1 INT, @rc2 INT;

BEGIN TRANSACTION;

EXEC @rc1 = dbo.usp_PostInstalment
    @LoanID = 10196, @PaymentID = 4474,
    @Amount = 517.14, @PaidDate = '2026-09-30';

EXEC @rc2 = dbo.usp_PostInstalment
    @LoanID = 10430, @PaymentID = 9528,
    @Amount = 784.33, @PaidDate = '2026-09-30';

PRINT CONCAT(N'Return codes: ', @rc1, N' and ', @rc2,
             N'; open transactions: ', @@TRANCOUNT);

SELECT LoanID, OutstandingBalance
FROM dbo.Loan
WHERE LoanID IN (10196, 10430)
ORDER BY LoanID;

ROLLBACK TRANSACTION;                    -- a test: undo it all
GO

-- ============================================================
-- 7. XACT_STATE(): can the transaction still be committed?
-- ============================================================
PRINT CONCAT(N'None: XACT_STATE ', XACT_STATE(),
             N', @@TRANCOUNT ', @@TRANCOUNT);

BEGIN TRANSACTION;
BEGIN TRANSACTION;
PRINT CONCAT(N'Two BEGINs: XACT_STATE ', XACT_STATE(),
             N', @@TRANCOUNT ', @@TRANCOUNT);

ROLLBACK TRANSACTION;
PRINT CONCAT(N'After ROLLBACK: XACT_STATE ', XACT_STATE(),
             N', @@TRANCOUNT ', @@TRANCOUNT);
GO

-- ============================================================
-- Applied example
-- ============================================================

-- ============================================================
-- Step 1. Create the posting log.
-- ============================================================
DROP TABLE IF EXISTS dbo.PostingLog;

CREATE TABLE dbo.PostingLog (
    LogID      INT IDENTITY(1,1) NOT NULL
               CONSTRAINT PK_PostingLog PRIMARY KEY,
    LoanID     INT           NOT NULL,
    PaymentID  INT           NOT NULL,
    Amount     DECIMAL(12,2) NOT NULL,
    ReturnCode INT           NOT NULL      -- 0 posted, 1 refused
);
GO

-- ============================================================
-- Step 2. Run the batch.
-- ============================================================
SET NOCOUNT ON;
DECLARE @rc INT;

BEGIN TRANSACTION CardiffBatch;

EXEC @rc = dbo.usp_PostInstalment 10183, 4246, 776.21, '2026-09-30';
INSERT INTO dbo.PostingLog (LoanID, PaymentID, Amount, ReturnCode)
VALUES (10183, 4246, 776.21, @rc);

EXEC @rc = dbo.usp_PostInstalment 10207, 4719, 577.04, '2026-09-30';
INSERT INTO dbo.PostingLog (LoanID, PaymentID, Amount, ReturnCode)
VALUES (10207, 4719, 577.04, @rc);

EXEC @rc = dbo.usp_PostInstalment 10269, 6028, 2483.62, '2026-09-30';
INSERT INTO dbo.PostingLog (LoanID, PaymentID, Amount, ReturnCode)
VALUES (10269, 6028, 2483.62, @rc);

EXEC @rc = dbo.usp_PostInstalment 10322, 7113, 403.64, '2026-09-30';
INSERT INTO dbo.PostingLog (LoanID, PaymentID, Amount, ReturnCode)
VALUES (10322, 7113, 403.64, @rc);

PRINT CONCAT(N'Open transactions before COMMIT: ', @@TRANCOUNT);

COMMIT TRANSACTION CardiffBatch;
SET NOCOUNT OFF;
GO

-- ============================================================
-- Step 3. Prove the result.
-- ============================================================
SELECT g.LogID, g.LoanID, g.Amount, g.ReturnCode,
       l.OutstandingBalance
FROM dbo.PostingLog AS g
INNER JOIN dbo.Loan AS l
    ON l.LoanID = g.LoanID
ORDER BY g.LogID;
GO

-- ============================================================
-- Step 4. Reverse the batch.
-- ============================================================
DECLARE @PayRows INT, @LoanRows INT;

BEGIN TRANSACTION;

UPDATE p
SET PaidDate = NULL, AmountPaid = 0.00, DaysLate = NULL
FROM dbo.Payment AS p
INNER JOIN dbo.PostingLog AS g
    ON g.PaymentID = p.PaymentID
WHERE g.ReturnCode = 0;
SET @PayRows = @@ROWCOUNT;

UPDATE l
SET OutstandingBalance = l.OutstandingBalance + g.Amount
FROM dbo.Loan AS l
INNER JOIN dbo.PostingLog AS g
    ON g.LoanID = l.LoanID
WHERE g.ReturnCode = 0;
SET @LoanRows = @@ROWCOUNT;

IF @PayRows = 3 AND @LoanRows = 3
    COMMIT TRANSACTION;
ELSE
    ROLLBACK TRANSACTION;

SELECT COUNT(*) - COUNT(PaidDate) AS MissedInstalments
FROM dbo.Payment;

SELECT SUM(OutstandingBalance) AS TotalOutstanding
FROM dbo.Loan;
GO

-- ============================================================
-- Step 5. Remove the objects of the chapter.
-- ============================================================
DROP PROCEDURE IF EXISTS dbo.usp_PostInstalment;
DROP PROCEDURE IF EXISTS dbo.usp_Bad_LeaveOpen;
DROP PROCEDURE IF EXISTS dbo.usp_Bad_RollbackAll;
DROP TABLE IF EXISTS dbo.PostingLog;
GO

-- ============================================================
-- Clean-up: no transaction may stay open. The base tables are as loaded.
-- ============================================================
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO
