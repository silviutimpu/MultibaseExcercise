-- MultiBase — 07 — Validation engine
-- Runs in: WH_Incidents
-- Called by: PL_Incidents_Load, between the bronze load and gold.LoadGold
--
-- Rule types are code. Rule instances are metadata: which source, which column,
-- which threshold, which severity. A new rule type requires new code — and it
-- has to, otherwise it could not be tested.
--
-- Each block below is one rule type: measure first, then write one log row per
-- active rule of that type. If meta.DQRules holds no active rule of that type,
-- the block produces nothing.
--
-- A rule with SourceId NULL applies to every source; one with a SourceId set
-- applies only to that source. Default globally, override where needed — so a
-- newly registered source is validated without anyone remembering to give it
-- rules. The log always records @SourceId, never r.SourceId: the rule may be
-- global, the run never is.


CREATE OR ALTER PROCEDURE meta.RunValidations
    @SourceId INT
AS
BEGIN
    DECLARE @Now   DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @RunId VARCHAR(50)  =
        CONVERT(VARCHAR(30), @Now, 126) + '-' + CAST(@SourceId AS VARCHAR(10));


    -- SchemaDrift ----------------------------------------------------------
    -- Columns that arrived in bronze with no active mapping. Warning: it does
    -- not stop the load, but the list is the input of the mapping agent.
    DECLARE @Unmapped     INT;
    DECLARE @UnmappedList VARCHAR(4000);

    SELECT @Unmapped     = COUNT(*),
           @UnmappedList = STRING_AGG(u.SourceColumn, ', ')
    FROM (
        SELECT DISTINCT b.SourceColumn
        FROM bronze.incidents_raw AS b
        WHERE b.SourceID = @SourceId
          AND NOT EXISTS (
                SELECT 1
                FROM meta.ColumnMapping AS m
                WHERE m.SourceId     = b.SourceID
                  AND m.SourceColumn = b.SourceColumn
                  AND m.IsActive     = 1)
    ) AS u;

    INSERT INTO audit.ValidationLog
        (RunId, RunTimestamp, SourceId, RuleId, RuleName, Severity, Passed, Details)
    SELECT
        @RunId, @Now, @SourceId, r.RuleId, r.RuleName, r.Severity,
        CASE WHEN @Unmapped = 0 THEN 1 ELSE 0 END,
        CONCAT('unmapped columns: ', @Unmapped, COALESCE('; ' + @UnmappedList, ''))
    FROM meta.DQRules AS r
    WHERE r.RuleType = 'SchemaDrift'
      AND (r.SourceId = @SourceId OR r.SourceId IS NULL)
      AND r.IsActive = 1;


    -- MissingColumn --------------------------------------------------------
    -- The mirror of the rule above: active mappings for which no row arrived.
    -- Error, because the loaded data is incomplete, and in the report that
    -- looks like a genuine drop in incidents.
    DECLARE @Missing     INT;
    DECLARE @MissingList VARCHAR(4000);

    SELECT @Missing     = COUNT(*),
           @MissingList = STRING_AGG(m.SourceColumn, ', ')
    FROM meta.ColumnMapping AS m
    WHERE m.SourceId = @SourceId
      AND m.IsActive = 1
      AND NOT EXISTS (
            SELECT 1
            FROM bronze.incidents_raw AS b
            WHERE b.SourceID     = m.SourceId
              AND b.SourceColumn = m.SourceColumn);

    INSERT INTO audit.ValidationLog
        (RunId, RunTimestamp, SourceId, RuleId, RuleName, Severity, Passed, Details)
    SELECT
        @RunId, @Now, @SourceId, r.RuleId, r.RuleName, r.Severity,
        CASE WHEN @Missing = 0 THEN 1 ELSE 0 END,
        CONCAT('missing columns: ', @Missing, COALESCE('; ' + @MissingList, ''))
    FROM meta.DQRules AS r
    WHERE r.RuleType = 'MissingColumn'
      AND (r.SourceId = @SourceId OR r.SourceId IS NULL)
      AND r.IsActive = 1;


    -- RowCount -------------------------------------------------------------
    DECLARE @Rows INT = (
        SELECT COUNT(*)
        FROM bronze.incidents_raw
        WHERE SourceID = @SourceId);

    INSERT INTO audit.ValidationLog
        (RunId, RunTimestamp, SourceId, RuleId, RuleName, Severity, Passed, Details)
    SELECT
        @RunId, @Now, @SourceId, r.RuleId, r.RuleName, r.Severity,
        CASE WHEN @Rows >= CAST(JSON_VALUE(r.RuleParameters, '$.min') AS INT)
             THEN 1 ELSE 0 END,
        CONCAT('rows: ', @Rows)
    FROM meta.DQRules AS r
    WHERE r.RuleType = 'RowCount'
      AND (r.SourceId = @SourceId OR r.SourceId IS NULL)
      AND r.IsActive = 1;


    -- NotNull --------------------------------------------------------------
    -- null_counts is a lookup table built on the fly: column name -> how many
    -- empty values it has. The rule joins to it through TargetColumn.
    --
    -- LEFT JOIN, not INNER: a rule pointing at a column the engine does not
    -- know finds no row, Bad stays NULL, and the rule fails visibly. With an
    -- INNER JOIN it would have vanished from the log without a trace.
    WITH null_counts AS (
        SELECT 'Plant' AS ColName, COUNT(*) AS Bad
        FROM bronze.incidents_raw
        WHERE SourceID = @SourceId AND (Plant IS NULL OR LTRIM(RTRIM(Plant)) = '')
        UNION ALL
        SELECT 'SourceColumn', COUNT(*)
        FROM bronze.incidents_raw
        WHERE SourceID = @SourceId AND (SourceColumn IS NULL OR LTRIM(RTRIM(SourceColumn)) = '')
        UNION ALL
        SELECT 'Month', COUNT(*)
        FROM bronze.incidents_raw
        WHERE SourceID = @SourceId AND [Month] IS NULL
        UNION ALL
        SELECT 'Value', COUNT(*)
        FROM bronze.incidents_raw
        WHERE SourceID = @SourceId AND Value IS NULL
    )
    INSERT INTO audit.ValidationLog
        (RunId, RunTimestamp, SourceId, RuleId, RuleName, Severity, Passed, Details)
    SELECT
        @RunId, @Now, @SourceId, r.RuleId, r.RuleName, r.Severity,
        CASE WHEN n.Bad IS NULL THEN 0
             WHEN n.Bad = 0     THEN 1
             ELSE 0 END,
        CASE WHEN n.Bad IS NULL
             THEN CONCAT('column unknown to the engine: ', r.TargetColumn)
             ELSE CONCAT('missing values in ', r.TargetColumn, ': ', n.Bad) END
    FROM meta.DQRules AS r
    LEFT JOIN null_counts AS n
           ON n.ColName = r.TargetColumn
    WHERE r.RuleType = 'NotNull'
      AND (r.SourceId = @SourceId OR r.SourceId IS NULL)
      AND r.IsActive = 1;


    -- Range ----------------------------------------------------------------
    -- Compare the smallest value in the data with the threshold from metadata.
    -- Simpler than counting violations, and the log shows how close to the
    -- threshold you are, not merely that you passed.
    DECLARE @MinValue INT = (
        SELECT MIN(Value)
        FROM bronze.incidents_raw
        WHERE SourceID = @SourceId);

    INSERT INTO audit.ValidationLog
        (RunId, RunTimestamp, SourceId, RuleId, RuleName, Severity, Passed, Details)
    SELECT
        @RunId, @Now, @SourceId, r.RuleId, r.RuleName, r.Severity,
        CASE WHEN @MinValue >= CAST(JSON_VALUE(r.RuleParameters, '$.min') AS INT)
             THEN 1 ELSE 0 END,
        CONCAT('minimum value: ', @MinValue)
    FROM meta.DQRules AS r
    WHERE r.RuleType = 'Range'
      AND (r.SourceId = @SourceId OR r.SourceId IS NULL)
      AND r.IsActive = 1;


    -- Unique ---------------------------------------------------------------
    -- The fact grain, checked on silver, where Classification and CodeGroup
    -- already exist. The column list in RuleParameters documents the intent;
    -- the implementation hard-codes it, because anything else would mean SQL
    -- built from a string.
    DECLARE @Dupes INT = (
        SELECT COUNT(*)
        FROM (
            SELECT Plant, [Month], Classification, CodeGroup
            FROM silver.incidents
            GROUP BY Plant, [Month], Classification, CodeGroup
            HAVING COUNT(*) > 1
        ) AS g);

    INSERT INTO audit.ValidationLog
        (RunId, RunTimestamp, SourceId, RuleId, RuleName, Severity, Passed, Details)
    SELECT
        @RunId, @Now, @SourceId, r.RuleId, r.RuleName, r.Severity,
        CASE WHEN @Dupes = 0 THEN 1 ELSE 0 END,
        CONCAT('duplicate combinations: ', @Dupes)
    FROM meta.DQRules AS r
    WHERE r.RuleType = 'Unique'
      AND (r.SourceId = @SourceId OR r.SourceId IS NULL)
      AND r.IsActive = 1;


    -- Stop -----------------------------------------------------------------
    -- Without this, Severity would be just a text column.
    IF EXISTS (
        SELECT 1
        FROM audit.ValidationLog
        WHERE RunId    = @RunId
          AND Passed   = 0
          AND Severity = 'Error')
        THROW 50001, 'Validation failed. See audit.ValidationLog for this RunId.', 1;
END
GO


-- Check: 6 rows, all Passed = 1
EXEC meta.RunValidations @SourceId = 1;

SELECT RunId, RuleId, RuleName, Severity, Passed, Details
FROM audit.ValidationLog
WHERE RunTimestamp = (SELECT MAX(RunTimestamp) FROM audit.ValidationLog)
ORDER BY RuleId;
