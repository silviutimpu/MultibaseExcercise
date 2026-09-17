CREATE   PROCEDURE meta.RegisterSource
    @SourceName  VARCHAR(100),
    @FilePath    VARCHAR(500),
    @SheetName   VARCHAR(100),
    @PlantColumn VARCHAR(200) = 'Plant',
    @MonthColumn VARCHAR(200) = 'Month'
AS
BEGIN
    IF EXISTS (SELECT 1 FROM meta.SourceRegistry WHERE FilePath = @FilePath)
        THROW 50002, 'This file is already registered.', 1;

    DECLARE @SourceId INT = (SELECT COALESCE(MAX(SourceId), 0) + 1 FROM meta.SourceRegistry);

    -- leftover rows for this id would give the dataflow duplicate column names
    IF EXISTS (SELECT 1 FROM meta.KeyColumnMapping WHERE SourceId = @SourceId)
        THROW 50003, 'Identifying columns already exist for this SourceId.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- the file
        INSERT INTO meta.SourceRegistry (SourceId, SourceName, FilePath, SheetName, IsActive)
        VALUES (@SourceId, @SourceName, @FilePath, @SheetName, 1);

        -- its identifying columns
        INSERT INTO meta.KeyColumnMapping (SourceId, SourceColumn, TargetColumn, DataType)
        VALUES
            (@SourceId, @PlantColumn, 'Plant', 'text'),
            (@SourceId, @MonthColumn, 'Month', 'date');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    SELECT @SourceId AS NewSourceId;
END