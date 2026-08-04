terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# 1. Enable Required GCP APIs
resource "google_project_service" "run_api" {
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifactregistry_api" {
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

# 2. Artifact Registry for Docker Images
resource "google_artifact_registry_repository" "repo" {
  location      = var.region
  repository_id = "fidelity-repo"
  description   = "Docker repository for Fidelity backend"
  format        = "DOCKER"
  depends_on    = [google_project_service.artifactregistry_api]
}

# 3. Cloud Run Service
resource "google_cloud_run_v2_service" "backend" {
  name     = "fidelity-backend"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      # Use a placeholder image initially; CI/CD will push the real one
      image = "us-docker.pkg.dev/cloudrun/container/hello"
      
      ports {
        container_port = 8000
      }

      env {
        name  = "DATABASE_URL"
        value = var.database_url
      }

      env {
        name  = "GEMINI_API_KEY"
        value = var.gemini_api_key
      }
    }
  }

  depends_on = [google_project_service.run_api]
}

# 4. Make Cloud Run public
resource "google_cloud_run_v2_service_iam_member" "public" {
  location = google_cloud_run_v2_service.backend.location
  name     = google_cloud_run_v2_service.backend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# 5. Cloud Storage Bucket
resource "google_storage_bucket" "receipts" {
  name          = "${var.project_id}-receipt-images"
  location      = var.region
  force_destroy = true
  
  uniform_bucket_level_access = true
  
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
}

