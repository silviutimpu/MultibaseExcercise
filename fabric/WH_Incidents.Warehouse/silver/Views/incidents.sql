-- Auto Generated (Do not modify) 160F3BF31EA2EB4024C90B0CA5AAB1786D51CC028FAB9F5DBF43379B4FD778EA
CREATE VIEW silver.incidents AS
SELECT
    b.Plant,
    b.Month,
    m.Classification,
    m.CodeGroup,
    b.Value AS Incidents
FROM bronze.incidents_raw AS b
INNER JOIN meta.ColumnMapping AS m
       -- cheia întreagă: (SourceId, SourceColumn)
       ON m.SourceId     = b.SourceID
      AND m.SourceColumn = b.SourceColumn
WHERE m.IsActive = 1;