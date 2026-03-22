output "bucket_name" {
  description = "GCS data lake bucket name"
  value       = google_storage_bucket.data_lake.name
}

output "raw_dataset" {
  description = "BigQuery raw dataset ID"
  value       = google_bigquery_dataset.raw.dataset_id
}

output "dbt_dataset" {
  description = "BigQuery dbt dataset ID"
  value       = google_bigquery_dataset.dbt.dataset_id
}
