-- MultiBase — 08 — Promoting the agent's proposals
-- Runs in: WH_Incidents
-- Called manually, after a human has reviewed the proposals.
--
-- The agent (NB_Metadata_Agent) writes to a Delta table in the Lakehouse. It has
-- no write access to meta.* — not as a policy, but as an impossibility. The only
-- path into production metadata goes through this procedure.
--
-- "Pending" is not a status column: the Lakehouse SQL endpoint is read-only, so
-- T-SQL could never update one. A proposal is pending as long as it does not
-- exist in meta.ColumnMapping. Approval is the INSERT itself.


-- What is pending
SELECT p.SourceId, p.SourceColumn, p.Classification, p.CodeGroup,
       p.Confidence, p.Rationale, p.ModelName, p.ProposedAt
FROM [LH_Incidents].[dbo].[column_mapping_proposal] AS p
WHERE NOT EXISTS (
        SELECT 1
        FROM meta.ColumnMapping AS m
        WHERE m.SourceId     = p.SourceId
          AND m.SourceColumn = p.SourceColumn)
ORDER BY p.SourceId, p.Confidence DESC;
GO


CREATE OR ALTER PROCEDURE meta.ApproveProposals
    @SourceId      INT,
    @MinConfidence DECIMAL(3,2) = 0.90
AS
BEGIN
    DECLARE @NextId INT = (SELECT COALESCE(MAX(MappingId), 0) FROM meta.ColumnMapping);

    -- The agent appends, so a re-run leaves several proposals for the same
    -- column. Only the most recent one counts.
    WITH latest AS (
        SELECT p.SourceId, p.SourceColumn, p.Classification, p.CodeGroup, p.Confidence,
               ROW_NUMBER() OVER (PARTITION BY p.SourceId, p.SourceColumn
                                  ORDER BY p.ProposedAt DESC) AS rn
        FROM [LH_Incidents].[dbo].[column_mapping_proposal] AS p
        WHERE p.SourceId = @SourceId
    )
    INSERT INTO meta.ColumnMapping
        (MappingId, SourceId, SourceColumn, Classification, CodeGroup, IsActive)
    SELECT
        @NextId + ROW_NUMBER() OVER (ORDER BY l.SourceColumn),
        l.SourceId,
        l.SourceColumn,
        l.Classification,
        l.CodeGroup,
        1
    FROM latest AS l
    WHERE l.rn = 1
      AND l.Confidence >= @MinConfidence
      -- idempotent: run it ten times, it inserts once
      AND NOT EXISTS (
            SELECT 1
            FROM meta.ColumnMapping AS m
            WHERE m.SourceId     = l.SourceId
              AND m.SourceColumn = l.SourceColumn);
END
GO


-- Approve and check
EXEC meta.ApproveProposals @SourceId = 2;

SELECT MappingId, SourceId, SourceColumn, Classification, CodeGroup, IsActive
FROM meta.ColumnMapping
ORDER BY MappingId;
