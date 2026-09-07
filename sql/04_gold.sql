-- MultiBase — 04 — Gold: star schema structure
-- Runs in: WH_Incidents
-- Reasoning: docs/DESIGN.md §7
--
-- Structure only. gold.LoadGold fills it (see 05_load_gold.sql): the tables are
-- emptied and refilled, not recreated, so the Direct Lake semantic model is not
-- forced to rebind on every load.

DROP TABLE IF EXISTS gold.FactIncidents;
DROP TABLE IF EXISTS gold.DimPlant;
DROP TABLE IF EXISTS gold.DimDate;
DROP TABLE IF EXISTS gold.DimIncidentType;
GO


CREATE TABLE gold.DimPlant (
    PlantKey  BIGINT       NOT NULL,
    PlantCode VARCHAR(100) NOT NULL
);
GO


CREATE TABLE gold.DimIncidentType (
    IncidentTypeKey  BIGINT       NOT NULL,
    Classification   VARCHAR(50)  NOT NULL,
    CodeGroup        VARCHAR(50)  NOT NULL,
    IncidentTypeName VARCHAR(100) NOT NULL,
    SortOrder        BIGINT       NOT NULL
);
GO


CREATE TABLE gold.DimDate (
    DateKey     INT         NOT NULL,
    [Date]      DATE        NOT NULL,
    [Year]      INT         NOT NULL,
    MonthNumber INT         NOT NULL,
    MonthShort  VARCHAR(3)  NOT NULL,
    -- label for the PERIOD slicer: 'Jan–Dec 2019'
    Period      VARCHAR(30) NOT NULL
);
GO


CREATE TABLE gold.FactIncidents (
    PlantKey        BIGINT NOT NULL,
    DateKey         INT    NOT NULL,
    IncidentTypeKey BIGINT NOT NULL,
    Incidents       INT    NOT NULL
);
GO
