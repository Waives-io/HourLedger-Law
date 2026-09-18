-- HourLedger-Law — Supabase schema
-- Run once in the Supabase dashboard: SQL Editor → New query → paste → Run.
-- Safe to re-run (idempotent).

create extension if not exists pgcrypto;

-- ---------- tables ----------

create table if not exists public.orgs (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  webhook    text,
  created_at timestamptz not null default now()
);

create table if not exists public.profiles (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  org_id     uuid not null references public.orgs(id) on delete cascade,
  email      text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.clients (
  org_id     uuid not null references public.orgs(id) on delete cascade,
  name       text not null,
  created_at timestamptz not null default now(),
  primary key (org_id, name)
);

create table if not exists public.categories (
  org_id uuid not null references public.orgs(id) on delete cascade,
  id     text not null,
  he     text not null,
  en     text not null,
  sort   int  not null default 0,
  primary key (org_id, id)
);

-- one row = one billing line (same model as the app and the Google Sheet)
create table if not exists public.records (
  org_id     uuid not null references public.orgs(id) on delete cascade,
  id         text not null,
  group_id   text,
  date       date not null,
  client     text not null,
  category   text not null,
  hours      numeric(6,2) not null,
  notes      text not null default '',
  other_text text not null default '',   -- free text when category = 'other'
  user_email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (org_id, id)
);
create index if not exists records_org_date on public.records (org_id, date);
alter table public.records add column if not exists other_text text not null default '';

-- ---------- helpers ----------

-- the org of the signed-in user
create or replace function public.my_org()
returns uuid
language sql stable security definer
set search_path = public
as $$
  select org_id from public.profiles where user_id = auth.uid()
$$;

-- every new auth user gets a fresh org + profile.
-- firm name and webhook come from the signup metadata the app sends.
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  new_org uuid;
begin
  insert into public.orgs (name, webhook)
  values (
    coalesce(nullif(new.raw_user_meta_data->>'firm', ''), split_part(new.email, '@', 1)),
    nullif(new.raw_user_meta_data->>'webhook', '')
  )
  returning id into new_org;

  insert into public.profiles (user_id, org_id, email)
  values (new.id, new_org, new.email);

  return new;
end
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ---------- row level security ----------
-- each user sees and edits only their own org's rows

alter table public.orgs       enable row level security;
alter table public.profiles   enable row level security;
alter table public.clients    enable row level security;
alter table public.categories enable row level security;
alter table public.records    enable row level security;

drop policy if exists "orgs: members read"   on public.orgs;
drop policy if exists "orgs: members update" on public.orgs;
create policy "orgs: members read"   on public.orgs for select using (id = public.my_org());
create policy "orgs: members update" on public.orgs for update using (id = public.my_org()) with check (id = public.my_org());

drop policy if exists "profiles: own" on public.profiles;
create policy "profiles: own" on public.profiles for select using (user_id = auth.uid());

drop policy if exists "clients: org" on public.clients;
create policy "clients: org" on public.clients for all
  using (org_id = public.my_org()) with check (org_id = public.my_org());

drop policy if exists "categories: org" on public.categories;
create policy "categories: org" on public.categories for all
  using (org_id = public.my_org()) with check (org_id = public.my_org());

drop policy if exists "records: org" on public.records;
create policy "records: org" on public.records for all
  using (org_id = public.my_org()) with check (org_id = public.my_org());

-- 17.9.2026: default invoice email per client (used by the dashboard "create invoice" flow).
-- Existing projects: run this line once in the SQL editor.
alter table public.clients add column if not exists email text;
alter table public.clients add column if not exists tax_id text;   -- ח.פ / ע.מ, the billing identifier

-- ============================================================
-- 18.9.2026: teams — several lawyers / trainees in one office.
-- Existing projects: run everything from here down once in the SQL editor (idempotent).
-- Roles: owner (ראשי) sees and edits everything; lawyer sees + edits their own entries and
-- those of the trainees whose supervisor they are; trainee sees only their own.
-- ============================================================

alter table public.profiles add column if not exists role text not null default 'owner';
alter table public.profiles add column if not exists supervisor_id uuid references public.profiles(user_id) on delete set null;
alter table public.profiles add column if not exists display_name text;
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('owner','lawyer','trainee'));

-- who reported the line. auth.uid() as default = older app builds that do not send it still get tagged.
alter table public.records add column if not exists user_id uuid default auth.uid();
update public.records r set user_id = p.user_id
  from public.profiles p
  where r.user_id is null and r.org_id = p.org_id and lower(r.user_email) = lower(p.email);
create index if not exists records_org_user on public.records (org_id, user_id);

-- one-time codes the owner hands out; a signup carrying a valid code joins that org instead of opening a new one
create table if not exists public.invites (
  code          text primary key,
  org_id        uuid not null references public.orgs(id) on delete cascade,
  email         text,
  role          text not null default 'trainee' check (role in ('lawyer','trainee')),
  supervisor_id uuid references public.profiles(user_id) on delete set null,
  created_by    uuid references public.profiles(user_id) on delete set null,
  created_at    timestamptz not null default now(),
  used_at       timestamptz,
  used_by       uuid
);

create or replace function public.my_role()
returns text
language sql stable security definer
set search_path = public
as $$
  select role from public.profiles where user_id = auth.uid()
$$;

-- may the signed-in user see / edit a line reported by `who`?
create or replace function public.can_see(who uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select case
    when public.my_role() = 'owner' then true
    when who is null then false
    when who = auth.uid() then true
    when public.my_role() = 'lawyer' then exists (
      select 1 from public.profiles p where p.user_id = who and p.supervisor_id = auth.uid())
    else false
  end
$$;

-- the signup form calls this (anon) to show "joining office X as …" before the account is created
create or replace function public.invite_info(code text)
returns table (org_name text, role text, email text, supervisor_name text)
language sql stable security definer
set search_path = public
as $$
  select o.name, i.role, i.email, coalesce(s.display_name, s.email)
  from public.invites i
  join public.orgs o on o.id = i.org_id
  left join public.profiles s on s.user_id = i.supervisor_id
  where i.code = invite_info.code and i.used_at is null
$$;
grant execute on function public.invite_info(text) to anon, authenticated;

-- new auth user: with a valid invite code in the metadata → joins that org; otherwise opens a fresh org as owner
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  new_org uuid;
  inv public.invites%rowtype;
  code text := nullif(new.raw_user_meta_data->>'invite', '');
  dname text := nullif(new.raw_user_meta_data->>'name', '');
begin
  if code is not null then
    select * into inv from public.invites where invites.code = handle_new_user.code and used_at is null;
    if found then
      insert into public.profiles (user_id, org_id, email, role, supervisor_id, display_name)
      values (new.id, inv.org_id, new.email, inv.role, inv.supervisor_id, dname);
      update public.invites set used_at = now(), used_by = new.id where invites.code = inv.code;
      return new;
    end if;
  end if;

  insert into public.orgs (name, webhook)
  values (
    coalesce(nullif(new.raw_user_meta_data->>'firm', ''), split_part(new.email, '@', 1)),
    nullif(new.raw_user_meta_data->>'webhook', '')
  )
  returning id into new_org;

  insert into public.profiles (user_id, org_id, email, role, display_name)
  values (new.id, new_org, new.email, 'owner', dname);

  return new;
end
$$;

-- ---------- row level security (teams) ----------

alter table public.invites enable row level security;

-- every member sees the office roster (names next to entries); only the owner changes it
drop policy if exists "profiles: own"          on public.profiles;
drop policy if exists "profiles: org read"     on public.profiles;
drop policy if exists "profiles: owner edit"   on public.profiles;
drop policy if exists "profiles: owner remove" on public.profiles;
create policy "profiles: org read"   on public.profiles for select using (org_id = public.my_org());
create policy "profiles: owner edit" on public.profiles for update
  using (org_id = public.my_org() and public.my_role() = 'owner')
  with check (org_id = public.my_org());
create policy "profiles: owner remove" on public.profiles for delete
  using (org_id = public.my_org() and public.my_role() = 'owner' and user_id <> auth.uid());

drop policy if exists "invites: owner" on public.invites;
create policy "invites: owner" on public.invites for all
  using (org_id = public.my_org() and public.my_role() = 'owner')
  with check (org_id = public.my_org() and public.my_role() = 'owner');

-- clients + categories: everyone reads, only the owner writes
drop policy if exists "clients: org"         on public.clients;
drop policy if exists "clients: org read"    on public.clients;
drop policy if exists "clients: owner write" on public.clients;
create policy "clients: org read" on public.clients for select using (org_id = public.my_org());
create policy "clients: owner write" on public.clients for all
  using (org_id = public.my_org() and public.my_role() = 'owner')
  with check (org_id = public.my_org() and public.my_role() = 'owner');

drop policy if exists "categories: org"         on public.categories;
drop policy if exists "categories: org read"    on public.categories;
drop policy if exists "categories: owner write" on public.categories;
create policy "categories: org read" on public.categories for select using (org_id = public.my_org());
create policy "categories: owner write" on public.categories for all
  using (org_id = public.my_org() and public.my_role() = 'owner')
  with check (org_id = public.my_org() and public.my_role() = 'owner');

-- records: visibility follows the hierarchy; a new line is always the reporter's own
drop policy if exists "records: org"     on public.records;
drop policy if exists "records: see"     on public.records;
drop policy if exists "records: add own" on public.records;
drop policy if exists "records: edit"    on public.records;
drop policy if exists "records: remove"  on public.records;
create policy "records: see" on public.records for select
  using (org_id = public.my_org() and public.can_see(user_id));
create policy "records: add own" on public.records for insert
  with check (org_id = public.my_org() and (user_id = auth.uid() or public.my_role() = 'owner'));
create policy "records: edit" on public.records for update
  using (org_id = public.my_org() and public.can_see(user_id))
  with check (org_id = public.my_org() and public.can_see(user_id));
create policy "records: remove" on public.records for delete
  using (org_id = public.my_org() and public.can_see(user_id));
