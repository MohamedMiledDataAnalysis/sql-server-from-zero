/* SQL Server from Zero — Volume 2
   Chapter 31: Certificates, keys, encryption and auditing
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022).
   Run as a member of the sysadmin role. Creates server-level objects (a certificate and
   possibly a master key in master, two server audits, the database NorthbridgePractice)
   and removes them in the clean-up block at the end. */
USE NorthbridgeLending;
GO


-- ==============================================================
-- Start-up clean-up: objects left by an interrupted earlier run
-- ==============================================================

-- Audit specifications must be switched off before they are dropped
IF EXISTS (SELECT 1 FROM sys.database_audit_specifications
           WHERE name = N'NorthbridgeCustomerReads')
BEGIN
    ALTER DATABASE AUDIT SPECIFICATION NorthbridgeCustomerReads
        WITH (STATE = OFF);
    DROP DATABASE AUDIT SPECIFICATION NorthbridgeCustomerReads;
END;
IF EXISTS (SELECT 1 FROM sys.database_audit_specifications
           WHERE name = N'NorthbridgeLoanReads')
BEGIN
    ALTER DATABASE AUDIT SPECIFICATION NorthbridgeLoanReads
        WITH (STATE = OFF);
    DROP DATABASE AUDIT SPECIFICATION NorthbridgeLoanReads;
END;
GO
USE master;
GO
IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = N'NorthbridgeAudit')
BEGIN
    ALTER SERVER AUDIT NorthbridgeAudit WITH (STATE = OFF);
    DROP SERVER AUDIT NorthbridgeAudit;
END;
IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = N'NorthbridgeLoanAudit')
BEGIN
    ALTER SERVER AUDIT NorthbridgeLoanAudit WITH (STATE = OFF);
    DROP SERVER AUDIT NorthbridgeLoanAudit;
END;
GO
-- TDE practice database, then its certificate in master
DROP DATABASE IF EXISTS NorthbridgePractice;
GO
USE master;
GO
IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'NorthbridgeTDECert')
    DROP CERTIFICATE NorthbridgeTDECert;
GO
USE NorthbridgeLending;
GO
-- Database-level objects: procedures and users before the keys they use
-- (including those of the solutions script, whose certificates also
-- depend on the database master key)
DROP PROCEDURE IF EXISTS dbo.usp_BranchExposure;
DROP USER IF EXISTS nb_risk31;
DROP USER IF EXISTS NorthbridgeExposureUser;
DROP TABLE IF EXISTS dbo.Practice_Income;
DROP TABLE IF EXISTS dbo.Practice_Branch;
DROP PROCEDURE IF EXISTS dbo.usp_LoanCountByStatus;
DROP PROCEDURE IF EXISTS dbo.usp_GetCustomerPhone;
DROP USER IF EXISTS nb_analyst31;
DROP USER IF EXISTS nb_collections31;
DROP USER IF EXISTS NorthbridgeSigningUser;
DROP TABLE IF EXISTS dbo.Practice_Customer;
CLOSE ALL SYMMETRIC KEYS;
GO
IF EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'NorthbridgeCustomerKey')
    DROP SYMMETRIC KEY NorthbridgeCustomerKey;
IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'NorthbridgeDataCert')
    DROP CERTIFICATE NorthbridgeDataCert;
IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'NorthbridgeSigningCert')
    DROP CERTIFICATE NorthbridgeSigningCert;
IF EXISTS (SELECT 1 FROM sys.asymmetric_keys WHERE name = N'NorthbridgeSigningKey')
    DROP ASYMMETRIC KEY NorthbridgeSigningKey;
IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'NorthbridgeExposureCert')
    DROP CERTIFICATE NorthbridgeExposureCert;
IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'NorthbridgeReportCert')
    DROP CERTIFICATE NorthbridgeReportCert;
GO
IF EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
    DROP MASTER KEY;
GO

-- ==============================================================
-- 1. The encryption hierarchy and the database master key
-- ==============================================================

-- The service master key, created at installation
SELECT name, algorithm_desc, key_length
FROM master.sys.symmetric_keys
WHERE name = N'##MS_ServiceMasterKey##';
GO
-- Deliberate error 15581: no database master key yet
CREATE CERTIFICATE NorthbridgeDataCert
    WITH SUBJECT = N'Northbridge customer data',
    EXPIRY_DATE = '20271231';
GO
-- Create the database master key (real passwords never go in scripts)
CREATE MASTER KEY
    ENCRYPTION BY PASSWORD = N'Nb#MasterKey2026!';

SELECT name, algorithm_desc, key_length
FROM sys.symmetric_keys;

SELECT is_master_key_encrypted_by_server
FROM sys.databases
WHERE name = N'NorthbridgeLending';
GO
-- Opening and closing the master key by hand
OPEN MASTER KEY DECRYPTION BY PASSWORD = N'Nb#MasterKey2026!';
CLOSE MASTER KEY;
GO

-- ==============================================================
-- 2. Certificates and asymmetric keys
-- ==============================================================

CREATE CERTIFICATE NorthbridgeDataCert
    WITH SUBJECT = N'Northbridge customer data',
    EXPIRY_DATE = '20271231';

CREATE ASYMMETRIC KEY NorthbridgeSigningKey
    WITH ALGORITHM = RSA_2048;
GO
SELECT name, subject, expiry_date,
       pvt_key_encryption_type_desc AS PrivateKeyProtection
FROM sys.certificates;

SELECT name, algorithm_desc, key_length
FROM sys.asymmetric_keys;
GO

-- ==============================================================
-- 3. Symmetric keys: encrypting a column
-- ==============================================================

CREATE SYMMETRIC KEY NorthbridgeCustomerKey
    WITH ALGORITHM = AES_256
    ENCRYPTION BY CERTIFICATE NorthbridgeDataCert;

DROP TABLE IF EXISTS dbo.Practice_Customer;

SELECT *
INTO dbo.Practice_Customer
FROM dbo.Customer;

ALTER TABLE dbo.Practice_Customer
    ADD EmailEncrypted VARBINARY(512) NULL;  -- ciphertext column
GO
-- Open the key, encrypt, decrypt three rows, close the key
OPEN SYMMETRIC KEY NorthbridgeCustomerKey
    DECRYPTION BY CERTIFICATE NorthbridgeDataCert;

UPDATE dbo.Practice_Customer
SET EmailEncrypted =
    ENCRYPTBYKEY(KEY_GUID(N'NorthbridgeCustomerKey'), Email);

SELECT CustomerID,
       CONVERT(NVARCHAR(100), DECRYPTBYKEY(EmailEncrypted))
           AS Email
FROM dbo.Practice_Customer
WHERE CustomerID <= 3
ORDER BY CustomerID;

CLOSE SYMMETRIC KEY NorthbridgeCustomerKey;
GO
-- With the key closed, DECRYPTBYKEY returns NULL (no error)
SELECT CustomerID,
       CONVERT(NVARCHAR(100), DECRYPTBYKEY(EmailEncrypted))
           AS Email
FROM dbo.Practice_Customer
WHERE CustomerID <= 3
ORDER BY CustomerID;
GO
-- The clear column goes
ALTER TABLE dbo.Practice_Customer
    DROP COLUMN Email;
GO

-- ==============================================================
-- 4. Hashing with HASHBYTES
-- ==============================================================

SELECT LEFT(CONVERT(VARCHAR(66),
            HASHBYTES('SHA2_256', 'N1 3BW'), 1), 18)  AS VarcharHash,
       LEFT(CONVERT(VARCHAR(66),
            HASHBYTES('SHA2_256', N'N1 3BW'), 1), 18) AS NvarcharHash,
       DATALENGTH(HASHBYTES('SHA2_256', 'N1 3BW'))   AS Bytes;
GO
-- A hash column gives back equality search
ALTER TABLE dbo.Practice_Customer
    ADD EmailHash VARBINARY(32) NULL;
GO

UPDATE pc
SET EmailHash = HASHBYTES('SHA2_256', c.Email)
FROM dbo.Practice_Customer AS pc
INNER JOIN dbo.Customer AS c
    ON c.CustomerID = pc.CustomerID;   -- the clear email is gone

SELECT CustomerID, FirstName, LastName
FROM dbo.Practice_Customer
WHERE EmailHash = HASHBYTES('SHA2_256',
                            N'lucas.edwards2@example.co.uk');
GO

-- ==============================================================
-- 5. Backing up certificates and keys
-- ==============================================================

-- Full path of a file in the default Backup, Data or Log folder,
-- identical on Windows, Linux and Docker on macOS
CREATE OR ALTER FUNCTION dbo.ufn_InstanceFile
(
    @Folder   NVARCHAR(10),          -- N'Backup', N'Data' or N'Log'
    @FileName NVARCHAR(200)
)
RETURNS NVARCHAR(400)
AS
BEGIN
    DECLARE @Dir NVARCHAR(400) = CAST(
        CASE @Folder
            WHEN N'Backup'
                THEN SERVERPROPERTY('InstanceDefaultBackupPath')
            WHEN N'Data'
                THEN SERVERPROPERTY('InstanceDefaultDataPath')
            WHEN N'Log'
                THEN SERVERPROPERTY('InstanceDefaultLogPath')
        END AS NVARCHAR(400));
    DECLARE @Sep NCHAR(1) =
        CASE WHEN CHARINDEX(N'/', @Dir) > 0 THEN N'/' ELSE N'\' END;

    IF RIGHT(@Dir, 1) NOT IN (N'/', N'\')
        SET @Dir += @Sep;            -- add the missing separator
    RETURN @Dir + @FileName;
END;
GO
-- Back up the certificate with its private key, and the master key.
-- The paths are literals in these statements: dynamic SQL (chapter 18).
DECLARE @Stamp NVARCHAR(15) =
    FORMAT(SYSDATETIME(), N'yyyyMMdd_HHmmss');   -- e.g. 20261002_143015
DECLARE @Cer NVARCHAR(400) = dbo.ufn_InstanceFile(N'Backup',
    N'NorthbridgeDataCert_' + @Stamp + N'.cer');
DECLARE @Pvk NVARCHAR(400) = dbo.ufn_InstanceFile(N'Backup',
    N'NorthbridgeDataCert_' + @Stamp + N'.pvk');
DECLARE @Key NVARCHAR(400) = dbo.ufn_InstanceFile(N'Backup',
    N'NorthbridgeLending_DMK_' + @Stamp + N'.key');
DECLARE @Sql NVARCHAR(MAX);

SET @Sql = N'BACKUP CERTIFICATE NorthbridgeDataCert TO FILE = '''
    + REPLACE(@Cer, N'''', N'''''')
    + N''' WITH PRIVATE KEY (FILE = '''
    + REPLACE(@Pvk, N'''', N'''''')
    + N''', ENCRYPTION BY PASSWORD = ''Nb#CertFile2026!'');';
EXEC sys.sp_executesql @Sql;

SET @Sql = N'BACKUP MASTER KEY TO FILE = '''
    + REPLACE(@Key, N'''', N'''''')
    + N''' ENCRYPTION BY PASSWORD = ''Nb#KeyFile2026!'';';
EXEC sys.sp_executesql @Sql;

SELECT name,
       CASE WHEN pvt_key_last_backup_date IS NOT NULL
            THEN 1 ELSE 0 END AS PrivateKeyBackedUp
FROM sys.certificates;
GO

-- ==============================================================
-- 6. Signing a procedure with a certificate
-- ==============================================================

DROP USER IF EXISTS nb_analyst31;
CREATE USER nb_analyst31 WITHOUT LOGIN;
GO

CREATE OR ALTER PROCEDURE dbo.usp_LoanCountByStatus
    @BranchID INT
AS
BEGIN
    SET NOCOUNT ON;
    EXEC sys.sp_executesql
        N'SELECT LoanStatus, COUNT(*) AS Loans
          FROM dbo.Loan
          WHERE BranchID = @b
          GROUP BY LoanStatus
          ORDER BY LoanStatus;',
        N'@b INT',
        @b = @BranchID;
END;
GO

GRANT EXECUTE ON dbo.usp_LoanCountByStatus TO nb_analyst31;
GO
-- Deliberate error 229: dynamic SQL breaks the ownership chain
EXECUTE AS USER = N'nb_analyst31';
EXEC dbo.usp_LoanCountByStatus @BranchID = 4;
REVERT;
GO
-- Safety net: make sure we are ourselves again
IF USER_NAME() = N'nb_analyst31'
    REVERT;
GO
-- Sign the procedure and give the certificate user SELECT on dbo.Loan
CREATE CERTIFICATE NorthbridgeSigningCert
    WITH SUBJECT = N'Signs Northbridge reporting procedures',
    EXPIRY_DATE = '20271231';

ADD SIGNATURE TO dbo.usp_LoanCountByStatus
    BY CERTIFICATE NorthbridgeSigningCert;

CREATE USER NorthbridgeSigningUser
    FROM CERTIFICATE NorthbridgeSigningCert;

GRANT SELECT ON dbo.Loan TO NorthbridgeSigningUser;
GO

EXECUTE AS USER = N'nb_analyst31';
EXEC dbo.usp_LoanCountByStatus @BranchID = 4;
REVERT;
GO
-- The signature in the catalogue
SELECT OBJECT_NAME(major_id) AS ModuleName, crypt_type_desc
FROM sys.crypt_properties
WHERE major_id = OBJECT_ID(N'dbo.usp_LoanCountByStatus');
GO

-- ==============================================================
-- 7. Transparent Data Encryption and Always Encrypted
-- ==============================================================

USE master;
GO
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys
               WHERE name = N'##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'Nb#MasterDmk2026!';

CREATE CERTIFICATE NorthbridgeTDECert
    WITH SUBJECT = N'Northbridge TDE certificate',
    EXPIRY_DATE = '20271231';
GO
-- Back up the TDE certificate before any database depends on it
DECLARE @Stamp NVARCHAR(15) = FORMAT(SYSDATETIME(), N'yyyyMMdd_HHmmss');
DECLARE @Cer NVARCHAR(400) = NorthbridgeLending.dbo.ufn_InstanceFile(
    N'Backup', N'NorthbridgeTDECert_' + @Stamp + N'.cer');
DECLARE @Pvk NVARCHAR(400) = NorthbridgeLending.dbo.ufn_InstanceFile(
    N'Backup', N'NorthbridgeTDECert_' + @Stamp + N'.pvk');
DECLARE @Sql NVARCHAR(MAX) =
    N'BACKUP CERTIFICATE NorthbridgeTDECert TO FILE = '''
    + REPLACE(@Cer, N'''', N'''''')
    + N''' WITH PRIVATE KEY (FILE = '''
    + REPLACE(@Pvk, N'''', N'''''')
    + N''', ENCRYPTION BY PASSWORD = ''Nb#TdeFile2026!'');';
EXEC sys.sp_executesql @Sql;     -- runs in master, where the certificate is
GO

CREATE DATABASE NorthbridgePractice;
GO
USE NorthbridgeLending;
GO
SELECT *
INTO NorthbridgePractice.dbo.Customer
FROM dbo.Customer;
GO
USE NorthbridgePractice;
GO
CREATE DATABASE ENCRYPTION KEY
    WITH ALGORITHM = AES_256
    ENCRYPTION BY SERVER CERTIFICATE NorthbridgeTDECert;
GO
USE NorthbridgeLending;
GO
ALTER DATABASE NorthbridgePractice SET ENCRYPTION ON;
GO
-- Wait until the background encryption has finished (state 3)
DECLARE @Waited INT = 0;
WHILE @Waited < 60 AND NOT EXISTS (
    SELECT 1 FROM sys.dm_database_encryption_keys
    WHERE database_id = DB_ID(N'NorthbridgePractice')
      AND encryption_state = 3)          -- 3 = encrypted
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @Waited += 1;
END;

SELECT DB_NAME(database_id) AS DatabaseName,
       encryption_state, key_algorithm, key_length, encryptor_type
FROM sys.dm_database_encryption_keys
WHERE database_id = DB_ID(N'NorthbridgePractice');

SELECT COUNT(*) AS Customers
FROM NorthbridgePractice.dbo.Customer;
GO
-- Switch encryption off and wait for decryption (state 1)
ALTER DATABASE NorthbridgePractice SET ENCRYPTION OFF;
GO
DECLARE @Waited INT = 0;
WHILE @Waited < 60 AND NOT EXISTS (
    SELECT 1 FROM sys.dm_database_encryption_keys
    WHERE database_id = DB_ID(N'NorthbridgePractice')
      AND encryption_state = 1)          -- 1 = unencrypted
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @Waited += 1;
END;

SELECT DB_NAME(database_id) AS DatabaseName, encryption_state
FROM sys.dm_database_encryption_keys
WHERE database_id = DB_ID(N'NorthbridgePractice');
GO
-- Remove the practice database, the TDE certificate, and the master
-- key of master when no certificate or key of master uses it
DROP DATABASE IF EXISTS NorthbridgePractice;
GO
USE master;
GO
IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'NorthbridgeTDECert')
    DROP CERTIFICATE NorthbridgeTDECert;
GO
IF EXISTS (SELECT 1 FROM sys.symmetric_keys
           WHERE name = N'##MS_DatabaseMasterKey##')
   AND NOT EXISTS (SELECT 1 FROM sys.certificates
                   WHERE pvt_key_encryption_type = 'MK'
                     AND name NOT LIKE N'##%')
   AND NOT EXISTS (SELECT 1 FROM sys.asymmetric_keys
                   WHERE pvt_key_encryption_type = 'MK'
                     AND name NOT LIKE N'##%')
   AND NOT EXISTS (SELECT 1 FROM sys.symmetric_keys
                   WHERE name NOT LIKE N'##%')
    DROP MASTER KEY;
GO
USE NorthbridgeLending;
GO

-- Always Encrypted needs client drivers and an external key store:
-- set it up with the SSMS "Encrypt Columns" wizard (not run here).

-- ==============================================================
-- 8. SQL Server Audit
-- ==============================================================

USE master;
GO
DECLARE @Sql NVARCHAR(MAX) =
    N'CREATE SERVER AUDIT NorthbridgeAudit TO FILE (FILEPATH = '''
    + REPLACE(NorthbridgeLending.dbo.ufn_InstanceFile(N'Log', N''),
              N'''', N'''''')
    + N''', MAXSIZE = 10 MB) WITH (QUEUE_DELAY = 1000, '
    + N'ON_FAILURE = CONTINUE);';
EXEC sys.sp_executesql @Sql;
GO
ALTER SERVER AUDIT NorthbridgeAudit WITH (STATE = ON);
GO
USE NorthbridgeLending;
GO
CREATE DATABASE AUDIT SPECIFICATION NorthbridgeCustomerReads
    FOR SERVER AUDIT NorthbridgeAudit
    ADD (SELECT ON OBJECT::dbo.Customer BY public)
    WITH (STATE = ON);
GO
-- Two reads of the customer table, then the audit file
SELECT COUNT(*) AS Customers FROM dbo.Customer;

SELECT FirstName, LastName
FROM dbo.Customer
WHERE CustomerID = 1;

WAITFOR DELAY '00:00:02';          -- let the queue reach the file

DECLARE @Pattern NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Log', N'NorthbridgeAudit_*.sqlaudit');
DECLARE @Guid NVARCHAR(36) = (SELECT CAST(audit_guid AS NVARCHAR(36))
                              FROM sys.server_audits
                              WHERE name = N'NorthbridgeAudit');

SELECT action_id, succeeded, database_name, schema_name, object_name
FROM sys.fn_get_audit_file(@Pattern, DEFAULT, DEFAULT)
WHERE file_name LIKE N'%' + @Guid + N'%'    -- this audit only
  AND action_id = 'SL'
ORDER BY event_time, sequence_number;
GO
-- Remove: specification off, dropped; audit off, dropped
ALTER DATABASE AUDIT SPECIFICATION NorthbridgeCustomerReads
    WITH (STATE = OFF);
DROP DATABASE AUDIT SPECIFICATION NorthbridgeCustomerReads;
GO
USE master;     -- server audits are changed from master
GO
ALTER SERVER AUDIT NorthbridgeAudit WITH (STATE = OFF);
DROP SERVER AUDIT NorthbridgeAudit;
GO
USE NorthbridgeLending;
GO

-- ==============================================================
-- Applied example: phone numbers readable through one procedure
-- ==============================================================

-- Step 1. Encrypt the phones with an authenticator
ALTER TABLE dbo.Practice_Customer
    ADD PhoneEncrypted VARBINARY(256) NULL;
GO

OPEN SYMMETRIC KEY NorthbridgeCustomerKey
    DECRYPTION BY CERTIFICATE NorthbridgeDataCert;

UPDATE dbo.Practice_Customer
SET PhoneEncrypted = ENCRYPTBYKEY(
        KEY_GUID(N'NorthbridgeCustomerKey'), Phone,
        1, CONVERT(VARBINARY(4), CustomerID));   -- authenticator

CLOSE SYMMETRIC KEY NorthbridgeCustomerKey;

ALTER TABLE dbo.Practice_Customer
    DROP COLUMN Phone;
GO

SELECT COUNT(PhoneEncrypted) AS EncryptedPhones
FROM dbo.Practice_Customer;
GO
-- Step 2. The procedure runs as its owner
CREATE OR ALTER PROCEDURE dbo.usp_GetCustomerPhone
    @CustomerID INT
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    OPEN SYMMETRIC KEY NorthbridgeCustomerKey
        DECRYPTION BY CERTIFICATE NorthbridgeDataCert;

    SELECT CustomerID, FirstName, LastName,
           CONVERT(VARCHAR(20), DECRYPTBYKEY(PhoneEncrypted,
               1, CONVERT(VARBINARY(4), CustomerID))) AS Phone
    FROM dbo.Practice_Customer
    WHERE CustomerID = @CustomerID;

    CLOSE SYMMETRIC KEY NorthbridgeCustomerKey;
END;
GO
-- Step 3. The collections officer gets EXECUTE and nothing else
DROP USER IF EXISTS nb_collections31;
CREATE USER nb_collections31 WITHOUT LOGIN;
GRANT EXECUTE ON dbo.usp_GetCustomerPhone TO nb_collections31;
GO

EXECUTE AS USER = N'nb_collections31';
EXEC dbo.usp_GetCustomerPhone @CustomerID = 1;
SELECT HAS_PERMS_BY_NAME(N'dbo.Practice_Customer', N'OBJECT',
                         N'SELECT') AS CanSelectTable;
REVERT;
GO
-- Step 4. Move customer 3's ciphertext into customer 1's row
UPDATE pc1
SET PhoneEncrypted = pc3.PhoneEncrypted
FROM dbo.Practice_Customer AS pc1
CROSS JOIN dbo.Practice_Customer AS pc3
WHERE pc1.CustomerID = 1
  AND pc3.CustomerID = 3;

EXEC dbo.usp_GetCustomerPhone @CustomerID = 1;
GO

-- ==============================================================
-- Clean-up (step 5): every object of this chapter, keys last
-- ==============================================================

DROP PROCEDURE IF EXISTS dbo.usp_GetCustomerPhone;
DROP PROCEDURE IF EXISTS dbo.usp_LoanCountByStatus;   -- removes its signature
DROP USER IF EXISTS nb_collections31;
DROP USER IF EXISTS nb_analyst31;
DROP USER IF EXISTS NorthbridgeSigningUser;
DROP TABLE IF EXISTS dbo.Practice_Customer;
CLOSE ALL SYMMETRIC KEYS;
GO
IF EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'NorthbridgeCustomerKey')
    DROP SYMMETRIC KEY NorthbridgeCustomerKey;
IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'NorthbridgeDataCert')
    DROP CERTIFICATE NorthbridgeDataCert;
IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'NorthbridgeSigningCert')
    DROP CERTIFICATE NorthbridgeSigningCert;
IF EXISTS (SELECT 1 FROM sys.asymmetric_keys WHERE name = N'NorthbridgeSigningKey')
    DROP ASYMMETRIC KEY NorthbridgeSigningKey;
GO
IF EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
    DROP MASTER KEY;
GO
DROP FUNCTION IF EXISTS dbo.ufn_InstanceFile;
GO
-- The backup files (.cer, .pvk, .key) and the .sqlaudit files stay in
-- the default folders: delete them with the operating system when no
-- longer needed. The base tables were never changed by this chapter.
