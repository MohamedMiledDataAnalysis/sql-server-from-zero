/* SQL Server from Zero — Volume 2
   Chapter 37: BACKUP and RESTORE — solutions to the exercises
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022).
   Run as a member of the sysadmin role. Writes backup files (NB37_Ex*) to the default backup
   folder and creates NorthbridgeRestored, dropped again by each exercise. Creates its own
   helper function and procedure, so it runs after the chapter script or on its own. */
USE NorthbridgeLending;
GO


-- ==============================================================
-- Setup: clean-up of an interrupted run, and the helpers of the
-- chapter (dbo.ufn_InstanceFile, dbo.usp_RestoreAs)
-- ==============================================================

DROP DATABASE IF EXISTS NorthbridgeRestored;
DROP TABLE IF EXISTS dbo.Practice_Product;
DROP TABLE IF EXISTS dbo.Practice_Loan;
GO
-- The exercises need FULL recovery (the default copied from model)
ALTER DATABASE NorthbridgeLending SET RECOVERY FULL;
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
CREATE OR ALTER PROCEDURE dbo.usp_RestoreAs
    @BackupFile NVARCHAR(200),         -- file in the backup folder
    @NewName    SYSNAME,               -- database to create
    @FileNumber INT = 1,               -- backup set in the file
    @Recovery   BIT = 1                -- 0 = NORECOVERY
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Path NVARCHAR(400) =
        dbo.ufn_InstanceFile(N'Backup', @BackupFile);
    DECLARE @Mdf NVARCHAR(400) =
        dbo.ufn_InstanceFile(N'Data', @NewName + N'.mdf');
    DECLARE @Ldf NVARCHAR(400) =
        dbo.ufn_InstanceFile(N'Log', @NewName + N'_log.ldf');
    DECLARE @Sql NVARCHAR(MAX) =
        N'RESTORE DATABASE ' + QUOTENAME(@NewName)
        + N' FROM DISK = @p WITH FILE = @n, '
        + N'MOVE N''NorthbridgeLending'' TO N'''
        + REPLACE(@Mdf, N'''', N'''''') + N''', '
        + N'MOVE N''NorthbridgeLending_log'' TO N'''
        + REPLACE(@Ldf, N'''', N'''''') + N''', '
        + CASE WHEN @Recovery = 1 THEN N'RECOVERY;'
               ELSE N'NORECOVERY;' END;

    EXEC sys.sp_executesql @Sql,
        N'@p NVARCHAR(400), @n INT',
        @p = @Path, @n = @FileNumber;
END;
GO

-- ==============================================================
-- Correction 37.1
-- ==============================================================

SELECT name, recovery_model_desc
FROM sys.databases
WHERE name IN (N'master', N'msdb', N'tempdb', N'NorthbridgeLending')
ORDER BY name;
GO

-- ==============================================================
-- Correction 37.2
-- ==============================================================

DECLARE @File NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Backup', N'NB37_Ex2.bak');

BACKUP DATABASE NorthbridgeLending
    TO DISK = @File
    WITH INIT,                      -- overwrite earlier sets
         COMPRESSION,
         CHECKSUM,
         NAME = N'Exercise 37.2';

RESTORE VERIFYONLY FROM DISK = @File
    WITH CHECKSUM;                  -- recompute the checksums
GO

-- ==============================================================
-- Correction 37.3
-- ==============================================================

DECLARE @File NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Backup', N'NB37_Ex2.bak');

RESTORE FILELISTONLY FROM DISK = @File;
GO

-- ==============================================================
-- Correction 37.4
-- ==============================================================

DROP TABLE IF EXISTS dbo.Practice_Product;

SELECT *
INTO dbo.Practice_Product
FROM dbo.Product;
GO

DECLARE @File NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Backup', N'NB37_Ex4.bak');

BACKUP DATABASE NorthbridgeLending TO DISK = @File
    WITH INIT, COMPRESSION, NAME = N'Ex4 full';         -- position 1

UPDATE dbo.Practice_Product
SET BaseRate = BaseRate + 0.10;

BACKUP DATABASE NorthbridgeLending TO DISK = @File
    WITH DIFFERENTIAL, NOINIT, COMPRESSION,
         NAME = N'Ex4 differential';                    -- position 2

DELETE FROM dbo.Practice_Product
WHERE ProductCode = 'PL-CONS';

BACKUP LOG NorthbridgeLending TO DISK = @File
    WITH NOINIT, COMPRESSION, NAME = N'Ex4 log';        -- position 3

RESTORE HEADERONLY FROM DISK = @File;
GO

-- ==============================================================
-- Correction 37.5
-- ==============================================================

SELECT TOP (3)
       bs.position,
       bs.type,
       bs.name
FROM msdb.dbo.backupset AS bs
INNER JOIN msdb.dbo.backupmediafamily AS bmf
    ON bmf.media_set_id = bs.media_set_id
WHERE bmf.physical_device_name LIKE N'%NB37_Ex4.bak'
ORDER BY bs.backup_set_id DESC;
GO

-- ==============================================================
-- Correction 37.6
-- ==============================================================

EXEC dbo.usp_RestoreAs
    @BackupFile = N'NB37_Ex4.bak',
    @NewName    = N'NorthbridgeRestored',
    @FileNumber = 1;

SELECT N'Branch' AS TableName,
       (SELECT COUNT(*) FROM dbo.Branch) AS LiveRows,
       (SELECT COUNT(*) FROM NorthbridgeRestored.dbo.Branch)
           AS RestoredRows
UNION ALL
SELECT N'Collateral', (SELECT COUNT(*) FROM dbo.Collateral),
       (SELECT COUNT(*) FROM NorthbridgeRestored.dbo.Collateral)
UNION ALL
SELECT N'CreditRating', (SELECT COUNT(*) FROM dbo.CreditRating),
       (SELECT COUNT(*) FROM NorthbridgeRestored.dbo.CreditRating)
UNION ALL
SELECT N'Customer', (SELECT COUNT(*) FROM dbo.Customer),
       (SELECT COUNT(*) FROM NorthbridgeRestored.dbo.Customer)
UNION ALL
SELECT N'Loan', (SELECT COUNT(*) FROM dbo.Loan),
       (SELECT COUNT(*) FROM NorthbridgeRestored.dbo.Loan)
UNION ALL
SELECT N'LoanOfficer', (SELECT COUNT(*) FROM dbo.LoanOfficer),
       (SELECT COUNT(*) FROM NorthbridgeRestored.dbo.LoanOfficer)
UNION ALL
SELECT N'Payment', (SELECT COUNT(*) FROM dbo.Payment),
       (SELECT COUNT(*) FROM NorthbridgeRestored.dbo.Payment)
UNION ALL
SELECT N'Product', (SELECT COUNT(*) FROM dbo.Product),
       (SELECT COUNT(*) FROM NorthbridgeRestored.dbo.Product);
GO
DROP DATABASE IF EXISTS NorthbridgeRestored;
GO

-- ==============================================================
-- Correction 37.7
-- ==============================================================

-- State at the differential backup (positions 1 and 2)
EXEC dbo.usp_RestoreAs
    @BackupFile = N'NB37_Ex4.bak',
    @NewName    = N'NorthbridgeRestored',
    @FileNumber = 1,
    @Recovery   = 0;
GO
DECLARE @File NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Backup', N'NB37_Ex4.bak');

RESTORE DATABASE NorthbridgeRestored FROM DISK = @File
    WITH FILE = 2, RECOVERY;              -- stop at the differential

SELECT COUNT(*) AS Products,
       MAX(CASE WHEN ProductCode = 'MTG-FIX2' THEN BaseRate END)
           AS Fix2Rate
FROM NorthbridgeRestored.dbo.Practice_Product;
GO
DROP DATABASE IF EXISTS NorthbridgeRestored;
GO
-- State at the log backup (positions 1, 2 and 3)
EXEC dbo.usp_RestoreAs
    @BackupFile = N'NB37_Ex4.bak',
    @NewName    = N'NorthbridgeRestored',
    @FileNumber = 1,
    @Recovery   = 0;
GO
DECLARE @File NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Backup', N'NB37_Ex4.bak');

RESTORE DATABASE NorthbridgeRestored FROM DISK = @File
    WITH FILE = 2, NORECOVERY;
RESTORE LOG NorthbridgeRestored FROM DISK = @File
    WITH FILE = 3, RECOVERY;              -- up to the log backup

SELECT COUNT(*) AS Products,
       MAX(CASE WHEN ProductCode = 'MTG-FIX2' THEN BaseRate END)
           AS Fix2Rate
FROM NorthbridgeRestored.dbo.Practice_Product;
GO
DROP DATABASE IF EXISTS NorthbridgeRestored;
GO

-- ==============================================================
-- Correction 37.8
-- ==============================================================

DROP TABLE IF EXISTS dbo.Practice_Loan;

SELECT *
INTO dbo.Practice_Loan
FROM dbo.Loan;
GO
DECLARE @Full NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Backup', N'NB37_Ex8.bak');
DECLARE @Log NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Backup', N'NB37_Ex8.trn');

BACKUP DATABASE NorthbridgeLending TO DISK = @Full
    WITH INIT, COMPRESSION, CHECKSUM;

BEGIN TRANSACTION PurgeRepaid WITH MARK 'PurgeRepaid';
    DELETE FROM dbo.Practice_Loan
    WHERE BranchID = 8
      AND LoanStatus = N'Repaid';
COMMIT TRANSACTION PurgeRepaid;

BACKUP LOG NorthbridgeLending TO DISK = @Log
    WITH INIT, COMPRESSION, CHECKSUM;
GO
EXEC dbo.usp_RestoreAs
    @BackupFile = N'NB37_Ex8.bak',
    @NewName    = N'NorthbridgeRestored',
    @Recovery   = 0;
GO
DECLARE @Log NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Backup', N'NB37_Ex8.trn');

RESTORE LOG NorthbridgeRestored FROM DISK = @Log
    WITH STOPBEFOREMARK = 'PurgeRepaid', RECOVERY;

SELECT (SELECT COUNT(*) FROM dbo.Practice_Loan
        WHERE BranchID = 8 AND LoanStatus = N'Repaid') AS LiveRepaid,
       (SELECT COUNT(*) FROM NorthbridgeRestored.dbo.Practice_Loan
        WHERE BranchID = 8 AND LoanStatus = N'Repaid')
           AS RestoredRepaid;
GO
DROP DATABASE IF EXISTS NorthbridgeRestored;
GO

-- ==============================================================
-- Clean-up: remove every object created by the exercises
-- ==============================================================

DROP DATABASE IF EXISTS NorthbridgeRestored;
DROP TABLE IF EXISTS dbo.Practice_Product;
DROP TABLE IF EXISTS dbo.Practice_Loan;
DROP PROCEDURE IF EXISTS dbo.usp_RestoreAs;
DROP FUNCTION IF EXISTS dbo.ufn_InstanceFile;
GO
-- NorthbridgeLending stays in FULL recovery (its default). The NB37_Ex*
-- backup files stay in the default backup folder.
