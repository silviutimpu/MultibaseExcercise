# MultiBase — Incident Analytics on Microsoft Fabric
## Design document

Every decision here has a reason and, where it mattered, a rejected alternative.

---

## 1. The problem

The source is wide: four measure columns whose names carry two dimensions.

```
Incidents  IC   01/02
           └┬┘  └─┬─┘
            │     └── Code group:     01/02 | 05/06
            └──────── Classification: IC (Internal) | Ext (External)
```

**Three of the four mockup visuals are impossible on this shape.** A slicer filters values in a column, and "Internal" is not a value anywhere. An axis displays distinct rows, and those four categories are columns.

So the unpivot to long form is a technical precondition, not a stylistic preference.

---

## 2. Metadata-driven

How does the solution know that `Incidents IC 01/02` means `Internal` + `01/02`?

That knowledge can live in the SQL:

```sql
SELECT Plant, Month, 'Internal' AS Classification, '01/02' AS CodeGroup, [Incidents IC 01/02] ...
UNION ALL
SELECT Plant, Month, 'Internal', '05/06', [Incidents IC 05/06] ...
```

Or in a table, with the transformation joining to it:

```sql
SELECT b.Plant, b.Month, m.Classification, m.CodeGroup, b.Value
FROM   bronze.incidents_raw AS b
JOIN   meta.ColumnMapping   AS m ON m.SourceColumn = b.SourceColumn
```

**I chose the second.** The first names every column in code, so a new column means editing a procedure. The second names none.

| | Mapping in code | Mapping in data |
|---|---|---|
| Who changes it | a developer | an analyst |
| What it takes | edit → PR → deploy → test | one `INSERT` |
| What can break | the procedure | that row |
| Revert | redeploy | `DELETE` |

**Why not a regex on the column name.** If the client sends `INT` instead of `IC` it misclassifies silently, exceptions have nowhere to live, and nobody reviews a regex — while anyone can review four rows.

---

## 3. The metadata tables

**Cutting principle:** a column stays only if code reads it today.

### `meta.SourceRegistry` — one row per source

Read by the pipeline's Lookup and ForEach. The column that does the work is `KeyColumns`: it feeds the dynamic unpivot in M, so a source keyed on `Plant,Line,Month` is a new row rather than new code.

### `meta.ColumnMapping` — one row per measure column

Read by the warehouse join. `SourceId` is part of the key, because a column name is unique only within a source. This is a **dbt seed**.

| MappingId | SourceId | SourceColumn | Classification | CodeGroup | IsActive |
|---|---|---|---|---|---|
| 1 | 1 | Incidents IC 01/02 | Internal | 01/02 | 1 |

### `meta.DQRules` — one row per rule

| RuleId | SourceId | RuleName | RuleType | TargetColumn | Severity |
|---|---|---|---|---|---|
| 1 | *NULL* | All source columns are mapped | SchemaDrift | | Warning |
| 2 | *NULL* | File is not empty | RowCount | | Error |
| 3 | *NULL* | Plant is populated | NotNull | Plant | Error |
| 4 | *NULL* | Incidents are not negative | Range | Value | Error |
| 5 | *NULL* | Fact grain is unique | Unique | | Error |
| 6 | *NULL* | No mapped column is missing | MissingColumn | | Error |

**`SourceId NULL` means every source**, and a rule with a `SourceId` applies to that one only — global default, targeted override. The first version stored a copy per source; a source registered without its rules was then validated against nothing while the pipeline stayed green. Global rules make that impossible rather than merely discouraged.

**Why `RuleType` plus a JSON parameter column:** one block of code per type. A new rule of an existing type is a row; a new type is a block. Cost grows with types, not rules.

**`Severity` is the fail-loud-or-silent decision, taken per rule.** Rules 1 and 6 are the same check from opposite ends — columns that arrived without a mapping, and mappings whose column never arrived — and they carry different severities. An extra column leaves the load correct. A missing one leaves it incomplete, and since incidents are a count, the report then shows a decrease that never happened.

---

## 4. Architecture

```
  Files/landing/*.xlsx
         │  Lookup meta.SourceRegistry → ForEach
         ▼
  Dataflow Gen2        Excel → Table.UnpivotOtherColumns → bronze
         ▼
  meta.RunValidations  6 rules → audit.ValidationLog · Error? THROW
         ▼
  NB_Metadata_Agent    unmapped columns → LLM → proposal queue
         ▼
  Warehouse            bronze JOIN meta.ColumnMapping → silver → gold
         ▼
  Direct Lake          SM_Incidents → RPT_Plant_Overview
```

| Component | Why it exists |
|---|---|
| Lakehouse | the only place a raw file can sit |
| Dataflow Gen2 | M has a natively dynamic unpivot; T-SQL does not |
| Warehouse | joins, aggregation, star schema, validation |
| Notebook | the only component that can call an external API |
| Data pipeline | orchestration, and the `Lookup → ForEach` pattern |
| Direct Lake | a semantic model with no refresh to schedule |

**Why the unpivot is in M.** `Table.UnpivotOtherColumns` takes the columns to keep and unpivots the rest, so it never names the four measure columns and a fifth is picked up automatically. T-SQL's `UNPIVOT` needs the literal list, and making it dynamic means `sp_executesql`. Generally: M is better at transformations that depend on shape, SQL at set operations.

**Landing zone.** `Files/landing/` holds the file as the source sent it, immutable. What it buys is reprocessing — a bug found three months later is fixed by re-running from the original.

**Why both a Lakehouse and a Warehouse.** A Warehouse has no `Files` area, so the Excel can only land in a Lakehouse; the Lakehouse SQL endpoint is read-only, so metadata cannot be authored there with T-SQL. This is not two silos: both write Delta Parquet into the same OneLake, and the Warehouse reads Lakehouse tables natively with three-part naming.

---

## 5. Orchestration

```
[Get sources] ─► [For each source]                                                        ─► [Load gold]
   Lookup          └─ [Clear Bronze] ─► [Load Bronze] ─► [Run Validations] ─► [Propose Mapping]
```

Validation sits inside the loop because each run checks one source and stamps the log with its id. After the loop it would have needed a hard-coded `SourceId`.

**Delete-then-append, not Replace.** A Dataflow Gen2 destination cannot be parameterised, so every source writes to the same table:

| Method | With two sources |
|---|---|
| `Replace` | the second deletes the first one's rows |
| `Append` alone | doubles on every re-run |
| **`Append` + delete by `SourceId`** | correct and idempotent |

The dataflow offers "delete everything" or "delete nothing". `bronze.DeleteSource` is the missing third option.

Dataflow parameters are **optional rather than Required**: with Required, a dataflow can no longer be run manually or scheduled, which would have removed isolated testing.

---

## 6. The validation engine

Six blocks, one per rule type, each of the same shape: measure into a variable, then insert one log row per active rule of that type. No cursor, no loop. A block produces nothing if no rule of its type exists — the metadata decides what runs.

**Where "generic" stops.** A fully generic engine would build SQL from `RuleType` and `TargetColumn` and execute it. That is a SQL injection surface and untestable.

**Rule types are code, rule instances are metadata.** The code knows how NotNull is checked; the metadata says on which source, which column, which threshold, with what severity. dbt tests, Great Expectations and Deequ all work this way.

The column name from metadata is compared, never concatenated:

```sql
LEFT JOIN null_counts AS n ON n.ColName = r.TargetColumn
```

`LEFT JOIN` rather than `INNER`: a rule on an unknown column fails visibly instead of vanishing from the log.

**Stopping.** Any `Passed = 0` with `Severity = 'Error'` raises `THROW`, the activity fails, and `gold.LoadGold` never starts, so gold keeps the last valid load. The check is at the end, so all six rules always run and you see the whole picture rather than the first failure.

Unlike `gold.LoadGold`, this procedure is deliberately **not** in a transaction — after a broken load you want the evidence in the log.

**Accepted limitation.** The `Unique` rule does not read its column list from `RuleParameters`; the grain is fixed in code. Making it dynamic would need a `GROUP BY` built from a string.

---

## 7. The metadata agent

The weak point of a metadata-driven design is that somebody still has to write the metadata.

Validation reports the unmapped columns. The notebook sends those names, plus the existing mappings as examples, to an LLM and writes the result to a proposal queue in the Lakehouse. A person approves, and a T-SQL procedure moves the approved rows into `meta.ColumnMapping`. The next load brings the data into gold.

**A proposal queue, not a direct write.** The agent has no write access to `meta.*` — not a policy it respects, something it cannot do.

**A closed vocabulary, derived from the data.** The model picks among existing `Classification` and `CodeGroup` values, and that list comes from the approved mappings rather than the prompt. Generation becomes classification.

**The prompt asks; the code enforces.** Every proposal is filtered against the allowed values in Python. The gap between proposed and valid is the hallucination rate, measured.

**Only metadata leaves the tenant** — column names, example mappings, allowed values. No data rows. The prompt is printed before the call, so this is verifiable rather than asserted. The precise phrasing: structure leaves the tenant, not content.

### Why approval stays manual

The filter guarantees a **valid** mapping, not a **correct** one. The worst case is plausible and wrong — `Incidents internes 05/06` classified as External. It passes the filter, and internal incidents are counted as external from then on, with no error anywhere.

That is the class of defect the rest of this solution prevents.

What would justify automation is a real confidence signal. The model's self-reported confidence is not one: it returned the maximum value for every proposal, so the threshold filters nothing. Agreement between two models would be real, at the cost of one extra call.

### The agent is advisory

If the API is unavailable the notebook exits cleanly, the activity succeeds, and the load continues. An external service must not be able to stop a data pipeline. A second guard on the way in: if nothing is unmapped it exits before calling the model.

Three additional sources with German, French and Spanish headers were mapped correctly. **German was the hard case** — `Vorfälle` has no lexical similarity to `Incidents`, while French and Spanish are near-cognates of the English examples.

---

## 8. The gold model

**One combined dimension, `DimIncidentType`, not two.** Plant and date are independent concepts; `Classification` and `CodeGroup` are two attributes of one — there is no "Internal" without a code.

The mockup's "Incident mix" is where the designs diverge. Combined, `IncidentTypeName` goes on the axis. Separate, those four categories do not exist as a column: either both fields go on the axis and Power BI builds a drill hierarchy, or you add a calculated column concatenating them — rebuilding the combined design inside the model.

```
 DimPlant  ─────┐
 DimDate  ──────┼──► FactIncidents
 DimIncidentType┘      PlantKey · DateKey · IncidentTypeKey · Incidents
```

`DimIncidentType` is derived from the mapping table rather than written by hand:

```sql
SELECT DISTINCT Classification, CodeGroup FROM meta.ColumnMapping WHERE IsActive = 1
```

Four plants and four header languages later, it is still four rows. `SortOrder` exists because alphabetically "Ext" precedes "Int" and the mockup needs the opposite.

**Why the date table is daily, not monthly.** Time intelligence and "Mark as Date Table" need a date column contiguous at day level; a monthly table has gaps and the marking fails. Marking the table also makes time intelligence remove filters from **all** its columns — without it, a filter on `Period` survives the year shift and every PY measure returns blank, with no error.

**Surrogate keys** are not necessary at this size. They buy the star schema convention, better VertiPaq compression, and an open door to SCD2. Not over-engineering, because it is the default pattern rather than an addition.

### Two Fabric specifics that changed the design

**PK and FK are `NOT ENFORCED`.** You can declare them; the database will still accept orphans. That is why the `Unique` rule is not decorative — it is the only thing checking the grain.

**Direct Lake does not read views.** Point a Direct Lake model at a view and it falls back to DirectQuery, so gold has to be materialised regardless of size.

| Layer | Where | Form | Why |
|---|---|---|---|
| landing | Lakehouse `Files/` | file | forced — no file area in a Warehouse |
| bronze | Warehouse | table | structured landing, audited |
| silver | Warehouse | view | cheap derivation |
| gold | Warehouse | tables | forced — Direct Lake needs physical tables |

**The Lakehouse holds the raw file. Everything that is a table lives in the Warehouse.** My first version put bronze in the Lakehouse per the medallion convention; I moved it, because that convention exists for unstructured or large data.

Keeping silver as a view mattered more than expected: when a mapping is approved, silver sees the new rows immediately, so only `gold.LoadGold` runs and bronze is not reloaded.

**What I did not invent.** `DimPlant` has one useful column. The source has no region, country, capacity or manager, and I added none.

---

## 9. Stack choice

**SQL-first.** All transformation and validation in T-SQL. The exercise ends in a live demo, and a simple stack defended well beats an impressive one read hesitantly.

The only notebook is the metadata agent, where Python is mandatory because T-SQL cannot make an HTTP call.

---

## 10. Deliberately excluded

| Excluded | Why |
|---|---|
| `SourceType`, `LoadMode` in the registry | nothing branches on them |
| `MeasureName` in ColumnMapping | same value on every row |
| `AllowedValues` as a rule type | on plants it is a trap — a new plant is good news, not a defect |
| **EAV** for ColumnMapping | needs a pivot back on every run, everything becomes `VARCHAR`, no constraints, unreadable |
| DAX definitions as metadata | DAX changes rarely and reads badly when generated |
| A star-schema generator | at four tables it costs more than it saves |
| Credentials in metadata or code | Fabric connections for data sources, Azure Key Vault for the API key |
| Automatic source registration from the folder | it would move `SheetName` and `KeyColumns` from data into code |

EAV is the line between metadata-driven and over-engineering.

---

## 11. Known gaps

**A partially mapped source.** If an existing file gains a new column, the others load and that one is dropped. The plant appears with understated figures and the pipeline stays green. More dangerous than a source that fails entirely: an absent plant gets noticed, a present one with low numbers looks safe.

The fix is for severity to depend on the state of the source — onboarding is a warning, a partial load is an error. Today the rule carries a fixed severity, so it cannot tell the difference.

**A warning nobody reads.** The validation log made drift visible only to someone who knew to query it. `RPT_Data_Quality` plus an alert close that: the alert says something happened, the report says what. The business report was left untouched — different audience.

**Self-reported confidence.** The threshold is a parameter; the number behind it is not calibrated.

---

## 12. Decision journal

| # | Decision | Why | Rejected |
|---|---|---|---|
| 1 | Unpivot wide → long | 3 of 4 mockup visuals are impossible otherwise | wide + DAX |
| 2 | Mapping in a table | moves the change from code risk to data risk | hard-coded `UNION ALL` |
| 3 | No string parsing | explicit and auditable beats clever and silent | regex on the column name |
| 4 | Unpivot in M | M has a natively dynamic unpivot | `UNPIVOT` + `sp_executesql` |
| 5 | Explicit columns, not EAV | typing, readability, constraints | EAV |
| 6 | Minimal metadata | an unused column is a question with no payoff | an anticipatory registry |
| 7 | ~~Notebook for validation~~ **reversed by #21** | *(then: the only component seeing the raw file)* | a notebook as JD filler |
| 8 | SQL-first | defensible in a live demo | PySpark |
| 9 | `Severity` per rule | fail-loud-or-silent is not a global decision | one global setting |
| 10 | Combined `DimIncidentType` | one concept, two attributes; the mockup needs a flat axis | two dimensions |
| 11 | Daily `DimDate` | time intelligence needs day-level contiguity | a monthly table |
| 12 | Gold materialised, silver a view | Direct Lake reads only physical tables | views throughout |
| 13 | No invented attributes | fabricated data as real is worse than a thin dimension | plausible Region/Country |
| 14 | Lakehouse **and** Warehouse | no `Files` in a Warehouse; read-only SQL in a Lakehouse | Lakehouse-only |
| 15 | Metadata in the Warehouse | instant T-SQL authoring | metadata in the Lakehouse |
| 16 | Gold structure separate from load | recreating tables forces the model to rebind | CTAS |
| 17 | Gold load in a procedure | stays a versioned object the client can read | inline SQL in the pipeline |
| 18 | Transaction in `LoadGold` | a failed load leaves yesterday's data | no transaction |
| 19 | `Append` + delete by `SourceId` | the destination cannot be parameterised | `Replace`, or plain `Append` |
| 20 | Dataflow parameters optional | Required removes manual and scheduled runs | Required |
| 21 | Validation in T-SQL | no Spark needed to count rows in a Warehouse | a notebook (reverses #7) |
| 22 | Types in code, instances in metadata | generated SQL is an injection surface and untestable | a fully generic engine |
| 23 | `MissingColumn` Error, `SchemaDrift` Warning | one leaves the data correct, the other incomplete | the same severity |
| 24 | Validation inside the ForEach | the run is per source and stamps the log | one activity after the loop |
| 25 | `RunValidations` without a transaction | after a broken load you want the evidence | a transaction |
| 26 | `LEFT JOIN` in NotNull | an unknown column fails visibly | `INNER JOIN`, silent |
| 27 | Global rules (`SourceId NULL`) | no source can escape validation | one copy per source |
| 28 | Agent writes to a proposal queue | no write access to production metadata | writing into `meta.ColumnMapping` |
| 29 | Approval stays manual | the filter guarantees valid, not correct | auto-approval above a threshold |
| 30 | The agent fails clean | an external service must not stop a pipeline | letting it propagate |
| 31 | Data quality in a separate report | different audience | a second page in the main report |
| 32 | API key in Azure Key Vault | it never enters a file, so Git integration is safe | the key inline in the notebook |
