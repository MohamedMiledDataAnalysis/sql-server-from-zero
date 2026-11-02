/* SQL Server from Zero — Volume 2
   Chapter 34: TRY…CATCH, THROW, RAISERROR and XACT_ABORT — solutions to the exercises
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- ==============================================================
-- Exercise setup: the error log of section 8 (for 34.7 and 34.8)
-- ==============================================================

IF EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 50345)
    EXEC sys.sp_dropmessage @msgnum = 50345;
GO
DROP PROCEDURE IF EXISTS dbo.usp_TransferOfficerLoans;
DROP PROCEDURE IF EXISTS dbo.usp_ChangeLoanStatus;
DROP PROCEDURE IF EXISTS dbo.usp_Ex34_CustomerReport;
DROP PROCEDURE IF EXISTS dbo.usp_Ex34_AvgPrincipal;
DROP PROCEDURE IF EXISTS dbo.usp_LogError;
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

-- ==============================================================
-- Correction 34.1
-- ==============================================================
GO
DECLARE @Score INT;

BEGIN TRY
    SET @Score = CAST(N'9O0' AS INT);      -- letter O, not zero
    PRINT CONCAT(N'Score: ', @Score);
END TRY
BEGIN CATCH
    PRINT CONCAT(N'Error ', ERROR_NUMBER(), N': ', ERROR_MESSAGE());
END CATCH;
GO

-- ==============================================================
-- Correction 34.2
-- ==============================================================
GO
DECLARE @Branch NVARCHAR(60), @Arrears INT, @Default INT;

SELECT @Branch  = b.BranchName,
       @Arrears = SUM(CASE WHEN l.LoanStatus = N'Arrears'
                           THEN 1 ELSE 0 END),
       @Default = SUM(CASE WHEN l.LoanStatus = N'Default'
                           THEN 1 ELSE 0 END)
FROM dbo.Branch AS b
INNER JOIN dbo.Loan AS l
    ON l.BranchID = b.BranchID
WHERE b.BranchID = 6
GROUP BY b.BranchName;

RAISERROR (N'%s: %d loans in arrears, %d in default.', 10, 1,
           @Branch, @Arrears, @Default);
GO

-- ==============================================================
-- Correction 34.3
-- ==============================================================
GO
DECLARE @Arrears INT, @Msg NVARCHAR(2048);

SELECT @Arrears = COUNT(*)
FROM dbo.Loan
WHERE BranchID = 2
  AND LoanStatus = N'Arrears';

BEGIN TRY
    IF @Arrears = 0
    BEGIN
        SET @Msg = N'Branch 2 has no loan in arrears.';
        THROW 50010, @Msg, 1;
    END;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()   AS ErrNumber,
           ERROR_SEVERITY() AS ErrSeverity,
           ERROR_STATE()    AS ErrState,
           ERROR_MESSAGE()  AS ErrMessage;
END CATCH;
GO

-- ==============================================================
-- Correction 34.4
-- ==============================================================
GO
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE dbo.Loan
    SET LoanStatus = N'Written Off'
    WHERE LoanID = 10002;

    INSERT INTO dbo.Payment               -- payment 18418 again:
    SELECT * FROM dbo.Payment             -- duplicate key
    WHERE PaymentID = 18418;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;             -- undo the UPDATE
    PRINT CONCAT(N'Rolled back. Error ', ERROR_NUMBER(), N': ',
                 ERROR_MESSAGE());
END CATCH;

SET XACT_ABORT OFF;

SELECT LoanStatus, @@TRANCOUNT AS OpenTransactions
FROM dbo.Loan
WHERE LoanID = 10002;
GO

-- ==============================================================
-- Correction 34.5
-- ==============================================================
GO
IF EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 50345)
    EXEC sys.sp_dropmessage @msgnum = 50345;

EXEC sys.sp_addmessage
    @msgnum   = 50345,
    @severity = 16,
    @msgtext  = N'Officer %s (branch %d) has %d loans in default.',
    @lang     = 'us_english';

DECLARE @Name NVARCHAR(81), @Branch INT, @Defaults INT;

SELECT TOP (1)
       @Name     = CONCAT(o.FirstName, N' ', o.LastName),
       @Branch   = o.BranchID,
       @Defaults = COUNT(*)
FROM dbo.LoanOfficer AS o
INNER JOIN dbo.Loan AS l
    ON l.OfficerID = o.OfficerID
WHERE l.LoanStatus = N'Default'
GROUP BY o.OfficerID, o.FirstName, o.LastName, o.BranchID
ORDER BY COUNT(*) DESC, o.OfficerID;

PRINT FORMATMESSAGE(50345, @Name, @Branch, @Defaults);

SELECT message_id, severity, text
FROM sys.messages
WHERE message_id = 50345;

EXEC sys.sp_dropmessage @msgnum = 50345;
GO

-- ==============================================================
-- Correction 34.6
-- ==============================================================
GO
CREATE OR ALTER PROCEDURE dbo.usp_Ex34_AvgPrincipal
    @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Total DECIMAL(14,2), @Loans INT;

    SELECT @Total = ISNULL(SUM(Principal), 0),
           @Loans = COUNT(*)
    FROM dbo.Loan
    WHERE CustomerID = @CustomerID;

    PRINT CONCAT(N'Average principal: ', @Total / @Loans);
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Ex34_CustomerReport
    @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.usp_Ex34_AvgPrincipal @CustomerID = @CustomerID;
END;
GO

BEGIN TRY
    EXEC dbo.usp_Ex34_CustomerReport @CustomerID = 3;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrNumber,
           ERROR_PROCEDURE() AS ErrProcedure,
           ERROR_LINE()      AS ErrLine;
END CATCH;
GO

-- ==============================================================
-- Correction 34.7
-- ==============================================================
GO
CREATE OR ALTER PROCEDURE dbo.usp_ChangeLoanStatus
    @LoanID    INT,
    @NewStatus NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Msg NVARCHAR(2048);

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @NewStatus NOT IN (N'Active', N'Repaid', N'Arrears',
                              N'Default', N'Written Off')
        BEGIN
            SET @Msg = FORMATMESSAGE(
                N'Status %s is not a valid loan status.', @NewStatus);
            THROW 50020, @Msg, 1;
        END;

        UPDATE dbo.Loan
        SET LoanStatus = @NewStatus
        WHERE LoanID = @LoanID;

        IF @@ROWCOUNT = 0
        BEGIN
            SET @Msg = FORMATMESSAGE(
                N'Loan %d does not exist.', @LoanID);
            THROW 50021, @Msg, 1;
        END;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        EXEC dbo.usp_LogError;
        THROW;
    END CATCH;
END;
GO

EXEC dbo.usp_ChangeLoanStatus @LoanID = 10002,
                              @NewStatus = N'Written Off';

BEGIN TRY
    EXEC dbo.usp_ChangeLoanStatus @LoanID = 10002,
                                  @NewStatus = N'Closed';
END TRY
BEGIN CATCH
    PRINT ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    EXEC dbo.usp_ChangeLoanStatus @LoanID = 10950,
                                  @NewStatus = N'Default';
END TRY
BEGIN CATCH
    PRINT ERROR_MESSAGE();
END CATCH;

SELECT ErrorNumber, ErrorLine, ErrorMessage
FROM dbo.ErrorLog
ORDER BY ErrorLogID;

EXEC dbo.usp_ChangeLoanStatus @LoanID = 10002,
                              @NewStatus = N'Default';
GO

-- ==============================================================
-- Correction 34.8
-- ==============================================================
GO
CREATE OR ALTER PROCEDURE dbo.usp_TransferOfficerLoans
    @FromOfficerID INT,
    @ToOfficerID   INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Msg NVARCHAR(2048), @FromBranch NVARCHAR(60),
            @ToBranch NVARCHAR(60);

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @FromBranch =
                   MAX(CASE WHEN o.OfficerID = @FromOfficerID
                            THEN b.BranchName END),
               @ToBranch =
                   MAX(CASE WHEN o.OfficerID = @ToOfficerID
                            THEN b.BranchName END)
        FROM dbo.LoanOfficer AS o
        INNER JOIN dbo.Branch AS b
            ON b.BranchID = o.BranchID
        WHERE o.OfficerID IN (@FromOfficerID, @ToOfficerID);

        IF @FromBranch IS NULL OR @ToBranch IS NULL
           OR @FromBranch <> @ToBranch
        BEGIN
            SET @Msg = N'Officers %d (%s) and %d (%s) work at '
                     + N'different branches.';
            SET @Msg = FORMATMESSAGE(@Msg, @FromOfficerID,
                           @FromBranch, @ToOfficerID, @ToBranch);
            THROW 50030, @Msg, 1;
        END;

        UPDATE dbo.Loan
        SET OfficerID = @ToOfficerID
        WHERE OfficerID = @FromOfficerID
          AND LoanStatus = N'Active';

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        EXEC dbo.usp_LogError;
        THROW;
    END CATCH;
END;
GO

BEGIN TRANSACTION;                        -- test 1: outer transaction

EXEC dbo.usp_TransferOfficerLoans @FromOfficerID = 101,
                                  @ToOfficerID   = 102;

SELECT OfficerID, COUNT(*) AS ActiveLoans
FROM dbo.Loan
WHERE OfficerID IN (101, 102)
  AND LoanStatus = N'Active'
GROUP BY OfficerID
ORDER BY OfficerID;

ROLLBACK TRANSACTION;                     -- undo the transfer
GO

BEGIN TRY                                 -- test 2: two branches
    EXEC dbo.usp_TransferOfficerLoans @FromOfficerID = 101,
                                      @ToOfficerID   = 104;
END TRY
BEGIN CATCH
    PRINT CONCAT(N'Error ', ERROR_NUMBER(), N': ', ERROR_MESSAGE());
END CATCH;
GO

-- ==============================================================
-- Clean-up: restore the data, remove every object of the exercises
-- ==============================================================

IF @@TRANCOUNT > 0 ROLLBACK;
SET XACT_ABORT OFF;

UPDATE dbo.Loan
SET LoanStatus = N'Default'              -- status at 30 Sep 2026
WHERE LoanID = 10002;
GO
DROP PROCEDURE IF EXISTS dbo.usp_TransferOfficerLoans;
DROP PROCEDURE IF EXISTS dbo.usp_ChangeLoanStatus;
DROP PROCEDURE IF EXISTS dbo.usp_Ex34_CustomerReport;
DROP PROCEDURE IF EXISTS dbo.usp_Ex34_AvgPrincipal;
DROP PROCEDURE IF EXISTS dbo.usp_LogError;
DROP TABLE IF EXISTS dbo.ErrorLog;
GO
IF EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 50345)
    EXEC sys.sp_dropmessage @msgnum = 50345;
GO
