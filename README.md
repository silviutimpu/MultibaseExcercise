# MultiBase — Incident Analytics on Microsoft Fabric

An end-to-end, metadata-driven analytics solution built for the Senior Microsoft Fabric exercise: monthly incident counts from an Excel workbook, through ingestion, validation and a star schema, to the "Plant Overview" report.

The dataset is small on purpose. **The design and the reasoning behind it are the deliverable** — they live in [`docs/DESIGN.md`](docs/DESIGN.md).

---

## Where to start

| Read this | For |
|---|---|
| [`docs/DESIGN.md`](docs/DESIGN.md) | every decision, with its reasoning, trade-offs and the rejected alternatives |
| [`docs/DESIGN.md` §12](docs/DESIGN.md) | the decision journal — including one decision that was reversed |
| [`docs/DESIGN.md` §11](docs/DESIGN.md) | the known gaps, stated rather than discovered |

---

## The shape of it

```
Files/landing/*.xlsx
      │  Lookup meta.SourceRegistry → ForEach
      ▼
Dataflow Gen2      Excel → dynamic unpivot → bronze
      ▼
meta.RunValidations    6 rules from metadata → audit.ValidationLog
      ▼
NB_Metadata_Agent      unmapped columns → LLM → proposal queue (advisory)
      ▼
Warehouse          bronze JOIN meta.ColumnMapping → silver → gold star schema
      ▼
Direct Lake        SM_Incidents → RPT_Plant_Overview
```

**What makes it metadata-driven:** no column name of the source appears anywhere in the code. Registering a new source — a new plant, a new year, headers in another language — is one `INSERT`.

---

## Repository layout

```
sql/     execution order matters; the numbers are the order
docs/    the design document
report/  the Power BI project (PBIP)
```

### SQL scripts

| Script | What it does |
|---|---|
| `01_create_metadata.sql` | the three metadata tables and the audit log |
| `02_create_layers.sql` | bronze / silver / gold schemas |
| `03_silver.sql` | the view where raw data acquires meaning |
| `04_gold.sql` | star schema structure |
| `05_load_gold.sql` | `gold.LoadGold` — transactional load |
| `06_bronze_delete_source.sql` | `bronze.DeleteSource` — what makes the load idempotent |
| `07_validations.sql` | `meta.RunValidations` — the validation engine |
| `08_approve_proposals.sql` | `meta.ApproveProposals` — human approval of the agent's proposals |
| `99_demo.sql` | a runbook, not part of the build |

Run `01` through `08` in order. Each one says at the top where it runs and what calls it.

---

## Fabric items

| Item | Name |
|---|---|
| Workspace | `MultiBase-Incidents` |
| Lakehouse | `LH_Incidents` |
| Warehouse | `WH_Incidents` |
| Dataflow | `DF_Bronze_Incidents` |
| Notebook | `NB_Metadata_Agent` |
| Pipeline | `PL_Incidents_Load` |
| Semantic model | `SM_Incidents` |
| Reports | `RPT_Plant_Overview`, `RPT_Data_Quality` |

---

## Notes

**The metadata agent** calls an LLM through OpenRouter to propose mappings for column headers it has not seen before. Only column names and the existing mappings leave the tenant — no data rows. It writes to a proposal queue; it has no write access to production metadata. Approval is manual by design, and the reasoning for that is in [section 7](docs/DESIGN.md).

**The API key** is not in this repository and not in the notebook. It is read at run time from Azure Key Vault via `notebookutils.credentials.getSecret`.

**The source data** supplied by MultiBase is not published here.
