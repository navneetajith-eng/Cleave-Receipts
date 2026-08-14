begin;

alter table public.profiles
  add column if not exists display_name text;

update public.profiles
set display_name = username
where display_name is null or btrim(display_name) = '';

-- Keep the auth.users trigger compatible with the new required column. The
-- trigger remains SECURITY DEFINER with an empty search path and fully
-- qualified object references, matching the hardened behavior from migration
-- 001/004.
create or replace function public.handle_new_user()
returns trigger as $$
declare
  base_username text := split_part(coalesce(new.email, 'user'), '@', 1);
  resolved_username text;
  resolved_display_name text;
begin
  resolved_username := case
    when exists (
      select 1
      from public.profiles
      where username = base_username
    ) then left(base_username, 31) || '-' || left(new.id::text, 8)
    else base_username
  end;

  resolved_display_name := left(
    coalesce(
      nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''),
      nullif(btrim(new.raw_user_meta_data ->> 'username'), ''),
      resolved_username
    ),
    80
  );

  insert into public.profiles (id, email, username, display_name)
  values (new.id, new.email, resolved_username, resolved_display_name)
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer set search_path = '';

revoke execute on function public.handle_new_user() from public, anon, authenticated;

alter table public.profiles
  alter column display_name set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_display_name_length_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_display_name_length_check
      check (char_length(btrim(display_name)) between 1 and 80);
  end if;
end $$;

alter table public.receipts
  add column if not exists currency_code text;

update public.receipts as receipt
set currency_code = case profile.region_code
  when 'IN' then 'INR'
  when 'AE' then 'AED'
  else 'USD'
end
from public.profiles as profile
where profile.id = receipt.admin_id
  and receipt.currency_code is null;

update public.receipts
set currency_code = 'USD'
where currency_code is null;

alter table public.receipts
  alter column currency_code set default 'USD',
  alter column currency_code set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'receipts_currency_code_check'
      and conrelid = 'public.receipts'::regclass
  ) then
    alter table public.receipts
      add constraint receipts_currency_code_check
      check (currency_code in ('USD', 'INR', 'AED'));
  end if;
end $$;

commit;
