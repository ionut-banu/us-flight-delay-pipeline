# us-flight-delay-pipeline

## ✈️ US Flight Delay Analytics Pipeline

End-to-end batch ELT pipeline built with Terraform, Kestra, dbt, and BigQuery on GCP.

This project ingests BTS US on-time performance data for 2022–2024, loads it into BigQuery, transforms it with dbt, and produces analytics-ready models for airline delay trends, cancellation patterns, and route performance.

Built as the capstone project for the [DataTalks.Club Data Engineering Zoomcamp](https://github.com/DataTalksClub/data-engineering-zoomcamp).

## Questions answered

- Which airlines have the worst on-time performance, and why?
- Is flight delay getting better or worse over time?
- Which routes, airports, and carriers contribute most to delays and cancellations?

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
├── docker-compose.yml
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
│   └── flows/
│       ├── 01_ingest_lookups.yml
│       └── 02_ingest_flights.yml
│
└── dbt/
    ├── dbt_project.yml
    ├── profiles.yml               ← GITIGNORED — never committed
    ├── profiles.yml.example       ← committed template
    ├── packages.yml
    ├── schema.yml
    └── models/
        ├── staging/
        │   ├── sources.yml
        │   ├── stg_flights.sql
        │   ├── stg_airports.sql
        │   └── stg_carriers.sql
        ├── intermediate/
        │   └── int_flights_enriched.sql
        └── mart/
            ├── mart_carrier_performance.sql
            └── mart_route_performance.sql
```

## Prerequisites

Install these locally before starting:

- Google Cloud SDK (`gcloud`)
- Terraform
- Docker and Docker Compose
- Python 3.11+
- A GCP project

---

## Phase 1 — GCP project and service account

### 1. Create the GCP project

```bash
export PROJECT_ID="your-project-id"   # must be globally unique

gcloud projects create $PROJECT_ID
gcloud config set project $PROJECT_ID
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

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:us-flight-delay-pipeline-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/bigquery.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:us-flight-delay-pipeline-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

mkdir -p keys

gcloud iam service-accounts keys create ./keys/gcp-creds.json \
  --iam-account=us-flight-delay-pipeline-sa@$PROJECT_ID.iam.gserviceaccount.com
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
  -var="project_id=$PROJECT_ID" \
  -var="bucket_name=$PROJECT_ID-flights-lake"

terraform apply \
  -var="project_id=$PROJECT_ID" \
  -var="bucket_name=$PROJECT_ID-flights-lake"
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
  -var="project_id=$PROJECT_ID" \
  -var="bucket_name=$PROJECT_ID-flights-lake"
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

1. `01_ingest_lookups.yml`
2. `02_ingest_flights.yml`

The first flow loads lookup/reference tables. The second loads monthly or yearly flight records into the raw BigQuery dataset.

---

## Phase 4 — dbt local setup

Use a dedicated Python virtual environment for dbt.

### 1. Create and activate the virtual environment

```bash
python3 -m venv .venv
source .venv/bin/activate
```

### 2. Upgrade pip and install dbt

```bash
python -m pip install --upgrade pip
python -m pip install dbt-bigquery
```

### 3. Verify the installation

```bash
which python
which pip
which dbt
dbt --version
```

Expected result:

- `python`, `pip`, and `dbt` should resolve from `.venv/bin/`
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
dbt deps --profiles-dir .
dbt debug --profiles-dir .
dbt run --profiles-dir .
dbt test --profiles-dir .
```

### 6. Generate documentation

```bash
dbt docs generate --profiles-dir .
dbt docs serve --profiles-dir .
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
7. Run `dbt deps`, `dbt debug`, `dbt run`, and `dbt test`
8. Generate dbt docs
9. Build the dashboard on top of the mart models

---

## Data model

The dbt project builds models in layers:

- **Staging**: clean raw flight, carrier, and airport data
- **Intermediate**: enrich flights with joined reference data
- **Mart**: carrier and route performance models for analytics and dashboards

---

## Cleanup

To avoid GCP charges:

```bash
cd terraform

terraform destroy \
  -var="project_id=$PROJECT_ID" \
  -var="bucket_name=$PROJECT_ID-flights-lake"
```

Stop local services when finished:

```bash
docker compose down
deactivate
```