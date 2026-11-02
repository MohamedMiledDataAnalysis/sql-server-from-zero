/* SQL Server from Zero — Northbridge Lending dataset
   Step 1 of 3: create the database
   Run in SQL Server Management Studio (SSMS) or sqlcmd. Target: SQL Server 2025 (also runs on 2022). */

USE master;
GO

-- Remove an earlier copy so that the script can be run again from a clean state.
IF DB_ID(N'NorthbridgeLending') IS NOT NULL
BEGIN
    ALTER DATABASE NorthbridgeLending SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE NorthbridgeLending;
END;
GO

CREATE DATABASE NorthbridgeLending;
GO

USE NorthbridgeLending;
GO
