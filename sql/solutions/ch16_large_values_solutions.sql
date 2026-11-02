/* SQL Server from Zero — Volume 1
   Chapter 16: Large values: NVARCHAR(MAX), VARBINARY(MAX) and the deprecated text commands
   Requires: NorthbridgeLending database (sql/setup). Target: SQL Server 2025 (runs on 2022). */
USE NorthbridgeLending;
GO

/* Run sql/chapters/ch16_large_values.sql first: corrections 16.4 and 16.5
   use dbo.CreditMemo and dbo.DocumentStore created there.
   On Docker, replace C:\NorthbridgeData\ with /var/opt/mssql/data/import/. */

-- Correction 16.1
SELECT
    CustomerID,
    LEN(Email)        AS Characters,  -- characters, no trailing spaces
    DATALENGTH(Email) AS Bytes        -- bytes: 2 per NVARCHAR char
FROM dbo.Customer
WHERE CustomerID IN (1, 2, 3)
ORDER BY CustomerID;
GO

-- Correction 16.2
SELECT
    LEN(REPLICATE(N'x', 6000))        AS PlainChars,   -- truncated
    DATALENGTH(REPLICATE(N'x', 6000)) AS PlainBytes,
    LEN(REPLICATE(CAST(N'x' AS NVARCHAR(MAX)), 6000))
                                      AS MaxChars,     -- complete
    DATALENGTH(REPLICATE(CAST(N'x' AS NVARCHAR(MAX)), 6000))
                                      AS MaxBytes;
GO

-- Correction 16.3
SELECT
    CAST('Arrears' AS VARBINARY(20))              AS AsVarchar,
    DATALENGTH(CAST('Arrears' AS VARBINARY(20)))  AS BytesVarchar,
    CAST(N'Arrears' AS VARBINARY(20))             AS AsNvarchar,
    DATALENGTH(CAST(N'Arrears' AS VARBINARY(20))) AS BytesNvarchar;
GO

-- Correction 16.4
UPDATE dbo.CreditMemo
SET MemoText.WRITE(
        N'arrears',                            -- 7 new characters
        CHARINDEX(N'default', MemoText) - 1,   -- offset from 0
        7)                                     -- replace 7
WHERE MemoID = 2;

SELECT
    LEN(MemoText)               AS Characters,
    SUBSTRING(MemoText, 38, 21) AS Middle
FROM dbo.CreditMemo
WHERE MemoID = 2;
GO

-- Correction 16.5
INSERT INTO dbo.DocumentStore (DocumentID, FileName, Content)
SELECT 3, N'Collateral.csv', f.BulkColumn   -- bytes of the file
FROM OPENROWSET(
        BULK 'C:\NorthbridgeData\Collateral.csv',
        SINGLE_BLOB                         -- VARBINARY(MAX)
     ) AS f;

SELECT
    DocumentID,
    FileName,
    DATALENGTH(Content)                     AS Bytes,
    LEFT(CAST(Content AS VARCHAR(MAX)), 12) AS FirstChars
FROM dbo.DocumentStore
ORDER BY DocumentID;
GO

-- Correction 16.6
DROP TABLE IF EXISTS dbo.Practice_LegacyNote;

CREATE TABLE dbo.Practice_LegacyNote (
    NoteID   INT  NOT NULL PRIMARY KEY,
    NoteText TEXT NULL                         -- deprecated type
);

INSERT INTO dbo.Practice_LegacyNote (NoteID, NoteText)
VALUES (1, 'Letter sent on 2026-09-15.');
GO

SET NOCOUNT ON;
DECLARE @ptr VARBINARY(16);

SELECT @ptr = TEXTPTR(NoteText)                -- pointer of note 1
FROM dbo.Practice_LegacyNote
WHERE NoteID = 1;

-- offset 11 = after 'Letter sent'; delete 0 bytes; insert text
UPDATETEXT dbo.Practice_LegacyNote.NoteText @ptr 11 0 ' by post';

READTEXT dbo.Practice_LegacyNote.NoteText @ptr 0 19;  -- 19 bytes

SELECT DATALENGTH(NoteText) AS Bytes
FROM dbo.Practice_LegacyNote
WHERE NoteID = 1;
SET NOCOUNT OFF;                          -- row counts back on
GO

-- Correction 16.7
DROP TABLE IF EXISTS dbo.Practice_OldDocs;

CREATE TABLE dbo.Practice_OldDocs (
    DocID INT   NOT NULL PRIMARY KEY,
    Note  NTEXT NULL,                      -- legacy Unicode text
    Scan  IMAGE NULL                       -- legacy binary
);

INSERT INTO dbo.Practice_OldDocs (DocID, Note, Scan)
VALUES (1, N'Valuation report received', 0x4E424C);

SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'dbo'
  AND TABLE_NAME = 'Practice_OldDocs'
ORDER BY ORDINAL_POSITION;

-- ALTER TABLE: chapter 22 explains it in full.
ALTER TABLE dbo.Practice_OldDocs
ALTER COLUMN Note NVARCHAR(MAX) NULL;      -- ntext -> NVARCHAR(MAX)

ALTER TABLE dbo.Practice_OldDocs
ALTER COLUMN Scan VARBINARY(MAX) NULL;     -- image -> VARBINARY(MAX)

UPDATE dbo.Practice_OldDocs
SET Note = Note,                           -- rewrite in new format
    Scan = Scan;

SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'dbo'
  AND TABLE_NAME = 'Practice_OldDocs'
ORDER BY ORDINAL_POSITION;
GO

-- Correction 16.8
DROP TABLE IF EXISTS dbo.Practice_LongMemo;

CREATE TABLE dbo.Practice_LongMemo (
    MemoID   INT           NOT NULL PRIMARY KEY,
    MemoText NVARCHAR(MAX) NOT NULL
);

INSERT INTO dbo.Practice_LongMemo (MemoID, MemoText)
VALUES (1, N'');                          -- empty, not NULL
GO

SET NOCOUNT ON;                           -- hide 100 row counts
DECLARE @Line NVARCHAR(100) = REPLICATE(N'0123456789', 10);
DECLARE @i INT = 1;

WHILE @i <= 100
BEGIN
    UPDATE dbo.Practice_LongMemo
    SET MemoText.WRITE(@Line, NULL, NULL) -- append one line
    WHERE MemoID = 1;

    SET @i = @i + 1;
END;

SELECT
    LEN(MemoText)        AS Characters,
    DATALENGTH(MemoText) AS Bytes,
    RIGHT(MemoText, 10)  AS LastTen
FROM dbo.Practice_LongMemo
WHERE MemoID = 1;
GO

-- Clean-up: remove every table created by the chapter and the exercises.
-- The base tables were not changed.
DROP TABLE IF EXISTS dbo.CreditMemo;
DROP TABLE IF EXISTS dbo.DocumentStore;
DROP TABLE IF EXISTS dbo.LegacyMemo;
DROP TABLE IF EXISTS dbo.CommitteeMemo;
DROP TABLE IF EXISTS dbo.Practice_LegacyNote;
DROP TABLE IF EXISTS dbo.Practice_OldDocs;
DROP TABLE IF EXISTS dbo.Practice_LongMemo;
GO
