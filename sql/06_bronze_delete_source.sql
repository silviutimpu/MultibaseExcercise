-- MultiBase — 06 — Clear bronze for a single source
-- Runs in: WH_Incidents
-- Called by: PL_Incidents_Load, inside ForEach, BEFORE the dataflow
--
-- The dataflow destination is set to Append. Each iteration first deletes the
-- rows of the current source, then the dataflow appends them again. That is how
-- several sources coexist in bronze.incidents_raw, separated by SourceID.
--
-- With Replace, the second source would have deleted the first one's rows.

CREATE OR ALTER PROCEDURE bronze.DeleteSource
    @Id INT
AS
BEGIN
    DELETE FROM bronze.incidents_raw
    WHERE SourceID = @Id;
END
GO
