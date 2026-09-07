CREATE   PROCEDURE bronze.DeleteSource
    @Id INT
AS
BEGIN
    DELETE FROM bronze.incidents_raw
    WHERE SourceID = @Id;
END