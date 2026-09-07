-- MultiBase — 02 — Schemas for the data layers
-- Runs in: WH_Incidents
--
-- Re-running raises "schema already exists" — expected, skip it.
-- Fabric has no CREATE SCHEMA IF NOT EXISTS.

CREATE SCHEMA bronze;
GO

CREATE SCHEMA silver;
GO

CREATE SCHEMA gold;
GO


-- Check: expecting bronze, silver, gold, meta, audit
SELECT name
FROM sys.schemas
WHERE name IN ('bronze', 'silver', 'gold', 'meta', 'audit')
ORDER BY name;
