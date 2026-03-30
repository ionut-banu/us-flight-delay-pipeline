# us-flight-delay-pipeline

## ✈️ US Flight Delay Analytics Pipeline

End-to-end batch ELT pipeline built with Terraform, Kestra, dbt, and BigQuery on GCP.

Built as the capstone project for the [DataTalks.Club Data Engineering Zoomcamp](https://github.com/DataTalksClub/data-engineering-zoomcamp).

---

## Problem Description

Flight delays cost the US economy an estimated **$33 billion per year** — affecting passengers, airlines, and airports alike. The Bureau of Transportation Statistics (BTS) publishes detailed on-time performance records for every domestic US flight, but the raw data is split across hundreds of monthly CSV files, lacks any join to carrier or airport reference data, and contains no pre-built aggregations. This makes it nearly impossible to answer even basic operational questions without significant data engineering work.

**The core problem:** there is no analytics-ready layer on top of this public dataset. Analysts cannot easily answer:

- Which airlines consistently underperform, and is their delay driven by carrier operations, late aircraft, or NAS congestion?
- Are delays getting better or worse over time across the industry?
- Which specific routes and airports are the worst offenders for delays and cancellations?

This project solves that by building a fully automated, end-to-end batch ELT pipeline that:

1. **Ingests** raw BTS monthly flight records and lookup tables (carriers, airports) into Google Cloud Storage
2. **Loads** them into BigQuery as a raw data lake layer
3. **Transforms** them with dbt into clean staging models, an enriched intermediate layer (flights joined with carrier and airport names), and two analytics mart tables optimized for dashboarding
4. **Produces** a dashboard that surfaces delay trends by carrier, route, and time period

The result is a reproducible, cloud-native pipeline that turns 30+ years of raw government flight data into actionable insights — provisioned entirely through code with Terraform and orchestrated automatically with Kestra.

**Data source:** [BTS On-Time Performance](https://transtats.bts.gov/DL_SelectFields.aspx?gnoyr_VQ=FGJ&QO_fu146_anzr=b0-gvzr)

---

## Questions Answered

- Which airlines have the worst on-time performance, and why (carrier delay vs. NAS vs. weather)?
- Is flight delay getting better or worse over time?
- Which routes, airports, and carriers contribute most to delays and cancellations?

---

## Stack

- **Cloud**: GCP (BigQuery, GCS, IAM)
- **Infrastructure**: Terraform
- **Orchestration**: Kestra
- **Transformations**: dbt Core + dbt-bigquery
- **Language**: SQL, YAML, Python
- **Source data**: BTS On-Time Performance data

## Project structure

```text
us-flight-delay-pipeline/
│
├── .gitignore
├── .env.example
├── README.md
├── Makefile
│
├── keys/                          ← GITIGNORED — never committed
│   └── gcp-creds.json             ← local GCP service account key
│
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
│
├── kestra/
|   ├──docker-compose.yml
│   └──flows/
│       ├── main_flights.01_ingest_lookups.yml
│       └── main_flights.02_ingest_flights.yml
│
└── dbt/
    ├── dbt_project.yml
    ├── profiles.yml               ← GITIGNORED — never committed
    ├── profiles.yml.example       ← committed template
    ├── packages.yml
    └── models/
        ├── staging/
        │   ├── staging.yml
        |   ├── lookups.yml
        │   ├── sources.yml
        │   ├── stg_flights.sql
        │   ├── stg_airports.sql
        │   └── stg_carriers.sql
        ├── intermediate/
        │   ├── intermediate.yml
        |   └── int_flights_enriched.sql
        └── mart/
            ├── mart.yml
            ├── mart_carrier_monthly.sql
            ├── mart_routes.sql
            └── exposures.yml
```

## Prerequisites

Install these locally before starting:

- Google Cloud SDK (`gcloud`)
- Terraform
- Docker and Docker Compose
- Python 3.11+
- [uv](https://docs.astral.sh/uv/) — fast Python package and environment manager
- A GCP project

Install `uv` with the standalone installer (no Python required):

```bash
# macOS / Linux
curl -LsSf https://astral.sh/uv/install.sh | sh

# Windows (PowerShell)
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

---

## Phase 1 — GCP project and service account

### 1. Create the GCP project

```bash
export GCP_PROJECT_ID="your-project-id"   # must be globally unique


gcloud projects create $GCP_PROJECT_ID
gcloud config set project $GCP_PROJECT_ID
```

### 2. Enable required APIs

```bash
gcloud services enable \
  bigquery.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com
```

### 3. Create the service account and download the key

```bash
gcloud iam service-accounts create us-flight-delay-pipeline-sa \
  --display-name="US Flight Delay Pipeline Service Account"


gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:us-flight-delay-pipeline-sa@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/bigquery.admin"


gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:us-flight-delay-pipeline-sa@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.admin"


mkdir -p keys


gcloud iam service-accounts keys create ./keys/gcp-creds.json \
  --iam-account=us-flight-delay-pipeline-sa@$GCP_PROJECT_ID.iam.gserviceaccount.com
```

### 4. Create the local environment file

```bash
cp .env.example .env
```

Example `.env.example`:

```bash
GCP_PROJECT_ID=your-project-id
GCP_REGION=us-central1
GCP_BUCKET_NAME=your-project-id-flights-lake
GCP_CREDENTIALS_PATH=./keys/gcp-creds.json
```

## Credentials flow

The same service account key is used by multiple parts of the project:

```text
keys/gcp-creds.json
    │
    ├── Terraform ──────► provider "google" { credentials = file("../keys/gcp-creds.json") }
    │
    ├── dbt ────────────► profiles.yml: keyfile: ../keys/gcp-creds.json
    │
    └── Kestra ─────────► stored as a Secret and injected into flows
```

---

## Phase 2 — Terraform

Provision the GCS bucket and BigQuery datasets.

```bash
cd terraform


terraform init


terraform plan \
  -var="project_id=$GCP_PROJECT_ID" \
  -var="bucket_name=$GCP_PROJECT_ID-flights-lake"


terraform apply \
  -var="project_id=$GCP_PROJECT_ID" \
  -var="bucket_name=$GCP_PROJECT_ID-flights-lake"
```

Expected outputs:

```text
bucket_name = "your-project-id-flights-lake"
raw_dataset = "flights_raw"
dbt_dataset = "flights_dbt"
```

To tear everything down later:

```bash
terraform destroy \
  -var="project_id=$GCP_PROJECT_ID" \
  -var="bucket_name=$GCP_PROJECT_ID-flights-lake"
```

---

## Phase 3 — Kestra

Start Kestra locally:

```bash
docker compose up -d
```

Open the UI at:

```text
http://localhost:8080
```

### How Kestra authenticates to GCP

Kestra uses Google Application Default Credentials through the `GOOGLE_APPLICATION_CREDENTIALS` environment variable.

In `docker-compose.yml`, the local `keys/` folder is mounted into the container as read-only, and the container points Google client libraries to the service account key file inside that mount.

This means Kestra reads the same service account key file from inside the container at:

```text
/keys/gcp-creds.json
```

### Kestra configuration

In the `flights` namespace, add these values to **KV Store**:

| Key | Value |
|---|---|
| `GCP_PROJECT_ID` | your-project-id |
| `GCP_LOCATION` | BigQuery dataset location, for example `US` |
| `GCP_BUCKET_NAME` | your-project-id-flights-lake |

### Run ingestion flows

Run the flows in this order:

1. `main_flights.01_ingest_lookups.yml`
2. `main_flights.02_ingest_flights.yml`

The first flow loads lookup/reference tables. The second loads monthly or yearly flight records into the raw BigQuery dataset.

---

## Phase 4 — dbt local setup

Use `uv` to manage the Python virtual environment and install dbt.

### 1. Create and activate the virtual environment

```bash
uv venv .venv --python 3.11
source .venv/bin/activate
```

### 2. Install dbt

```bash
uv pip install dbt-bigquery
```

> No separate pip upgrade step is needed — `uv` ships its own dependency resolver and does not rely on pip's version.

### 3. Verify the installation

```bash
which python
which dbt
dbt --version
```

Expected result:

- `python` and `dbt` should resolve from `.venv/bin/`
- `dbt --version` should show dbt Core and the BigQuery plugin

### 4. Configure the dbt profile

```bash
cd dbt
cp profiles.yml.example profiles.yml
```

Edit `profiles.yml` with your real GCP values.

Example:

```yaml
flights:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: service-account
      project: your-project-id
      dataset: flights_dbt
      threads: 4
      keyfile: ../keys/gcp-creds.json
      location: US
      priority: interactive
      timeout_seconds: 300
```

### 5. Install packages and validate the project

```bash
uv run dbt deps --profiles-dir .
uv run dbt debug --profiles-dir .
uv run dbt run --profiles-dir .
uv run dbt test --profiles-dir .
```

### 6. Generate documentation

```bash
uv run dbt docs generate --profiles-dir .
uv run dbt docs serve --profiles-dir . --port 8081
```

### 7. Reactivate dbt in new terminal sessions

Whenever you open a new shell:

```bash
source .venv/bin/activate
```

---

## Run order

Use this order for a full local run:

1. Create the GCP project and service account
2. Apply Terraform
3. Start Kestra
4. Add Kestra KV values
5. Run the Kestra ingestion flows
6. Set up the dbt virtual environment 