begin;

-- Cleave uses Supabase Auth, but all application data access goes through the
-- authenticated Cloud Run API. Remove both present and future Data API grants
-- so a publishable key cannot bypass the backend's group/receipt checks.
revoke all privileges on all tables in schema public from anon, authenticated;
revoke all privileges on all sequences in schema public from anon, authenticated;
revoke all privileges on all functions in schema public from anon, authenticated;

alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on functions from anon, authenticated;

-- Supabase reserves ownership of the supabase_admin default ACL and rejects
-- project migrations that try to change it. Cleave migrations run as postgres,
-- whose defaults are locked down above. After every dashboard-created schema
-- object, rerun the direct-grant audit because Supabase-managed tooling can use
-- its internal owner role.

create index if not exists settlements_reviewed_by_idx
  on public.settlements (reviewed_by)
  where reviewed_by is not null;

commit;
