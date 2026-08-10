variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "Google Cloud region"
  type        = string
  default     = "us-central1"
}

variable "cloud_run_service_name" {
  description = "Existing production Cloud Run service name"
  type        = string
  default     = "fidelity-backend"
}

variable "artifact_repository_name" {
  description = "Existing production Artifact Registry repository name"
  type        = string
  default     = "fidelity-repo"
}

variable "receipt_bucket_name" {
  description = "Existing private receipt-image bucket name"
  type        = string
}

variable "runtime_service_account_id" {
  description = "Dedicated Cloud Run runtime service-account ID"
  type        = string
  default     = "cleave-backend-runtime"
}

variable "database_url_secret_id" {
  description = "Secret Manager ID containing the PostgreSQL database URL"
  type        = string
  default     = "cleave-database-url"
}

variable "database_url_secret_version" {
  description = "Pinned enabled version of the database URL secret"
  type        = string
  default     = "3"

  validation {
    condition     = can(regex("^[1-9][0-9]*$", var.database_url_secret_version))
    error_message = "The database secret version must be a positive integer."
  }
}

variable "gemini_api_key_secret_id" {
  description = "Secret Manager ID containing the Gemini API key"
  type        = string
  default     = "cleave-gemini-api-key"
}

variable "gemini_api_key_secret_version" {
  description = "Pinned enabled version of the Gemini API key secret"
  type        = string
  default     = "1"

  validation {
    condition     = can(regex("^[1-9][0-9]*$", var.gemini_api_key_secret_version))
    error_message = "The Gemini secret version must be a positive integer."
  }
}

variable "supabase_secret_key_secret_id" {
  description = "Secret Manager ID containing the backend-only Supabase secret key"
  type        = string
  default     = "cleave-supabase-secret-key"
}

variable "supabase_secret_key_secret_version" {
  description = "Pinned enabled version of the Supabase backend secret"
  type        = string
  default     = "1"

  validation {
    condition     = can(regex("^[1-9][0-9]*$", var.supabase_secret_key_secret_version))
    error_message = "The Supabase secret version must be a positive integer."
  }
}

variable "supabase_url" {
  description = "Public Supabase project URL used for JWKS validation and account administration"
  type        = string
}

variable "backend_image" {
  description = "Bootstrap Cloud Run image; GitHub Actions owns subsequent image rollouts"
  type        = string
}

variable "cors_allowed_origins" {
  description = "Comma-separated browser origins; leave empty for the native iOS-only API"
  type        = string
  default     = ""
}
