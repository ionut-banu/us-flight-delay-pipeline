# ─────────────────────────────────────────────
# Load .env if it exists, export all vars to
# sub-shells so every recipe can read them.
# The leading dash suppresses the error when
# .env doesn't exist yet.
# ─────────────────────────────────────────────
-include .env
export

# Derived variable — defined once, used everywhere
SA_NAME  := us-flight-delay-pipeline-sa
SA_EMAIL := $(SA_NAME)@$(GCP_PROJECT_ID).iam.gserviceaccount.com

# ─────────────────────────────────────────────
# Help — shown by default when you run `make`
# ─────────────────────────────────────────────
.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo ""
	@echo "  US Flight Delay Pipeline"
	@echo ""
	@echo "  Phase 1 — GCP bootstrap"
	@echo "    make gcp-project   Create the GCP project and set it as active"
	@echo "    make gcp-apis      Enable BigQuery, GCS, and IAM APIs"
	@echo "    make gcp-sa        Create the service account and download the key"
	@echo "    make gcp-env       Copy .env.example → .env (skips if .env exists)"
	@echo "    make phase1        Run all Phase 1 steps in order"
	@echo ""
	@echo "  Phase 2 — Terraform"
	@echo "    make tf-init       Initialise the Terraform working directory"
	@echo "    make tf-plan       Preview infrastructure changes (dry run)"
	@echo "    make tf-apply      Provision GCS bucket + BigQuery datasets"
	@echo "    make tf-destroy    Tear down all Terraform-managed resources"
	@echo "    make phase2        tf-init + tf-apply"
	@echo ""
	@echo "  Phase 3 — Kestra"
	@echo "    make kestra-up      Start Kestra in the background (docker compose up -d)"
	@echo "    make kestra-down    Stop Kestra"
	@echo "    make kestra-logs    Tail Kestra container logs"
	@echo "    make kestra-restart Restart Kestra (down then up)"
	@echo "    make kestra-status  Show running container status"
	@echo "    make phase3         Start Kestra + print KV Store setup instructions"
	@echo ""
	@echo "  Phase 4 — dbt"
	@echo "    make dbt-venv          Create .venv with uv and install dbt-bigquery"
	@echo "    make dbt-profile       Copy profiles.yml.example → profiles.yml (skips if exists)"
	@echo "    make dbt-deps          Install dbt packages (dbt deps)"
	@echo "    make dbt-debug         Validate BigQuery connection (dbt debug)"
	@echo "    make dbt-run           Build all models (dbt run)"
	@echo "    make dbt-test          Run all tests (dbt test)"
	@echo "    make dbt-docs-generate Generate dbt documentation"
	@echo "    make dbt-docs-serve    Serve dbt docs at http://localhost:8081"
	@echo "    make dbt-docs          Generate then serve docs"
	@echo "    make phase4            Full dbt setup: venv → profile → deps → debug → run → test"
	@echo ""

# ─────────────────────────────────────────────
# Phase 1 targets
# ─────────────────────────────────────────────

.PHONY: gcp-project
gcp-project:
	@echo "→ Creating GCP project: $(GCP_PROJECT_ID)"
	gcloud projects create $(GCP_PROJECT_ID) || echo "  Project already exists, continuing"
	gcloud config set project $(GCP_PROJECT_ID)

.PHONY: gcp-apis
gcp-apis:
	@echo "→ Enabling APIs on $(GCP_PROJECT_ID)"
	gcloud services enable \
		bigquery.googleapis.com \
		storage.googleapis.com \
		iam.googleapis.com

.PHONY: gcp-sa
gcp-sa:
	@echo "→ Creating service account: $(SA_NAME)"
	gcloud iam service-accounts create $(SA_NAME) \
		--display-name="US Flight Delay Pipeline Service Account" \
		|| echo "  Service account already exists, continuing"
	@echo "→ Granting BigQuery Admin"
	gcloud projects add-iam-policy-binding $(GCP_PROJECT_ID) \
		--member="serviceAccount:$(SA_EMAIL)" \
		--role="roles/bigquery.admin"
	@echo "→ Granting Storage Admin"
	gcloud projects add-iam-policy-binding $(GCP_PROJECT_ID) \
		--member="serviceAccount:$(SA_EMAIL)" \
		--role="roles/storage.admin"
	@echo "→ Downloading key to ./keys/gcp-creds.json"
	mkdir -p keys
	gcloud iam service-accounts keys create ./keys/gcp-creds.json \
		--iam-account=$(SA_EMAIL)

.PHONY: gcp-env
gcp-env:
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "  Created .env from .env.example — fill in your real values"; \
	else \
		echo "  .env already exists, skipping"; \
	fi

.PHONY: phase1
phase1: gcp-env gcp-project gcp-apis gcp-sa
	@echo ""
	@echo "✓ Phase 1 complete."
	@echo "  Key written to ./keys/gcp-creds.json"
	@echo "  Edit .env if you haven't already, then run: make phase2"
	@echo ""


# ─────────────────────────────────────────────
# Phase 2 — Terraform
# ─────────────────────────────────────────────

# Shared Terraform var flags — derived from .env, used in every terraform command
TF_VARS := -var="project_id=$(GCP_PROJECT_ID)" -var="bucket_name=$(GCP_BUCKET_NAME)"
TF_DIR  := terraform

.PHONY: tf-init
tf-init:
	@echo "→ Initialising Terraform"
	cd $(TF_DIR) && terraform init

.PHONY: tf-plan
tf-plan:
	@echo "→ Planning Terraform changes"
	cd $(TF_DIR) && terraform plan $(TF_VARS)

.PHONY: tf-apply
tf-apply:
	@echo "→ Applying Terraform"
	cd $(TF_DIR) && terraform apply $(TF_VARS) -auto-approve

.PHONY: tf-destroy
tf-destroy:
	@echo "→ Destroying Terraform-managed resources"
	@echo "  WARNING: this will delete the GCS bucket and BigQuery datasets"
	cd $(TF_DIR) && terraform destroy $(TF_VARS) -auto-approve

.PHONY: phase2
phase2: tf-init tf-apply
	@echo ""
	@echo "✓ Phase 2 complete."
	@echo "  GCS bucket and BigQuery datasets provisioned."
	@echo "  Run: make phase3"
	@echo ""

# ─────────────────────────────────────────────
# Phase 3 — Kestra
# ─────────────────────────────────────────────

KESTRA_DIR := kestra

.PHONY: kestra-up
kestra-up:
	@echo "→ Starting Kestra"
	cd $(KESTRA_DIR) && docker compose up -d
	@echo "  Kestra UI available at http://localhost:8080"

.PHONY: kestra-down
kestra-down:
	@echo "→ Stopping Kestra"
	cd $(KESTRA_DIR) && docker compose down

.PHONY: kestra-logs
kestra-logs:
	cd $(KESTRA_DIR) && docker compose logs -f

.PHONY: kestra-restart
kestra-restart: kestra-down kestra-up

.PHONY: kestra-status
kestra-status:
	cd $(KESTRA_DIR) && docker compose ps

.PHONY: phase3
phase3: kestra-up
	@echo ""
	@echo "✓ Phase 3 complete."
	@echo "  Kestra is running at http://localhost:8080"
	@echo ""
	@echo "  Next steps (manual):"
	@echo "  1. Open http://localhost:8080"
	@echo "  2. In the 'flights' namespace, add these KV Store values:"
	@echo "       GCP_PROJECT_ID  → $(GCP_PROJECT_ID)"
	@echo "       GCP_LOCATION    → $(GCP_REGION)"
	@echo "       GCP_BUCKET_NAME → $(GCP_BUCKET_NAME)"
	@echo "  3. Run flows in order:"
	@echo "       main_flights.01_ingest_lookups"
	@echo "       main_flights.02_ingest_flights"
	@echo ""
	@echo "  Then run: make phase4"
	@echo ""

# ─────────────────────────────────────────────
# Phase 4 — dbt
# ─────────────────────────────────────────────

# Absolute path to the dbt binary inside the venv so cd into dbt/ doesn't
# break the reference
VENV    := .venv
UV      := uv
DBT     := $(CURDIR)/$(VENV)/bin/dbt
DBT_DIR := dbt

.PHONY: dbt-venv
dbt-venv:
	@echo "→ Creating virtual environment with uv"
	$(UV) venv $(VENV) --python 3.11
	@echo "→ Installing dbt-bigquery"
	$(UV) pip install dbt-bigquery --python $(VENV)/bin/python
	@echo "  dbt installed at $(DBT)"

.PHONY: dbt-profile
dbt-profile:
	@if [ ! -f $(DBT_DIR)/profiles.yml ]; then \
		cp $(DBT_DIR)/profiles.yml.example $(DBT_DIR)/profiles.yml; \
		echo "  Created dbt/profiles.yml — fill in your GCP project ID and location"; \
	else \
		echo "  dbt/profiles.yml already exists, skipping"; \
	fi

.PHONY: dbt-deps
dbt-deps:
	@echo "→ Installing dbt packages"
	cd $(DBT_DIR) && $(DBT) deps --profiles-dir .

.PHONY: dbt-debug
dbt-debug:
	@echo "→ Validating dbt connection to BigQuery"
	cd $(DBT_DIR) && $(DBT) debug --profiles-dir .

.PHONY: dbt-run
dbt-run:
	@echo "→ Running dbt models"
	cd $(DBT_DIR) && $(DBT) run --profiles-dir .

.PHONY: dbt-test
dbt-test:
	@echo "→ Running dbt tests"
	cd $(DBT_DIR) && $(DBT) test --profiles-dir .

.PHONY: dbt-docs-generate
dbt-docs-generate:
	@echo "→ Generating dbt docs"
	cd $(DBT_DIR) && $(DBT) docs generate --profiles-dir .

.PHONY: dbt-docs-serve
dbt-docs-serve:
	@echo "→ Serving dbt docs at http://localhost:8081"
	cd $(DBT_DIR) && $(DBT) docs serve --profiles-dir . --port 8081

.PHONY: dbt-docs
dbt-docs: dbt-docs-generate dbt-docs-serve

.PHONY: phase4
phase4: dbt-venv dbt-profile dbt-deps dbt-debug dbt-run dbt-test
	@echo ""
	@echo "✓ Phase 4 complete."
	@echo "  All dbt models built and tested."
	@echo "  Run: make dbt-docs to generate and serve documentation"
	@echo ""