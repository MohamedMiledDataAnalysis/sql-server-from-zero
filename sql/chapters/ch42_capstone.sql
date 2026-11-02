/* SQL Server from Zero — Volume 2
   Chapter 42: Capstone: the month-end loan-book batch
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- ==============================================================
-- Start from a clean state: remove what an earlier run left
-- ==============================================================

-- Server level: the restored copy and the operator's login
IF DB_ID(N'NorthbridgeRestored') IS NOT NULL
    DROP DATABASE NorthbridgeRestored;
GO
DROP PROCEDURE IF EXISTS dbo.usp_MonthEndClose;
DROP USER IF EXISTS nb_month_end;
DROP ROLE IF EXISTS month_end_operator;
GO
IF SUSER_ID(N'nb_month_end') IS NOT NULL
    DROP LOGIN nb_month_end;
GO
-- Database level: Service Broker objects, in dependency order
IF EXISTS (SELECT 1 FROM sys.services
           WHERE name = N'//Northbridge/Collections')
    DROP SERVICE [//Northbridge/Collections];
IF EXISTS (SELECT 1 FROM sys.services
           WHERE name = N'//Northbridge/MonthEnd')
    DROP SERVICE [//Northbridge/MonthEnd];
IF OBJECT_ID(N'dbo.CollectionsQueue') IS NOT NULL
    DROP QUEUE dbo.CollectionsQueue;
IF OBJECT_ID(N'dbo.MonthEndInitiatorQueue') IS NOT NULL
    DROP QUEUE dbo.MonthEndInitiatorQueue;
IF EXISTS (SELECT 1 FROM sys.service_contracts
           WHERE name = N'//Northbridge/NewDefaultContract')
    DROP CONTRACT [//Northbridge/NewDefaultContract];
IF EXISTS (SELECT 1 FROM sys.service_message_types
           WHERE name = N'//Northbridge/NewDefault')
    DROP MESSAGE TYPE [//Northbridge/NewDefault];
GO
-- An earlier run changed dbo.Loan: put it back from the audit
IF OBJECT_ID(N'dbo.LoanStatusAudit') IS NOT NULL
    UPDATE l
    SET LoanStatus = a.OldStatus
    FROM dbo.Loan AS l
    INNER JOIN dbo.LoanStatusAudit AS a
        ON a.LoanID = l.LoanID;
GO
DROP TABLE IF EXISTS dbo.CollectionsWorklist;
DROP TABLE IF EXISTS dbo.MonthEndRunLog;
DROP TABLE IF EXISTS dbo.MonthEndReport;
DROP TABLE IF EXISTS dbo.LoanStatusAudit;
DROP TABLE IF EXISTS dbo.InterestAccrual;
GO


-- ==============================================================
-- 1. The project: what the month-end batch does
-- ==============================================================

-- The starting point: loans by status on 30 September 2026
SELECT LoanStatus, COUNT(*) AS Loans
FROM dbo.Loan
GROUP BY LoanStatus
ORDER BY LoanStatus;
GO

-- ==============================================================
-- 2. Security: the operator's login, user and role
-- ==============================================================

CREATE LOGIN nb_month_end
    WITH PASSWORD = N'Nb#MonthEnd2026!',
         DEFAULT_DATABASE = NorthbridgeLending,
         CHECK_POLICY = ON,
         CHECK_EXPIRATION = OFF;
GO
CREATE USER nb_month_end FOR LOGIN nb_month_end;

CREATE ROLE month_end_operator;

ALTER ROLE month_end_operator ADD MEMBER nb_month_end;
GO

-- ==============================================================
-- 3. The tables and the Service Broker objects
-- ==============================================================

CREATE TABLE dbo.InterestAccrual (
    AsOfDate        DATE           NOT NULL,
    LoanID          INT            NOT NULL
                    CONSTRAINT FK_InterestAccrual_Loan
                    REFERENCES dbo.Loan (LoanID),
    Balance         DECIMAL(12,2)  NOT NULL,
    InterestRate    DECIMAL(5,2)   NOT NULL,
    AccruedInterest DECIMAL(12,2)  NOT NULL,
    CONSTRAINT PK_InterestAccrual PRIMARY KEY (AsOfDate, LoanID)
);

CREATE TABLE dbo.LoanStatusAudit (
    AuditID     INT IDENTITY(1,1) NOT NULL
                CONSTRAINT PK_LoanStatusAudit PRIMARY KEY,
    AsOfDate    DATE           NOT NULL,
    LoanID      INT            NOT NULL,
    OldStatus   NVARCHAR(20)   NOT NULL,
    NewStatus   NVARCHAR(20)   NOT NULL,
    Balance     DECIMAL(12,2)  NOT NULL,
    DaysPastDue INT            NOT NULL,
    ChangedBy   NVARCHAR(128)  NOT NULL
                CONSTRAINT DF_LoanStatusAudit_By
                DEFAULT ORIGINAL_LOGIN()
);

CREATE TABLE dbo.MonthEndReport (
    AsOfDate        DATE           NOT NULL,
    ProductType     NVARCHAR(20)   NOT NULL,
    Loans           INT            NOT NULL,
    Balance         DECIMAL(14,2)  NOT NULL,
    AccruedInterest DECIMAL(12,2)  NOT NULL,
    DefaultBalance  DECIMAL(14,2)  NOT NULL,
    ShareOfBookPct  DECIMAL(5,2)   NOT NULL,
    CONSTRAINT PK_MonthEndReport PRIMARY KEY (AsOfDate, ProductType)
);

CREATE TABLE dbo.MonthEndRunLog (
    RunID         INT IDENTITY(1,1) NOT NULL
                  CONSTRAINT PK_MonthEndRunLog PRIMARY KEY,
    AsOfDate      DATE            NOT NULL,
    Outcome       NVARCHAR(10)    NOT NULL,
    StepReached   TINYINT         NOT NULL,
    AccrualRows   INT             NULL,
    StatusChanges INT             NULL,
    MessagesSent  INT             NULL,
    ErrorNumber   INT             NULL,
    ErrorMessage  NVARCHAR(4000)  NULL,
    RunBy         NVARCHAR(128)   NOT NULL
                  CONSTRAINT DF_MonthEndRunLog_By DEFAULT ORIGINAL_LOGIN(),
    LoggedAt      DATETIME2(0)    NOT NULL
                  CONSTRAINT DF_MonthEndRunLog_At DEFAULT SYSDATETIME()
);

CREATE TABLE dbo.CollectionsWorklist (
    WorkItemID  INT IDENTITY(1,1) NOT NULL
                CONSTRAINT PK_CollectionsWorklist PRIMARY KEY,
    LoanID      INT            NOT NULL,
    Balance     DECIMAL(12,2)  NOT NULL,
    DaysPastDue INT            NOT NULL,
    ReceivedAt  DATETIME2(0)   NOT NULL
                CONSTRAINT DF_CollectionsWorklist_At DEFAULT SYSDATETIME()
);
GO
-- Service Broker must be enabled in the database (chapter 40)
USE master;
GO
ALTER DATABASE NorthbridgeLending
    SET ENABLE_BROKER WITH ROLLBACK IMMEDIATE;
GO
USE NorthbridgeLending;
GO
CREATE MESSAGE TYPE [//Northbridge/NewDefault]
    VALIDATION = WELL_FORMED_XML;

CREATE CONTRACT [//Northbridge/NewDefaultContract]
    ([//Northbridge/NewDefault] SENT BY INITIATOR);

CREATE QUEUE dbo.MonthEndInitiatorQueue WITH STATUS = ON;
CREATE QUEUE dbo.CollectionsQueue WITH STATUS = ON;

CREATE SERVICE [//Northbridge/MonthEnd]
    ON QUEUE dbo.MonthEndInitiatorQueue;

CREATE SERVICE [//Northbridge/Collections]
    ON QUEUE dbo.CollectionsQueue ([//Northbridge/NewDefaultContract]);
GO
SELECT name, is_broker_enabled
FROM sys.databases
WHERE name = N'NorthbridgeLending';
GO

-- ==============================================================
-- 4. The copy-only backup before the batch
-- ==============================================================

-- A file name without a folder goes to the default backup folder
BACKUP DATABASE NorthbridgeLending
    TO DISK = N'NorthbridgeLending_MonthEnd.bak'
    WITH COPY_ONLY, INIT, CHECKSUM,
         NAME = N'Before month-end close 2026-09-30';
GO

-- ==============================================================
-- 5. The procedure dbo.usp_MonthEndClose
-- ==============================================================

CREATE OR ALTER PROCEDURE dbo.usp_MonthEndClose
    @AsOfDate         DATE,
    @MaxStatusChanges INT     = NULL,    -- NULL: no limit
    @FailAtStep       TINYINT = NULL     -- drills only
WITH EXECUTE AS OWNER                    -- runs with dbo's rights
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;                   -- any error: roll back all

    DECLARE @Step     TINYINT = 0,
            @Accruals INT = 0,
            @Changes  INT = 0,
            @Reported INT = 0,
            @Sent     INT = 0,
            @Outcome  NVARCHAR(10) = N'SUCCESS',
            @Msg      NVARCHAR(200),
            @Dialog   UNIQUEIDENTIFIER,
            @Body     XML;

    BEGIN TRY
        BEGIN TRANSACTION MonthEnd;

        ---------- Step 1: accrue one month of interest ----------
        SET @Step = 1;
        SAVE TRANSACTION Step1;

        IF EXISTS (SELECT 1 FROM dbo.InterestAccrual
                   WHERE AsOfDate = @AsOfDate)
        BEGIN
            SET @Msg = CONCAT(N'Month ', @AsOfDate,
                              N' is already closed.');
            THROW 50041, @Msg, 1;
        END;

        INSERT INTO dbo.InterestAccrual
            (AsOfDate, LoanID, Balance, InterestRate, AccruedInterest)
        SELECT @AsOfDate, LoanID, OutstandingBalance, InterestRate,
               CAST(ROUND(OutstandingBalance * InterestRate / 1200, 2)
                    AS DECIMAL(12,2))          -- annual % / 12 months
        FROM dbo.Loan
        WHERE LoanStatus IN (N'Active', N'Arrears', N'Default')
          AND OutstandingBalance > 0;
        SET @Accruals = @@ROWCOUNT;
        PRINT CONCAT(N'Step 1: ', @Accruals, N' accrual(s).');

        ---------- Step 2: arrears and default by days past due --
        SET @Step = 2;
        SAVE TRANSACTION Step2;

        WITH LastPaid AS (               -- last instalment paid
            SELECT LoanID, MAX(DueDate) AS LastPaidDue
            FROM dbo.Payment
            WHERE PaidDate IS NOT NULL
            GROUP BY LoanID
        ),
        Overdue AS (                     -- oldest unpaid since then
            SELECT p.LoanID,
                   DATEDIFF(DAY, MIN(p.DueDate), @AsOfDate)
                       AS DaysPastDue
            FROM dbo.Payment AS p
            LEFT JOIN LastPaid AS lp
                ON lp.LoanID = p.LoanID
            WHERE p.PaidDate IS NULL
              AND p.DueDate <= @AsOfDate
              AND (lp.LastPaidDue IS NULL
                   OR p.DueDate > lp.LastPaidDue)
            GROUP BY p.LoanID
        )
        UPDATE l
        SET LoanStatus = CASE WHEN o.DaysPastDue >= 90
                              THEN N'Default'
                              ELSE N'Arrears' END
        OUTPUT @AsOfDate, inserted.LoanID, deleted.LoanStatus,
               inserted.LoanStatus, inserted.OutstandingBalance,
               o.DaysPastDue
        INTO dbo.LoanStatusAudit
            (AsOfDate, LoanID, OldStatus, NewStatus, Balance,
             DaysPastDue)
        FROM dbo.Loan AS l
        INNER JOIN Overdue AS o
            ON o.LoanID = l.LoanID
        WHERE (l.LoanStatus = N'Active' AND o.DaysPastDue >= 1)
           OR (l.LoanStatus = N'Arrears' AND o.DaysPastDue >= 90);
        SET @Changes = @@ROWCOUNT;

        IF @FailAtStep = 2
            THROW 50042, N'Simulated failure in step 2.', 1;

        IF @Changes > @MaxStatusChanges  -- a business check, no error
        BEGIN
            ROLLBACK TRANSACTION Step2;  -- undo step 2 only
            PRINT CONCAT(N'Step 2: ', @Changes, N' change(s) exceed',
                         N' the limit; step 2 undone.');
            SET @Changes = 0;
            SET @Outcome = N'PARTIAL';
        END
        ELSE
            PRINT CONCAT(N'Step 2: ', @Changes, N' status change(s).');

        ---------- Step 3: the month-end report ------------------
        SET @Step = 3;
        SAVE TRANSACTION Step3;

        INSERT INTO dbo.MonthEndReport
            (AsOfDate, ProductType, Loans, Balance, AccruedInterest,
             DefaultBalance, ShareOfBookPct)
        SELECT @AsOfDate,
               p.ProductType,
               COUNT(*),
               SUM(l.OutstandingBalance),
               SUM(a.AccruedInterest),
               SUM(CASE WHEN l.LoanStatus = N'Default'
                        THEN l.OutstandingBalance ELSE 0 END),
               CAST(100.0 * SUM(l.OutstandingBalance)
                    / SUM(SUM(l.OutstandingBalance)) OVER ()
                    AS DECIMAL(5,2))   -- share of the whole book
        FROM dbo.InterestAccrual AS a
        INNER JOIN dbo.Loan AS l
            ON l.LoanID = a.LoanID
        INNER JOIN dbo.Product AS p
            ON p.ProductCode = l.ProductCode
        WHERE a.AsOfDate = @AsOfDate
        GROUP BY p.ProductType;
        SET @Reported = @@ROWCOUNT;
        PRINT CONCAT(N'Step 3: ', @Reported, N' report row(s).');

        ---------- Step 4: one message per new default -----------
        SET @Step = 4;
        SAVE TRANSACTION Step4;

        IF EXISTS (SELECT 1 FROM dbo.LoanStatusAudit
                   WHERE AsOfDate = @AsOfDate
                     AND NewStatus = N'Default')
        BEGIN
            BEGIN DIALOG CONVERSATION @Dialog
                FROM SERVICE [//Northbridge/MonthEnd]
                TO SERVICE N'//Northbridge/Collections'
                ON CONTRACT [//Northbridge/NewDefaultContract]
                WITH ENCRYPTION = OFF;

            DECLARE default_cursor CURSOR LOCAL FAST_FORWARD FOR
                SELECT CAST(CONCAT(N'<NewDefault><LoanID>', LoanID,
                           N'</LoanID><Balance>', Balance,
                           N'</Balance><DaysPastDue>', DaysPastDue,
                           N'</DaysPastDue></NewDefault>') AS XML)
                FROM dbo.LoanStatusAudit
                WHERE AsOfDate = @AsOfDate
                  AND NewStatus = N'Default'
                ORDER BY LoanID;

            OPEN default_cursor;
            FETCH NEXT FROM default_cursor INTO @Body;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                SEND ON CONVERSATION @Dialog
                    MESSAGE TYPE [//Northbridge/NewDefault] (@Body);
                SET @Sent += 1;
                FETCH NEXT FROM default_cursor INTO @Body;
            END;
            CLOSE default_cursor;
            DEALLOCATE default_cursor;
        END;
        PRINT CONCAT(N'Step 4: ', @Sent, N' message(s) sent.');

        INSERT INTO dbo.MonthEndRunLog
            (AsOfDate, Outcome, StepReached, AccrualRows,
             StatusChanges, MessagesSent)
        VALUES (@AsOfDate, @Outcome, @Step, @Accruals, @Changes, @Sent);

        COMMIT TRANSACTION MonthEnd;     -- everything, or nothing
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;        -- steps 1 to 4, all undone

        INSERT INTO dbo.MonthEndRunLog   -- written after the rollback
            (AsOfDate, Outcome, StepReached, ErrorNumber, ErrorMessage)
        VALUES (@AsOfDate, N'FAILED', @Step, ERROR_NUMBER(),
                ERROR_MESSAGE());
        THROW;                           -- tell the caller
    END CATCH;
END;
GO
-- The operator may run the procedure, and do nothing else
GRANT EXECUTE ON OBJECT::dbo.usp_MonthEndClose TO month_end_operator;
GO
-- Proof: as the operator, reading a table is refused (error 229)
EXECUTE AS LOGIN = N'nb_month_end';
BEGIN TRY
    SELECT TOP (1) LoanID FROM dbo.Loan;
END TRY
BEGIN CATCH
    PRINT CONCAT(N'Refused: error ', ERROR_NUMBER(), N', ',
                 ERROR_MESSAGE());
END CATCH;
REVERT;
GO
IF SUSER_SNAME() <> ORIGINAL_LOGIN() REVERT;   -- safety net
GO

-- ==============================================================
-- 6. The drill: a failure in step 2, and the proof of rollback
-- ==============================================================

EXECUTE AS LOGIN = N'nb_month_end';
BEGIN TRY
    EXEC dbo.usp_MonthEndClose @AsOfDate = '2026-09-30',
                               @FailAtStep = 2;
END TRY
BEGIN CATCH
    PRINT CONCAT(N'The batch failed: error ', ERROR_NUMBER(), N', ',
                 ERROR_MESSAGE());
END CATCH;
REVERT;
GO
IF SUSER_SNAME() <> ORIGINAL_LOGIN() REVERT;   -- safety net
GO
IF @@TRANCOUNT > 0 ROLLBACK;
GO
SELECT @@TRANCOUNT AS OpenTransactions,
       (SELECT COUNT(*) FROM dbo.InterestAccrual)  AS Accruals,
       (SELECT COUNT(*) FROM dbo.LoanStatusAudit)  AS AuditRows,
       (SELECT COUNT(*) FROM dbo.Loan
        WHERE LoanStatus = N'Default')             AS DefaultLoans,
       (SELECT COUNT(*) FROM dbo.CollectionsQueue) AS QueuedMessages;

SELECT RunID, Outcome, StepReached, ErrorNumber, ErrorMessage
FROM dbo.MonthEndRunLog
ORDER BY RunID;
GO

-- ==============================================================
-- 7. The live run as the operator, and the integrity check
-- ==============================================================

EXECUTE AS LOGIN = N'nb_month_end';
BEGIN TRY
    EXEC dbo.usp_MonthEndClose @AsOfDate = '2026-09-30';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'The batch failed: error ', ERROR_NUMBER(), N', ',
                 ERROR_MESSAGE());
END CATCH;
REVERT;
GO
IF SUSER_SNAME() <> ORIGINAL_LOGIN() REVERT;   -- safety net
GO
-- Integrity of the tables the batch changed (chapter 39)
DBCC CHECKTABLE (N'dbo.Loan') WITH NO_INFOMSGS;
DBCC CHECKTABLE (N'dbo.InterestAccrual') WITH NO_INFOMSGS;
DBCC CHECKTABLE (N'dbo.LoanStatusAudit') WITH NO_INFOMSGS;
GO
SELECT RunID, Outcome, StepReached, AccrualRows, StatusChanges,
       MessagesSent
FROM dbo.MonthEndRunLog
ORDER BY RunID;

SELECT ProductType, Loans, Balance, AccruedInterest, DefaultBalance,
       ShareOfBookPct
FROM dbo.MonthEndReport
WHERE AsOfDate = '2026-09-30'
ORDER BY Balance DESC;
GO
-- Delivery to the collections queue happens at COMMIT
WAITFOR DELAY '00:00:02';

SELECT COUNT(*) AS QueuedMessages
FROM dbo.CollectionsQueue;
GO

-- ==============================================================
-- Applied example: the morning after
-- ==============================================================

-- Step 1. Collections receives the messages into its worklist
DECLARE @Msg TABLE (
    ConversationHandle UNIQUEIDENTIFIER,
    MessageType        NVARCHAR(256),
    Body               VARBINARY(MAX)
);
DECLARE @Handle UNIQUEIDENTIFIER;

BEGIN TRANSACTION;                       -- receive and work together

WAITFOR (
    RECEIVE conversation_handle, message_type_name, message_body
    FROM dbo.CollectionsQueue
    INTO @Msg
), TIMEOUT 5000;                         -- wait up to 5 seconds

INSERT INTO dbo.CollectionsWorklist (LoanID, Balance, DaysPastDue)
SELECT m.x.value('(/NewDefault/LoanID)[1]', 'INT'),
       m.x.value('(/NewDefault/Balance)[1]', 'DECIMAL(12,2)'),
       m.x.value('(/NewDefault/DaysPastDue)[1]', 'INT')
FROM (SELECT CAST(Body AS XML) AS x
      FROM @Msg
      WHERE MessageType = N'//Northbridge/NewDefault') AS m;

SELECT TOP (1) @Handle = ConversationHandle FROM @Msg;
END CONVERSATION @Handle;                -- the target ends the dialog

COMMIT TRANSACTION;
GO
-- Step 2. The month-end side receives EndDialog and ends its side
DECLARE @Handle UNIQUEIDENTIFIER, @Type NVARCHAR(256);

BEGIN TRANSACTION;

WAITFOR (
    RECEIVE TOP (1) @Handle = conversation_handle,
                    @Type = message_type_name
    FROM dbo.MonthEndInitiatorQueue
), TIMEOUT 5000;

IF @Type = N'http://schemas.microsoft.com/SQL/ServiceBroker/EndDialog'
    END CONVERSATION @Handle;

COMMIT TRANSACTION;

SELECT @Type AS ReceivedType;
GO
SELECT TOP (5) LoanID, Balance, DaysPastDue
FROM dbo.CollectionsWorklist
ORDER BY Balance DESC;

SELECT (SELECT COUNT(*) FROM dbo.CollectionsWorklist) AS WorkItems,
       (SELECT COUNT(*) FROM dbo.CollectionsQueue)    AS LeftInQueue;
GO
-- Step 3. Restore the copy-only backup under another name
DECLARE @BackupDir NVARCHAR(400) =
            CAST(SERVERPROPERTY('InstanceDefaultBackupPath')
                 AS NVARCHAR(400)),
        @DataDir   NVARCHAR(400) =
            CAST(SERVERPROPERTY('InstanceDefaultDataPath')
                 AS NVARCHAR(400)),
        @LogDir    NVARCHAR(400) =
            CAST(SERVERPROPERTY('InstanceDefaultLogPath')
                 AS NVARCHAR(400)),
        @Sep       NCHAR(1);

-- Windows paths use \, Linux paths use /; add one if it is missing
SET @Sep = CASE WHEN CHARINDEX(N'/', @DataDir) > 0
                THEN N'/' ELSE N'\' END;
IF RIGHT(@BackupDir, 1) <> @Sep SET @BackupDir += @Sep;
IF RIGHT(@DataDir, 1) <> @Sep SET @DataDir += @Sep;
IF RIGHT(@LogDir, 1) <> @Sep SET @LogDir += @Sep;

DECLARE @File NVARCHAR(400) =
            @BackupDir + N'NorthbridgeLending_MonthEnd.bak',
        @Sql  NVARCHAR(MAX) =
            N'RESTORE DATABASE NorthbridgeRestored FROM DISK = @f '
            + N'WITH MOVE N''NorthbridgeLending'' TO N'''
            + REPLACE(@DataDir, N'''', N'''''')
            + N'NorthbridgeRestored.mdf'', '
            + N'MOVE N''NorthbridgeLending_log'' TO N'''
            + REPLACE(@LogDir, N'''', N'''''')
            + N'NorthbridgeRestored_log.ldf'', '
            + N'RECOVERY, NEW_BROKER;';  -- its own Service Broker ID

EXEC sys.sp_executesql @Sql, N'@f NVARCHAR(400)', @f = @File;
GO
-- Step 4. Reconcile: loans by status before and after the batch
SELECT a.LoanStatus,
       ISNULL(b.Loans, 0)          AS BeforeBatch,
       a.Loans                     AS AfterBatch,
       a.Loans - ISNULL(b.Loans, 0) AS Change
FROM (SELECT LoanStatus, COUNT(*) AS Loans
      FROM dbo.Loan
      GROUP BY LoanStatus) AS a
LEFT JOIN (SELECT LoanStatus, COUNT(*) AS Loans
           FROM NorthbridgeRestored.dbo.Loan
           GROUP BY LoanStatus) AS b
    ON b.LoanStatus = a.LoanStatus
ORDER BY a.LoanStatus;

SELECT (SELECT COUNT(*) FROM NorthbridgeRestored.dbo.InterestAccrual)
           AS AccrualsBefore,
       (SELECT COUNT(*) FROM dbo.InterestAccrual) AS AccrualsAfter;
GO
-- Step 5. Remove the restored copy
DROP DATABASE NorthbridgeRestored;
GO

-- ==============================================================
-- Clean-up: remove every object created by this chapter
-- ==============================================================

IF SUSER_SNAME() <> ORIGINAL_LOGIN() REVERT;
GO
IF DB_ID(N'NorthbridgeRestored') IS NOT NULL
    DROP DATABASE NorthbridgeRestored;
GO
DROP PROCEDURE IF EXISTS dbo.usp_MonthEndClose;
DROP USER IF EXISTS nb_month_end;
DROP ROLE IF EXISTS month_end_operator;
GO
IF SUSER_ID(N'nb_month_end') IS NOT NULL
    DROP LOGIN nb_month_end;
GO
IF EXISTS (SELECT 1 FROM sys.services
           WHERE name = N'//Northbridge/Collections')
    DROP SERVICE [//Northbridge/Collections];
IF EXISTS (SELECT 1 FROM sys.services
           WHERE name = N'//Northbridge/MonthEnd')
    DROP SERVICE [//Northbridge/MonthEnd];
IF OBJECT_ID(N'dbo.CollectionsQueue') IS NOT NULL
    DROP QUEUE dbo.CollectionsQueue;
IF OBJECT_ID(N'dbo.MonthEndInitiatorQueue') IS NOT NULL
    DROP QUEUE dbo.MonthEndInitiatorQueue;
IF EXISTS (SELECT 1 FROM sys.service_contracts
           WHERE name = N'//Northbridge/NewDefaultContract')
    DROP CONTRACT [//Northbridge/NewDefaultContract];
IF EXISTS (SELECT 1 FROM sys.service_message_types
           WHERE name = N'//Northbridge/NewDefault')
    DROP MESSAGE TYPE [//Northbridge/NewDefault];
GO
-- Put dbo.Loan back as it was: the batch changed LoanStatus only,
-- and the audit table holds every change it committed
IF OBJECT_ID(N'dbo.LoanStatusAudit') IS NOT NULL
    UPDATE l
    SET LoanStatus = a.OldStatus
    FROM dbo.Loan AS l
    INNER JOIN dbo.LoanStatusAudit AS a
        ON a.LoanID = l.LoanID;
GO
DROP TABLE IF EXISTS dbo.CollectionsWorklist;
DROP TABLE IF EXISTS dbo.MonthEndRunLog;
DROP TABLE IF EXISTS dbo.MonthEndReport;
DROP TABLE IF EXISTS dbo.LoanStatusAudit;
DROP TABLE IF EXISTS dbo.InterestAccrual;
GO
