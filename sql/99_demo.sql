-- MultiBase — 99 — Presentation runbook
-- Runs in: WH_Incidents
--
-- Not part of the build sequence. Holds the demo statements, written in
-- advance, so that no SQL has to be typed in front of anyone.
--
-- ⚠ SourceId is NOT the plant number:
--      SourceId 1 = their file     (PLNT1, PLNT2)   2019–2020
--      SourceId 2 = PLNT3          German           2021
--      SourceId 3 = PLNT4          French           2022
--      SourceId 4 = PLNT5          Spanish          2023


-- ===========================================================================
-- PART A — validation rules are driven from metadata
-- ===========================================================================
-- Two 30-second tests. No file required.

-- A1. Warning: a column becomes unmapped. The rule fails, the pipeline goes on.
UPDATE meta.ColumnMapping SET IsActive = 0 WHERE MappingId = 4;
EXEC meta.RunValidations @SourceId = 1;

SELECT RuleId, RuleName, Severity, Passed, Details
FROM audit.ValidationLog
WHERE RunTimestamp = (SELECT MAX(RunTimestamp) FROM audit.ValidationLog)
ORDER BY RuleId;
-- expect: SchemaDrift Passed = 0, procedure completes normally

UPDATE meta.ColumnMapping SET IsActive = 1 WHERE MappingId = 4;


-- A2. Error: declare a column the file does not contain. The procedure throws.
INSERT INTO meta.ColumnMapping
    (MappingId, SourceId, SourceColumn, Classification, CodeGroup, IsActive)
VALUES (999, 1, 'Incidents Ext 09/10', 'External', '09/10', 1);

EXEC meta.RunValidations @SourceId = 1;
-- expect: error 50001. THROW ends the batch, so read the log separately:

SELECT RuleId, RuleName, Severity, Passed, Details
FROM audit.ValidationLog
WHERE RunTimestamp = (SELECT MAX(RunTimestamp) FROM audit.ValidationLog)
ORDER BY RuleId;

DELETE FROM meta.ColumnMapping WHERE MappingId = 999;

-- ⚠ Do not run gold.LoadGold between the INSERT and the DELETE:
-- DimIncidentType is built from meta.ColumnMapping, so it would gain a phantom
-- incident type with no facts behind it.
--
-- An UPDATE and an INSERT changed how the pipeline behaves. No code touched.
-- The difference between "warn" and "stop" is one value in the Severity column.


-- ===========================================================================
-- PART B — REHEARSAL: PLNT4, French, 2022
-- ===========================================================================
-- First: upload MultiBase_plant4_202610.xlsx to LH_Incidents / Files/landing/

-- B1. Only the new source runs; the others received no new files.
--     IsActive drives the loop, not the data: bronze keeps the other rows,
--     silver still sees them, gold stays complete.
UPDATE meta.SourceRegistry SET IsActive = 0 WHERE SourceId IN (1, 2);

-- B2. Register the file
INSERT INTO meta.SourceRegistry
    (SourceId, SourceName, FilePath, SheetName, TargetTable, KeyColumns, IsActive)
VALUES
    (3, 'Incidents Plant4',
        'Files/landing/MultiBase_plant4_202610.xlsx',
        'Sheet1', 'bronze.incidents_raw', 'Plant,Month', 1);

-- No rules to add: they are global (SourceId NULL), so the new source is
-- validated from its first run. Registering a source is one INSERT.

-- >>> RUN PL_Incidents_Load   (~1 minute, a single iteration)

-- B4. What validation detected
SELECT RuleId, RuleName, Severity, Passed, Details
FROM audit.ValidationLog
WHERE SourceId = 3
ORDER BY RunTimestamp DESC, RuleId;
-- expect: rule 1 (SchemaDrift) Passed = 0, listing the four French columns

-- B5. What the agent proposed
SELECT p.SourceColumn, p.Classification, p.CodeGroup,
       p.Confidence, p.Rationale, p.ModelName
FROM [LH_Incidents].[dbo].[column_mapping_proposal] AS p
WHERE p.SourceId = 3
  AND NOT EXISTS (
        SELECT 1 FROM meta.ColumnMapping AS m
        WHERE m.SourceId = p.SourceId AND m.SourceColumn = p.SourceColumn);

-- B6. Approval — the only step that is not automatic, by design
EXEC meta.ApproveProposals @SourceId = 3;

SELECT MappingId, SourceId, SourceColumn, Classification, CodeGroup
FROM meta.ColumnMapping
ORDER BY MappingId;

-- B7. Gold. Bronze is not reloaded: silver is a view, so it sees the French
--     rows the moment the mapping exists.
EXEC gold.LoadGold;

SELECT COUNT(*) AS Facts  FROM gold.FactIncidents;     -- 240 + 48 = 288
SELECT COUNT(*) AS Plants FROM gold.DimPlant;          -- 4
SELECT COUNT(*) AS Types  FROM gold.DimIncidentType;   -- 4, unchanged

-- B8. The warning is gone
EXEC meta.RunValidations @SourceId = 3;

SELECT RuleId, RuleName, Passed, Details
FROM audit.ValidationLog
WHERE SourceId = 3
ORDER BY RunTimestamp DESC, RuleId;

-- B9. Reactivate the sources
UPDATE meta.SourceRegistry SET IsActive = 1 WHERE SourceId IN (1, 2);

-- >>> Service: SM_Incidents → Refresh now   (Direct Lake reframing)
-- >>> Report: PLNT4 and Jan–Dec 2022 appear in the slicers


-- ===========================================================================
-- PART C — PRESENTATION: PLNT5, Spanish, 2023
-- ===========================================================================
-- First: upload MultiBase_plant5_202611.xlsx to LH_Incidents / Files/landing/
-- Identical to part B. Only the file, the SourceId and the rule offset differ.

-- C1. Only the new source runs
UPDATE meta.SourceRegistry SET IsActive = 0 WHERE SourceId IN (1, 2, 3);

-- C2. Register the file
INSERT INTO meta.SourceRegistry
    (SourceId, SourceName, FilePath, SheetName, TargetTable, KeyColumns, IsActive)
VALUES
    (4, 'Incidents Plant5',
        'Files/landing/MultiBase_plant5_202611.xlsx',
        'Sheet1', 'bronze.incidents_raw', 'Plant,Month', 1);

-- No rules to add — they are global.

-- >>> RUN PL_Incidents_Load   (~1 minute, a single iteration)
-- >>> Show RPT_Data_Quality: rule 1 failed for source 4, with the Spanish columns

-- C4. What the agent proposed
SELECT p.SourceColumn, p.Classification, p.CodeGroup,
       p.Confidence, p.Rationale, p.ModelName
FROM [LH_Incidents].[dbo].[column_mapping_proposal] AS p
WHERE p.SourceId = 4
  AND NOT EXISTS (
        SELECT 1 FROM meta.ColumnMapping AS m
        WHERE m.SourceId = p.SourceId AND m.SourceColumn = p.SourceColumn);

-- C5. Approval — the only step that is not automatic, by design
EXEC meta.ApproveProposals @SourceId = 4;

-- C6. Gold. Bronze is not reloaded: silver is a view.
EXEC gold.LoadGold;

SELECT COUNT(*) AS Facts  FROM gold.FactIncidents;     -- 288 + 48 = 336
SELECT COUNT(*) AS Plants FROM gold.DimPlant;          -- 5
SELECT COUNT(*) AS Types  FROM gold.DimIncidentType;   -- 4, unchanged

-- C7. The warning is gone
EXEC meta.RunValidations @SourceId = 4;

-- C8. Reactivate the sources
UPDATE meta.SourceRegistry SET IsActive = 1 WHERE SourceId IN (1, 2, 3);

-- >>> Service: SM_Incidents → Refresh now
-- >>> Report: PLNT5 and Jan–Dec 2023 appear in the slicers
-- >>> RPT_Data_Quality: the card returns to 0


-- ===========================================================================
-- The validation log, for the closing of the demo
-- ===========================================================================
-- The same rule, before and after. The story reads itself.
SELECT RunTimestamp, SourceId, RuleName, Passed, Details
FROM audit.ValidationLog
WHERE RuleName = 'All source columns are mapped'
ORDER BY RunTimestamp;
