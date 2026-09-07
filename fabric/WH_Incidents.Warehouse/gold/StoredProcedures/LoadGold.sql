-- MultiBase — 05 — Procedura de încărcare gold
-- Rulează în: WH_Incidents
-- Apelată de: PL_Incidents_Load (activitate Stored procedure)
--
-- Golește și reumple; nu recreează tabelele — modelul Direct Lake rămâne legat.
-- Totul într-o singură tranzacție: dacă pică la mijloc, gold nu rămâne pe jumătate.

CREATE   PROCEDURE gold.LoadGold
AS
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION;

        -- golire ---------------------------------------------------
        DELETE FROM gold.FactIncidents;
        DELETE FROM gold.DimPlant;
        DELETE FROM gold.DimIncidentType;
        DELETE FROM gold.DimDate;


        -- DimPlant -------------------------------------------------
        WITH plants AS (
            SELECT DISTINCT Plant
            FROM silver.incidents
        )
        INSERT INTO gold.DimPlant (PlantKey, PlantCode)
        SELECT ROW_NUMBER() OVER (ORDER BY Plant), Plant
        FROM plants;


        -- DimIncidentType ------------------------------------------
        WITH types AS (
            SELECT DISTINCT Classification, CodeGroup
            FROM meta.ColumnMapping
            WHERE IsActive = 1
        ),
        ordered AS (
            SELECT
                Classification,
                CodeGroup,
                ROW_NUMBER() OVER (
                    ORDER BY CASE Classification WHEN 'Internal' THEN 1 ELSE 2 END,
                             CodeGroup
                ) AS SortOrder
            FROM types
        )
        INSERT INTO gold.DimIncidentType
            (IncidentTypeKey, Classification, CodeGroup, IncidentTypeName, SortOrder)
        SELECT
            SortOrder,
            Classification,
            CodeGroup,
            CONCAT(
                CASE Classification WHEN 'Internal' THEN 'Int' ELSE 'Ext' END,
                ' ',
                CodeGroup
            ),
            SortOrder
        FROM ordered;


        -- DimDate --------------------------------------------------
        WITH bounds AS (
            SELECT DATEFROMPARTS(YEAR(MIN(Month)), 1, 1)   AS StartDate,
                   DATEFROMPARTS(YEAR(MAX(Month)), 12, 31) AS EndDate
            FROM silver.incidents
        ),
        dates AS (
            SELECT DATEADD(DAY, gs.value, b.StartDate) AS [Date]
            FROM bounds AS b
            CROSS JOIN GENERATE_SERIES(0, 36524) AS gs
            WHERE gs.value <= DATEDIFF(DAY, b.StartDate, b.EndDate)
        ),
        -- eticheta perioadei, din prima și ultima lună CU DATE din fiecare an
        periods AS (
            SELECT
                YEAR(Month) AS Yr,
                CAST(CONCAT(
                    LEFT(DATENAME(MONTH, MIN(Month)), 3),
                    '–',
                    LEFT(DATENAME(MONTH, MAX(Month)), 3),
                    ' ',
                    YEAR(Month)
                ) AS VARCHAR(30)) AS Period
            FROM silver.incidents
            GROUP BY YEAR(Month)
        )
        INSERT INTO gold.DimDate (DateKey, [Date], [Year], MonthNumber, MonthShort, Period)
        SELECT
            YEAR(d.[Date]) * 10000 + MONTH(d.[Date]) * 100 + DAY(d.[Date]),
            d.[Date],
            YEAR(d.[Date]),
            MONTH(d.[Date]),
            -- CAST: DATENAME returnează NVARCHAR, pe care Fabric nu-l acceptă
            CAST(LEFT(DATENAME(MONTH, d.[Date]), 3) AS VARCHAR(3)),
            p.Period
        FROM dates AS d
        INNER JOIN periods AS p
                ON p.Yr = YEAR(d.[Date]);


        -- FactIncidents --------------------------------------------
        INSERT INTO gold.FactIncidents (PlantKey, DateKey, IncidentTypeKey, Incidents)
        SELECT
            p.PlantKey,
            d.DateKey,
            t.IncidentTypeKey,
            s.Incidents
        FROM silver.incidents AS s
        INNER JOIN gold.DimPlant AS p
                ON p.PlantCode = s.Plant
        INNER JOIN gold.DimDate AS d
                ON d.[Date] = s.Month
        INNER JOIN gold.DimIncidentType AS t
                ON t.Classification = s.Classification
               AND t.CodeGroup      = s.CodeGroup;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END