terraform {
  required_version = ">= 1.5.0"

  backend "gcs" {
    bucket = "gen-lang-client-0983510869-terraform-state"
    prefix = "cleave/production"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0, < 8.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  backend_secrets = {
    database_url = {
      env_name       = "DATABASE_URL"
      secret_id      = var.database_url_secret_id
      secret_version = var.database_url_secret_version
    }
    gemini_api_key = {
      env_name       = "GEMINI_API_KEY"
      secret_id      = var.gemini_api_key_secret_id
      secret_version = var.gemini_api_key_secret_version
    }
    supabase_secret_key = {
      env_name       = "SUPABASE_SECRET_KEY"
      secret_id      = var.supabase_secret_key_secret_id
      secret_version = var.supabase_secret_key_secret_version
    }
  }
}

resource "google_project_service" "required" {
  for_each = toset([
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "storage-api.googleapis.com",
  ])

  service            = each.value
  disable_on_destroy = false
}

resource "google_secret_manager_secret" "backend" {
  for_each = local.backend_secrets

  secret_id = each.value.secret_id

  replication {
    auto {}
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.required]
}

# Secret versions are intentionally not managed by Terraform so their values never
# enter Terraform state. Add and rotate versions with gcloud or Secret Manager.

resource "google_service_account" "backend" {
  account_id   = var.runtime_service_account_id
  display_name = "Cleave backend Cloud Run runtime"
}

resource "google_artifact_registry_repository" "repo" {
  location      = var.region
  repository_id = var.artifact_repository_name
  description   = "Docker repository for the Cleave backend"
  format        = "DOCKER"

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.required]
}

resource "google_storage_bucket" "receipts" {
  name                        = var.receipt_bucket_name
  location                    = var.region
  force_destroy               = false
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.required]
}

resource "google_storage_bucket_iam_member" "backend_objects" {
  bucket = google_storage_bucket.receipts.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.backend.email}"
}

resource "google_secret_manager_secret_iam_member" "backend_secrets" {
  for_each = google_secret_manager_secret.backend

  secret_id = each.value.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.backend.email}"
}

resource "google_cloud_run_v2_service" "backend" {
  name                = var.cloud_run_service_name
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = true

  template {
    service_account                  = google_service_account.backend.email
    timeout                          = "300s"
    max_instance_request_concurrency = 80

    scaling {
      max_instance_count = 20
    }

    containers {
      image = var.backend_image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1000m"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      dynamic "env" {
        for_each = local.backend_secrets
        content {
          name = env.value.env_name
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.backend[env.key].secret_id
              version = env.value.secret_version
            }
          }
        }
      }

      env {
        name  = "SUPABASE_URL"
        value = var.supabase_url
      }

      env {
        name  = "GCS_BUCKET_NAME"
        value = google_storage_bucket.receipts.name
      }

      dynamic "env" {
        for_each = var.cors_allowed_origins == "" ? [] : [var.cors_allowed_origins]
        content {
          name  = "CORS_ALLOWED_ORIGINS"
          value = env.value
        }
      }
    }
  }

  lifecycle {
    # GitHub Actions owns application image rollouts; Terraform owns the service
    # identity, limits, networking, and secret bindings.
    ignore_changes = [
      client,
      client_version,
      template[0].containers[0].image,
      template[0].labels,
      template[0].revision,
    ]
  }

  depends_on = [
    google_storage_bucket_iam_member.backend_objects,
    google_secret_manager_secret_iam_member.backend_secrets,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "public" {
  location = google_cloud_run_v2_service.backend.location
  name     = google_cloud_run_v2_service.backend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

output "backend_url" {
  description = "Public Cloud Run URL"
  value       = google_cloud_run_v2_service.backend.uri
}

output "runtime_service_account" {
  description = "Least-privilege Cloud Run runtime identity"
  value       = google_service_account.backend.email
}
