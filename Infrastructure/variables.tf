variable "project_id" {
  description = "The ID of the Google Cloud project"
  type        = string
}

variable "region" {
  description = "The region to deploy resources to"
  type        = string
  default     = "us-central1"
}

variable "database_url" {
  description = "The PostgreSQL database URL (e.g., from Supabase)"
  type        = string
  sensitive   = true
}

variable "gemini_api_key" {
  description = "The Gemini API key for receipt parsing"
  type        = string
  sensitive   = true
}
