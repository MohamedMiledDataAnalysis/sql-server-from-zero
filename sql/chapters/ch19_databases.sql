/* SQL Server from Zero — Volume 1
   Chapter 19: Databases and filegroups
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- 1. What a database is made of
USE NorthbridgeLending;
GO
SELECT file_id,
       name,                -- logical name
       type_desc,           -- ROWS = data file, LOG = log file
       physical_name        -- full path on disk
FROM sys.database_files
ORDER BY file_id;
GO
SELECT SERVERPROPERTY('InstanceDefaultDataPath') AS DataFolder,
       SERVERPROPERTY('InstanceDefaultLogPath')  AS LogFolder;
GO

-- 2. Creating a database with CREATE DATABASE
USE master;
GO
DECLARE @DataPath NVARCHAR(260) =
    CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS NVARCHAR(260));
DECLARE @LogPath  NVARCHAR(260) =
    CAST(SERVERPROPERTY('InstanceDefaultLogPath') AS NVARCHAR(260));

DECLARE @sql NVARCHAR(MAX) = N'
CREATE DATABASE NorthbridgePractice
ON PRIMARY
(
    NAME       = NorthbridgePractice_data,
    FILENAME   = N''' + @DataPath + N'NorthbridgePractice.mdf'',
    SIZE       = 64MB,
    MAXSIZE    = 1GB,
    FILEGROWTH = 64MB
)
LOG ON
(
    NAME       = NorthbridgePractice_log,
    FILENAME   = N''' + @LogPath + N'NorthbridgePractice_log.ldf'',
    SIZE       = 32MB,
    MAXSIZE    = 512MB,
    FILEGROWTH = 32MB
);';

PRINT @sql;      -- the statement, with your folders
EXEC (@sql);
GO
USE NorthbridgePractice;
GO
SELECT file_id,
       name,
       type_desc,
       size * 8 / 1024     AS SizeMB,     -- pages -> MB
       growth * 8 / 1024   AS GrowthMB,   -- pages, if not percent
       max_size * 8 / 1024 AS MaxSizeMB
FROM sys.database_files
ORDER BY file_id;
GO

-- 3. Looking at databases: sys.databases, sys.master_files and DB_ID
SELECT name,
       state_desc,            -- ONLINE, OFFLINE, RESTORING ...
       recovery_model_desc,   -- FULL, SIMPLE, BULK_LOGGED
       user_access_desc,      -- MULTI_USER, SINGLE_USER ...
       is_read_only,
       compatibility_level
FROM sys.databases
WHERE name IN (N'NorthbridgeLending', N'NorthbridgePractice')
ORDER BY name;
GO
SELECT DB_ID(N'NorthbridgePractice') AS PracticeID,
       DB_ID(N'NoSuchDatabase')      AS MissingID;
GO
USE master;
GO
SELECT name,
       type_desc,
       size * 8 / 1024 AS SizeMB
FROM sys.master_files
WHERE database_id = DB_ID(N'NorthbridgePractice')
ORDER BY file_id;
GO

-- 4. Changing settings with ALTER DATABASE … SET
USE master;
GO
ALTER DATABASE NorthbridgePractice
SET RECOVERY SIMPLE,
    AUTO_SHRINK OFF,
    AUTO_CLOSE OFF,
    PAGE_VERIFY CHECKSUM;

SELECT name,
       recovery_model_desc,
       is_auto_shrink_on,
       is_auto_close_on,
       page_verify_option_desc
FROM sys.databases
WHERE name = N'NorthbridgePractice';
GO
USE master;
GO
ALTER DATABASE NorthbridgePractice
SET READ_ONLY WITH ROLLBACK IMMEDIATE;

-- Try to create a table in it from master (three-part name)
-- Fails on purpose with Msg 3906: NorthbridgePractice is read-only.
-- SELECT BranchID, BranchName
-- INTO NorthbridgePractice.dbo.BranchTest
-- FROM NorthbridgeLending.dbo.Branch;
GO
ALTER DATABASE NorthbridgePractice
SET READ_WRITE WITH ROLLBACK IMMEDIATE;
GO
ALTER DATABASE NorthbridgePractice SET COMPATIBILITY_LEVEL = 160;

SELECT name, compatibility_level
FROM sys.databases
WHERE name = N'NorthbridgePractice';
GO
USE master;
GO
ALTER DATABASE NorthbridgePractice MODIFY NAME = NorthbridgeSandbox;
ALTER DATABASE NorthbridgeSandbox  MODIFY NAME = NorthbridgePractice;
GO
-- Error demonstration: remove the leading -- and run these lines
-- on their own to see the error described in the book.
-- USE NorthbridgePractice;
-- GO
-- ALTER DATABASE NorthbridgePractice MODIFY NAME = NorthbridgeSandbox;
GO

-- 5. Changing files with ALTER DATABASE … MODIFY FILE
USE master;
GO
ALTER DATABASE NorthbridgePractice
MODIFY FILE (NAME = NorthbridgePractice_data, SIZE = 128MB);

ALTER DATABASE NorthbridgePractice
MODIFY FILE (NAME = NorthbridgePractice_data, FILEGROWTH = 128MB);

SELECT name,
       size * 8 / 1024   AS SizeMB,
       growth * 8 / 1024 AS GrowthMB
FROM sys.master_files
WHERE database_id = DB_ID(N'NorthbridgePractice')
  AND type_desc = N'ROWS';
GO
ALTER DATABASE NorthbridgePractice
MODIFY FILE (NAME = NorthbridgePractice_log,
             NEWNAME = NorthbridgePractice_logfile);

ALTER DATABASE NorthbridgePractice
MODIFY FILE (NAME = NorthbridgePractice_logfile,
             NEWNAME = NorthbridgePractice_log);
GO
-- Error demonstration: remove the leading -- and run these lines
-- on their own to see the error described in the book.
-- ALTER DATABASE NorthbridgePractice
-- MODIFY FILE (NAME = NorthbridgePractice_data, SIZE = 32MB);
GO

-- 6. Filegroups: ADD FILEGROUP, ADD FILE and ON <filegroup>
USE master;
GO
ALTER DATABASE NorthbridgePractice ADD FILEGROUP Archive;

DECLARE @DataPath NVARCHAR(260) =
    CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS NVARCHAR(260));

DECLARE @sql NVARCHAR(MAX) = N'
ALTER DATABASE NorthbridgePractice
ADD FILE
(
    NAME       = NorthbridgePractice_archive1,
    FILENAME   = N''' + @DataPath + N'NorthbridgePractice_archive1.ndf'',
    SIZE       = 16MB,
    FILEGROWTH = 16MB
)
TO FILEGROUP Archive;';

PRINT @sql;
EXEC (@sql);
GO
USE NorthbridgePractice;
GO
SELECT fg.name               AS FilegroupName,
       fg.is_default,
       df.name               AS FileName,
       df.size * 8 / 1024    AS SizeMB
FROM sys.filegroups AS fg
INNER JOIN sys.database_files AS df
    ON df.data_space_id = fg.data_space_id
ORDER BY fg.data_space_id, df.file_id;
GO
USE NorthbridgePractice;
GO
SELECT PaymentID, LoanID, InstalmentNumber, DueDate,
       AmountDue, PaidDate, AmountPaid, DaysLate
INTO dbo.Payment2021 ON Archive
FROM NorthbridgeLending.dbo.Payment
WHERE DueDate < '2022-01-01';
GO
SELECT t.name  AS TableName,
       fg.name AS FilegroupName
FROM sys.tables AS t
INNER JOIN sys.indexes AS i
    ON i.object_id = t.object_id
   AND i.index_id IN (0, 1)          -- the table's own storage
INNER JOIN sys.filegroups AS fg
    ON fg.data_space_id = i.data_space_id
ORDER BY t.name;
GO
ALTER DATABASE NorthbridgePractice MODIFY FILEGROUP Archive DEFAULT;

SELECT BranchID, BranchName, City
INTO dbo.Branch_Copy                 -- no ON: goes to the default
FROM NorthbridgeLending.dbo.Branch;

ALTER DATABASE NorthbridgePractice MODIFY FILEGROUP [PRIMARY] DEFAULT;
GO

-- 7. Removing files, filegroups and databases
-- Error demonstration: remove the leading -- and run these lines
-- on their own to see the error described in the book.
-- USE master;
-- GO
-- ALTER DATABASE NorthbridgePractice
-- REMOVE FILE NorthbridgePractice_archive1;
GO
USE NorthbridgePractice;
GO
DROP TABLE IF EXISTS dbo.Payment2021, dbo.Branch_Copy;

USE master;
GO
ALTER DATABASE NorthbridgePractice
REMOVE FILE NorthbridgePractice_archive1;

ALTER DATABASE NorthbridgePractice
REMOVE FILEGROUP Archive;
GO
-- Error demonstration: remove the leading -- and run these lines
-- on their own to see the error described in the book.
-- USE master;
-- GO
-- DROP DATABASE NorthbridgePractice;
GO
USE master;
GO
IF DB_ID(N'NorthbridgePractice') IS NOT NULL
BEGIN
    ALTER DATABASE NorthbridgePractice
    SET SINGLE_USER WITH ROLLBACK IMMEDIATE;

    DROP DATABASE NorthbridgePractice;
END;

SELECT COUNT(*) AS Remaining
FROM sys.databases
WHERE name = N'NorthbridgePractice';
GO

-- Applied example

-- Step 1. Create the database with three filegroups, rerunnably
USE master;
GO
IF DB_ID(N'NorthbridgePractice') IS NOT NULL
BEGIN
    ALTER DATABASE NorthbridgePractice
    SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE NorthbridgePractice;
END;

DECLARE @D NVARCHAR(260) =
    CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS NVARCHAR(260));
DECLARE @L NVARCHAR(260) =
    CAST(SERVERPROPERTY('InstanceDefaultLogPath') AS NVARCHAR(260));

DECLARE @sql NVARCHAR(MAX) = N'
CREATE DATABASE NorthbridgePractice
ON PRIMARY
( NAME = NorthbridgePractice_data,
  FILENAME = N''' + @D + N'NorthbridgePractice.mdf'',
  SIZE = 16MB, FILEGROWTH = 16MB ),
FILEGROUP CurrentData
( NAME = NorthbridgePractice_current,
  FILENAME = N''' + @D + N'NorthbridgePractice_current.ndf'',
  SIZE = 64MB, FILEGROWTH = 64MB ),
FILEGROUP HistoryData
( NAME = NorthbridgePractice_history,
  FILENAME = N''' + @D + N'NorthbridgePractice_history.ndf'',
  SIZE = 64MB, FILEGROWTH = 64MB )
LOG ON
( NAME = NorthbridgePractice_log,
  FILENAME = N''' + @L + N'NorthbridgePractice_log.ldf'',
  SIZE = 64MB, FILEGROWTH = 64MB );';

PRINT @sql;
EXEC (@sql);
GO

-- Step 2. Set the recovery model and the default filegroup
ALTER DATABASE NorthbridgePractice SET RECOVERY SIMPLE;
ALTER DATABASE NorthbridgePractice
MODIFY FILEGROUP CurrentData DEFAULT;
GO

-- Step 3. Load the data
USE NorthbridgePractice;
GO
-- Loans: default filegroup (CurrentData)
SELECT *
INTO dbo.Loan
FROM NorthbridgeLending.dbo.Loan;

-- Recent payments: default filegroup (CurrentData)
SELECT *
INTO dbo.PaymentCurrent
FROM NorthbridgeLending.dbo.Payment
WHERE DueDate >= '2025-01-01';

-- Older payments: HistoryData, named explicitly
SELECT *
INTO dbo.PaymentHistory ON HistoryData
FROM NorthbridgeLending.dbo.Payment
WHERE DueDate < '2025-01-01';
GO

-- Step 4. Report the files
SELECT df.type_desc,
       df.name                     AS FileName,
       ISNULL(fg.name, N'(log)')   AS FilegroupName,
       df.size * 8 / 1024          AS SizeMB,
       df.growth * 8 / 1024        AS GrowthMB
FROM sys.database_files AS df
LEFT JOIN sys.filegroups AS fg
    ON fg.data_space_id = df.data_space_id
ORDER BY df.type_desc DESC, df.name;
GO

-- Step 5. Report the tables, their filegroups and row counts
SELECT t.name   AS TableName,
       fg.name  AS FilegroupName,
       p.rows   AS RowCnt
FROM sys.tables AS t
INNER JOIN sys.indexes AS i
    ON i.object_id = t.object_id
   AND i.index_id IN (0, 1)
INNER JOIN sys.filegroups AS fg
    ON fg.data_space_id = i.data_space_id
INNER JOIN sys.partitions AS p
    ON p.object_id = t.object_id
   AND p.index_id  = i.index_id
ORDER BY t.name;
GO

-- Clean-up: remove the practice database (NorthbridgeLending is untouched)
USE master;
GO
IF DB_ID(N'NorthbridgePractice') IS NOT NULL
BEGIN
    ALTER DATABASE NorthbridgePractice
    SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE NorthbridgePractice;
END;
GO
