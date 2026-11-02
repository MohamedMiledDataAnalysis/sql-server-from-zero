/* SQL Server from Zero — Volume 2
   Chapter 31: Certificates, keys, encryption and auditing — solutions to the exercises
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022).
   Run as a member of the sysadmin role. Creates a server audit (exercise 31.8) and removes
   it at the end; creates its own keys, so it runs after the chapter script or on its own. */
USE NorthbridgeLending;
GO


-- ==============================================================
-- Start-up clean-up: objects left by an interrupted earlier run
-- ==============================================================

IF EXISTS (SELECT 1 FROM sys.database_audit_specifications
           WHERE name = N'NorthbridgeLoanReads')
BEGIN
    ALTER DATABASE AUDIT SPECIFICATION NorthbridgeLoanReads
        WITH (STATE = OFF);
    DROP DATABASE AUDIT SPECIFICATION NorthbridgeLoanReads;
END;
GO
IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = N'NorthbridgeLoanAudit')
BEGIN
    ALTER SERVER AUDIT NorthbridgeLoanAudit WITH (STATE = OFF);
    DROP SERVER AUDIT NorthbridgeLoanAudit;
END;
GO
DROP PROCEDURE IF EXISTS dbo.usp_BranchExposure;
DROP USER IF EXISTS nb_risk31;
DROP USER IF EXISTS NorthbridgeExposureUser;
DROP TABLE IF EXISTS dbo.Practice_Income;
DROP TABLE IF EXISTS dbo.Practice_Branch;
CLOSE ALL SYMMETRIC KEYS;
GO
IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'NorthbridgeExposureCert')
    DROP CERTIFICATE NorthbridgeExposureCert;
IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'NorthbridgeReportCert')
    DROP CERTIFICATE NorthbridgeReportCert;
GO

-- ==============================================================
-- Exercise setup: the master key, certificate and symmetric key
-- of sections 1 to 3, and the path function of section 5
-- ==============================================================

IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys
               WHERE name = N'##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'Nb#MasterKey2026!';
GO
IF NOT EXISTS (SELECT 1 FROM sys.certificates
               WHERE name = N'NorthbridgeDataCert')
    CREATE CERTIFICATE NorthbridgeDataCert
        WITH SUBJECT = N'Northbridge customer data',
        EXPIRY_DATE = '20271231';
GO
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys
               WHERE name = N'NorthbridgeCustomerKey')
    CREATE SYMMETRIC KEY NorthbridgeCustomerKey
        WITH ALGORITHM = AES_256
        ENCRYPTION BY CERTIFICATE NorthbridgeDataCert;
GO
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

-- ==============================================================
-- Correction 31.1
-- ==============================================================

SELECT N'CERTIFICATE' AS KeyKind,
       name           AS KeyName,
       CAST(NULL AS NVARCHAR(60)) AS Algorithm  -- no algorithm column
FROM sys.certificates
UNION ALL
SELECT N'ASYMMETRIC KEY', name, algorithm_desc
FROM sys.asymmetric_keys
UNION ALL
SELECT N'SYMMETRIC KEY', name, algorithm_desc
FROM sys.symmetric_keys
ORDER BY KeyKind, KeyName;
GO

-- ==============================================================
-- Correction 31.2
-- ==============================================================

SELECT CustomerID,
       LEFT(CONVERT(VARCHAR(66),
            HASHBYTES('SHA2_256', Email), 1), 18) AS HashStart,
       DATALENGTH(HASHBYTES('SHA2_256', Email))  AS HashBytes
FROM dbo.Customer
WHERE CustomerID <= 3
ORDER BY CustomerID;
GO

-- ==============================================================
-- Correction 31.3
-- ==============================================================

CREATE CERTIFICATE NorthbridgeReportCert
    WITH SUBJECT = N'Northbridge monthly reports',
    EXPIRY_DATE = '20270630';

SELECT name, subject, expiry_date,
       pvt_key_encryption_type_desc AS PrivateKeyProtection
FROM sys.certificates
WHERE name = N'NorthbridgeReportCert';

DROP CERTIFICATE NorthbridgeReportCert;
GO

-- ==============================================================
-- Correction 31.4
-- ==============================================================

DROP TABLE IF EXISTS dbo.Practice_Income;

CREATE TABLE dbo.Practice_Income (
    CustomerID      INT            NOT NULL PRIMARY KEY,
    IncomeEncrypted VARBINARY(256) NULL
);
GO

OPEN SYMMETRIC KEY NorthbridgeCustomerKey
    DECRYPTION BY CERTIFICATE NorthbridgeDataCert;

INSERT INTO dbo.Practice_Income (CustomerID, IncomeEncrypted)
SELECT CustomerID,
       ENCRYPTBYKEY(KEY_GUID(N'NorthbridgeCustomerKey'),
                    CONVERT(VARCHAR(20), AnnualIncome))  -- text first
FROM dbo.Customer
WHERE HomeBranchID = 8;

SELECT COUNT(*) AS Customers,
       SUM(CONVERT(DECIMAL(12,2),             -- back to a number
           CONVERT(VARCHAR(20), DECRYPTBYKEY(IncomeEncrypted))))
           AS TotalIncome
FROM dbo.Practice_Income;

CLOSE SYMMETRIC KEY NorthbridgeCustomerKey;
GO

-- ==============================================================
-- Correction 31.5
-- ==============================================================

CLOSE ALL SYMMETRIC KEYS;              -- start from a closed key

SELECT COUNT(DECRYPTBYKEY(IncomeEncrypted)) AS DecryptedClosed
FROM dbo.Practice_Income;

OPEN SYMMETRIC KEY NorthbridgeCustomerKey
    DECRYPTION BY CERTIFICATE NorthbridgeDataCert;

SELECT COUNT(DECRYPTBYKEY(IncomeEncrypted)) AS DecryptedOpen
FROM dbo.Practice_Income;

CLOSE SYMMETRIC KEY NorthbridgeCustomerKey;
GO

-- ==============================================================
-- Correction 31.6
-- ==============================================================

DROP TABLE IF EXISTS dbo.Practice_Branch;

SELECT *
INTO dbo.Practice_Branch
FROM dbo.Branch;

UPDATE dbo.Practice_Branch
SET BranchName = N'Leeds Wellington Place'
WHERE BranchID = 4;

UPDATE dbo.Practice_Branch
SET Region = N'South Wales'
WHERE BranchID = 7;

SELECT b.BranchID
FROM dbo.Branch AS b
INNER JOIN dbo.Practice_Branch AS p
    ON p.BranchID = b.BranchID
WHERE HASHBYTES('SHA2_256',
          CONCAT_WS(N'|', b.BranchID, b.BranchName, b.City,
                    b.Region, b.OpenedDate))
   <> HASHBYTES('SHA2_256',
          CONCAT_WS(N'|', p.BranchID, p.BranchName, p.City,
                    p.Region, p.OpenedDate))
ORDER BY b.BranchID;
GO

-- ==============================================================
-- Correction 31.7
-- ==============================================================

DROP USER IF EXISTS nb_risk31;
CREATE USER nb_risk31 WITHOUT LOGIN;
GO

CREATE OR ALTER PROCEDURE dbo.usp_BranchExposure
    @BranchID INT
AS
BEGIN
    SET NOCOUNT ON;
    EXEC sys.sp_executesql
        N'SELECT LoanStatus, COUNT(*) AS Loans,
                 SUM(OutstandingBalance) AS Balance
          FROM dbo.Loan
          WHERE BranchID = @b
          GROUP BY LoanStatus
          ORDER BY LoanStatus;',
        N'@b INT', @b = @BranchID;
END;
GO

CREATE CERTIFICATE NorthbridgeExposureCert
    WITH SUBJECT = N'Signs dbo.usp_BranchExposure',
    EXPIRY_DATE = '20271231';
ADD SIGNATURE TO dbo.usp_BranchExposure
    BY CERTIFICATE NorthbridgeExposureCert;
CREATE USER NorthbridgeExposureUser
    FROM CERTIFICATE NorthbridgeExposureCert;
GRANT SELECT ON dbo.Loan TO NorthbridgeExposureUser;  -- the cert user
GRANT EXECUTE ON dbo.usp_BranchExposure TO nb_risk31; -- the person
GO

EXECUTE AS USER = N'nb_risk31';
EXEC dbo.usp_BranchExposure @BranchID = 8;
REVERT;
GO

CREATE OR ALTER PROCEDURE dbo.usp_BranchExposure
    @BranchID INT
AS
BEGIN
    -- exposure per status for one branch (comment added)
    SET NOCOUNT ON;
    EXEC sys.sp_executesql
        N'SELECT LoanStatus, COUNT(*) AS Loans,
                 SUM(OutstandingBalance) AS Balance
          FROM dbo.Loan
          WHERE BranchID = @b
          GROUP BY LoanStatus
          ORDER BY LoanStatus;',
        N'@b INT', @b = @BranchID;
END;
GO

SELECT COUNT(*) AS Signatures
FROM sys.crypt_properties
WHERE major_id = OBJECT_ID(N'dbo.usp_BranchExposure');
GO

-- ==============================================================
-- Correction 31.8
-- ==============================================================

USE master;
GO
DECLARE @Sql NVARCHAR(MAX) =
    N'CREATE SERVER AUDIT NorthbridgeLoanAudit TO FILE (FILEPATH = '''
    + REPLACE(NorthbridgeLending.dbo.ufn_InstanceFile(N'Log', N''),
              N'''', N'''''')
    + N''', MAXSIZE = 10 MB) WITH (QUEUE_DELAY = 1000);';
EXEC sys.sp_executesql @Sql;
GO
ALTER SERVER AUDIT NorthbridgeLoanAudit WITH (STATE = ON);
GO
USE NorthbridgeLending;
GO
CREATE DATABASE AUDIT SPECIFICATION NorthbridgeLoanReads
    FOR SERVER AUDIT NorthbridgeLoanAudit
    ADD (SELECT ON OBJECT::dbo.Loan BY public)
    WITH (STATE = ON);
GO

SELECT COUNT(*) AS Loans FROM dbo.Loan;
SELECT MAX(Principal) AS LargestLoan FROM dbo.Loan;

WAITFOR DELAY '00:00:02';

DECLARE @Pattern NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Log', N'NorthbridgeLoanAudit_*.sqlaudit');
DECLARE @Guid NVARCHAR(36) = (SELECT CAST(audit_guid AS NVARCHAR(36))
                              FROM sys.server_audits
                              WHERE name = N'NorthbridgeLoanAudit');

SELECT COUNT(*) AS LoanReads
FROM sys.fn_get_audit_file(@Pattern, DEFAULT, DEFAULT)
WHERE file_name LIKE N'%' + @Guid + N'%'
  AND action_id = 'SL'
  AND object_name = N'Loan';
GO

ALTER DATABASE AUDIT SPECIFICATION NorthbridgeLoanReads
    WITH (STATE = OFF);
DROP DATABASE AUDIT SPECIFICATION NorthbridgeLoanReads;
GO
ALTER SERVER AUDIT NorthbridgeLoanAudit WITH (STATE = OFF);
DROP SERVER AUDIT NorthbridgeLoanAudit;
GO

-- ==============================================================
-- Clean-up: remove every object created by the exercises
-- ==============================================================

DROP PROCEDURE IF EXISTS dbo.usp_BranchExposure;   -- removes any signature
DROP USER IF EXISTS nb_risk31;
DROP USER IF EXISTS NorthbridgeExposureUser;
DROP TABLE IF EXISTS dbo.Practice_Income;
DROP TABLE IF EXISTS dbo.Practice_Branch;
CLOSE ALL SYMMETRIC KEYS;
GO
IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'NorthbridgeExposureCert')
    DROP CERTIFICATE NorthbridgeExposureCert;
IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'NorthbridgeReportCert')
    DROP CERTIFICATE NorthbridgeReportCert;
IF EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'NorthbridgeCustomerKey')
    DROP SYMMETRIC KEY NorthbridgeCustomerKey;
IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'NorthbridgeDataCert')
    DROP CERTIFICATE NorthbridgeDataCert;
GO
-- Drop the master key only if no key or certificate still needs it
IF EXISTS (SELECT 1 FROM sys.symmetric_keys
           WHERE name = N'##MS_DatabaseMasterKey##')
   AND NOT EXISTS (SELECT 1 FROM sys.certificates)
   AND NOT EXISTS (SELECT 1 FROM sys.asymmetric_keys)
   AND NOT EXISTS (SELECT 1 FROM sys.symmetric_keys
                   WHERE name <> N'##MS_DatabaseMasterKey##')
    DROP MASTER KEY;
GO
DROP FUNCTION IF EXISTS dbo.ufn_InstanceFile;
GO
-- The .sqlaudit files stay in the default log folder; the base tables
-- were never changed by the exercises.
