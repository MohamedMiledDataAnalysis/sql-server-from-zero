/* SQL Server from Zero — Volume 2
   Chapter 34: TRY…CATCH, THROW, RAISERROR and XACT_ABORT
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- Server-level object of this chapter: user-defined message 50341 in
-- sys.messages. Remove a copy left by an earlier run.
IF EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 50341)
    EXEC sys.sp_dropmessage @msgnum = 50341;
GO
DROP PROCEDURE IF EXISTS dbo.usp_PostPayment;
DROP PROCEDURE IF EXISTS dbo.usp_LogError;
DROP TABLE IF EXISTS dbo.ErrorLog;
GO

-- ==============================================================
-- 1. What an error is: number, severity, state and line
-- ==============================================================

-- A statement error without TRY...CATCH: the batch continues
-- (deliberate error 8134)
GO
DECLARE @Loans INT = 0, @Ratio INT;
SET @Ratio = 1000 / @Loans;
PRINT N'The batch continues after error 8134.';
GO

-- The catalogue of messages
SELECT message_id, severity
FROM sys.messages
WHERE message_id IN (208, 547, 2627, 8134)
  AND language_id = 1033            -- us_english
ORDER BY message_id;
GO

-- ==============================================================
-- 2. BEGIN TRY ... END TRY BEGIN CATCH ... END CATCH
-- ==============================================================

-- Average balance in arrears at Manchester Central (none in arrears)
DECLARE @BranchID INT = 2,               -- Manchester Central
        @Loans    INT,
        @Balance  DECIMAL(12,2);

SELECT @Loans   = COUNT(*),
       @Balance = ISNULL(SUM(OutstandingBalance), 0)
FROM dbo.Loan
WHERE BranchID = @BranchID
  AND LoanStatus = N'Arrears';

BEGIN TRY
    PRINT CONCAT(N'Average balance in arrears: ', @Balance / @Loans);
    PRINT N'This line runs only if the division worked.';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'Caught error ', ERROR_NUMBER(), N': ',
                 ERROR_MESSAGE());
END CATCH;

PRINT N'The batch continues after END CATCH.';
GO

-- The six error functions (this batch starts with BEGIN TRY: line 1)
GO
BEGIN TRY
    INSERT INTO dbo.Payment
        (PaymentID, LoanID, InstalmentNumber, DueDate, AmountDue,
         PaidDate, AmountPaid, DaysLate)
    VALUES (1, 10004, 29, '2026-10-17', 678.64,
            '2026-10-15', 678.64, 0);      -- PaymentID 1 exists
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrNumber,
           ERROR_SEVERITY()  AS ErrSeverity,
           ERROR_STATE()     AS ErrState,
           ERROR_PROCEDURE() AS ErrProcedure,
           ERROR_LINE()      AS ErrLine;
    PRINT ERROR_MESSAGE();
END CATCH;
GO

-- Outside a CATCH block the functions return NULL
SELECT ERROR_NUMBER() AS ErrNumber;
GO

-- ==============================================================
-- 3. What TRY...CATCH does not catch
-- ==============================================================

-- Name resolution error at the same level: NOT caught
-- (deliberate error 208)
GO
BEGIN TRY
    SELECT LoanID FROM dbo.LoanArchive;    -- no such table
END TRY
BEGIN CATCH
    PRINT N'Caught: this line is never printed.';
END CATCH;
GO

-- The same error one level lower (dynamic SQL): caught
BEGIN TRY
    EXEC sys.sp_executesql N'SELECT LoanID FROM dbo.LoanArchive;';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'Caught error ', ERROR_NUMBER(), N': ',
                 ERROR_MESSAGE());
END CATCH;
GO

-- ==============================================================
-- 4. THROW: raising and re-raising errors
-- ==============================================================

-- Raise your own error (deliberate error 50001)
GO
DECLARE @LoanID INT = 10950,
        @Msg    NVARCHAR(2048);

IF NOT EXISTS (SELECT 1 FROM dbo.Loan WHERE LoanID = @LoanID)
BEGIN
    SET @Msg = CONCAT(N'Loan ', @LoanID, N' does not exist.');
    THROW 50001, @Msg, 1;
END;

PRINT N'Not printed: THROW ended the batch.';
GO

-- Re-raise the caught error with THROW; (deliberate error 2627)
GO
BEGIN TRY
    INSERT INTO dbo.Payment
        (PaymentID, LoanID, InstalmentNumber, DueDate, AmountDue,
         PaidDate, AmountPaid, DaysLate)
    VALUES (1, 10004, 29, '2026-10-17', 678.64,
            '2026-10-15', 678.64, 0);
END TRY
BEGIN CATCH
    PRINT N'Payment not recorded: the error goes back to the caller.';
    THROW;
END CATCH;
GO

-- ==============================================================
-- 5. RAISERROR: severity, state and substitution
-- ==============================================================

-- Severity 10 is a message; severity 16 is an error that does not
-- stop the batch (deliberate error 50000)
GO
DECLARE @Branch NVARCHAR(60), @Arrears INT;

SELECT @Branch  = b.BranchName,
       @Arrears = COUNT(*)
FROM dbo.Branch AS b
INNER JOIN dbo.Loan AS l
    ON l.BranchID = b.BranchID
WHERE b.BranchID = 3
  AND l.LoanStatus = N'Arrears'
GROUP BY b.BranchName;

RAISERROR (N'Branch %s: %d loans in arrears.', 10, 1,
           @Branch, @Arrears);
RAISERROR (N'%s needs a review this week.', 16, 1, @Branch);
PRINT N'RAISERROR did not stop the batch.';
GO

-- Progress messages sent at once with WITH NOWAIT
DECLARE @Step INT = 1;

WHILE @Step <= 3
BEGIN
    WAITFOR DELAY '00:00:01';              -- one second of "work"
    RAISERROR (N'Step %d of 3 finished.', 0, 1, @Step) WITH NOWAIT;
    SET @Step += 1;
END;
GO

-- ==============================================================
-- 6. sp_addmessage, sys.messages and FORMATMESSAGE
-- ==============================================================

EXEC sys.sp_addmessage
    @msgnum   = 50341,
    @severity = 16,
    @msgtext  = N'Loan %d cannot take a payment: its status is %s.',
    @lang     = 'us_english';

SELECT message_id, language_id, severity, text
FROM sys.messages
WHERE message_id = 50341;
GO

-- FORMATMESSAGE builds the text; RAISERROR raises the stored message
-- (deliberate error 50341)
GO
DECLARE @LoanID INT = 10006,
        @Status NVARCHAR(20);

SELECT @Status = LoanStatus
FROM dbo.Loan
WHERE LoanID = @LoanID;

PRINT FORMATMESSAGE(50341, @LoanID, @Status);
RAISERROR (50341, -1, 1, @LoanID, @Status);
GO

-- FORMATMESSAGE with a text instead of a message number
PRINT FORMATMESSAGE(N'Loan %d: %s instalments missed.', 10002, N'8');
GO

-- ==============================================================
-- 7. SET XACT_ABORT ON
-- ==============================================================

-- XACT_ABORT OFF: the failed INSERT is undone, the UPDATE stays and
-- the transaction stays open (deliberate error 2627)
GO
SET XACT_ABORT OFF;                     -- the default
BEGIN TRANSACTION;

UPDATE dbo.Loan
SET OutstandingBalance = OutstandingBalance - 599.73
WHERE LoanID = 10004;

INSERT INTO dbo.Payment              -- payment 1 again:
SELECT * FROM dbo.Payment WHERE PaymentID = 1;   -- duplicate key

SELECT @@TRANCOUNT AS OpenTransactions,
       OutstandingBalance
FROM dbo.Loan
WHERE LoanID = 10004;

ROLLBACK TRANSACTION;
GO
IF @@TRANCOUNT > 0 ROLLBACK;
GO

-- XACT_ABORT ON: the error ends the batch and rolls back everything
-- (deliberate error 2627)
GO
SET XACT_ABORT ON;
BEGIN TRANSACTION;

UPDATE dbo.Loan
SET OutstandingBalance = OutstandingBalance - 599.73
WHERE LoanID = 10004;

INSERT INTO dbo.Payment              -- payment 1 again
SELECT * FROM dbo.Payment WHERE PaymentID = 1;

PRINT N'Never printed: the batch stopped.';
COMMIT TRANSACTION;
GO
IF @@TRANCOUNT > 0 ROLLBACK;
GO

-- The proof
SELECT @@TRANCOUNT AS OpenTransactions,
       OutstandingBalance
FROM dbo.Loan
WHERE LoanID = 10004;
GO

-- XACT_ABORT ON inside TRY...CATCH: the transaction is doomed
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE dbo.Loan
    SET OutstandingBalance = OutstandingBalance - 599.73
    WHERE LoanID = 10004;

    INSERT INTO dbo.Payment          -- payment 1 again
    SELECT * FROM dbo.Payment WHERE PaymentID = 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    PRINT CONCAT(N'XACT_STATE() in CATCH: ', XACT_STATE());
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    PRINT CONCAT(N'After ROLLBACK: @@TRANCOUNT = ', @@TRANCOUNT);
END CATCH;

SET XACT_ABORT OFF;
GO

-- ==============================================================
-- 8. The error log table and the standard template
-- ==============================================================

DROP TABLE IF EXISTS dbo.ErrorLog;

CREATE TABLE dbo.ErrorLog (
    ErrorLogID     INT IDENTITY(1,1) NOT NULL
                   CONSTRAINT PK_ErrorLog PRIMARY KEY,
    ErrorTime      DATETIME2(0)   NOT NULL
                   CONSTRAINT DF_ErrorLog_Time
                   DEFAULT SYSDATETIME(),
    LoginName      NVARCHAR(128)  NOT NULL
                   CONSTRAINT DF_ErrorLog_Login
                   DEFAULT ORIGINAL_LOGIN(),
    ErrorNumber    INT            NOT NULL,
    ErrorSeverity  INT            NULL,
    ErrorState     INT            NULL,
    ErrorProcedure NVARCHAR(128)  NULL,
    ErrorLine      INT            NULL,
    ErrorMessage   NVARCHAR(4000) NOT NULL
);
GO
CREATE OR ALTER PROCEDURE dbo.usp_LogError
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.ErrorLog
        (ErrorNumber, ErrorSeverity, ErrorState, ErrorProcedure,
         ErrorLine, ErrorMessage)
    VALUES (ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(),
            ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE());
END;
GO
-- Test from a batch (this batch starts with BEGIN TRY: line 1)
GO
BEGIN TRY
    DECLARE @Zero INT = 0;
    SELECT @Zero = 1 / @Zero;
END TRY
BEGIN CATCH
    EXEC dbo.usp_LogError;
END CATCH;

SELECT ErrorLogID, ErrorNumber, ErrorSeverity, ErrorProcedure,
       ErrorLine, ErrorMessage
FROM dbo.ErrorLog;
GO

-- ==============================================================
-- Applied example: dbo.usp_PostPayment
-- ==============================================================

-- Step 1 is a calculation in the book: no code.

-- Step 2. The procedure (the CREATE line is line 1 of its batch)
GO
CREATE OR ALTER PROCEDURE dbo.usp_PostPayment
    @LoanID   INT,
    @Amount   DECIMAL(12,2),
    @PaidDate DATE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Msg NVARCHAR(2048), @Next SMALLINT, @Due DATE;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. Interest first, the rest repays principal (chapter 11)
        UPDATE dbo.Loan
        SET OutstandingBalance = OutstandingBalance
            - (@Amount - ROUND(OutstandingBalance * InterestRate
                               / 1200, 2))
        WHERE LoanID = @LoanID
          AND LoanStatus IN (N'Active', N'Arrears', N'Default');

        IF @@ROWCOUNT = 0
        BEGIN
            SET @Msg = FORMATMESSAGE(
                N'Loan %d is not open for payments.', @LoanID);
            THROW 50001, @Msg, 1;
        END;

        IF EXISTS (SELECT 1 FROM dbo.Loan
                   WHERE LoanID = @LoanID
                     AND OutstandingBalance < 0)
        BEGIN
            SET @Msg = FORMATMESSAGE(
                N'Payment of %s exceeds the balance of loan %d.',
                CONVERT(NVARCHAR(20), @Amount), @LoanID);
            THROW 50002, @Msg, 1;
        END;

        -- 2. Record the payment as the next instalment
        SELECT @Next = MAX(InstalmentNumber) + 1
        FROM dbo.Payment
        WHERE LoanID = @LoanID;

        SELECT @Due = DATEADD(month, @Next, OriginationDate)
        FROM dbo.Loan
        WHERE LoanID = @LoanID;

        INSERT INTO dbo.Payment
            (PaymentID, LoanID, InstalmentNumber, DueDate, AmountDue,
             PaidDate, AmountPaid, DaysLate)
        SELECT (SELECT MAX(PaymentID) + 1 FROM dbo.Payment),
               LoanID, @Next, @Due, MonthlyPayment, @PaidDate,
               @Amount,
               CASE WHEN @PaidDate <= @Due THEN 0
                    ELSE DATEDIFF(day, @Due, @PaidDate) END
        FROM dbo.Loan
        WHERE LoanID = @LoanID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;          -- 1. undo everything
        EXEC dbo.usp_LogError;            -- 2. log, outside the txn
        THROW;                            -- 3. tell the caller
    END CATCH;
END;
GO

-- Step 3. A correct payment
EXEC dbo.usp_PostPayment
    @LoanID   = 10004,
    @Amount   = 678.64,
    @PaidDate = '2026-10-15';

SELECT LoanID, OutstandingBalance
FROM dbo.Loan
WHERE LoanID = 10004;

SELECT PaymentID, InstalmentNumber, DueDate, PaidDate, AmountPaid,
       DaysLate
FROM dbo.Payment
WHERE PaymentID > 18418;
GO

-- Step 4. A payment larger than the balance, handled by the caller
BEGIN TRY
    EXEC dbo.usp_PostPayment
        @LoanID   = 10004,
        @Amount   = 20000.00,
        @PaidDate = '2026-10-20';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'Payment refused. Error ', ERROR_NUMBER(), N': ',
                 ERROR_MESSAGE());
END CATCH;

SELECT l.OutstandingBalance,
       (SELECT COUNT(*) FROM dbo.Payment AS p
        WHERE p.LoanID = l.LoanID) AS Instalments,
       @@TRANCOUNT AS OpenTransactions
FROM dbo.Loan AS l
WHERE l.LoanID = 10004;
GO

-- Step 5. A repaid loan, not handled by the caller
-- (deliberate error 50001)
GO
EXEC dbo.usp_PostPayment
    @LoanID   = 10006,
    @Amount   = 250.00,
    @PaidDate = '2026-10-15';
GO
IF @@TRANCOUNT > 0 ROLLBACK;
GO

-- Step 6. What the log recorded
SELECT ErrorLogID, ErrorNumber, ErrorProcedure, ErrorLine,
       ErrorMessage
FROM dbo.ErrorLog
ORDER BY ErrorLogID;
GO

-- ==============================================================
-- Clean-up: restore the base tables, remove the chapter's objects
-- ==============================================================

DELETE FROM dbo.Payment
WHERE PaymentID > 18418;                 -- the posted instalment

UPDATE dbo.Loan
SET OutstandingBalance = 12728.03        -- value at 30 Sep 2026
WHERE LoanID = 10004;
GO
DROP PROCEDURE IF EXISTS dbo.usp_PostPayment;
DROP PROCEDURE IF EXISTS dbo.usp_LogError;
DROP TABLE IF EXISTS dbo.ErrorLog;
GO
IF EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 50341)
    EXEC sys.sp_dropmessage @msgnum = 50341;
GO
