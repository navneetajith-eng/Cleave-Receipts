# Cleave TestFlight runbook

This runbook starts after the local backend and iOS test suites pass. Never put
the database password, Gemini key, or Supabase secret key in the iOS project.

## 0. Rotate the previously committed database credential

`Backend/.env` was present in the existing Git history and contained a database
URL. Removing the file from the current revision does not erase that history.
Before production deployment:

1. In Supabase, rotate/reset the database password.
2. Add a new version to the `cleave-database-url` Secret Manager secret with a
   connection string containing the new password.
3. Invalidate the old credential; do not reuse it in local `.env` files.
4. If this repository has ever been shared, decide whether its history also
   needs to be rewritten. Credential rotation is required either way.

## 1. Gather the account-owned values

You will need:

- Apple Developer Team ID and access to App Store Connect.
- Supabase project URL, publishable key, secret key, and database direct or
  session-pooler connection string.
- Google Cloud project ID with billing enabled.
- Google Gemini API key.
- GitHub repository admin access if automatic deployment will be enabled.

Treat every value as secret except the Apple Team ID, Supabase URL, Supabase
publishable key, Google project ID, and deployed API URL. This project validates
ES256 access tokens through Supabase JWKS, so it does not copy a static JWT
signing secret into Google Cloud.

## 2. Apply the Supabase database migrations

1. Open the Supabase dashboard and select the Cleave project.
2. Open **SQL Editor** and create a new query.
3. Confirm the migration history includes every file from
   `001_authoritative_api.sql` through
   `011_display_names_and_receipt_currencies.sql`. Apply only missing
   migrations, in filename order. Migration 010 is required before deploying
   the individual item-claim API; migration 011 is required before deploying
   display names, friend profiles, or receipt-currency support.
4. Open **Table Editor** and confirm these tables exist:
   `profiles`, `groups`, `group_members`, `receipts`, `receipt_items`,
   `receipt_assignments`, `receipt_participants`, `receipt_memories`,
   `receipt_experiences`, and `settlements`.
6. Confirm Row Level Security is enabled for all public application tables.

Do not run `schema.sql` over an existing database. It is the reference schema
for a new project.

## 3. Create backend secrets in Google Secret Manager

In Google Cloud Console, select the production project, enable **Secret
Manager**, and create these three secrets with an initial version:

| Secret name | Secret value |
| --- | --- |
| `cleave-database-url` | Supabase PostgreSQL connection string |
| `cleave-gemini-api-key` | Gemini API key |
| `cleave-supabase-secret-key` | Supabase backend secret key (`sb_secret_...`) |

The Supabase secret key is backend-only. Never add it to an xcconfig file or
App Store Connect. Secret values are added with `gcloud secrets versions add`;
Terraform intentionally manages secret containers and IAM, not secret versions,
so plaintext values never enter Terraform state.

After rotating the database password, populate each version from Terminal with
the secure prompt helper. The pasted value is not echoed or stored in shell
history:

```sh
./Infrastructure/add-secret-version.sh cleave-database-url
./Infrastructure/add-secret-version.sh cleave-gemini-api-key
./Infrastructure/add-secret-version.sh cleave-supabase-secret-key
```

Confirm only version status—never payloads—with:

```sh
gcloud secrets versions list SECRET_NAME
```

## 4. Provision Google Cloud resources

Terraform and Google Cloud CLI are installed on this Mac. The CLI lives at
`/Users/ajith/google-cloud-sdk/bin/gcloud`; either use that full path or add its
`bin` directory to the shell path.

1. Install Terraform and the Google Cloud CLI using their official installers
   or Homebrew.
2. Authenticate and select the project:

   ```sh
   gcloud auth login
   gcloud auth application-default login
   gcloud config set project gen-lang-client-0983510869
   ```

3. Copy `Infrastructure/terraform.tfvars.example` to
   `Infrastructure/terraform.tfvars` and fill in only the non-secret values.
4. Initialize and inspect the import-first plan. The committed import blocks
   adopt the existing `fidelity-backend`, `fidelity-repo`, and receipt bucket;
   they must not be recreated under new names.

   ```sh
   terraform -chdir=Infrastructure init
   terraform -chdir=Infrastructure plan -out=production.tfplan
   terraform -chdir=Infrastructure show production.tfplan
   terraform -chdir=Infrastructure apply production.tfplan
   ```

Terraform adopts the live bucket, Artifact Registry repository, and Cloud Run
service; enforces public-access prevention on the bucket; creates a dedicated
least-privilege runtime identity; and mounts the three backend secrets. Do not
apply a plan that replaces the bucket, repository, or Cloud Run service.
Production state is stored in the private, versioned
`gen-lang-client-0983510869-terraform-state` bucket under
`cleave/production`; never commit a local state file.

## 5. Configure automatic backend deployment

Create a Google Workload Identity Federation provider and a deployment service
account restricted to this GitHub repository. Grant that deployment identity:

- Artifact Registry Writer on `fidelity-repo`.
- Cloud Run Admin for `fidelity-backend`.
- Service Account User on `cleave-backend-runtime`.
The deployment identity does not need to read application secrets. Cloud Run's
dedicated runtime identity receives Secret Manager Secret Accessor only on the
three named secrets.

Then add these GitHub Actions secrets under **Repository Settings → Secrets and
variables → Actions**:

| GitHub secret | Value |
| --- | --- |
| `GCP_PROJECT_ID` | Google Cloud project ID |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Full workload identity provider resource name |
| `GCP_SERVICE_ACCOUNT` | Deployment service-account email |
| `SUPABASE_URL` | Supabase project URL |

Backend credential values remain in Google Secret Manager and are mounted into
Cloud Run by `.github/workflows/deploy.yml`; they are not duplicated in GitHub.
Push to `main` only after reviewing the changes. The workflow runs backend tests,
builds the image, deploys it, and verifies `/health`.

Before distributing any matching iOS build, require both production contract
checks to pass:

```sh
curl --fail --silent https://YOUR_CLOUD_RUN_HOST/health
curl --fail --silent https://YOUR_CLOUD_RUN_HOST/api/capabilities
```

`/health` must report `"status":"ok"` and `"api_version":3`.
`/api/capabilities` must report `"api_version":3` with receipt review,
payment review, unified profile settings, scan idempotency, individual receipt
claims, receipt deletion, group leave, display names, receipt currencies, and
friend profiles enabled. A health
response containing only `{"status":"ok"}` is the legacy API and must block the
TestFlight release.

The workflow updates only the container image and preserves Terraform-managed
environment and secret bindings. Secret versions are pinned in Terraform; test
a rotated version on a zero-traffic tagged revision before changing the pinned
version and promoting it.

## 6. Configure the iOS Release build

1. Copy `iOS/Config/CleaveSecrets.example.xcconfig` to
   `iOS/Config/CleaveSecrets.xcconfig`.
2. Set:

   ```text
   CLEAVE_SUPABASE_ANON_KEY = YOUR_SUPABASE_PUBLISHABLE_OR_LEGACY_ANON_KEY
   CLEAVE_API_BASE_URL = https:/$()/YOUR_CLOUD_RUN_HOST/api/
   DEVELOPMENT_TEAM = YOUR_10_CHARACTER_APPLE_TEAM_ID
   ```

3. Keep the `https:/$()/` syntax; xcconfig treats an unescaped `//` as a
   comment.
4. In the Apple Developer portal, confirm the App ID
   `com.cleave.Cleave` exists and **Sign in with Apple** is enabled.
5. Open Xcode → **Settings → Accounts**, add the Apple ID, and download signing
   assets. The project uses automatic signing.
6. Regenerate the project with XcodeGen and select the Cleave team in **Signing
   & Capabilities** if Xcode requests it.

## 7. Complete a two-account production smoke test

Use two real test accounts on two devices or one device plus a second simulator:

1. Sign in with Apple as account A and account B.
2. A creates a group and adds B.
3. B scans a receipt in A's group. Verify B—not group creator A—is listed as the
   receipt admin.
4. Interrupt the first upload after submission, then retry the saved draft.
   Verify only one receipt exists and the same draft completes instead of
   creating a duplicate.
5. B chooses only B's items and reaches the summary while A is still shown as
   pending. A then chooses A's own items. Verify a shared item is divided across
   both claimants and neither person's save overwrites the other.
6. Verify payment marking remains locked while a participant is pending or an
   item is unclaimed. B can use Admin corrections after everyone submits, but A
   cannot edit other members' allocations.
7. A marks their payment as sent and B confirms it. Verify B's own share is
   shown as the receipt payer's portion and never as a payment to themselves.
8. Relaunch both clients. Verify claims, pending status, payment state, admin
   label, and balances converge without manual refresh.
9. Each account saves a different rating and memory photo. Verify Moments shows
   who added each rating/photo and remains limited to group members.
10. Long-press the receipt as A and verify deletion is unavailable. Long-press
   as admin B, cancel once, then delete and verify it disappears for both users.
11. Leave the group as its creator while another member remains. Verify the
   group stays visible to remaining members, ownership transfers, pending claims
   from the leaver no longer block settlement, and no client offers group deletion.
12. Verify a non-member cannot load the group receipt, review state, or photo.
13. Delete a disposable test account in Settings; verify it is signed out and
   cannot sign back into the deleted Cleave account without creating a new one.
14. Re-run both production contract checks from section 5.

Do not automatically mark a Venmo handoff as settled. The app cannot verify that
an external payment completed; settlement confirmation needs a deliberate
product decision or a payment-provider callback.

## 8. App Store Connect and TestFlight

1. Create the Cleave app record with bundle ID `com.cleave.Cleave`.
2. Add the support URL and a publicly hosted privacy-policy URL. The in-app
   policy is not a substitute for the App Store Connect URL.
3. Complete App Privacy using `iOS/Cleave/Resources/PrivacyInfo.xcprivacy` as the
   engineering baseline, then verify the answers against the live vendors and
   actual retention policy.
4. In Xcode, select **Any iOS Device (arm64)**, then **Product → Archive**.
5. In Organizer, run **Validate App**, resolve every error, and choose
   **Distribute App → App Store Connect → Upload**.
6. In App Store Connect, add the processed build to an internal TestFlight
   group, complete export-compliance questions, and invite internal testers.
7. Monitor crashes, sign-in failures, receipt parsing failures, latency, and
   account deletion during the beta before adding external testers.

## Current external gates

- No Apple code-signing identity is installed on this Mac.
- Apple Developer Team ID and App Store Connect access are still required.
- Terraform 1.15.8, Google Cloud CLI 579.0.0, and GitHub CLI 2.97.0 are installed
  and authenticated; Application Default Credentials still require completion.
- The Release xcconfig has the Supabase publishable key and deployed API URL;
  its Apple Team ID is still unset.
- Production migration 010 is deployed. Every client release must still be
  paired with a backend whose capability contract includes individual claims,
  receipt deletion, and group leave.
- Cloud Build API is enabled, but the current Google account cannot submit a
  build. Grant the deployment identity the documented build/deploy permissions
  or run the authenticated GitHub deployment workflow; do not broaden the
  runtime service account's secret access.
- A public support URL and privacy-policy URL still need to be chosen.
- Settlement confirmation and crash/error monitoring still need product choices.
