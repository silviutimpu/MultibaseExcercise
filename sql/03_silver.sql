-- MultiBase — 03 — Silver: raw data acquires meaning
-- Runs in: WH_Incidents
-- Reasoning: docs/DESIGN.md §4 (metadata-driven), §7.4 (view vs table)

DROP VIEW IF EXISTS silver.incidents;
GO

CREATE VIEW silver.incidents AS
SELECT
    b.Plant,
    b.Month,
    m.Classification,
    m.CodeGroup,
    b.Value AS Incidents
FROM bronze.incidents_raw AS b
INNER JOIN meta.ColumnMapping AS m
       -- the whole key: (SourceId, SourceColumn)
       ON m.SourceId     = b.SourceId
      AND m.SourceColumn = b.SourceColumn
WHERE m.IsActive = 1;
GO
