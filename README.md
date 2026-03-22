# us-flight-delay-pipeline

## ✈️ US Flight Delay Analytics Pipeline

End-to-end batch data pipeline built with Terraform, Kestra, dbt, and BigQuery on GCP. Analyzes 21M+ US flights (2022–2024) on-time performance to surface airline delay trends and cancellation patterns using BTS data. Built as the capstone project for the
[DataTalks.Club Data Engineering Zoomcamp](https://github.com/DataTalksClub/data-engineering-zoomcamp).

### Problem Statement

US flight delays cost airlines and passengers billions of dollars annually.
This pipeline ingests 3 years of BTS on-time performance data (~21M flights),
transforms it in BigQuery, and surfaces two key questions via a dashboard:

- Which airlines have the worst on-time performance, and why?
- Is flight delay getting better or worse over time?

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
│   └── gcp-creds.json             ← your GCP service account key
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
    ├── profiles.yml.example       ← committed — template only
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

Phase 1 — GCP Service Account Setup
This is the only fully manual phase. Every command goes in your terminal.

Step 1: Create the GCP Project

```bash
# Set your project name once — reuse this variable throughout
export PROJECT_ID="your-project-id"   # must be globally unique

gcloud projects create $PROJECT_ID
gcloud config set project $PROJECT_ID

# Link billing (required for BigQuery + GCS)
# Do this manually in: console.cloud.google.com/billing
```

Step 2: Enable Required APIs

```bash
gcloud services enable \
  bigquery.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com
```

Step 3: Create the Service Account + Download Key

```bash
# Create the service account
gcloud iam service-accounts create us-flight-delay-pipeline-sa \
  --display-name="US Flight Delay Pipeline Service Account"

# Grant BigQuery Admin
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:us-flight-delay-pipeline-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/bigquery.admin"

# Grant Storage Admin
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:us-flight-delay-pipeline-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

# Download the JSON key into your keys/ folder
mkdir -p keys
gcloud iam service-accounts keys create ./keys/gcp-creds.json \
  --iam-account=us-flight-delay-pipeline-sa@$PROJECT_ID.iam.gserviceaccount.com
```

Step 4: Set the .env File

```bash
# .env.example (committed to GitHub — template only)
GCP_PROJECT_ID=your-project-id
GCP_REGION=us-central1
GCP_BUCKET_NAME=your-project-id-flights-lake
GCP_CREDENTIALS_PATH=../keys/gcp-creds.json
```

```bash
# Actual usage: copy and fill in
cp .env.example .env
# Edit .env with your real values
```

How the Key Gets Used

The gcp-creds.json file flows into three places — each consumes it differently:

```text
keys/gcp-creds.json
    │
    ├── Terraform ──────► provider "google" { credentials = file("../keys/gcp-creds.json") }
    │
    ├── dbt ─────────────► profiles.yml: keyfile: ../keys/gcp-creds.json
    │
    └── Kestra ──────────► stored as a secret → injected into flows as {{ secret('GCP_CREDS') }}
```

Phase 2 — Terraform

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

After apply you will see:

```text
Outputs:
bucket_name = "your-project-id-flights-lake"
raw_dataset = "flights_raw"
dbt_dataset = "flights_dbt"
To tear everything down when you're done (avoids GCP costs):
```

```bash
terraform destroy \
  -var="project_id=$PROJECT_ID" \
  -var="bucket_name=$PROJECT_ID-flights-lake"
```

Phase 3 — Kestra (Docker Compose)

```bash
docker-compose up -d
# Kestra UI → http://localhost:8080
```

Storing the GCP Key in Kestra

In the Kestra UI, go to Namespaces → flights → KV Store, and add:

| Key             | Value                                                         |
| --------------- | ------------------------------------------------------------- |
| GCP_PROJECT_ID  | your-project-id                                               |
| GCP_LOCATION    | Data location for the BigQuery datasets (click on a dataset and go to Details tab)                           |
| GCP_BUCKET_NAME | your-project-id-flights-lake                                  |
