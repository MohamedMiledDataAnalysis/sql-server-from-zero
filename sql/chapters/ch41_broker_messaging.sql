/* SQL Server from Zero — Volume 2
   Chapter 41: BEGIN DIALOG, SEND, RECEIVE and END CONVERSATION
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO


-- ==============================================================
-- Start from a clean state (chapter 40, section 8, plus this chapter's objects)
-- ==============================================================

IF EXISTS (SELECT 1 FROM sys.services
           WHERE name = N'//Northbridge/Collections/ArrearsCheckService')
    DROP SERVICE [//Northbridge/Collections/ArrearsCheckService];
IF EXISTS (SELECT 1 FROM sys.services
           WHERE name = N'//Northbridge/Payments/PostingService')
    DROP SERVICE [//Northbridge/Payments/PostingService];

IF OBJECT_ID(N'dbo.ArrearsCheckQueue', N'SQ') IS NOT NULL
    DROP QUEUE dbo.ArrearsCheckQueue;
IF OBJECT_ID(N'dbo.PaymentPostingQueue', N'SQ') IS NOT NULL
    DROP QUEUE dbo.PaymentPostingQueue;

IF EXISTS (SELECT 1 FROM sys.service_contracts
           WHERE name = N'//Northbridge/Collections/ArrearsCheckContract')
    DROP CONTRACT [//Northbridge/Collections/ArrearsCheckContract];

IF EXISTS (SELECT 1 FROM sys.service_message_types
           WHERE name = N'//Northbridge/Collections/ArrearsCheckRequest')
    DROP MESSAGE TYPE [//Northbridge/Collections/ArrearsCheckRequest];
IF EXISTS (SELECT 1 FROM sys.service_message_types
           WHERE name = N'//Northbridge/Collections/ArrearsCheckResult')
    DROP MESSAGE TYPE [//Northbridge/Collections/ArrearsCheckResult];
IF EXISTS (SELECT 1 FROM sys.service_message_types
           WHERE name = N'//Northbridge/Collections/Cancel')
    DROP MESSAGE TYPE [//Northbridge/Collections/Cancel];

DROP PROCEDURE IF EXISTS dbo.usp_ArrearsCheck_Target;
DROP PROCEDURE IF EXISTS dbo.usp_ArrearsCheck_Initiator;
DROP PROCEDURE IF EXISTS dbo.usp_PostPaymentWithCheck;
DROP TABLE IF EXISTS dbo.ArrearsCheckLog;
DROP TABLE IF EXISTS dbo.Practice_PaymentPosting;
GO

-- ==============================================================
-- 1. Conversations, dialogs and the objects of chapter 40
-- ==============================================================

-- The objects of chapter 40 (sections 3, 5, 6 and 7)
CREATE MESSAGE TYPE [//Northbridge/Collections/ArrearsCheckRequest]
    VALIDATION = WELL_FORMED_XML;
CREATE MESSAGE TYPE [//Northbridge/Collections/ArrearsCheckResult]
    VALIDATION = WELL_FORMED_XML;
CREATE MESSAGE TYPE [//Northbridge/Collections/Cancel]
    VALIDATION = EMPTY;
GO

CREATE CONTRACT [//Northbridge/Collections/ArrearsCheckContract]
(
    [//Northbridge/Collections/ArrearsCheckRequest] SENT BY INITIATOR,
    [//Northbridge/Collections/ArrearsCheckResult]  SENT BY TARGET,
    [//Northbridge/Collections/Cancel]              SENT BY ANY
);
GO

CREATE QUEUE dbo.ArrearsCheckQueue;
CREATE QUEUE dbo.PaymentPostingQueue;
GO

CREATE SERVICE [//Northbridge/Collections/ArrearsCheckService]
    ON QUEUE dbo.ArrearsCheckQueue
    ([//Northbridge/Collections/ArrearsCheckContract]);
CREATE SERVICE [//Northbridge/Payments/PostingService]
    ON QUEUE dbo.PaymentPostingQueue;
GO

-- The table that holds the results of the arrears checks
DROP TABLE IF EXISTS dbo.ArrearsCheckLog;

CREATE TABLE dbo.ArrearsCheckLog (
    LogID             INT IDENTITY(1,1) NOT NULL
                      CONSTRAINT PK_ArrearsCheckLog PRIMARY KEY,
    LoanID            INT            NOT NULL,
    MissedInstalments INT            NOT NULL,
    AmountMissed      DECIMAL(12,2)  NOT NULL,
    LoggedAt          DATETIME2(0)   NOT NULL
                      CONSTRAINT DF_ArrearsCheckLog_At
                      DEFAULT SYSDATETIME()
);
GO

-- ==============================================================
-- 2. BEGIN DIALOG and SEND
-- ==============================================================

DECLARE @h UNIQUEIDENTIFIER;
DECLARE @Body VARBINARY(MAX) =
    CAST((SELECT LoanID
          FROM dbo.Loan
          WHERE LoanID = 10430
          FOR XML PATH('ArrearsCheck'), TYPE) AS VARBINARY(MAX));

BEGIN TRANSACTION;

BEGIN DIALOG CONVERSATION @h
    FROM SERVICE [//Northbridge/Payments/PostingService]
    TO SERVICE N'//Northbridge/Collections/ArrearsCheckService'
    ON CONTRACT [//Northbridge/Collections/ArrearsCheckContract]
    WITH ENCRYPTION = OFF;

SELECT is_initiator, state_desc
FROM sys.conversation_endpoints
WHERE conversation_handle = @h;

SEND ON CONVERSATION @h
    MESSAGE TYPE [//Northbridge/Collections/ArrearsCheckRequest]
    (@Body);

COMMIT TRANSACTION;

SELECT is_initiator, state_desc, far_service
FROM sys.conversation_endpoints
WHERE state <> 'CD'                        -- not closed
ORDER BY is_initiator DESC;
GO

-- Deliberate error 8432: the initiator cannot send a SENT BY TARGET type
DECLARE @h UNIQUEIDENTIFIER =
    (SELECT conversation_handle
     FROM sys.conversation_endpoints
     WHERE is_initiator = 1
       AND state = 'CO');

SEND ON CONVERSATION @h
    MESSAGE TYPE [//Northbridge/Collections/ArrearsCheckResult];
GO
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO

-- ==============================================================
-- 3. Reading a queue: SELECT, RECEIVE and WAITFOR
-- ==============================================================

SELECT status,
       message_type_name,
       CAST(message_body AS XML).value(
           '(/ArrearsCheck/LoanID)[1]', 'INT') AS LoanID
FROM dbo.ArrearsCheckQueue;
GO

-- RECEIVE inside a transaction; ROLLBACK returns the message
DECLARE @Received TABLE (
    conversation_handle UNIQUEIDENTIFIER,
    message_type_name   NVARCHAR(256),
    message_body        VARBINARY(MAX));

BEGIN TRANSACTION;

RECEIVE TOP (1) conversation_handle, message_type_name, message_body
FROM dbo.ArrearsCheckQueue
INTO @Received;

SELECT CAST(message_body AS XML).value(
           '(/ArrearsCheck/LoanID)[1]', 'INT') AS ReceivedLoanID,
       (SELECT COUNT(*) FROM dbo.ArrearsCheckQueue) AS LeftInQueue
FROM @Received;

ROLLBACK TRANSACTION;

SELECT COUNT(*) AS LeftAfterRollback
FROM dbo.ArrearsCheckQueue;
GO

-- WAITFOR (RECEIVE ...) on the empty payments queue
WAITFOR (
    RECEIVE TOP (1) conversation_handle, message_type_name
    FROM dbo.PaymentPostingQueue
), TIMEOUT 2000;

PRINT CONCAT(N'Messages received: ', @@ROWCOUNT);
GO

-- ==============================================================
-- 4. Replying and END CONVERSATION
-- ==============================================================

-- Target side: receive, compute, reply, end
DECLARE @h UNIQUEIDENTIFIER, @Type NVARCHAR(256), @Body VARBINARY(MAX);
DECLARE @LoanID INT, @Missed INT, @Amount DECIMAL(12,2),
        @Reply VARBINARY(MAX);

BEGIN TRANSACTION;

WAITFOR (
    RECEIVE TOP (1)
        @h    = conversation_handle,
        @Type = message_type_name,
        @Body = message_body
    FROM dbo.ArrearsCheckQueue
), TIMEOUT 2000;

IF @Type = N'//Northbridge/Collections/ArrearsCheckRequest'
BEGIN
    SET @LoanID = CAST(@Body AS XML).value(
                      '(/ArrearsCheck/LoanID)[1]', 'INT');

    SELECT @Missed = COUNT(*),
           @Amount = ISNULL(SUM(AmountDue), 0)
    FROM dbo.Payment
    WHERE LoanID = @LoanID
      AND PaidDate IS NULL;                -- missed instalments

    SET @Reply = CAST((SELECT @LoanID AS LoanID,
                              @Missed AS MissedInstalments,
                              @Amount AS AmountMissed
                       FOR XML PATH('ArrearsCheckResult'), TYPE)
                      AS VARBINARY(MAX));

    SEND ON CONVERSATION @h
        MESSAGE TYPE [//Northbridge/Collections/ArrearsCheckResult]
        (@Reply);

    END CONVERSATION @h;                   -- the target's side ends

    PRINT CONCAT(N'Loan ', @LoanID, N': ', @Missed,
                 N' missed instalment(s) totalling ', @Amount, N'.');
END;

COMMIT TRANSACTION;
GO

-- Initiator side: the result and the EndDialog, then end
DECLARE @Received TABLE (
    conversation_handle     UNIQUEIDENTIFIER,
    message_sequence_number BIGINT,
    message_type_name       NVARCHAR(256),
    message_body            VARBINARY(MAX));
DECLARE @h UNIQUEIDENTIFIER;

BEGIN TRANSACTION;

WAITFOR (
    RECEIVE conversation_handle, message_sequence_number,
            message_type_name, message_body
    FROM dbo.PaymentPostingQueue
    INTO @Received
), TIMEOUT 2000;

SELECT message_type_name AS MessageType,
       CAST(message_body AS XML).value(
           '(/ArrearsCheckResult/MissedInstalments)[1]', 'INT')
           AS Missed,
       CAST(message_body AS XML).value(
           '(/ArrearsCheckResult/AmountMissed)[1]', 'DECIMAL(12,2)')
           AS Amount
FROM @Received
ORDER BY message_sequence_number;

SET @h = (SELECT TOP (1) conversation_handle FROM @Received);

END CONVERSATION @h;                       -- the initiator's side ends

COMMIT TRANSACTION;
GO

-- ==============================================================
-- 5. Diagnosing stuck messages
-- ==============================================================

-- A wrong letter case in the target service name
DECLARE @h UNIQUEIDENTIFIER;
DECLARE @Body VARBINARY(MAX) =
    CAST((SELECT 10583 AS LoanID
          FOR XML PATH('ArrearsCheck'), TYPE) AS VARBINARY(MAX));

BEGIN DIALOG CONVERSATION @h
    FROM SERVICE [//Northbridge/Payments/PostingService]
    TO SERVICE N'//Northbridge/Collections/arrearscheckservice'
    ON CONTRACT [//Northbridge/Collections/ArrearsCheckContract]
    WITH ENCRYPTION = OFF;

SEND ON CONVERSATION @h
    MESSAGE TYPE [//Northbridge/Collections/ArrearsCheckRequest]
    (@Body);

WAITFOR DELAY '00:00:02';

SELECT to_service_name, is_end_of_dialog, is_conversation_error
FROM sys.transmission_queue;

SELECT COUNT(*) AS InTargetQueue
FROM dbo.ArrearsCheckQueue;
GO

-- The conversation can never complete: administrator clean-up
DECLARE @h UNIQUEIDENTIFIER =
    (SELECT TOP (1) conversation_handle
     FROM sys.transmission_queue
     WHERE to_service_name =
           N'//Northbridge/Collections/arrearscheckservice');

END CONVERSATION @h WITH CLEANUP;

SELECT COUNT(*) AS StuckMessages
FROM sys.transmission_queue;
GO

-- ==============================================================
-- 6. GET CONVERSATION GROUP, BEGIN CONVERSATION TIMER and MOVE CONVERSATION
-- ==============================================================

DECLARE @h UNIQUEIDENTIFIER;
DECLARE @Body VARBINARY(MAX) =
    CAST((SELECT 10583 AS LoanID
          FOR XML PATH('ArrearsCheck'), TYPE) AS VARBINARY(MAX));

BEGIN DIALOG CONVERSATION @h
    FROM SERVICE [//Northbridge/Payments/PostingService]
    TO SERVICE N'//Northbridge/Collections/ArrearsCheckService'
    ON CONTRACT [//Northbridge/Collections/ArrearsCheckContract]
    WITH ENCRYPTION = OFF;

SEND ON CONVERSATION @h
    MESSAGE TYPE [//Northbridge/Collections/ArrearsCheckRequest]
    (@Body);

BEGIN CONVERSATION TIMER (@h) TIMEOUT = 2;   -- remind me in 2 s
GO

WAITFOR DELAY '00:00:04';

SELECT message_type_name
FROM dbo.PaymentPostingQueue;
GO

-- Payments gives up on the DialogTimer and ends its side
DECLARE @h UNIQUEIDENTIFIER, @Type NVARCHAR(256);

BEGIN TRANSACTION;

RECEIVE TOP (1)
    @h    = conversation_handle,
    @Type = message_type_name
FROM dbo.PaymentPostingQueue;

IF @Type = N'http://schemas.microsoft.com/SQL/ServiceBroker/DialogTimer'
BEGIN
    END CONVERSATION @h;                   -- no answer in time
END;

COMMIT TRANSACTION;
GO

-- Collections finds the request and the EndDialog, and ends its side
DECLARE @h UNIQUEIDENTIFIER;

BEGIN TRANSACTION;

WAITFOR (
    RECEIVE TOP (1) @h = conversation_handle
    FROM dbo.ArrearsCheckQueue
), TIMEOUT 2000;

END CONVERSATION @h;                       -- discards the EndDialog too

COMMIT TRANSACTION;
GO

-- ==============================================================
-- 7. Poison messages
-- ==============================================================

-- A request whose LoanID is not a number
DECLARE @h UNIQUEIDENTIFIER;
DECLARE @Body VARBINARY(MAX) =
    CAST(CAST(N'<ArrearsCheck><LoanID>ABC</LoanID></ArrearsCheck>'
              AS XML) AS VARBINARY(MAX));

BEGIN DIALOG CONVERSATION @h
    FROM SERVICE [//Northbridge/Payments/PostingService]
    TO SERVICE N'//Northbridge/Collections/ArrearsCheckService'
    ON CONTRACT [//Northbridge/Collections/ArrearsCheckContract]
    WITH ENCRYPTION = OFF;

SEND ON CONVERSATION @h
    MESSAGE TYPE [//Northbridge/Collections/ArrearsCheckRequest]
    (@Body);
GO

-- Five rolled-back attempts disable the queue
SET XACT_ABORT ON;
DECLARE @Attempt INT = 1, @Body VARBINARY(MAX), @LoanID INT;

WHILE @Attempt <= 5
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION;

        RECEIVE TOP (1) @Body = message_body
        FROM dbo.ArrearsCheckQueue;

        SET @LoanID = CAST(CAST(@Body AS XML).value(
                          '(/ArrearsCheck/LoanID)[1]', 'NVARCHAR(20)')
                          AS INT);         -- 'ABC' fails here

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;          -- the message goes back
        PRINT CONCAT(N'Attempt ', @Attempt, N': rolled back.');
    END CATCH;

    SET @Attempt += 1;
END;

SET XACT_ABORT OFF;
WAITFOR DELAY '00:00:01';

SELECT name, is_receive_enabled AS ReceiveOn
FROM sys.service_queues
WHERE name = N'ArrearsCheckQueue';
GO

-- Deliberate error 9617: the queue is disabled
RECEIVE TOP (1) message_type_name
FROM dbo.ArrearsCheckQueue;
GO
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO

-- Recovering: queue on, poison conversation ended with an error
ALTER QUEUE dbo.ArrearsCheckQueue
    WITH STATUS = ON;

DECLARE @h UNIQUEIDENTIFIER =
    (SELECT TOP (1) conversation_handle
     FROM dbo.ArrearsCheckQueue);

END CONVERSATION @h
    WITH ERROR = 50020
    DESCRIPTION = N'Loan identifier is not a number: message removed.';

SELECT COUNT(*) AS MessagesLeft
FROM dbo.ArrearsCheckQueue;
GO

-- The payments side reads the Error message and ends its side
DECLARE @Received TABLE (
    conversation_handle UNIQUEIDENTIFIER,
    message_type_name   NVARCHAR(256),
    message_body        VARBINARY(MAX));
DECLARE @h UNIQUEIDENTIFIER;

BEGIN TRANSACTION;

WAITFOR (
    RECEIVE conversation_handle, message_type_name, message_body
    FROM dbo.PaymentPostingQueue
    INTO @Received
), TIMEOUT 2000;

SELECT REPLACE(message_type_name,
               N'http://schemas.microsoft.com/SQL/ServiceBroker/', N'')
           AS MessageType,
       CAST(message_body AS XML).value(
           'declare namespace
                sb="http://schemas.microsoft.com/SQL/ServiceBroker/Error";
            (/sb:Error/sb:Code)[1]', 'INT') AS Code,
       CAST(message_body AS XML).value(
           'declare namespace
                sb="http://schemas.microsoft.com/SQL/ServiceBroker/Error";
            (/sb:Error/sb:Description)[1]', 'NVARCHAR(3000)')
           AS Description
FROM @Received;

SET @h = (SELECT TOP (1) conversation_handle FROM @Received);

END CONVERSATION @h;

COMMIT TRANSACTION;
GO

-- ==============================================================
-- 8. Activation: let SQL Server process the queue
-- ==============================================================

CREATE OR ALTER PROCEDURE dbo.usp_ArrearsCheck_Target
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @h UNIQUEIDENTIFIER, @Type NVARCHAR(256),
            @Body VARBINARY(MAX), @LoanID INT, @Missed INT,
            @Amount DECIMAL(12,2), @Reply VARBINARY(MAX);

    WHILE 1 = 1
    BEGIN
        SET @h = NULL;
        BEGIN TRY
            BEGIN TRANSACTION;

            WAITFOR (
                RECEIVE TOP (1)
                    @h    = conversation_handle,
                    @Type = message_type_name,
                    @Body = message_body
                FROM dbo.ArrearsCheckQueue
            ), TIMEOUT 1000;

            IF @h IS NULL                  -- nothing for 1 second
            BEGIN
                COMMIT TRANSACTION;
                BREAK;                     -- the procedure stops
            END;

            IF @Type = N'//Northbridge/Collections/ArrearsCheckRequest'
            BEGIN
                SET @LoanID = CAST(@Body AS XML).value(
                                  '(/ArrearsCheck/LoanID)[1]', 'INT');
                SELECT @Missed = COUNT(*),
                       @Amount = ISNULL(SUM(AmountDue), 0)
                FROM dbo.Payment
                WHERE LoanID = @LoanID
                  AND PaidDate IS NULL;
                SET @Reply = CAST((SELECT @LoanID AS LoanID,
                                          @Missed AS MissedInstalments,
                                          @Amount AS AmountMissed
                                   FOR XML PATH('ArrearsCheckResult'),
                                       TYPE) AS VARBINARY(MAX));
                SEND ON CONVERSATION @h
                    MESSAGE TYPE
                    [//Northbridge/Collections/ArrearsCheckResult]
                    (@Reply);
                END CONVERSATION @h;
            END
            ELSE                           -- EndDialog, Error, Cancel
            BEGIN
                END CONVERSATION @h;
            END;

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;
            THROW;                         -- to the error log
        END CATCH;
    END;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ArrearsCheck_Initiator
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @h UNIQUEIDENTIFIER, @Type NVARCHAR(256),
            @Body VARBINARY(MAX), @Xml XML;

    WHILE 1 = 1
    BEGIN
        SET @h = NULL;
        BEGIN TRY
            BEGIN TRANSACTION;

            WAITFOR (
                RECEIVE TOP (1)
                    @h    = conversation_handle,
                    @Type = message_type_name,
                    @Body = message_body
                FROM dbo.PaymentPostingQueue
            ), TIMEOUT 1000;

            IF @h IS NULL
            BEGIN
                COMMIT TRANSACTION;
                BREAK;
            END;

            IF @Type = N'//Northbridge/Collections/ArrearsCheckResult'
            BEGIN
                SET @Xml = CAST(@Body AS XML);
                INSERT INTO dbo.ArrearsCheckLog
                    (LoanID, MissedInstalments, AmountMissed)
                VALUES (
                    @Xml.value('(/ArrearsCheckResult/LoanID)[1]', 'INT'),
                    @Xml.value('(/ArrearsCheckResult/MissedInstalments)[1]',
                               'INT'),
                    @Xml.value('(/ArrearsCheckResult/AmountMissed)[1]',
                               'DECIMAL(12,2)'));
            END
            ELSE                           -- EndDialog or Error
            BEGIN
                END CONVERSATION @h;
            END;

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;
            THROW;
        END CATCH;
    END;
END;
GO

-- Attach the procedures to the queues
ALTER QUEUE dbo.ArrearsCheckQueue
    WITH ACTIVATION (
        STATUS = ON,
        PROCEDURE_NAME = dbo.usp_ArrearsCheck_Target,
        MAX_QUEUE_READERS = 2,
        EXECUTE AS SELF);

ALTER QUEUE dbo.PaymentPostingQueue
    WITH ACTIVATION (
        STATUS = ON,
        PROCEDURE_NAME = dbo.usp_ArrearsCheck_Initiator,
        MAX_QUEUE_READERS = 1,
        EXECUTE AS SELF);

SELECT name, is_activation_enabled AS ActivationOn,
       max_readers AS MaxReaders
FROM sys.service_queues
WHERE is_ms_shipped = 0
ORDER BY name;
GO

-- One request per London City loan in arrears
DECLARE @h UNIQUEIDENTIFIER, @Body VARBINARY(MAX);
DECLARE @LoanID INT =
    (SELECT MIN(LoanID) FROM dbo.Loan
     WHERE BranchID = 1 AND LoanStatus = N'Arrears');

BEGIN TRANSACTION;

WHILE @LoanID IS NOT NULL
BEGIN
    SET @Body = CAST((SELECT @LoanID AS LoanID
                      FOR XML PATH('ArrearsCheck'), TYPE)
                     AS VARBINARY(MAX));

    BEGIN DIALOG CONVERSATION @h
        FROM SERVICE [//Northbridge/Payments/PostingService]
        TO SERVICE N'//Northbridge/Collections/ArrearsCheckService'
        ON CONTRACT [//Northbridge/Collections/ArrearsCheckContract]
        WITH ENCRYPTION = OFF;

    SEND ON CONVERSATION @h
        MESSAGE TYPE [//Northbridge/Collections/ArrearsCheckRequest]
        (@Body);

    SET @LoanID = (SELECT MIN(LoanID) FROM dbo.Loan
                   WHERE BranchID = 1 AND LoanStatus = N'Arrears'
                     AND LoanID > @LoanID);
END;

COMMIT TRANSACTION;
GO

-- Activation is asynchronous: wait (15 seconds at most)
DECLARE @Seconds INT = 0;

WHILE @Seconds < 15
  AND ((SELECT COUNT(*) FROM dbo.ArrearsCheckLog) < 3
       OR EXISTS (SELECT 1 FROM sys.conversation_endpoints
                  WHERE state <> 'CD'))
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @Seconds += 1;
END;

SELECT LoanID, MissedInstalments, AmountMissed
FROM dbo.ArrearsCheckLog
ORDER BY LoanID;
GO

-- ==============================================================
-- Applied example: a posting procedure that queues its arrears check
-- ==============================================================

-- Step 1. Prepare the posting table and empty the log
TRUNCATE TABLE dbo.ArrearsCheckLog;

DROP TABLE IF EXISTS dbo.Practice_PaymentPosting;

CREATE TABLE dbo.Practice_PaymentPosting (
    PostingID INT IDENTITY(1,1) NOT NULL
              CONSTRAINT PK_Practice_PaymentPosting PRIMARY KEY,
    LoanID    INT            NOT NULL,
    Amount    DECIMAL(12,2)  NOT NULL
              CONSTRAINT CK_Practice_PaymentPosting_Amount
              CHECK (Amount > 0),
    PostedOn  DATE           NOT NULL
);
GO

-- Step 2. The posting procedure
CREATE OR ALTER PROCEDURE dbo.usp_PostPaymentWithCheck
    @LoanID   INT,
    @Amount   DECIMAL(12,2),
    @PostedOn DATE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @h UNIQUEIDENTIFIER, @Body VARBINARY(MAX);

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dbo.Practice_PaymentPosting (LoanID, Amount, PostedOn)
        VALUES (@LoanID, @Amount, @PostedOn);

        SET @Body = CAST((SELECT @LoanID AS LoanID
                          FOR XML PATH('ArrearsCheck'), TYPE)
                         AS VARBINARY(MAX));

        BEGIN DIALOG CONVERSATION @h
            FROM SERVICE [//Northbridge/Payments/PostingService]
            TO SERVICE N'//Northbridge/Collections/ArrearsCheckService'
            ON CONTRACT [//Northbridge/Collections/ArrearsCheckContract]
            WITH ENCRYPTION = OFF;

        SEND ON CONVERSATION @h
            MESSAGE TYPE [//Northbridge/Collections/ArrearsCheckRequest]
            (@Body);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;          -- no posting, no message
        THROW;
    END CATCH;
END;
GO

-- Step 3. Post the day's payments; the fourth fails on purpose (error 547)
EXEC dbo.usp_PostPaymentWithCheck 10430, 784.33, '2026-09-30';
EXEC dbo.usp_PostPaymentWithCheck 10763, 2516.76, '2026-09-30';
EXEC dbo.usp_PostPaymentWithCheck 10005, 604.49, '2026-09-30';
GO

EXEC dbo.usp_PostPaymentWithCheck 10583, -216.89, '2026-09-30';
GO
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO

-- Step 4. Wait for the checks and compare
DECLARE @Seconds INT = 0;

WHILE @Seconds < 15
  AND ((SELECT COUNT(*) FROM dbo.ArrearsCheckLog) < 3
       OR EXISTS (SELECT 1 FROM sys.conversation_endpoints
                  WHERE state <> 'CD'))
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @Seconds += 1;
END;

SELECT p.LoanID, p.Amount, l.MissedInstalments, l.AmountMissed
FROM dbo.Practice_PaymentPosting AS p
LEFT JOIN dbo.ArrearsCheckLog AS l
    ON l.LoanID = p.LoanID
ORDER BY p.LoanID;
GO

-- Step 5. Switch activation off and check that nothing is left
ALTER QUEUE dbo.ArrearsCheckQueue
    WITH ACTIVATION (STATUS = OFF);
ALTER QUEUE dbo.PaymentPostingQueue
    WITH ACTIVATION (STATUS = OFF);

WAITFOR DELAY '00:00:02';                  -- running copies finish

SELECT (SELECT COUNT(*) FROM dbo.ArrearsCheckQueue)    AS TargetQueue,
       (SELECT COUNT(*) FROM dbo.PaymentPostingQueue)  AS InitiatorQueue,
       (SELECT COUNT(*) FROM sys.transmission_queue)   AS Transmission,
       (SELECT COUNT(*) FROM sys.conversation_endpoints
        WHERE state <> 'CD')                           AS OpenEndpoints;
GO

-- ==============================================================
-- Clean-up: drop every object of this chapter (order of chapter 40)
-- ==============================================================

IF EXISTS (SELECT 1 FROM sys.services
           WHERE name = N'//Northbridge/Collections/ArrearsCheckService')
    DROP SERVICE [//Northbridge/Collections/ArrearsCheckService];
IF EXISTS (SELECT 1 FROM sys.services
           WHERE name = N'//Northbridge/Payments/PostingService')
    DROP SERVICE [//Northbridge/Payments/PostingService];

IF OBJECT_ID(N'dbo.ArrearsCheckQueue', N'SQ') IS NOT NULL
    DROP QUEUE dbo.ArrearsCheckQueue;
IF OBJECT_ID(N'dbo.PaymentPostingQueue', N'SQ') IS NOT NULL
    DROP QUEUE dbo.PaymentPostingQueue;

IF EXISTS (SELECT 1 FROM sys.service_contracts
           WHERE name = N'//Northbridge/Collections/ArrearsCheckContract')
    DROP CONTRACT [//Northbridge/Collections/ArrearsCheckContract];

IF EXISTS (SELECT 1 FROM sys.service_message_types
           WHERE name = N'//Northbridge/Collections/ArrearsCheckRequest')
    DROP MESSAGE TYPE [//Northbridge/Collections/ArrearsCheckRequest];
IF EXISTS (SELECT 1 FROM sys.service_message_types
           WHERE name = N'//Northbridge/Collections/ArrearsCheckResult')
    DROP MESSAGE TYPE [//Northbridge/Collections/ArrearsCheckResult];
IF EXISTS (SELECT 1 FROM sys.service_message_types
           WHERE name = N'//Northbridge/Collections/Cancel')
    DROP MESSAGE TYPE [//Northbridge/Collections/Cancel];

DROP PROCEDURE IF EXISTS dbo.usp_ArrearsCheck_Target;
DROP PROCEDURE IF EXISTS dbo.usp_ArrearsCheck_Initiator;
DROP PROCEDURE IF EXISTS dbo.usp_PostPaymentWithCheck;
DROP TABLE IF EXISTS dbo.ArrearsCheckLog;
DROP TABLE IF EXISTS dbo.Practice_PaymentPosting;
GO
