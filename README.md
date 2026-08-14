# Cleave

Cleave is an iOS 17+ receipt-splitting app backed by FastAPI, PostgreSQL,
Supabase Auth, Google Gemini, private Google Cloud Storage, and Cloud Run.
The API is authoritative for profiles, groups, memberships, receipts,
assignments, balances, settlements, ratings, and receipt-memory metadata. The
iOS app keeps only an account-scoped cache.

## Local development

1. Copy `iOS/Config/CleaveSecrets.example.xcconfig` to
   `iOS/Config/CleaveSecrets.xcconfig` and set the Supabase publishable key (or
   legacy anon key). Debug uses
   `http://127.0.0.1:8000/api/` unless the secrets file overrides it.
2. Use Python 3.11 or newer, create a virtual environment, and install
   `Backend/requirements.txt`.
3. Set the backend environment values documented in
   `TESTFLIGHT_RUNBOOK.md`. Local SQLite is used when `DATABASE_URL` is absent.
4. Generate the Xcode project:

   ```sh
   ./xcodegen/bin/xcodegen generate --spec iOS/project.yml --project iOS
   ```

5. Start the API from `Backend/`:

   ```sh
   uvicorn app.main:app --reload
   ```

## Database

For an existing Supabase project, apply these migrations in order:

1. `Backend/migrations/001_authoritative_api.sql`
2. `Backend/migrations/002_release_hardening.sql`
3. `Backend/migrations/003_profiles_and_inbox.sql`
4. `Backend/migrations/004_backend_only_data_api.sql`
5. `Backend/migrations/005_timestamp_integrity.sql`
6. `Backend/migrations/006_query_indexes.sql`
7. `Backend/migrations/007_profile_payment_details.sql`
8. `Backend/migrations/008_collaboration_review_and_profile_privacy.sql`
9. `Backend/migrations/009_receipt_scan_idempotency.sql`
10. `Backend/migrations/010_individual_receipt_claims.sql`

For a new project, `schema.sql` represents the current complete schema. Mobile
clients cannot access application tables directly; all authorization is
enforced by the API.

## Verification

```sh
python -m pytest Backend/tests -q
```

```sh
xcodebuild -project iOS/Cleave.xcodeproj -scheme Cleave \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO test
```

The complete production setup and TestFlight checklist is in
`TESTFLIGHT_RUNBOOK.md`.
