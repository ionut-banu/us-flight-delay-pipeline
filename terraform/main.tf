terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project     = var.project_id
  region      = var.region
}

# ─── Data Lake: Google Cloud Storage ───────────────────────────────────────

resource "google_storage_bucket" "data_lake" {
  name                        = var.bucket_name
  location                    = var.bq_location
  force_destroy               = true
  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = 90                    # auto-delete raw files after 90 days
    }
    action {
      type = "Delete"
    }
  }

  versioning {
    enabled = false
  }
}

# ─── Data Warehouse: BigQuery ───────────────────────────────────────────────

# Raw dataset — landing zone for Kestra loads
resource "google_bigquery_dataset" "raw" {
  dataset_id    = "flights_raw"
  friendly_name = "Flights Raw"
  description   = "Raw BTS flight data loaded by Kestra"
  location      = var.bq_location

  delete_contents_on_destroy = true
}

# dbt dataset — transformed mart tables
resource "google_bigquery_dataset" "dbt" {
  dataset_id    = "flights_dbt"
  friendly_name = "Flights DBT"
  description   = "Transformed tables produced by dbt models"
  location      = var.bq_location

  delete_contents_on_destroy = true
}
