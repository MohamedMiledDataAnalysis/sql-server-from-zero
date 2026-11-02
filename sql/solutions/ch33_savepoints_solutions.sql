/* SQL Server from Zero — Volume 2
   Chapter 33: SAVE TRANSACTION, @@TRANCOUNT and nested transactions — solutions to the exercises
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022).
   Every change to a base table is rolled back: the dataset stays as loaded.
   Errors raised on purpose, each in its own batch and followed by a guarded
   ROLLBACK: 3902 (correction 33.4) and 266 (correction 33.8). */
USE NorthbridgeLending;
GO

-- Start clean: no transaction open, no procedure left by an earlier run.
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
SET IMPLICIT_TRANSACTIONS OFF;
DROP PROCEDURE IF EXISTS dbo.usp_SetLoanStatus;
DROP PROCEDURE IF EXISTS dbo.usp_WriteOffLoan;
GO

-- ==============================================================
-- Correction 33.1
-- ==============================================================
BEGIN TRANSACTION;
PRINT CONCAT(N'BEGIN: ', @@TRANCOUNT);
BEGIN TRANSACTION;
PRINT CONCAT(N'BEGIN: ', @@TRANCOUNT);
COMMIT TRANSACTION;                      -- inner: counter only
PRINT CONCAT(N'COMMIT: ', @@TRANCOUNT);
COMMIT TRANSACTION;                      -- outer: the real commit
PRINT CONCAT(N'COMMIT: ', @@TRANCOUNT);
GO

-- ==============================================================
-- Correction 33.2
-- ==============================================================
BEGIN TRANSACTION;                       -- outer
BEGIN TRANSACTION;                       -- inner

DELETE FROM dbo.CreditRating
WHERE CustomerID = 1;

COMMIT TRANSACTION;                      -- inner: nothing saved

SELECT COUNT(*) AS RatingsInside
FROM dbo.CreditRating
WHERE CustomerID = 1;

ROLLBACK TRANSACTION;                    -- outer: undoes the DELETE

SELECT COUNT(*) AS RatingsAfter
FROM dbo.CreditRating
WHERE CustomerID = 1;
GO

-- ==============================================================
-- Correction 33.3
-- ==============================================================
BEGIN TRANSACTION;

UPDATE dbo.Customer
SET Phone = '07700 900123'
WHERE CustomerID = 2;

SAVE TRANSACTION AfterCustomer2;

UPDATE dbo.Customer
SET Phone = '07700 900456'
WHERE CustomerID = 9;

ROLLBACK TRANSACTION AfterCustomer2;     -- undoes customer 9 only

SELECT CustomerID, Phone, @@TRANCOUNT AS OpenTransactions
FROM dbo.Customer
WHERE CustomerID IN (2, 9)
ORDER BY CustomerID;

ROLLBACK TRANSACTION;                    -- undoes customer 2
GO

-- ==============================================================
-- Correction 33.4
-- ==============================================================
-- Fails on purpose with Msg 3902 at the last line.
BEGIN TRANSACTION;
PRINT CONCAT(N'BEGIN: ', @@TRANCOUNT);        -- 1
BEGIN TRANSACTION;
PRINT CONCAT(N'BEGIN: ', @@TRANCOUNT);        -- 2
ROLLBACK TRANSACTION;
PRINT CONCAT(N'ROLLBACK: ', @@TRANCOUNT);     -- 0, not 1
COMMIT TRANSACTION;                           -- error 3902
GO
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO
-- The safe last line:
IF @@TRANCOUNT > 0
    COMMIT TRANSACTION;
GO

-- ==============================================================
-- Correction 33.5
-- ==============================================================
BEGIN TRANSACTION;

UPDATE dbo.Loan SET LoanStatus = N'Default' WHERE LoanID = 10183;
SAVE TRANSACTION Step;                   -- first Step

UPDATE dbo.Loan SET LoanStatus = N'Default' WHERE LoanID = 10207;
SAVE TRANSACTION Step;                   -- second Step: most recent

UPDATE dbo.Loan SET LoanStatus = N'Default' WHERE LoanID = 10269;

ROLLBACK TRANSACTION Step;               -- back to the second Step

SELECT LoanID, LoanStatus
FROM dbo.Loan
WHERE LoanID IN (10183, 10207, 10269)
ORDER BY LoanID;

ROLLBACK TRANSACTION;
GO

-- ==============================================================
-- Correction 33.6
-- ==============================================================
PRINT CONCAT(N'1. ', XACT_STATE(), N' / ', @@TRANCOUNT);
BEGIN TRANSACTION;
PRINT CONCAT(N'2. ', XACT_STATE(), N' / ', @@TRANCOUNT);
BEGIN TRANSACTION;
PRINT CONCAT(N'3. ', XACT_STATE(), N' / ', @@TRANCOUNT);
SAVE TRANSACTION S1;
ROLLBACK TRANSACTION S1;                 -- the counter does not move
PRINT CONCAT(N'4. ', XACT_STATE(), N' / ', @@TRANCOUNT);
COMMIT TRANSACTION;
PRINT CONCAT(N'5. ', XACT_STATE(), N' / ', @@TRANCOUNT);
COMMIT TRANSACTION;
PRINT CONCAT(N'6. ', XACT_STATE(), N' / ', @@TRANCOUNT);
GO

-- ==============================================================
-- Correction 33.7
-- ==============================================================
CREATE OR ALTER PROCEDURE dbo.usp_SetLoanStatus
    @LoanID    INT,
    @NewStatus NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @TranCount INT = @@TRANCOUNT;

    IF @TranCount = 0
        BEGIN TRANSACTION;
    ELSE
        SAVE TRANSACTION SetLoanStatus;

    UPDATE dbo.Loan
    SET LoanStatus = @NewStatus
    WHERE LoanID = @LoanID
      AND @NewStatus IN (N'Active', N'Arrears', N'Default',
                         N'Repaid', N'Written Off');

    IF @@ROWCOUNT = 1
    BEGIN
        IF @TranCount = 0
            COMMIT TRANSACTION;
        RETURN 0;
    END;

    IF @TranCount = 0
        ROLLBACK TRANSACTION;
    ELSE
        ROLLBACK TRANSACTION SetLoanStatus;
    RETURN 1;
END;
GO

DECLARE @rc INT;                         -- test 1: alone
EXEC @rc = dbo.usp_SetLoanStatus
    @LoanID = 10207, @NewStatus = N'Closed';
PRINT CONCAT(N'Alone: return code ', @rc,
             N', open transactions ', @@TRANCOUNT);
GO

DECLARE @rc1 INT, @rc2 INT;              -- test 2: nested
BEGIN TRANSACTION;
EXEC @rc1 = dbo.usp_SetLoanStatus
    @LoanID = 10183, @NewStatus = N'Default';
EXEC @rc2 = dbo.usp_SetLoanStatus
    @LoanID = 10207, @NewStatus = N'Closed';
PRINT CONCAT(N'Nested: return codes ', @rc1, N' and ', @rc2,
             N', open transactions ', @@TRANCOUNT);

SELECT LoanID, LoanStatus
FROM dbo.Loan
WHERE LoanID IN (10183, 10207)
ORDER BY LoanID;

ROLLBACK TRANSACTION;
GO

DROP PROCEDURE IF EXISTS dbo.usp_SetLoanStatus;
GO

-- ==============================================================
-- Correction 33.8
-- ==============================================================
-- The faulty procedure, as given in the exercise
CREATE OR ALTER PROCEDURE dbo.usp_WriteOffLoan
    @LoanID INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRANSACTION;
    UPDATE dbo.Loan
    SET LoanStatus = N'Written Off',
        OutstandingBalance = 0.00
    WHERE LoanID = @LoanID
      AND LoanStatus = N'Default';
    IF @@ROWCOUNT <> 1
    BEGIN
        ROLLBACK TRANSACTION;
        RETURN 1;
    END;
    COMMIT TRANSACTION;
    RETURN 0;
END;
GO

-- Fails on purpose with Msg 266 (Previous count = 1, current count = 0).
-- the faulty procedure, as given in the exercise, then:
DECLARE @rc1 INT, @rc2 INT;
BEGIN TRANSACTION;
EXEC @rc1 = dbo.usp_WriteOffLoan @LoanID = 10002;  -- in Default
EXEC @rc2 = dbo.usp_WriteOffLoan @LoanID = 10196;  -- in Arrears
PRINT CONCAT(N'Return codes ', @rc1, N' and ', @rc2,
             N', open transactions ', @@TRANCOUNT);

SELECT LoanID, LoanStatus, OutstandingBalance
FROM dbo.Loan
WHERE LoanID IN (10002, 10196)
ORDER BY LoanID;
GO
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO

-- The corrected procedure
CREATE OR ALTER PROCEDURE dbo.usp_WriteOffLoan
    @LoanID INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @TranCount INT = @@TRANCOUNT;  -- caller's transaction?

    IF @TranCount = 0
        BEGIN TRANSACTION;
    ELSE
        SAVE TRANSACTION WriteOffLoan;     -- my part only

    UPDATE dbo.Loan
    SET LoanStatus = N'Written Off',
        OutstandingBalance = 0.00
    WHERE LoanID = @LoanID
      AND LoanStatus = N'Default';

    IF @@ROWCOUNT = 1
    BEGIN
        IF @TranCount = 0
            COMMIT TRANSACTION;            -- never the caller's
        RETURN 0;
    END;

    IF @TranCount = 0
        ROLLBACK TRANSACTION;
    ELSE
        ROLLBACK TRANSACTION WriteOffLoan;
    RETURN 1;
END;
GO

DECLARE @rc1 INT, @rc2 INT;
BEGIN TRANSACTION;
EXEC @rc1 = dbo.usp_WriteOffLoan @LoanID = 10002;
EXEC @rc2 = dbo.usp_WriteOffLoan @LoanID = 10196;
PRINT CONCAT(N'Return codes ', @rc1, N' and ', @rc2,
             N', open transactions ', @@TRANCOUNT);

SELECT LoanID, LoanStatus, OutstandingBalance
FROM dbo.Loan
WHERE LoanID IN (10002, 10196)
ORDER BY LoanID;

ROLLBACK TRANSACTION;                    -- end of the test
GO

DROP PROCEDURE IF EXISTS dbo.usp_WriteOffLoan;
GO

-- ==============================================================
-- Clean-up: no transaction may stay open. The base tables are as loaded.
-- ==============================================================
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
DROP PROCEDURE IF EXISTS dbo.usp_SetLoanStatus;
DROP PROCEDURE IF EXISTS dbo.usp_WriteOffLoan;
GO
