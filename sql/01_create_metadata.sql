-- MultiBase — 01 — Metadata + audit
-- Runs in: WH_Incidents


CREATE SCHEMA meta;
GO

CREATE SCHEMA audit;
GO

DROP TABLE IF EXISTS meta.SourceRegistry;
DROP TABLE IF EXISTS meta.ColumnMapping;
DROP TABLE IF EXISTS meta.DQRules;
GO


-- Which files are processed, and how
CREATE TABLE meta.SourceRegistry (
    SourceId     INT          NOT NULL,
    SourceName   VARCHAR(100) NOT NULL,
    FilePath     VARCHAR(500) NOT NULL,
    SheetName    VARCHAR(100) NOT NULL,
    TargetTable  VARCHAR(200) NOT NULL,
    KeyColumns   VARCHAR(500) NOT NULL,
    IsActive     BIT          NOT NULL
);
GO

INSERT INTO meta.SourceRegistry
    (SourceId, SourceName, FilePath, SheetName, TargetTable, KeyColumns, IsActive)
VALUES
    (1, 'Incidents',
        'Files/landing/MultiBase_exercise_202608.xlsx',
        'Sheet1',
        'bronze.incidents_raw',
        'Plant,Month',
        1),
    (2, 'Incidents Plant3',
        'Files/landing/MultiBase_plant3_202609.xlsx',
        'Sheet1',
        'bronze.incidents_raw',
        'Plant,Month',
        1);
GO

SELECT * FROM meta.SourceRegistry;


-- What each source column means
CREATE TABLE meta.ColumnMapping (
    MappingId      INT          NOT NULL,
    SourceId       INT          NOT NULL,
    SourceColumn   VARCHAR(200) NOT NULL,
    Classification VARCHAR(50)  NOT NULL,
    CodeGroup      VARCHAR(50)  NOT NULL,
    IsActive       BIT          NOT NULL
);
GO

-- SourceColumn = the Excel header, character for character.
-- The collation is case-sensitive: a mismatch here empties the join without error.
INSERT INTO meta.ColumnMapping
    (MappingId, SourceId, SourceColumn, Classification, CodeGroup, IsActive)
VALUES
    (1, 1, 'Incidents IC 01/02',  'Internal', '01/02', 1),
    (2, 1, 'Incidents IC 05/06',  'Internal', '05/06', 1),
    (3, 1, 'Incidents Ext 01/02', 'External', '01/02', 1),
    (4, 1, 'Incidents Ext 05/06', 'External', '05/06', 1);
GO

SELECT * FROM meta.ColumnMapping;


-- The validation rules
CREATE TABLE meta.DQRules (
    RuleId         INT           NOT NULL,
    -- NULL = applies to every source. A SourceId means "this source only".
    SourceId       INT           NULL,
    RuleName       VARCHAR(200)  NOT NULL,
    RuleType       VARCHAR(50)   NOT NULL,  -- SchemaDrift | MissingColumn | RowCount | NotNull | Range | Unique
    TargetColumn   VARCHAR(200)  NULL,      -- NULL = table-level rule, not column-level
    RuleParameters VARCHAR(1000) NOT NULL,  -- JSON, read by meta.RunValidations
    Severity       VARCHAR(20)   NOT NULL,  -- Error = stop | Warning = log only
    IsActive       BIT           NOT NULL
);
GO

-- All six are global (SourceId NULL): they apply to every registered source,
-- including ones added later. Six rows instead of six per source — and no way
-- to register a source that escapes validation.
INSERT INTO meta.DQRules
    (RuleId, SourceId, RuleName, RuleType, TargetColumn, RuleParameters, Severity, IsActive)
VALUES
    (1, NULL, 'All source columns are mapped', 'SchemaDrift', NULL,
        '{}', 'Warning', 1),
    (2, NULL, 'File is not empty', 'RowCount', NULL,
        '{"min": 1}', 'Error', 1),
    (3, NULL, 'Plant is populated', 'NotNull', 'Plant',
        '{}', 'Error', 1),
    -- Targets 'Value': the check runs on bronze, where the column is not yet
    -- renamed. With the business name the condition would never match and the
    -- rule would pass every time — a green row for a check that never ran.
    (4, NULL, 'Incidents are not negative', 'Range', 'Value',
        '{"min": 0}', 'Error', 1),
    (5, NULL, 'Fact grain is unique', 'Unique', NULL,
        '{"cols": ["Plant","Month","Classification","CodeGroup"]}', 'Error', 1),
    -- Error, not Warning: a column that disappears makes the numbers drop with
    -- no explanation. The data is not wrong, it is incomplete — and in the
    -- report that looks like an improvement.
    (6, NULL, 'No mapped column is missing', 'MissingColumn', NULL,
        '{}', 'Error', 1);
GO

SELECT * FROM meta.DQRules;


-- The outcome of every validation run.
-- NOT dropped above: recreating it would erase the run history.
-- The first run creates it; later runs fail this statement — ignore it.
CREATE TABLE audit.ValidationLog (
    RunId        VARCHAR(50)   NOT NULL,
    RunTimestamp DATETIME2(0)  NOT NULL,
    SourceId     INT           NOT NULL,
    RuleId       INT           NOT NULL,
    RuleName     VARCHAR(200)  NOT NULL,
    Severity     VARCHAR(20)   NOT NULL,
    Passed       BIT           NOT NULL,
    Details      VARCHAR(4000) NULL
);
GO


-- Check
SELECT 'SourceRegistry' AS TableName, COUNT(*) AS Rows FROM meta.SourceRegistry
UNION ALL SELECT 'ColumnMapping', COUNT(*) FROM meta.ColumnMapping
UNION ALL SELECT 'DQRules',       COUNT(*) FROM meta.DQRules
UNION ALL SELECT 'ValidationLog', COUNT(*) FROM audit.ValidationLog;

SELECT DATABASEPROPERTYEX(DB_NAME(), 'Collation') AS Collation;
