# These blocks adopt the resources that predate Terraform state. Terraform treats
# an import as a no-op after the object is present in state.
import {
  for_each = toset([
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
  ])

  to = google_project_service.required[each.value]
  id = "${var.project_id}/${each.value}"
}

import {
  for_each = local.backend_secrets

  to = google_secret_manager_secret.backend[each.key]
  id = "projects/${var.project_id}/secrets/${each.value.secret_id}"
}

import {
  to = google_artifact_registry_repository.repo
  id = "projects/${var.project_id}/locations/${var.region}/repositories/${var.artifact_repository_name}"
}

import {
  to = google_storage_bucket.receipts
  id = var.receipt_bucket_name
}

import {
  to = google_cloud_run_v2_service.backend
  id = "projects/${var.project_id}/locations/${var.region}/services/${var.cloud_run_service_name}"
}
