/* SQL Server from Zero — Volume 2
   Chapter 37: BACKUP and RESTORE
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022).
   Run as a member of the sysadmin role. Writes backup files (NB37_*) to the default backup
   folder and creates the database NorthbridgeRestored, dropped again before the end.
   The base tables are never changed: every change goes to practice tables. */
USE NorthbridgeLending;
GO


-- ==============================================================
-- Start-up clean-up: objects left by an interrupted earlier run
-- ==============================================================

DROP DATABASE IF EXISTS NorthbridgeRestored;
DROP TABLE IF EXISTS dbo.Practice_Loan;
DROP TABLE IF EXISTS dbo.Practice_DrillClock;
DROP PROCEDURE IF EXISTS dbo.usp_RestoreAs;
GO

-- ==============================================================
-- 1. Why backups, and the recovery models
-- ==============================================================

SELECT name, recovery_model_desc
FROM sys.databases
WHERE name IN (N'master', N'tempdb', N'model', N'msdb',
               N'NorthbridgeLending')
ORDER BY database_id;
GO
ALTER DATABASE NorthbridgeLending SET RECOVERY SIMPLE;
GO
-- Deliberate errors 4208 and 3013: no log backup in SIMPLE recovery
BACKUP LOG NorthbridgeLending
    TO DISK = N'NB37_Wrong.trn';
GO
ALTER DATABASE NorthbridgeLending SET RECOVERY FULL;
GO
-- Deliberate errors 4214 and 3013: no full backup yet, no log chain
BACKUP LOG NorthbridgeLending
    TO DISK = N'NB37_Wrong.trn';
GO

-- ==============================================================
-- 2. Full backups: BACKUP DATABASE and its options
-- ==============================================================

-- A bare file name goes to the default backup folder
BACKUP DATABASE NorthbridgeLending
    TO DISK = N'NB37_First.bak'
    WITH FORMAT;
GO
-- Full path of a file in the default Backup, Data or Log folder
-- (chapter 31), identical on Windows, Linux and Docker on macOS
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
-- The practice table, then the "Sunday" full backup
DROP TABLE IF EXISTS dbo.Practice_Loan;

SELECT *
INTO dbo.Practice_Loan
FROM dbo.Loan;
GO

DECLARE @File NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Backup', N'NB37_Full.bak');

BACKUP DATABASE NorthbridgeLending
    TO DISK = @File
    WITH INIT,
         NAME = N'NorthbridgeLending full',
         COMPRESSION,
         CHECKSUM,
         STATS = 25;
GO

-- ==============================================================
-- 3. Differential, log and copy-only backups
-- ==============================================================

-- Monday: four Leeds loans move to Default, then the differential
UPDATE dbo.Practice_Loan
SET LoanStatus = N'Default'
WHERE BranchID = 4
  AND LoanStatus = N'Arrears';
GO

DECLARE @File NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Backup', N'NB37_Diff.bak');

BACKUP DATABASE NorthbridgeLending
    TO DISK = @File
    WITH DIFFERENTIAL, INIT,
         NAME = N'NorthbridgeLending differential',
         COMPRESSION, CHECKSUM;
GO
-- Tuesday: three Bristol loans move to Default, then a log backup
UPDATE dbo.Practice_Loan
SET LoanStatus = N'Default'
WHERE BranchID = 5
  AND LoanStatus = N'Arrears';
GO

DECLARE @File NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Backup', N'NB37_Log1.trn');

BACKUP LOG NorthbridgeLending
    TO DISK = @File
    WITH INIT,
         NAME = N'NorthbridgeLending log 1',
         COMPRESSION, CHECKSUM;
GO
-- A copy-only full backup for the auditors
DECLARE @File NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Backup', N'NB37_CopyOnly.bak');

BACKUP DATABASE NorthbridgeLending
    TO DISK = @File
    WITH COPY_ONLY, INIT,
         NAME = N'NorthbridgeLending copy-only',
         COMPRESSION, CHECKSUM;

SELECT COUNT(*) AS DefaultLoans
FROM dbo.Practice_Loan
WHERE LoanStatus = N'Default';
GO

-- ==============================================================
-- 4. Looking inside backups
-- ==============================================================

DECLARE @File NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Backup', N'NB37_Diff.bak');

RESTORE HEADERONLY FROM DISK = @File;
GO
-- The copy-only backup: BackupType 1, IsCopyOnly 1
DECLARE @File NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Backup', N'NB37_CopyOnly.bak');

RESTORE HEADERONLY FROM DISK = @File;
GO
DECLARE @File NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Backup', N'NB37_Full.bak');

RESTORE FILELISTONLY FROM DISK = @File;

RESTORE VERIFYONLY FROM DISK = @File WITH CHECKSUM;
GO
-- The bare-name backup is in the same default folder
DECLARE @File NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Backup', N'NB37_First.bak');

RESTORE VERIFYONLY FROM DISK = @File;
GO
-- History in msdb
SELECT TOP (5)
       bs.type,                     -- D full, I differential, L log
       bs.is_copy_only,
       bs.name
FROM msdb.dbo.backupset AS bs
INNER JOIN msdb.dbo.backupmediafamily AS bmf
    ON bmf.media_set_id = bs.media_set_id
WHERE bs.database_name = N'NorthbridgeLending'
ORDER BY bs.backup_set_id DESC;     -- most recent first
GO

-- ==============================================================
-- 5. Restoring under a new name: WITH MOVE
-- ==============================================================

-- Deliberate errors 1834, 3156, 3119 and 3013: no MOVE, the files
-- would overwrite those of the live database
DECLARE @File NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Backup', N'NB37_Full.bak');

RESTORE DATABASE NorthbridgeRestored
    FROM DISK = @File;
GO
-- MOVE takes literal paths: dynamic SQL, wrapped in a procedure
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

EXEC dbo.usp_RestoreAs
    @BackupFile = N'NB37_Full.bak',
    @NewName    = N'NorthbridgeRestored';

SELECT COUNT(*) AS DefaultLoans
FROM NorthbridgeRestored.dbo.Practice_Loan
WHERE LoanStatus = N'Default';
GO
DROP DATABASE IF EXISTS NorthbridgeRestored;
GO

-- ==============================================================
-- 6. Restore sequences: NORECOVERY and RECOVERY
-- ==============================================================

EXEC dbo.usp_RestoreAs
    @BackupFile = N'NB37_Full.bak',
    @NewName    = N'NorthbridgeRestored',
    @Recovery   = 0;                         -- more to come

SELECT name, state_desc
FROM sys.databases
WHERE name = N'NorthbridgeRestored';
GO

DECLARE @Diff NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Backup', N'NB37_Diff.bak');
DECLARE @Log1 NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Backup', N'NB37_Log1.trn');

RESTORE DATABASE NorthbridgeRestored
    FROM DISK = @Diff
    WITH NORECOVERY;                        -- still more to come

RESTORE LOG NorthbridgeRestored
    FROM DISK = @Log1
    WITH RECOVERY;                          -- last file: open it

SELECT name, state_desc
FROM sys.databases
WHERE name = N'NorthbridgeRestored';

SELECT COUNT(*) AS DefaultLoans
FROM NorthbridgeRestored.dbo.Practice_Loan
WHERE LoanStatus = N'Default';
GO
DROP DATABASE IF EXISTS NorthbridgeRestored;
GO

-- ==============================================================
-- 7. Point-in-time restore: STOPATMARK, STOPAT and the tail-log backup
-- ==============================================================

-- Wednesday: a marked rate change, then a mistaken DELETE
BEGIN TRANSACTION RateReview WITH MARK 'RateReview';
    UPDATE dbo.Practice_Loan
    SET InterestRate = InterestRate + 0.25
    WHERE ProductCode = 'MTG-TRK';
COMMIT TRANSACTION RateReview;

DELETE FROM dbo.Practice_Loan
WHERE BranchID = 7;                 -- the mistake
GO

DECLARE @Log2 NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Backup', N'NB37_Log2.trn');

BACKUP LOG NorthbridgeLending
    TO DISK = @Log2
    WITH INIT, NAME = N'NorthbridgeLending log 2',
         COMPRESSION, CHECKSUM;
GO
-- Restore the whole chain and stop at the mark
EXEC dbo.usp_RestoreAs
    @BackupFile = N'NB37_Full.bak',
    @NewName    = N'NorthbridgeRestored',
    @Recovery   = 0;
GO

DECLARE @Diff NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Backup', N'NB37_Diff.bak');
DECLARE @Log1 NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Backup', N'NB37_Log1.trn');
DECLARE @Log2 NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Backup', N'NB37_Log2.trn');

RESTORE DATABASE NorthbridgeRestored FROM DISK = @Diff
    WITH NORECOVERY;
RESTORE LOG NorthbridgeRestored FROM DISK = @Log1
    WITH NORECOVERY;
RESTORE LOG NorthbridgeRestored FROM DISK = @Log2
    WITH STOPATMARK = 'RateReview', RECOVERY;

SELECT (SELECT COUNT(*) FROM NorthbridgeRestored.dbo.Practice_Loan
        WHERE BranchID = 7)                       AS RestoredCardiff,
       (SELECT COUNT(*) FROM dbo.Practice_Loan
        WHERE BranchID = 7)                       AS LiveCardiff,
       (SELECT InterestRate
        FROM NorthbridgeRestored.dbo.Practice_Loan
        WHERE LoanID = 10009)                     AS RestoredRate;
GO
DROP DATABASE IF EXISTS NorthbridgeRestored;
GO

-- NOT RUN BY THE AUTOMATED TEST: a tail-log backup of NorthbridgeLending
-- leaves it in the RESTORING state (or reads a damaged database), which
-- would stop the rest of this script. Run it only on a database you are
-- about to restore, from master.
--
-- USE master;
-- GO
-- DECLARE @Tail NVARCHAR(400) =
--     NorthbridgeLending.dbo.ufn_InstanceFile(N'Backup', N'NB37_Tail.trn');
-- -- Database online: back up the tail and stop all changes
-- BACKUP LOG NorthbridgeLending
--     TO DISK = @Tail
--     WITH INIT, NORECOVERY;
-- -- Database damaged and unable to start: back up the log only
-- -- BACKUP LOG NorthbridgeLending
-- --     TO DISK = @Tail
-- --     WITH INIT, NO_TRUNCATE;
-- GO
-- -- The database is now RESTORING; to bring it back without a restore:
-- RESTORE DATABASE NorthbridgeLending WITH RECOVERY;
-- GO
-- USE NorthbridgeLending;
-- GO

-- ==============================================================
-- Applied example: the backup strategy and a restore drill
-- ==============================================================

-- Step 2. Sunday: a fresh practice table and the full backup
DROP TABLE IF EXISTS dbo.Practice_Loan;

SELECT *
INTO dbo.Practice_Loan
FROM dbo.Loan;

DROP TABLE IF EXISTS dbo.Practice_DrillClock;

CREATE TABLE dbo.Practice_DrillClock (
    Label     NVARCHAR(40) NOT NULL PRIMARY KEY,
    StampedAt DATETIME     NOT NULL
);
GO

DECLARE @File NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Backup', N'NB37_DrillFull.bak');

BACKUP DATABASE NorthbridgeLending TO DISK = @File
    WITH INIT, NAME = N'Drill full', COMPRESSION, CHECKSUM;
GO
-- Step 3. Monday's change and differential; Tuesday's payment,
-- the time stamp, and the accident
UPDATE dbo.Practice_Loan
SET LoanStatus = N'Default'
WHERE BranchID = 4
  AND LoanStatus = N'Arrears';
GO

DECLARE @File NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Backup', N'NB37_DrillDiff.bak');

BACKUP DATABASE NorthbridgeLending TO DISK = @File
    WITH DIFFERENTIAL, INIT, NAME = N'Drill differential',
         COMPRESSION, CHECKSUM;
GO

UPDATE dbo.Practice_Loan
SET OutstandingBalance = OutstandingBalance - 500.00
WHERE LoanID = 10009;

WAITFOR DELAY '00:00:01';
INSERT INTO dbo.Practice_DrillClock (Label, StampedAt)
VALUES (N'Before accident', SYSDATETIME());
WAITFOR DELAY '00:00:01';

UPDATE dbo.Practice_Loan
SET OutstandingBalance = 0;         -- the accident: no WHERE
GO

DECLARE @File NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Backup', N'NB37_DrillLog.trn');

BACKUP LOG NorthbridgeLending TO DISK = @File
    WITH INIT, NAME = N'Drill log', COMPRESSION, CHECKSUM;
GO
-- Step 4. Restore to the moment before the accident
EXEC dbo.usp_RestoreAs
    @BackupFile = N'NB37_DrillFull.bak',
    @NewName    = N'NorthbridgeRestored',
    @Recovery   = 0;
GO

DECLARE @Diff NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Backup', N'NB37_DrillDiff.bak');
DECLARE @Log NVARCHAR(400) =
    dbo.ufn_InstanceFile(N'Backup', N'NB37_DrillLog.trn');
DECLARE @StopAt DATETIME = (SELECT StampedAt
                            FROM dbo.Practice_DrillClock
                            WHERE Label = N'Before accident');

RESTORE DATABASE NorthbridgeRestored FROM DISK = @Diff
    WITH NORECOVERY;
RESTORE LOG NorthbridgeRestored FROM DISK = @Log
    WITH STOPAT = @StopAt, RECOVERY;
GO
-- Step 5. Compare, then repair the live table from the restored copy
SELECT (SELECT SUM(OutstandingBalance)
        FROM NorthbridgeRestored.dbo.Practice_Loan) AS RestoredTotal,
       (SELECT SUM(OutstandingBalance)
        FROM dbo.Practice_Loan)                     AS LiveTotal,
       (SELECT COUNT(*)
        FROM NorthbridgeRestored.dbo.Practice_Loan
        WHERE LoanStatus = N'Default')  AS RestoredDefaults;

UPDATE live
SET OutstandingBalance = r.OutstandingBalance
FROM dbo.Practice_Loan AS live
INNER JOIN NorthbridgeRestored.dbo.Practice_Loan AS r
    ON r.LoanID = live.LoanID;

SELECT (SELECT SUM(OutstandingBalance)
        FROM dbo.Practice_Loan)       AS LiveTotal,
       (SELECT OutstandingBalance
        FROM dbo.Practice_Loan
        WHERE LoanID = 10009)         AS Loan10009;
GO
-- Step 6. Drop the restored database
DROP DATABASE IF EXISTS NorthbridgeRestored;
GO

-- ==============================================================
-- Clean-up: remove every object created in this chapter
-- ==============================================================

DROP DATABASE IF EXISTS NorthbridgeRestored;
DROP TABLE IF EXISTS dbo.Practice_DrillClock;
DROP TABLE IF EXISTS dbo.Practice_Loan;
DROP PROCEDURE IF EXISTS dbo.usp_RestoreAs;
DROP FUNCTION IF EXISTS dbo.ufn_InstanceFile;
GO
-- NorthbridgeLending stays in FULL recovery, its default (copied from
-- model). The NB37_* backup files stay in the default backup folder:
-- delete them with the operating system when no longer needed.
