/* SQL Server from Zero — Volume 2
   Chapter 36: Linked servers, distributed transactions and external data
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022).
   Server-level objects: linked server NORTHBRIDGE_LOOP, login nb_link_reader, the options
   'Ad Hoc Distributed Queries' and 'show advanced options'. The clean-up block at the end
   removes them and sets both options back to 0, their default. */
USE NorthbridgeLending;
GO


-- ==============================================================
-- Preparation: remove what an earlier run may have left
-- ==============================================================

IF EXISTS (SELECT 1 FROM sys.servers
           WHERE name = N'NORTHBRIDGE_LOOP')
    EXEC sys.sp_dropserver @server = N'NORTHBRIDGE_LOOP',
                           @droplogins = 'droplogins';
GO
DROP TABLE IF EXISTS dbo.Practice_RemoteNote;
DROP TABLE IF EXISTS dbo.Practice_BranchRiskSnapshot;
DROP USER IF EXISTS nb_link_reader;
GO
-- Pooled connections opened by the linked server and OPENROWSET can stay
-- open after the queries end: close them with KILL (chapter 38), then drop
DECLARE @Session INT, @Kill NVARCHAR(30);
WHILE 1 = 1
BEGIN
    SELECT TOP (1) @Session = session_id
    FROM sys.dm_exec_sessions
    WHERE login_name = N'nb_link_reader'
      AND session_id <> @@SPID;
    IF @@ROWCOUNT = 0 BREAK;
    SET @Kill = N'KILL ' + CAST(@Session AS NVARCHAR(10)) + N';';
    EXEC (@Kill);
END;
IF EXISTS (SELECT 1 FROM sys.server_principals
           WHERE name = N'nb_link_reader')
    DROP LOGIN nb_link_reader;
GO


-- ==============================================================
-- 1. What a linked server is
-- ==============================================================

-- Row 0 of sys.servers is your own instance
SELECT server_id, is_linked
FROM sys.servers
WHERE server_id = 0;
GO


-- ==============================================================
-- 2. Creating and testing a linked server
-- ==============================================================

EXEC sys.sp_addlinkedserver
    @server     = N'NORTHBRIDGE_LOOP',   -- name you use in queries
    @srvproduct = N'',
    @provider   = N'MSOLEDBSQL',
    @datasrc    = N'localhost',          -- this machine
    @provstr    = N'Encrypt=yes;TrustServerCertificate=yes',
    @catalog    = N'NorthbridgeLending'; -- default database
GO

EXEC sys.sp_testlinkedserver N'NORTHBRIDGE_LOOP';
GO

SELECT name, provider, data_source, catalog,
       is_data_access_enabled AS DataAccess,
       is_rpc_out_enabled     AS RpcOut
FROM sys.servers
WHERE is_linked = 1
ORDER BY name;
GO


-- ==============================================================
-- 3. Linked server logins
-- ==============================================================

-- The default self-mapping
SELECT ll.local_principal_id,
       ll.uses_self_credential,
       ll.remote_name
FROM sys.linked_logins AS ll
INNER JOIN sys.servers AS s
    ON s.server_id = ll.server_id
WHERE s.name = N'NORTHBRIDGE_LOOP';
GO

-- A read-only login for the remote side (chapter 29).
-- Real passwords never go in scripts: this one is for practice only.
CREATE LOGIN nb_link_reader
    WITH PASSWORD = N'Nb#LinkReader2026!',
         DEFAULT_DATABASE = NorthbridgeLending;
GO
CREATE USER nb_link_reader FOR LOGIN nb_link_reader;
ALTER ROLE db_datareader ADD MEMBER nb_link_reader;
GO

-- Map every local login to nb_link_reader
EXEC sys.sp_addlinkedsrvlogin
    @rmtsrvname  = N'NORTHBRIDGE_LOOP',
    @useself     = N'FALSE',
    @locallogin  = NULL,                -- every local login
    @rmtuser     = N'nb_link_reader',
    @rmtpassword = N'Nb#LinkReader2026!';
GO

SELECT RemoteLogin, CanUpdateLoan
FROM OPENQUERY(NORTHBRIDGE_LOOP,
    'SELECT SUSER_SNAME() AS RemoteLogin,
            HAS_PERMS_BY_NAME(N''dbo.Loan'', N''OBJECT'',
                              N''UPDATE'') AS CanUpdateLoan;');
GO

-- Back to the self-mapping for the rest of the chapter
EXEC sys.sp_addlinkedsrvlogin
    @rmtsrvname = N'NORTHBRIDGE_LOOP',
    @useself    = N'TRUE',
    @locallogin = NULL;
GO

SELECT ll.local_principal_id,
       ll.uses_self_credential,
       ll.remote_name
FROM sys.linked_logins AS ll
INNER JOIN sys.servers AS s
    ON s.server_id = ll.server_id
WHERE s.name = N'NORTHBRIDGE_LOOP';
GO


-- ==============================================================
-- 4. Four-part names, OPENQUERY and the data access option
-- ==============================================================

-- Remote loans joined to local branches
SELECT b.BranchName,
       COUNT(*)                  AS Loans,
       SUM(l.OutstandingBalance) AS Balance
FROM NORTHBRIDGE_LOOP.NorthbridgeLending.dbo.Loan AS l   -- remote
INNER JOIN dbo.Branch AS b                               -- local
    ON b.BranchID = l.BranchID
WHERE l.LoanStatus = N'Arrears'
GROUP BY b.BranchName
ORDER BY Balance DESC;
GO

-- OPENQUERY: the remote server runs the whole query
SELECT LoanStatus, Loans, Balance
FROM OPENQUERY(NORTHBRIDGE_LOOP,
    'SELECT LoanStatus,
            COUNT(*) AS Loans,
            SUM(OutstandingBalance) AS Balance
     FROM dbo.Loan
     GROUP BY LoanStatus;') AS q
ORDER BY LoanStatus;
GO

-- data access off: deliberate error 7411
EXEC sys.sp_serveroption N'NORTHBRIDGE_LOOP', 'data access', 'false';
GO
SELECT COUNT(*) AS Branches
FROM NORTHBRIDGE_LOOP.NorthbridgeLending.dbo.Branch;
GO
EXEC sys.sp_serveroption N'NORTHBRIDGE_LOOP', 'data access', 'true';
GO
SELECT COUNT(*) AS Branches
FROM NORTHBRIDGE_LOOP.NorthbridgeLending.dbo.Branch;
GO


-- ==============================================================
-- 5. EXEC ... AT and the rpc out option
-- ==============================================================

-- rpc out is off: deliberate error 7411
EXEC (N'SELECT 1 AS One;') AT NORTHBRIDGE_LOOP;
GO

EXEC sys.sp_serveroption N'NORTHBRIDGE_LOOP', 'rpc out', 'true';
GO

-- A parameter marker ? receives the value 6
EXEC (N'SELECT ProductCode, COUNT(*) AS Loans
        FROM dbo.Loan
        WHERE BranchID = ?
        GROUP BY ProductCode
        ORDER BY ProductCode;', 6) AT NORTHBRIDGE_LOOP;
GO

-- A remote batch that creates and fills a table
EXEC (N'
SET NOCOUNT ON;
DROP TABLE IF EXISTS dbo.Practice_RemoteNote;
CREATE TABLE dbo.Practice_RemoteNote (
    NoteID INT           NOT NULL
           CONSTRAINT PK_Practice_RemoteNote PRIMARY KEY,
    LoanID INT           NOT NULL,
    Note   NVARCHAR(100) NOT NULL);
INSERT INTO dbo.Practice_RemoteNote (NoteID, LoanID, Note)
VALUES (1, 10196, N''Call scheduled''),
       (2, 10430, N''Payment plan agreed'');
') AT NORTHBRIDGE_LOOP;
GO

SELECT NoteID, LoanID, Note
FROM dbo.Practice_RemoteNote          -- read locally
ORDER BY NoteID;
GO


-- ==============================================================
-- 6. Ad hoc connections: OPENROWSET and OPENDATASOURCE
-- ==============================================================

-- Ad Hoc Distributed Queries is 0: deliberate error 15281
SELECT ProductCode, ProductName
FROM OPENROWSET('MSOLEDBSQL',
    'Server=localhost;UID=nb_link_reader;PWD=Nb#LinkReader2026!;Encrypt=no;',
    'SELECT ProductCode, ProductName
     FROM dbo.Product WHERE IsSecured = 0;') AS p
ORDER BY ProductCode;
GO

-- Enable ad hoc access (chapter 38 explains sp_configure in full)
EXEC sys.sp_configure N'show advanced options', 1;
RECONFIGURE;
EXEC sys.sp_configure N'Ad Hoc Distributed Queries', 1;
RECONFIGURE;
GO

SELECT ProductCode, ProductName
FROM OPENROWSET('MSOLEDBSQL',
    'Server=localhost;UID=nb_link_reader;PWD=Nb#LinkReader2026!;Encrypt=no;',
    'SELECT ProductCode, ProductName
     FROM dbo.Product WHERE IsSecured = 0;') AS p
ORDER BY ProductCode;
GO

-- NOT RUN BY THE AUTOMATED TEST: OPENDATASOURCE works on SQL Server for
-- Windows only; on Linux (Docker) it stops with error 7302 (MSDASC).
-- SELECT BranchID, BranchName
-- FROM OPENDATASOURCE('MSOLEDBSQL',
--     'Server=localhost;UID=nb_link_reader;PWD=Nb#LinkReader2026!;Encrypt=no;')
--     .NorthbridgeLending.dbo.Branch
-- WHERE Region = N'Scotland';
-- GO

-- Back to the defaults at once
EXEC sys.sp_configure N'Ad Hoc Distributed Queries', 0;
RECONFIGURE;
EXEC sys.sp_configure N'show advanced options', 0;
RECONFIGURE;
GO


-- ==============================================================
-- 7. Distributed transactions and MSDTC
-- ==============================================================

-- NOT RUN BY THE AUTOMATED TEST: needs MSDTC configured on both
-- servers and a second instance linked as NORTHBRIDGE_DR (a loopback
-- linked server cannot take part in a distributed transaction).
-- Replace nb-dr-sql01 with the name of your second server.
-- EXEC sys.sp_addlinkedserver
--     @server     = N'NORTHBRIDGE_DR',
--     @srvproduct = N'',
--     @provider   = N'MSOLEDBSQL',
--     @datasrc    = N'nb-dr-sql01',
--     @provstr    = N'Encrypt=yes',
--     @catalog    = N'NorthbridgeLending';
-- EXEC sys.sp_serveroption N'NORTHBRIDGE_DR', 'rpc out', 'true';
-- GO
--
-- SET XACT_ABORT ON;
-- BEGIN TRY
--     BEGIN DISTRIBUTED TRANSACTION;
--
--     UPDATE dbo.Loan                                    -- local
--     SET LoanStatus = N'Default'
--     WHERE LoanID = 10196;
--
--     UPDATE NORTHBRIDGE_DR.NorthbridgeLending.dbo.Loan  -- remote
--     SET LoanStatus = N'Default'
--     WHERE LoanID = 10196;
--
--     COMMIT TRANSACTION;          -- two-phase commit by MSDTC
-- END TRY
-- BEGIN CATCH
--     IF @@TRANCOUNT > 0
--         ROLLBACK TRANSACTION;    -- undone on both servers
--     THROW;
-- END CATCH;
-- GO
--
-- EXEC sys.sp_dropserver N'NORTHBRIDGE_DR', 'droplogins';
-- GO


-- ==============================================================
-- 8. External tables and data virtualisation
-- ==============================================================

-- NOT RUN BY THE AUTOMATED TEST: needs S3-compatible storage over
-- HTTPS, a bucket "nb-archive" with Parquet files, and, on SQL Server
-- 2022, the PolyBase feature installed and 'polybase enabled' set to 1.
-- CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'Nb#MasterKey2026!';
-- GO
-- CREATE DATABASE SCOPED CREDENTIAL nb_s3_credential
-- WITH IDENTITY = 'S3 Access Key',
--      SECRET   = '<AccessKeyID>:<SecretKeyID>';
-- GO
-- CREATE EXTERNAL DATA SOURCE nb_archive
-- WITH (LOCATION   = 's3://storage.northbridge.example:9000/',
--       CREDENTIAL = nb_s3_credential);
-- GO
-- CREATE EXTERNAL FILE FORMAT nb_parquet
-- WITH (FORMAT_TYPE = PARQUET);
-- GO
-- -- For CSV files instead:
-- -- CREATE EXTERNAL FILE FORMAT nb_csv
-- -- WITH (FORMAT_TYPE = DELIMITEDTEXT,
-- --       FORMAT_OPTIONS (FIELD_TERMINATOR = ',',
-- --                       STRING_DELIMITER = '"',
-- --                       FIRST_ROW = 2));
-- CREATE EXTERNAL TABLE dbo.ext_PaymentArchive (
--     PaymentID  INT,
--     LoanID     INT,
--     DueDate    DATE,
--     AmountPaid DECIMAL(12,2))
-- WITH (LOCATION    = '/nb-archive/payments/',
--       DATA_SOURCE = nb_archive,
--       FILE_FORMAT = nb_parquet);
-- GO
-- SELECT YEAR(DueDate) AS DueYear, SUM(AmountPaid) AS Paid
-- FROM dbo.ext_PaymentArchive
-- GROUP BY YEAR(DueDate)
-- ORDER BY DueYear;
--
-- SELECT COUNT(*) AS Payments                 -- no table needed
-- FROM OPENROWSET(BULK '/nb-archive/payments/',
--                 DATA_SOURCE = 'nb_archive',
--                 FORMAT = 'PARQUET') AS p;
-- GO
-- -- Clean-up, in the reverse order of creation
-- DROP EXTERNAL TABLE dbo.ext_PaymentArchive;
-- DROP EXTERNAL FILE FORMAT nb_parquet;
-- DROP EXTERNAL DATA SOURCE nb_archive;
-- DROP DATABASE SCOPED CREDENTIAL nb_s3_credential;
-- DROP MASTER KEY;
-- GO

-- What runs everywhere: the local file read of chapter 15
-- (Docker: /var/opt/mssql/data/import/Branch.csv)
SELECT LEN(BulkColumn) AS Characters,
       LEN(BulkColumn) - LEN(REPLACE(BulkColumn, CHAR(10), ''))
           AS Lines
FROM OPENROWSET(BULK 'C:\NorthbridgeData\Branch.csv',
                SINGLE_CLOB) AS f;
GO


-- ==============================================================
-- Applied example: a daily branch risk snapshot
-- ==============================================================

-- Step 1. Check the link before any work
EXEC sys.sp_testlinkedserver N'NORTHBRIDGE_LOOP';
GO

-- Step 2. The local snapshot table
DROP TABLE IF EXISTS dbo.Practice_BranchRiskSnapshot;

CREATE TABLE dbo.Practice_BranchRiskSnapshot (
    SnapshotDate  DATE          NOT NULL,
    BranchID      INT           NOT NULL,
    ArrearsLoans  INT           NOT NULL,
    DefaultLoans  INT           NOT NULL,   -- Default + Written Off
    BalanceAtRisk DECIMAL(14,2) NOT NULL,
    CONSTRAINT PK_Practice_BranchRiskSnapshot
        PRIMARY KEY (SnapshotDate, BranchID)
);
GO

-- Step 3. Group remotely, insert locally
INSERT INTO dbo.Practice_BranchRiskSnapshot
    (SnapshotDate, BranchID, ArrearsLoans, DefaultLoans,
     BalanceAtRisk)
SELECT '2026-09-30', BranchID, ArrearsLoans, DefaultLoans,
       BalanceAtRisk
FROM OPENQUERY(NORTHBRIDGE_LOOP,
    'SELECT BranchID,
            SUM(CASE WHEN LoanStatus = N''Arrears''
                     THEN 1 ELSE 0 END) AS ArrearsLoans,
            SUM(CASE WHEN LoanStatus IN (N''Default'', N''Written Off'')
                     THEN 1 ELSE 0 END) AS DefaultLoans,
            SUM(CASE WHEN LoanStatus IN (N''Arrears'', N''Default'',
                                         N''Written Off'')
                     THEN OutstandingBalance ELSE 0 END)
                AS BalanceAtRisk
     FROM dbo.Loan
     GROUP BY BranchID;');
GO

-- Step 4. The snapshot with branch names
SELECT s.BranchID, b.BranchName, s.ArrearsLoans, s.DefaultLoans,
       s.BalanceAtRisk
FROM dbo.Practice_BranchRiskSnapshot AS s
INNER JOIN dbo.Branch AS b
    ON b.BranchID = s.BranchID
ORDER BY s.BranchID;
GO

-- Step 5. Prove the copy matches the source: no rows expected
SELECT BranchID, ArrearsLoans, DefaultLoans, BalanceAtRisk
FROM dbo.Practice_BranchRiskSnapshot
EXCEPT
SELECT l.BranchID,
       SUM(CASE WHEN l.LoanStatus = N'Arrears' THEN 1 ELSE 0 END),
       SUM(CASE WHEN l.LoanStatus IN (N'Default', N'Written Off')
                THEN 1 ELSE 0 END),
       SUM(CASE WHEN l.LoanStatus IN (N'Arrears', N'Default',
                                      N'Written Off')
                THEN l.OutstandingBalance ELSE 0 END)
FROM NORTHBRIDGE_LOOP.NorthbridgeLending.dbo.Loan AS l
GROUP BY l.BranchID;
GO

-- Totals quoted after step 5
SELECT SUM(ArrearsLoans)  AS ArrearsLoans,
       SUM(DefaultLoans)  AS DefaultLoans,
       SUM(BalanceAtRisk) AS BalanceAtRisk
FROM dbo.Practice_BranchRiskSnapshot;
GO


-- ==============================================================
-- Clean-up (step 6): remove every object created in this chapter
-- ==============================================================

DROP TABLE IF EXISTS dbo.Practice_BranchRiskSnapshot;
DROP TABLE IF EXISTS dbo.Practice_RemoteNote;
GO
-- The linked server and its login mappings
IF EXISTS (SELECT 1 FROM sys.servers
           WHERE name = N'NORTHBRIDGE_LOOP')
    EXEC sys.sp_dropserver @server = N'NORTHBRIDGE_LOOP',
                           @droplogins = 'droplogins';
GO
DROP USER IF EXISTS nb_link_reader;
GO
-- Pooled connections opened by the linked server and OPENROWSET can stay
-- open after the queries end: close them with KILL (chapter 38), then drop
DECLARE @Session INT, @Kill NVARCHAR(30);
WHILE 1 = 1
BEGIN
    SELECT TOP (1) @Session = session_id
    FROM sys.dm_exec_sessions
    WHERE login_name = N'nb_link_reader'
      AND session_id <> @@SPID;
    IF @@ROWCOUNT = 0 BREAK;
    SET @Kill = N'KILL ' + CAST(@Session AS NVARCHAR(10)) + N';';
    EXEC (@Kill);
END;
IF EXISTS (SELECT 1 FROM sys.server_principals
           WHERE name = N'nb_link_reader')
    DROP LOGIN nb_link_reader;
GO
-- Both options back to their default, 0 (no message if already 0)
IF EXISTS (SELECT 1 FROM sys.configurations
           WHERE name = N'Ad Hoc Distributed Queries'
             AND CAST(value AS INT) <> 0)
BEGIN
    EXEC sys.sp_configure N'show advanced options', 1;
    RECONFIGURE;
    EXEC sys.sp_configure N'Ad Hoc Distributed Queries', 0;
    RECONFIGURE;
END;
GO
IF EXISTS (SELECT 1 FROM sys.configurations
           WHERE name = N'show advanced options'
             AND CAST(value AS INT) <> 0)
BEGIN
    EXEC sys.sp_configure N'show advanced options', 0;
    RECONFIGURE;
END;
GO
-- Proof: no linked server left, both options at 0
SELECT (SELECT COUNT(*) FROM sys.servers
        WHERE name = N'NORTHBRIDGE_LOOP')                 AS LinkedServers,
       (SELECT CAST(value_in_use AS INT) FROM sys.configurations
        WHERE name = N'Ad Hoc Distributed Queries')         AS AdHoc,
       (SELECT CAST(value_in_use AS INT) FROM sys.configurations
        WHERE name = N'show advanced options')               AS ShowAdvanced;
GO
