/* SQL Server from Zero — Volume 2
   Chapter 41: BEGIN DIALOG, SEND, RECEIVE and END CONVERSATION — solutions to the exercises
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO


-- ==============================================================
-- Setup: remove leftovers, then create the objects of chapter 40 (no activation)
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

-- ==============================================================
-- Correction 41.1
-- ==============================================================

DECLARE @h UNIQUEIDENTIFIER;
DECLARE @Body VARBINARY(MAX) =
    CAST((SELECT 10763 AS LoanID
          FOR XML PATH('ArrearsCheck'), TYPE) AS VARBINARY(MAX));

BEGIN TRANSACTION;

BEGIN DIALOG CONVERSATION @h
    FROM SERVICE [//Northbridge/Payments/PostingService]
    TO SERVICE N'//Northbridge/Collections/ArrearsCheckService'
    ON CONTRACT [//Northbridge/Collections/ArrearsCheckContract]
    WITH ENCRYPTION = OFF;

SEND ON CONVERSATION @h
    MESSAGE TYPE [//Northbridge/Collections/ArrearsCheckRequest]
    (@Body);

COMMIT TRANSACTION;                    -- the message is sent now

SELECT REPLACE(message_type_name, N'//Northbridge/Collections/', N'')
           AS MessageType,
       CAST(message_body AS XML).value(
           '(/ArrearsCheck/LoanID)[1]', 'INT') AS LoanID
FROM dbo.ArrearsCheckQueue;
GO

-- ==============================================================
-- Correction 41.2
-- ==============================================================

SELECT is_initiator, state_desc
FROM sys.conversation_endpoints
WHERE state <> 'CD'                    -- not closed
ORDER BY is_initiator DESC;
GO

-- ==============================================================
-- Correction 41.3
-- ==============================================================

WAITFOR (
    RECEIVE TOP (1) conversation_handle
    FROM dbo.PaymentPostingQueue
), TIMEOUT 1500;                        -- milliseconds

PRINT CONCAT(N'Messages received: ', @@ROWCOUNT);
GO

-- ==============================================================
-- Correction 41.4
-- ==============================================================

-- Target side: the target batch of section 4, unchanged
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

-- Initiator side
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

SELECT REPLACE(REPLACE(message_type_name,
           N'//Northbridge/Collections/', N''),
           N'http://schemas.microsoft.com/SQL/ServiceBroker/', N'')
           AS MessageType,
       CAST(message_body AS XML).value(
           '(/ArrearsCheckResult/MissedInstalments)[1]', 'INT')
           AS Missed,
       CAST(message_body AS XML).value(
           '(/ArrearsCheckResult/AmountMissed)[1]', 'DECIMAL(12,2)')
           AS Amount
FROM @Received
ORDER BY message_sequence_number;

SET @h = (SELECT TOP (1) conversation_handle FROM @Received);
END CONVERSATION @h;                  -- initiator ends: dialog complete

COMMIT TRANSACTION;
GO

WAITFOR DELAY '00:00:02';

SELECT COUNT(*) AS OpenEndpoints
FROM sys.conversation_endpoints
WHERE state <> 'CD';
GO

-- ==============================================================
-- Correction 41.5
-- ==============================================================

DECLARE @h UNIQUEIDENTIFIER;
DECLARE @Body VARBINARY(MAX) =
    CAST((SELECT 10005 AS LoanID
          FOR XML PATH('ArrearsCheck'), TYPE) AS VARBINARY(MAX));

BEGIN TRANSACTION;
BEGIN DIALOG CONVERSATION @h
    FROM SERVICE [//Northbridge/Payments/PostingService]
    TO SERVICE N'//Northbridge/Collections/ArrearsCheckService'
    ON CONTRACT [//Northbridge/Collections/ArrearsCheckContract]
    WITH ENCRYPTION = OFF;
SEND ON CONVERSATION @h
    MESSAGE TYPE [//Northbridge/Collections/ArrearsCheckRequest]
    (@Body);
SEND ON CONVERSATION @h
    MESSAGE TYPE [//Northbridge/Collections/Cancel];   -- no body
COMMIT TRANSACTION;
GO

-- Target: every message of the conversation in one RECEIVE
DECLARE @Received TABLE (
    conversation_handle     UNIQUEIDENTIFIER,
    message_sequence_number BIGINT,
    message_type_name       NVARCHAR(256));
DECLARE @h UNIQUEIDENTIFIER;

BEGIN TRANSACTION;
WAITFOR (
    RECEIVE conversation_handle, message_sequence_number,
            message_type_name
    FROM dbo.ArrearsCheckQueue
    INTO @Received
), TIMEOUT 2000;

SELECT REPLACE(message_type_name, N'//Northbridge/Collections/', N'')
           AS MessageType
FROM @Received
ORDER BY message_sequence_number;

SET @h = (SELECT TOP (1) conversation_handle FROM @Received);
END CONVERSATION @h;                  -- cancelled: no work done
COMMIT TRANSACTION;
GO

-- Initiator: the EndDialog
DECLARE @h UNIQUEIDENTIFIER, @Type NVARCHAR(256);

BEGIN TRANSACTION;
WAITFOR (
    RECEIVE TOP (1)
        @h    = conversation_handle,
        @Type = message_type_name
    FROM dbo.PaymentPostingQueue
), TIMEOUT 2000;
IF @Type = N'http://schemas.microsoft.com/SQL/ServiceBroker/EndDialog'
BEGIN
    END CONVERSATION @h;
END;
COMMIT TRANSACTION;
GO

-- ==============================================================
-- Correction 41.6
-- ==============================================================

DECLARE @h UNIQUEIDENTIFIER;
DECLARE @Body VARBINARY(MAX) =
    CAST((SELECT 10005 AS LoanID
          FOR XML PATH('ArrearsCheck'), TYPE) AS VARBINARY(MAX));

BEGIN DIALOG CONVERSATION @h
    FROM SERVICE [//Northbridge/Payments/PostingService]
    TO SERVICE N'//Northbridge/Collections/ArrearsCheckService'
    ON CONTRACT [//Northbridge/Collections/ArrearsCheckContract]
    WITH ENCRYPTION = OFF;
SEND ON CONVERSATION @h
    MESSAGE TYPE [//Northbridge/Collections/ArrearsCheckRequest]
    (@Body);
BEGIN CONVERSATION TIMER (@h) TIMEOUT = 1;     -- seconds
GO

WAITFOR DELAY '00:00:03';

SELECT REPLACE(message_type_name,
               N'http://schemas.microsoft.com/SQL/ServiceBroker/', N'')
           AS MessageType
FROM dbo.PaymentPostingQueue;
GO

-- Initiator: take the timer message and end its side
DECLARE @h UNIQUEIDENTIFIER;
BEGIN TRANSACTION;
RECEIVE TOP (1) @h = conversation_handle
FROM dbo.PaymentPostingQueue;
END CONVERSATION @h;
COMMIT TRANSACTION;
GO

-- Target: request + EndDialog, then end its side
DECLARE @h UNIQUEIDENTIFIER;
BEGIN TRANSACTION;
WAITFOR (
    RECEIVE TOP (1) @h = conversation_handle
    FROM dbo.ArrearsCheckQueue
), TIMEOUT 2000;
END CONVERSATION @h;                   -- discards the EndDialog too
COMMIT TRANSACTION;
GO

-- ==============================================================
-- Correction 41.7
-- ==============================================================

-- Send a request for loan 10005 (first batch of correction 41.5, without the Cancel)
DECLARE @h UNIQUEIDENTIFIER;
DECLARE @Body VARBINARY(MAX) =
    CAST((SELECT 10005 AS LoanID
          FOR XML PATH('ArrearsCheck'), TYPE) AS VARBINARY(MAX));

BEGIN TRANSACTION;
BEGIN DIALOG CONVERSATION @h
    FROM SERVICE [//Northbridge/Payments/PostingService]
    TO SERVICE N'//Northbridge/Collections/ArrearsCheckService'
    ON CONTRACT [//Northbridge/Collections/ArrearsCheckContract]
    WITH ENCRYPTION = OFF;
SEND ON CONVERSATION @h
    MESSAGE TYPE [//Northbridge/Collections/ArrearsCheckRequest]
    (@Body);
COMMIT TRANSACTION;
GO

-- Target
DECLARE @h UNIQUEIDENTIFIER, @Body VARBINARY(MAX), @LoanID INT,
        @Status NVARCHAR(20), @Missed INT, @Amount DECIMAL(12,2),
        @Reply VARBINARY(MAX), @Text NVARCHAR(3000);

BEGIN TRANSACTION;
WAITFOR (
    RECEIVE TOP (1)
        @h    = conversation_handle,
        @Body = message_body
    FROM dbo.ArrearsCheckQueue
), TIMEOUT 2000;

SET @LoanID = CAST(@Body AS XML).value(
                  '(/ArrearsCheck/LoanID)[1]', 'INT');
SET @Status = (SELECT LoanStatus FROM dbo.Loan
               WHERE LoanID = @LoanID);

IF @Status = N'Arrears'
BEGIN
    SELECT @Missed = COUNT(*),
           @Amount = ISNULL(SUM(AmountDue), 0)
    FROM dbo.Payment
    WHERE LoanID = @LoanID
      AND PaidDate IS NULL;
    SET @Reply = CAST((SELECT @LoanID AS LoanID,
                              @Missed AS MissedInstalments,
                              @Amount AS AmountMissed
                       FOR XML PATH('ArrearsCheckResult'), TYPE)
                      AS VARBINARY(MAX));
    SEND ON CONVERSATION @h
        MESSAGE TYPE [//Northbridge/Collections/ArrearsCheckResult]
        (@Reply);
    END CONVERSATION @h;
END
ELSE
BEGIN
    SET @Text = CONCAT(N'Loan ', @LoanID, N' is ', @Status,
                       N': no arrears check.');
    END CONVERSATION @h
        WITH ERROR = 50010 DESCRIPTION = @Text;   -- refuse politely
END;
COMMIT TRANSACTION;
GO

-- Initiator
DECLARE @h UNIQUEIDENTIFIER, @Body VARBINARY(MAX);

BEGIN TRANSACTION;
WAITFOR (
    RECEIVE TOP (1)
        @h    = conversation_handle,
        @Body = message_body
    FROM dbo.PaymentPostingQueue
), TIMEOUT 2000;

SELECT CAST(@Body AS XML).value(
           'declare namespace
                sb="http://schemas.microsoft.com/SQL/ServiceBroker/Error";
            (/sb:Error/sb:Code)[1]', 'INT') AS Code,
       CAST(@Body AS XML).value(
           'declare namespace
                sb="http://schemas.microsoft.com/SQL/ServiceBroker/Error";
            (/sb:Error/sb:Description)[1]', 'NVARCHAR(3000)')
           AS Description;

END CONVERSATION @h;
COMMIT TRANSACTION;
GO

-- ==============================================================
-- Correction 41.8
-- ==============================================================

-- The target procedure of section 8, unchanged
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

ALTER QUEUE dbo.ArrearsCheckQueue
    WITH ACTIVATION (
        STATUS = ON,
        PROCEDURE_NAME = dbo.usp_ArrearsCheck_Target,
        MAX_QUEUE_READERS = 2,
        EXECUTE AS SELF);
GO

-- Send one request per Leeds loan in arrears (loop of section 8, BranchID = 4)
DECLARE @h UNIQUEIDENTIFIER, @Body VARBINARY(MAX);
DECLARE @LoanID INT =
    (SELECT MIN(LoanID) FROM dbo.Loan
     WHERE BranchID = 4 AND LoanStatus = N'Arrears');

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
                   WHERE BranchID = 4 AND LoanStatus = N'Arrears'
                     AND LoanID > @LoanID);
END;

COMMIT TRANSACTION;
GO

-- Initiator: collect results until four dialogs are closed
DECLARE @Results TABLE (LoanID INT, MissedInstalments INT,
                        AmountMissed DECIMAL(12,2));
DECLARE @h UNIQUEIDENTIFIER, @Type NVARCHAR(256), @Body VARBINARY(MAX),
        @Xml XML, @Ended INT = 0, @EmptyWaits INT = 0;

WHILE @Ended < 4 AND @EmptyWaits < 10
BEGIN
    SET @h = NULL;
    BEGIN TRANSACTION;
    WAITFOR (
        RECEIVE TOP (1)
            @h    = conversation_handle,
            @Type = message_type_name,
            @Body = message_body
        FROM dbo.PaymentPostingQueue
    ), TIMEOUT 1000;

    IF @h IS NULL
        SET @EmptyWaits += 1;                    -- nothing yet
    ELSE IF @Type = N'//Northbridge/Collections/ArrearsCheckResult'
    BEGIN
        SET @Xml = CAST(@Body AS XML);
        INSERT INTO @Results
        VALUES (@Xml.value('(/ArrearsCheckResult/LoanID)[1]', 'INT'),
                @Xml.value('(/ArrearsCheckResult/MissedInstalments)[1]',
                           'INT'),
                @Xml.value('(/ArrearsCheckResult/AmountMissed)[1]',
                           'DECIMAL(12,2)'));
    END
    ELSE
    BEGIN
        END CONVERSATION @h;                     -- EndDialog
        SET @Ended += 1;
    END;
    COMMIT TRANSACTION;
END;

SELECT LoanID, MissedInstalments, AmountMissed
FROM @Results
ORDER BY LoanID;
GO

-- Activation off, and a pause for a running copy to finish
ALTER QUEUE dbo.ArrearsCheckQueue
    WITH ACTIVATION (STATUS = OFF);
WAITFOR DELAY '00:00:02';
GO

-- ==============================================================
-- Clean-up: drop every object created by the exercises
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
