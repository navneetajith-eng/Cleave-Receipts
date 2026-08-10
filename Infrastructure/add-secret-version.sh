#!/usr/bin/env bash
set -euo pipefail

readonly project_id="${CLEAVE_GCP_PROJECT_ID:-gen-lang-client-0983510869}"
readonly secret_name="${1:-}"
readonly allowed_secrets=" cleave-database-url cleave-gemini-api-key cleave-supabase-secret-key "

if [[ "${allowed_secrets}" != *" ${secret_name} "* ]]; then
  echo "Usage: $0 {cleave-database-url|cleave-gemini-api-key|cleave-supabase-secret-key}" >&2
  exit 64
fi

if command -v gcloud >/dev/null 2>&1; then
  gcloud_bin="$(command -v gcloud)"
elif [[ -x "/Users/ajith/google-cloud-sdk/bin/gcloud" ]]; then
  gcloud_bin="/Users/ajith/google-cloud-sdk/bin/gcloud"
else
  echo "gcloud was not found. Install or add Google Cloud CLI to PATH." >&2
  exit 69
fi

read -r -s -p "Paste the value for ${secret_name}, then press Return: " secret_value
echo
trap 'unset secret_value' EXIT

if [[ -z "${secret_value}" ]]; then
  echo "Secret value cannot be empty." >&2
  exit 65
fi

printf '%s' "${secret_value}" | CLOUDSDK_PYTHON="${CLOUDSDK_PYTHON:-/opt/homebrew/bin/python3.14}" \
  "${gcloud_bin}" secrets versions add "${secret_name}" \
  --project "${project_id}" \
  --data-file=-

echo "Added a new enabled version to ${secret_name}."
