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
