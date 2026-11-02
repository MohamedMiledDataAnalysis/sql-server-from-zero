/* SQL Server from Zero — Volume 2
   Chapter 40: Service Broker: message types, contracts, queues and services
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO


-- ==============================================================
-- Start from a clean state: remove the objects of an earlier run
-- (services, then queues, then contracts, then message types)
-- ==============================================================

IF EXISTS (SELECT 1 FROM sys.services
           WHERE name = N'//Northbridge/Collections/ArrearsCheckService')
    DROP SERVICE [//Northbridge/Collections/ArrearsCheckService];
IF EXISTS (SELECT 1 FROM sys.services
           WHERE name = N'//Northbridge/Payments/PostingService')
    DROP SERVICE [//Northbridge/Payments/PostingService];
IF EXISTS (SELECT 1 FROM sys.services
           WHERE name = N'//Northbridge/Statements/StatementService')
    DROP SERVICE [//Northbridge/Statements/StatementService];
IF EXISTS (SELECT 1 FROM sys.services
           WHERE name = N'//Northbridge/Branches/StatementRequester')
    DROP SERVICE [//Northbridge/Branches/StatementRequester];

IF OBJECT_ID(N'dbo.ArrearsCheckQueue', N'SQ') IS NOT NULL
    DROP QUEUE dbo.ArrearsCheckQueue;
IF OBJECT_ID(N'dbo.PaymentPostingQueue', N'SQ') IS NOT NULL
    DROP QUEUE dbo.PaymentPostingQueue;
IF OBJECT_ID(N'dbo.StatementQueue', N'SQ') IS NOT NULL
    DROP QUEUE dbo.StatementQueue;
IF OBJECT_ID(N'dbo.BranchStatementQueue', N'SQ') IS NOT NULL
    DROP QUEUE dbo.BranchStatementQueue;

IF EXISTS (SELECT 1 FROM sys.service_contracts
           WHERE name = N'//Northbridge/Collections/ArrearsCheckContract')
    DROP CONTRACT [//Northbridge/Collections/ArrearsCheckContract];
IF EXISTS (SELECT 1 FROM sys.service_contracts
           WHERE name = N'//Northbridge/Collections/ResultsOnly')
    DROP CONTRACT [//Northbridge/Collections/ResultsOnly];
IF EXISTS (SELECT 1 FROM sys.service_contracts
           WHERE name = N'//Northbridge/Statements/StatementContract')
    DROP CONTRACT [//Northbridge/Statements/StatementContract];

IF EXISTS (SELECT 1 FROM sys.service_message_types
           WHERE name = N'//Northbridge/Collections/ArrearsCheckRequest')
    DROP MESSAGE TYPE [//Northbridge/Collections/ArrearsCheckRequest];
IF EXISTS (SELECT 1 FROM sys.service_message_types
           WHERE name = N'//Northbridge/Collections/ArrearsCheckResult')
    DROP MESSAGE TYPE [//Northbridge/Collections/ArrearsCheckResult];
IF EXISTS (SELECT 1 FROM sys.service_message_types
           WHERE name = N'//Northbridge/Collections/Cancel')
    DROP MESSAGE TYPE [//Northbridge/Collections/Cancel];
IF EXISTS (SELECT 1 FROM sys.service_message_types
           WHERE name = N'//Northbridge/Statements/StatementRequest')
    DROP MESSAGE TYPE [//Northbridge/Statements/StatementRequest];
IF EXISTS (SELECT 1 FROM sys.service_message_types
           WHERE name = N'//Northbridge/Statements/StatementReady')
    DROP MESSAGE TYPE [//Northbridge/Statements/StatementReady];
IF EXISTS (SELECT 1 FROM sys.service_message_types
           WHERE name = N'//Northbridge/Statements/Cancel')
    DROP MESSAGE TYPE [//Northbridge/Statements/Cancel];
GO


-- ==============================================================
-- 2. Enabling Service Broker in a database
-- ==============================================================

SELECT name, is_broker_enabled
FROM sys.databases
WHERE name = N'NorthbridgeLending';
GO

-- ENABLE_BROKER needs an exclusive lock: run it from master
USE master;
GO

ALTER DATABASE NorthbridgeLending
SET DISABLE_BROKER
WITH ROLLBACK IMMEDIATE;

SELECT name, is_broker_enabled
FROM sys.databases
WHERE name = N'NorthbridgeLending';

ALTER DATABASE NorthbridgeLending
SET ENABLE_BROKER
WITH ROLLBACK IMMEDIATE;

SELECT name, is_broker_enabled
FROM sys.databases
WHERE name = N'NorthbridgeLending';
GO

USE NorthbridgeLending;
GO

-- NEW_BROKER: a new broker identifier (compare, never print, the GUID)
USE master;
GO

DECLARE @OldGuid UNIQUEIDENTIFIER =
    (SELECT service_broker_guid
     FROM sys.databases
     WHERE name = N'NorthbridgeLending');

ALTER DATABASE NorthbridgeLending
SET NEW_BROKER
WITH ROLLBACK IMMEDIATE;

SELECT CASE WHEN service_broker_guid <> @OldGuid
            THEN N'New identifier'
            ELSE N'Same identifier'
       END AS BrokerIdentity
FROM sys.databases
WHERE name = N'NorthbridgeLending';
GO

USE NorthbridgeLending;
GO


-- ==============================================================
-- 3. Message types
-- ==============================================================

CREATE MESSAGE TYPE [//Northbridge/Collections/ArrearsCheckRequest]
    VALIDATION = WELL_FORMED_XML;

CREATE MESSAGE TYPE [//Northbridge/Collections/ArrearsCheckResult]
    VALIDATION = WELL_FORMED_XML;

CREATE MESSAGE TYPE [//Northbridge/Collections/Cancel]
    VALIDATION = EMPTY;

SELECT name, validation_desc
FROM sys.service_message_types
WHERE name LIKE N'//Northbridge/%'
ORDER BY name;
GO

-- The DEFAULT message type and the system message types
SELECT name
FROM sys.service_message_types
WHERE name = N'DEFAULT'
   OR name LIKE N'http://schemas.microsoft.com/SQL/ServiceBroker/%'
ORDER BY name;
GO


-- ==============================================================
-- 4. Enough XML for messages
-- ==============================================================

DECLARE @Request XML =
    CAST(N'<ArrearsCheck><LoanID>10430</LoanID>'
       + N'<Reason>Payment posted</Reason></ArrearsCheck>' AS XML);

SELECT @Request.value('(/ArrearsCheck/LoanID)[1]', 'INT')
           AS LoanID,
       @Request.value('(/ArrearsCheck/Reason)[1]', 'NVARCHAR(50)')
           AS Reason;
GO

-- FOR XML PATH builds the XML from a query
SELECT (SELECT LoanID, BranchID, OutstandingBalance
        FROM dbo.Loan
        WHERE LoanID = 10430
        FOR XML PATH('ArrearsCheck'), TYPE) AS Request;
GO

-- The round trip XML -> VARBINARY(MAX) -> XML
DECLARE @Request XML =
    (SELECT LoanID, BranchID, OutstandingBalance
     FROM dbo.Loan
     WHERE LoanID = 10430
     FOR XML PATH('ArrearsCheck'), TYPE);

DECLARE @Body VARBINARY(MAX) =
    CAST(@Request AS VARBINARY(MAX));    -- what the sender sends

SELECT CAST(@Body AS XML).value(        -- what the receiver reads
           '(/ArrearsCheck/OutstandingBalance)[1]',
           'DECIMAL(12,2)') AS Balance;
GO

-- Text that is not well-formed XML is refused
DECLARE @Text NVARCHAR(100) =
    N'<ArrearsCheck><LoanID>10430</ArrearsCheck>';

BEGIN TRY
    DECLARE @Bad XML = CAST(@Text AS XML);    -- checked at run time
END TRY
BEGIN CATCH
    PRINT N'Refused: the request is not well-formed XML.';
END CATCH;
GO


-- ==============================================================
-- 5. Contracts
-- ==============================================================

CREATE CONTRACT [//Northbridge/Collections/ArrearsCheckContract]
(
    [//Northbridge/Collections/ArrearsCheckRequest] SENT BY INITIATOR,
    [//Northbridge/Collections/ArrearsCheckResult]  SENT BY TARGET,
    [//Northbridge/Collections/Cancel]              SENT BY ANY
);

SELECT mt.name                AS MessageType,
       u.is_sent_by_initiator AS ByInitiator,
       u.is_sent_by_target    AS ByTarget
FROM sys.service_contracts AS c
INNER JOIN sys.service_contract_message_usages AS u
    ON u.service_contract_id = c.service_contract_id
INNER JOIN sys.service_message_types AS mt
    ON mt.message_type_id = u.message_type_id
WHERE c.name = N'//Northbridge/Collections/ArrearsCheckContract'
ORDER BY mt.name;
GO

-- A contract in which the initiator can send nothing is refused
BEGIN TRY
    CREATE CONTRACT [//Northbridge/Collections/ResultsOnly]
    (
        [//Northbridge/Collections/ArrearsCheckResult] SENT BY TARGET
    );
END TRY
BEGIN CATCH
    PRINT N'CREATE CONTRACT refused: the initiator could send nothing.';
END CATCH;
GO


-- ==============================================================
-- 6. Queues
-- ==============================================================

CREATE QUEUE dbo.ArrearsCheckQueue
    WITH STATUS = ON,
         RETENTION = OFF,
         POISON_MESSAGE_HANDLING (STATUS = ON);

CREATE QUEUE dbo.PaymentPostingQueue;      -- every default
GO

SELECT name,
       is_receive_enabled                 AS ReceiveOn,
       is_enqueue_enabled                 AS EnqueueOn,
       is_retention_enabled               AS RetentionOn,
       is_poison_message_handling_enabled AS PoisonOn
FROM sys.service_queues
WHERE is_ms_shipped = 0
ORDER BY name;
GO

-- A queue can be read with SELECT (it is empty for now)
SELECT status, message_type_name, message_body
FROM dbo.ArrearsCheckQueue;
GO


-- ==============================================================
-- 7. Services
-- ==============================================================

CREATE SERVICE [//Northbridge/Collections/ArrearsCheckService]
    ON QUEUE dbo.ArrearsCheckQueue
    ([//Northbridge/Collections/ArrearsCheckContract]);

CREATE SERVICE [//Northbridge/Payments/PostingService]
    ON QUEUE dbo.PaymentPostingQueue;      -- initiator only
GO

SELECT s.name AS ServiceName,
       q.name AS QueueName,
       c.name AS ContractName
FROM sys.services AS s
INNER JOIN sys.service_queues AS q
    ON q.object_id = s.service_queue_id
LEFT JOIN sys.service_contract_usages AS cu
    ON cu.service_id = s.service_id
LEFT JOIN sys.service_contracts AS c
    ON c.service_contract_id = cu.service_contract_id
WHERE s.name LIKE N'//Northbridge/%'
ORDER BY s.name;
GO


-- ==============================================================
-- 8. ALTER and DROP, and the order of dropping
-- ==============================================================

-- Switching a queue off and on
ALTER QUEUE dbo.ArrearsCheckQueue
    WITH STATUS = OFF;

SELECT name, is_receive_enabled AS ReceiveOn
FROM sys.service_queues
WHERE name = N'ArrearsCheckQueue';

ALTER QUEUE dbo.ArrearsCheckQueue
    WITH STATUS = ON;

SELECT name, is_receive_enabled AS ReceiveOn
FROM sys.service_queues
WHERE name = N'ArrearsCheckQueue';
GO

-- Changing a message type and a service
ALTER MESSAGE TYPE [//Northbridge/Collections/Cancel]
    VALIDATION = NONE;

ALTER SERVICE [//Northbridge/Collections/ArrearsCheckService]
    (ADD CONTRACT [DEFAULT]);

SELECT (SELECT validation_desc
        FROM sys.service_message_types
        WHERE name = N'//Northbridge/Collections/Cancel')
           AS CancelValidation,
       (SELECT COUNT(*)
        FROM sys.service_contract_usages AS cu
        INNER JOIN sys.services AS s
            ON s.service_id = cu.service_id
        WHERE s.name = N'//Northbridge/Collections/ArrearsCheckService')
           AS ContractsAccepted;

ALTER MESSAGE TYPE [//Northbridge/Collections/Cancel]
    VALIDATION = EMPTY;                    -- back to the design

ALTER SERVICE [//Northbridge/Collections/ArrearsCheckService]
    (DROP CONTRACT [DEFAULT]);
GO

-- SQL Server refuses to drop an object that another one still uses
BEGIN TRY
    DROP QUEUE dbo.ArrearsCheckQueue;
END TRY
BEGIN CATCH
    PRINT N'DROP QUEUE refused: a service still uses the queue.';
END CATCH;

BEGIN TRY
    DROP MESSAGE TYPE [//Northbridge/Collections/ArrearsCheckRequest];
END TRY
BEGIN CATCH
    PRINT N'DROP MESSAGE TYPE refused: a contract still uses it.';
END CATCH;
GO

-- Drop in the reverse order of creation, safe to run twice
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

SELECT (SELECT COUNT(*) FROM sys.services
        WHERE name LIKE N'//Northbridge/%')          AS Services,
       (SELECT COUNT(*) FROM sys.service_queues
        WHERE is_ms_shipped = 0)                      AS Queues,
       (SELECT COUNT(*) FROM sys.service_contracts
        WHERE name LIKE N'//Northbridge/%')          AS Contracts,
       (SELECT COUNT(*) FROM sys.service_message_types
        WHERE name LIKE N'//Northbridge/%')          AS MessageTypes;
GO


-- ==============================================================
-- Applied example: the customer statements channel
-- ==============================================================

-- Step 1. Check the broker and create the message types
SELECT is_broker_enabled
FROM sys.databases
WHERE name = DB_NAME();                    -- the current database

CREATE MESSAGE TYPE [//Northbridge/Statements/StatementRequest]
    VALIDATION = WELL_FORMED_XML;
CREATE MESSAGE TYPE [//Northbridge/Statements/StatementReady]
    VALIDATION = WELL_FORMED_XML;
CREATE MESSAGE TYPE [//Northbridge/Statements/Cancel]
    VALIDATION = EMPTY;
GO

-- Step 2. Create the contract
CREATE CONTRACT [//Northbridge/Statements/StatementContract]
(
    [//Northbridge/Statements/StatementRequest] SENT BY INITIATOR,
    [//Northbridge/Statements/StatementReady]   SENT BY TARGET,
    [//Northbridge/Statements/Cancel]           SENT BY ANY
);
GO

-- Step 3. Create the queues and the services
CREATE QUEUE dbo.StatementQueue
    WITH STATUS = ON,
         RETENTION = ON;                   -- keep requests for audit
CREATE QUEUE dbo.BranchStatementQueue;
GO

CREATE SERVICE [//Northbridge/Statements/StatementService]
    ON QUEUE dbo.StatementQueue
    ([//Northbridge/Statements/StatementContract]);
CREATE SERVICE [//Northbridge/Branches/StatementRequester]
    ON QUEUE dbo.BranchStatementQueue;
GO

SELECT name, is_retention_enabled AS RetentionOn
FROM sys.service_queues
WHERE is_ms_shipped = 0
ORDER BY name;
GO

-- Step 4. Prepare the first request body (customer 53)
DECLARE @Request XML =
    (SELECT CustomerID, FirstName, LastName, Email,
            CAST('2026-09-30' AS DATE) AS StatementDate
     FROM dbo.Customer
     WHERE CustomerID = 53
     FOR XML PATH('StatementRequest'), TYPE);

DECLARE @Body VARBINARY(MAX) = CAST(@Request AS VARBINARY(MAX));

SELECT CAST(@Body AS XML).value(
           '(/StatementRequest/CustomerID)[1]', 'INT') AS CustomerID,
       CAST(@Body AS XML).value(
           '(/StatementRequest/Email)[1]', 'NVARCHAR(100)') AS Email,
       CAST(@Body AS XML).value(
           '(/StatementRequest/StatementDate)[1]', 'DATE')
           AS StatementDate;
GO

-- Step 5. Inventory the design
SELECT REPLACE(s.name, N'//Northbridge/Statements/', N'')
           AS ServiceName,
       REPLACE(mt.name, N'//Northbridge/Statements/', N'')
           AS MessageType,
       CASE WHEN u.is_sent_by_initiator = 1
                 AND u.is_sent_by_target = 1 THEN N'ANY'
            WHEN u.is_sent_by_initiator = 1 THEN N'INITIATOR'
            ELSE N'TARGET'
       END AS SentBy
FROM sys.services AS s
INNER JOIN sys.service_contract_usages AS cu
    ON cu.service_id = s.service_id
INNER JOIN sys.service_contract_message_usages AS u
    ON u.service_contract_id = cu.service_contract_id
INNER JOIN sys.service_message_types AS mt
    ON mt.message_type_id = u.message_type_id
WHERE s.name LIKE N'//Northbridge/Statements/%'
ORDER BY mt.name;
GO


-- ==============================================================
-- Clean-up: drop the statements objects (order of section 8)
-- ==============================================================

IF EXISTS (SELECT 1 FROM sys.services
           WHERE name = N'//Northbridge/Statements/StatementService')
    DROP SERVICE [//Northbridge/Statements/StatementService];
IF EXISTS (SELECT 1 FROM sys.services
           WHERE name = N'//Northbridge/Branches/StatementRequester')
    DROP SERVICE [//Northbridge/Branches/StatementRequester];

IF OBJECT_ID(N'dbo.StatementQueue', N'SQ') IS NOT NULL
    DROP QUEUE dbo.StatementQueue;
IF OBJECT_ID(N'dbo.BranchStatementQueue', N'SQ') IS NOT NULL
    DROP QUEUE dbo.BranchStatementQueue;

IF EXISTS (SELECT 1 FROM sys.service_contracts
           WHERE name = N'//Northbridge/Statements/StatementContract')
    DROP CONTRACT [//Northbridge/Statements/StatementContract];

IF EXISTS (SELECT 1 FROM sys.service_message_types
           WHERE name = N'//Northbridge/Statements/StatementRequest')
    DROP MESSAGE TYPE [//Northbridge/Statements/StatementRequest];
IF EXISTS (SELECT 1 FROM sys.service_message_types
           WHERE name = N'//Northbridge/Statements/StatementReady')
    DROP MESSAGE TYPE [//Northbridge/Statements/StatementReady];
IF EXISTS (SELECT 1 FROM sys.service_message_types
           WHERE name = N'//Northbridge/Statements/Cancel')
    DROP MESSAGE TYPE [//Northbridge/Statements/Cancel];
GO
