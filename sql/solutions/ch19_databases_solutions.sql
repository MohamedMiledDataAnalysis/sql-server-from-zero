/* SQL Server from Zero — Volume 1
   Chapter 19: Databases and filegroups
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

-- Correction 19.1
USE master;
GO
CREATE DATABASE NorthbridgeExercise;   -- everything from model
GO
USE NorthbridgeExercise;               -- view describes current DB
GO
SELECT file_id, name, type_desc
FROM sys.database_files
ORDER BY file_id;
GO

-- Step by step

-- Correction 19.2
USE master;
GO
SELECT name, recovery_model_desc          -- before
FROM sys.databases
WHERE name = N'NorthbridgeExercise';

ALTER DATABASE NorthbridgeExercise SET RECOVERY SIMPLE;

SELECT name, recovery_model_desc          -- after
FROM sys.databases
WHERE name = N'NorthbridgeExercise';
GO

-- Step by step

-- Correction 19.3
USE master;
GO
-- Size first (must be larger than the current 8 MB)
ALTER DATABASE NorthbridgeExercise
MODIFY FILE (NAME = NorthbridgeExercise, SIZE = 32MB);

-- Then the growth step
ALTER DATABASE NorthbridgeExercise
MODIFY FILE (NAME = NorthbridgeExercise, FILEGROWTH = 16MB);

SELECT name,
       size * 8 / 1024   AS SizeMB,     -- pages -> MB
       growth * 8 / 1024 AS GrowthMB
FROM sys.master_files
WHERE database_id = DB_ID(N'NorthbridgeExercise')
  AND type_desc = N'ROWS';
GO

-- Step by step

-- Correction 19.4
USE master;
GO
ALTER DATABASE NorthbridgeExercise ADD FILEGROUP Reporting;

DECLARE @D NVARCHAR(260) =
    CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS NVARCHAR(260));

DECLARE @sql NVARCHAR(MAX) = N'
ALTER DATABASE NorthbridgeExercise
ADD FILE
( NAME = NorthbridgeExercise_rep1,
  FILENAME = N''' + @D + N'NorthbridgeExercise_rep1.ndf'',
  SIZE = 16MB, FILEGROWTH = 16MB )
TO FILEGROUP Reporting;';

PRINT @sql;                 -- check the path before running
EXEC (@sql);
GO

USE NorthbridgeExercise;
GO
SELECT fg.name               AS FilegroupName,
       fg.is_default,
       COUNT(df.file_id)     AS FileCount   -- files per filegroup
FROM sys.filegroups AS fg
LEFT JOIN sys.database_files AS df
    ON df.data_space_id = fg.data_space_id
GROUP BY fg.name, fg.is_default, fg.data_space_id
ORDER BY fg.data_space_id;
GO

-- Step by step

-- Correction 19.5
USE NorthbridgeExercise;
GO
SELECT BranchID, BranchName, City, Region, OpenedDate
INTO dbo.BranchReport ON Reporting     -- explicit filegroup
FROM NorthbridgeLending.dbo.Branch;

SELECT t.name  AS TableName,
       fg.name AS FilegroupName
FROM sys.tables AS t
INNER JOIN sys.indexes AS i
    ON i.object_id = t.object_id
   AND i.index_id IN (0, 1)            -- heap or clustered
INNER JOIN sys.filegroups AS fg
    ON fg.data_space_id = i.data_space_id
ORDER BY t.name;
GO

-- Step by step

-- Correction 19.6
USE master;
GO
-- Too early: the file still holds dbo.BranchReport (error 5042).
-- Commented out so that the script runs end to end.
/*
ALTER DATABASE NorthbridgeExercise
REMOVE FILE NorthbridgeExercise_rep1;
*/
GO

USE NorthbridgeExercise;
GO
DROP TABLE IF EXISTS dbo.BranchReport;   -- empties the file

USE master;
GO
ALTER DATABASE NorthbridgeExercise
REMOVE FILE NorthbridgeExercise_rep1;    -- now succeeds

ALTER DATABASE NorthbridgeExercise
REMOVE FILEGROUP Reporting;
GO

USE NorthbridgeExercise;
GO
SELECT name, is_default
FROM sys.filegroups
ORDER BY data_space_id;
GO

-- Step by step

-- Correction 19.7
USE master;
GO
-- 1. Drop the database if it exists, disconnecting other sessions
IF DB_ID(N'NorthbridgeExercise') IS NOT NULL
BEGIN
    ALTER DATABASE NorthbridgeExercise
    SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE NorthbridgeExercise;
END;

-- 2. Read the default folders of the instance
DECLARE @D NVARCHAR(260) =
    CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS NVARCHAR(260));
DECLARE @L NVARCHAR(260) =
    CAST(SERVERPROPERTY('InstanceDefaultLogPath') AS NVARCHAR(260));

-- 3. Build and run CREATE DATABASE
DECLARE @sql NVARCHAR(MAX) = N'
CREATE DATABASE NorthbridgeExercise
ON PRIMARY
( NAME = NorthbridgeExercise_data,
  FILENAME = N''' + @D + N'NorthbridgeExercise.mdf'',
  SIZE = 64MB, MAXSIZE = 512MB, FILEGROWTH = 10% )
LOG ON
( NAME = NorthbridgeExercise_log,
  FILENAME = N''' + @L + N'NorthbridgeExercise_log.ldf'',
  SIZE = 16MB, MAXSIZE = UNLIMITED, FILEGROWTH = 16MB );';

PRINT @sql;
EXEC (@sql);

-- 4. Check from master
SELECT name, type_desc, size * 8 / 1024 AS SizeMB,
       growth, is_percent_growth
FROM sys.master_files
WHERE database_id = DB_ID(N'NorthbridgeExercise')
ORDER BY file_id;
GO

-- Step by step

-- Correction 19.8
USE NorthbridgeExercise;
GO
SELECT df.name                       AS FileName,
       ISNULL(fg.name, N'(log)')     AS FilegroupName,
       df.size * 8 / 1024            AS SizeMB,
       CASE
           WHEN df.is_percent_growth = 1
               THEN CONCAT(df.growth, N' %')            -- percent
           ELSE CONCAT(df.growth * 8 / 1024, N' MB')    -- pages
       END                           AS Growth,
       CASE
           WHEN df.max_size = -1
             OR (df.type_desc = N'LOG'
                 AND df.max_size = 268435456)
               THEN N'UNLIMITED'
           ELSE CONCAT(df.max_size * 8 / 1024, N' MB')
       END                           AS MaxSize
FROM sys.database_files AS df
LEFT JOIN sys.filegroups AS fg
    ON fg.data_space_id = df.data_space_id
ORDER BY df.file_id;
GO

-- Step by step

-- Clean-up: make sure the exercise database is gone
USE master;
GO
IF DB_ID(N'NorthbridgeExercise') IS NOT NULL
BEGIN
    ALTER DATABASE NorthbridgeExercise
    SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE NorthbridgeExercise;
END;
GO
