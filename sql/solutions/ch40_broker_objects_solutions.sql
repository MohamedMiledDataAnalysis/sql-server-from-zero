/* SQL Server from Zero — Volume 2
   Chapter 40: Service Broker: message types, contracts, queues and services — solutions to the exercises
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO


-- ==============================================================
-- Start from a clean state: remove callback objects of an earlier run
-- ==============================================================

IF EXISTS (SELECT 1 FROM sys.services
           WHERE name = N'//Northbridge/Collections/CallbackService')
    DROP SERVICE [//Northbridge/Collections/CallbackService];
IF EXISTS (SELECT 1 FROM sys.services
           WHERE name = N'//Northbridge/Branches/CallbackRequester')
    DROP SERVICE [//Northbridge/Branches/CallbackRequester];

IF OBJECT_ID(N'dbo.CallbackQueue', N'SQ') IS NOT NULL
    DROP QUEUE dbo.CallbackQueue;                 -- no service left
IF OBJECT_ID(N'dbo.CallbackRequesterQueue', N'SQ') IS NOT NULL
    DROP QUEUE dbo.CallbackRequesterQueue;

IF EXISTS (SELECT 1 FROM sys.service_contracts
           WHERE name = N'//Northbridge/Collections/CallbackContract')
    DROP CONTRACT [//Northbridge/Collections/CallbackContract];

IF EXISTS (SELECT 1 FROM sys.service_message_types
           WHERE name = N'//Northbridge/Collections/CallbackRequest')
    DROP MESSAGE TYPE [//Northbridge/Collections/CallbackRequest];
IF EXISTS (SELECT 1 FROM sys.service_message_types
           WHERE name = N'//Northbridge/Collections/CallbackDone')
    DROP MESSAGE TYPE [//Northbridge/Collections/CallbackDone];
GO

-- ==============================================================
-- Correction 40.1
-- ==============================================================

SELECT name,
       is_broker_enabled,
       is_honor_broker_priority_on        -- HONOR_BROKER_PRIORITY
FROM sys.databases
WHERE name = N'NorthbridgeLending';
GO

-- ==============================================================
-- Correction 40.2
-- ==============================================================

CREATE MESSAGE TYPE [//Northbridge/Collections/CallbackRequest]
    VALIDATION = WELL_FORMED_XML;       -- the request carries XML

CREATE MESSAGE TYPE [//Northbridge/Collections/CallbackDone]
    VALIDATION = EMPTY;                 -- a signal with no body

SELECT name, validation_desc
FROM sys.service_message_types
WHERE name LIKE N'//Northbridge/Collections/Callback%'
ORDER BY name;
GO

-- ==============================================================
-- Correction 40.3
-- ==============================================================

DECLARE @Request XML =
    (SELECT LoanID, BranchID, OutstandingBalance
     FROM dbo.Loan
     WHERE LoanID = 10583
     FOR XML PATH('CallbackRequest'), TYPE);   -- root element name

DECLARE @Body VARBINARY(MAX) =
    CAST(@Request AS VARBINARY(MAX));          -- message body form

SELECT CAST(@Body AS XML).value(
           '(/CallbackRequest/OutstandingBalance)[1]',
           'DECIMAL(12,2)') AS Balance;        -- back to a number
GO

-- ==============================================================
-- Correction 40.4
-- ==============================================================

CREATE CONTRACT [//Northbridge/Collections/CallbackContract]
(
    [//Northbridge/Collections/CallbackRequest] SENT BY INITIATOR,
    [//Northbridge/Collections/CallbackDone]    SENT BY TARGET
);

SELECT mt.name                AS MessageType,
       u.is_sent_by_initiator AS ByInitiator,
       u.is_sent_by_target    AS ByTarget
FROM sys.service_contracts AS c
INNER JOIN sys.service_contract_message_usages AS u
    ON u.service_contract_id = c.service_contract_id   -- contract → usages
INNER JOIN sys.service_message_types AS mt
    ON mt.message_type_id = u.message_type_id          -- usages → types
WHERE c.name = N'//Northbridge/Collections/CallbackContract'
ORDER BY mt.name;
GO

-- ==============================================================
-- Correction 40.5
-- ==============================================================

CREATE QUEUE dbo.CallbackQueue
    WITH STATUS = ON,
         RETENTION = OFF,
         POISON_MESSAGE_HANDLING (STATUS = ON);
CREATE QUEUE dbo.CallbackRequesterQueue;          -- defaults
GO

CREATE SERVICE [//Northbridge/Collections/CallbackService]
    ON QUEUE dbo.CallbackQueue
    ([//Northbridge/Collections/CallbackContract]);  -- target
CREATE SERVICE [//Northbridge/Branches/CallbackRequester]
    ON QUEUE dbo.CallbackRequesterQueue;             -- initiator
GO

SELECT s.name AS ServiceName,
       q.name AS QueueName,
       c.name AS ContractName
FROM sys.services AS s
INNER JOIN sys.service_queues AS q
    ON q.object_id = s.service_queue_id
LEFT JOIN sys.service_contract_usages AS cu      -- keep the initiator
    ON cu.service_id = s.service_id
LEFT JOIN sys.service_contracts AS c
    ON c.service_contract_id = cu.service_contract_id
WHERE s.name LIKE N'%Callback%'
ORDER BY s.name;
GO

-- ==============================================================
-- Correction 40.6
-- ==============================================================

ALTER QUEUE dbo.CallbackQueue
    WITH STATUS = OFF;                    -- incident: stop the queue

SELECT name, is_receive_enabled AS ReceiveOn
FROM sys.service_queues
WHERE name = N'CallbackQueue';

ALTER QUEUE dbo.CallbackQueue
    WITH STATUS = ON;                     -- back in service

ALTER MESSAGE TYPE [//Northbridge/Collections/CallbackDone]
    VALIDATION = NONE;

SELECT name, validation_desc
FROM sys.service_message_types
WHERE name = N'//Northbridge/Collections/CallbackDone';

ALTER MESSAGE TYPE [//Northbridge/Collections/CallbackDone]
    VALIDATION = EMPTY;                   -- restore the design
GO

-- ==============================================================
-- Correction 40.7
-- ==============================================================

DECLARE @Prefix NVARCHAR(40) = N'//Northbridge/Collections/';

SELECT REPLACE(s.name, @Prefix, N'')  AS ServiceName,  -- short names
       q.name                         AS QueueName,
       REPLACE(c.name, @Prefix, N'')  AS ContractName,
       REPLACE(mt.name, @Prefix, N'') AS MessageType,
       CASE WHEN u.is_sent_by_initiator = 1
                 AND u.is_sent_by_target = 1 THEN N'ANY'
            WHEN u.is_sent_by_initiator = 1 THEN N'INITIATOR'
            ELSE N'TARGET'
       END                            AS SentBy
FROM sys.services AS s
INNER JOIN sys.service_queues AS q
    ON q.object_id = s.service_queue_id               -- its queue
INNER JOIN sys.service_contract_usages AS cu
    ON cu.service_id = s.service_id                   -- its contracts
INNER JOIN sys.service_contracts AS c
    ON c.service_contract_id = cu.service_contract_id
INNER JOIN sys.service_contract_message_usages AS u
    ON u.service_contract_id = c.service_contract_id  -- types in it
INNER JOIN sys.service_message_types AS mt
    ON mt.message_type_id = u.message_type_id
WHERE s.name LIKE N'%Callback%'
ORDER BY s.name, mt.name;
GO

-- ==============================================================
-- Correction 40.8
-- ==============================================================

IF EXISTS (SELECT 1 FROM sys.services
           WHERE name = N'//Northbridge/Collections/CallbackService')
    DROP SERVICE [//Northbridge/Collections/CallbackService];
IF EXISTS (SELECT 1 FROM sys.services
           WHERE name = N'//Northbridge/Branches/CallbackRequester')
    DROP SERVICE [//Northbridge/Branches/CallbackRequester];

IF OBJECT_ID(N'dbo.CallbackQueue', N'SQ') IS NOT NULL
    DROP QUEUE dbo.CallbackQueue;                 -- no service left
IF OBJECT_ID(N'dbo.CallbackRequesterQueue', N'SQ') IS NOT NULL
    DROP QUEUE dbo.CallbackRequesterQueue;

IF EXISTS (SELECT 1 FROM sys.service_contracts
           WHERE name = N'//Northbridge/Collections/CallbackContract')
    DROP CONTRACT [//Northbridge/Collections/CallbackContract];

IF EXISTS (SELECT 1 FROM sys.service_message_types
           WHERE name = N'//Northbridge/Collections/CallbackRequest')
    DROP MESSAGE TYPE [//Northbridge/Collections/CallbackRequest];
IF EXISTS (SELECT 1 FROM sys.service_message_types
           WHERE name = N'//Northbridge/Collections/CallbackDone')
    DROP MESSAGE TYPE [//Northbridge/Collections/CallbackDone];

SELECT (SELECT COUNT(*) FROM sys.services
        WHERE name LIKE N'%Callback%')
     + (SELECT COUNT(*) FROM sys.service_queues
        WHERE name LIKE N'Callback%')
     + (SELECT COUNT(*) FROM sys.service_contracts
        WHERE name LIKE N'%Callback%')
     + (SELECT COUNT(*) FROM sys.service_message_types
        WHERE name LIKE N'%Callback%') AS CallbackObjectsLeft;
GO
