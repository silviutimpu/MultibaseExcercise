# Fabric notebook source

# METADATA ********************

# META {
# META   "kernel_info": {
# META     "name": "synapse_pyspark"
# META   },
# META   "dependencies": {
# META     "lakehouse": {
# META       "default_lakehouse": "c1f5c887-d1cd-449e-b587-fd9cd21e2f57",
# META       "default_lakehouse_name": "LH_Incidents",
# META       "default_lakehouse_workspace_id": "b457e757-c2bf-4d03-bd9e-a8398292560c",
# META       "known_lakehouses": [
# META         {
# META           "id": "c1f5c887-d1cd-449e-b587-fd9cd21e2f57"
# META         }
# META       ]
# META     }
# META   }
# META }

# PARAMETERS CELL ********************

API_KEY   = notebookutils.credentials.getSecret(
                "https://operoutermultibase.vault.azure.net/",
                "openrouter-key")
MODEL     = "deepseek/deepseek-v4-flash-0731"
SOURCE_ID = 2
WAREHOUSE = "WH_Incidents"

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

import com.microsoft.spark.fabric

mappings = spark.read.synapsesql(f"{WAREHOUSE}.meta.ColumnMapping")
bronze   = spark.read.synapsesql(f"{WAREHOUSE}.bronze.incidents_raw")

known = {r.SourceColumn for r in
         mappings.filter(f"SourceId = {SOURCE_ID} AND IsActive = true")
                 .select("SourceColumn").distinct().collect()}

arrived = {r.SourceColumn for r in
           bronze.filter(f"SourceID = {SOURCE_ID}").select("SourceColumn").distinct().collect()}

unmapped = sorted(arrived - known)

examples = [(r.SourceColumn, r.Classification, r.CodeGroup) for r in
            mappings.filter("IsActive = true")
                    .select("SourceColumn", "Classification", "CodeGroup").collect()]

print("de mapat:", unmapped)
print("exemple :", examples)

# Fără asta, agentul ar apela modelul la fiecare rulare de pipeline,
# inclusiv când nu are ce mapa.
if not unmapped:
    print("nimic de mapat pentru sursa", SOURCE_ID)
    notebookutils.notebook.exit("no-op")

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

# examples e o listă de rânduri: (coloană sursă, clasificare, grupă)
#   ('Incidents IC 01/02',     'Internal', '01/02')
#   ('Externe Vorfälle 05/06', 'External', '05/06')

# --- vocabularul permis, cules din mapările deja aprobate ---
classifications = set()
code_groups     = set()

for source_column, classification, code_group in examples:
    classifications.add(classification)
    code_groups.add(code_group)

classifications = sorted(classifications)
code_groups     = sorted(code_groups)

# --- exemplele, transformate în text pentru prompt ---
example_lines = ""
for source_column, classification, code_group in examples:
    example_lines += f'  "{source_column}"  ->  {classification}, {code_group}\n'

# --- coloanele de mapat, transformate în text ---
target_lines = ""
for column in unmapped:
    target_lines += f'  "{column}"\n'


prompt = f"""Mapează fiecare denumire de coloană la o clasificare și o grupă de coduri.

Valori permise pentru classification: {classifications}
Valori permise pentru code_group:     {code_groups}

Exemple din sistem:
{example_lines}
Coloane de mapat:
{target_lines}
Răspunde DOAR cu JSON, fără text în jur:
{{"mappings": [{{"source_column": "...", "classification": "...", "code_group": "...", "confidence": 0.0, "rationale": "..."}}]}}"""

print(prompt)

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark",
# META   "frozen": false,
# META   "editable": true
# META }

# CELL ********************

import json
import requests

# --- ce trimitem ---
url = "https://openrouter.ai/api/v1/chat/completions"

headers = {
    "Authorization": f"Bearer {API_KEY}"
}

body = {
    "model": MODEL,
    "messages": [
        {"role": "user", "content": prompt}
    ],
    "temperature": 0          # 0 = același răspuns la același prompt
}

# --- apelul ---
try:
    response = requests.post(url, headers=headers, json=body, timeout=60)
    response.raise_for_status()

    answer = response.json()["choices"][0]["message"]["content"]

    # modelul poate scrie text în jurul JSON-ului; păstrăm doar ce e între { și }
    start = answer.find("{")
    end   = answer.rfind("}") + 1
    proposals = json.loads(answer[start:end])["mappings"]

except Exception as e:
    # Agentul e consultativ. Un serviciu extern indisponibil nu are voie să
    # oprească încărcarea datelor.
    print("agent indisponibil:", e)
    notebookutils.notebook.exit("agent-failed")


# --- vocabularul e impus de cod, nu doar cerut în prompt ---
valid = []
for p in proposals:
    if p.get("classification") in classifications and p.get("code_group") in code_groups:
        valid.append(p)

print("propuse:", len(proposals), "| valide:", len(valid))

for p in valid:
    confidence = p.get("confidence", 0)
    rationale  = p.get("rationale", "")
    print(f'  {p["source_column"]} -> {p["classification"]} {p["code_group"]} '
          f'| {confidence:.2f} | {rationale}')

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

from datetime import datetime, timezone
from pyspark.sql import Row

# Dacă filtrul de vocabular a respins tot, nu avem ce scrie —
# iar createDataFrame pe o listă goală ar crăpa notebook-ul.
if not valid:
    print("nicio propunere validă")
    notebookutils.notebook.exit("no-valid-proposals")

# un singur moment pentru toate rândurile din această rulare
now = datetime.now(timezone.utc)

rows = []
for p in valid:
    rows.append(Row(
        SourceId       = SOURCE_ID,
        SourceColumn   = p["source_column"],
        Classification = p["classification"],
        CodeGroup      = p["code_group"],
        Confidence     = float(p.get("confidence", 0)),
        Rationale      = p.get("rationale", ""),
        ModelName      = MODEL,
        ProposedAt     = now,
    ))

df = spark.createDataFrame(rows)
df.write.mode("append").format("delta").saveAsTable("column_mapping_proposal")

display(spark.table("column_mapping_proposal"))

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }
