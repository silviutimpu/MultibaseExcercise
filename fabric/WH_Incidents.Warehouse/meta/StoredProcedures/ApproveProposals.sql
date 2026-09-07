CREATE   PROCEDURE meta.ApproveProposals
    @SourceId      INT,
    @MinConfidence DECIMAL(3,2) = 0.90
AS
BEGIN
    DECLARE @NextId INT = (SELECT COALESCE(MAX(MappingId), 0) FROM meta.ColumnMapping);

    -- Agentul scrie în append, deci o re-rulare lasă mai multe propuneri pentru
    -- aceeași coloană. Contează doar cea mai recentă.
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
        l.SourceId, l.SourceColumn, l.Classification, l.CodeGroup, 1
    FROM latest AS l
    WHERE l.rn = 1
      AND l.Confidence >= @MinConfidence
      AND NOT EXISTS (
            SELECT 1 FROM meta.ColumnMapping AS m
            WHERE m.SourceId = l.SourceId AND m.SourceColumn = l.SourceColumn);
END