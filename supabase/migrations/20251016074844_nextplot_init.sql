-- Same ASCII-only schema; you can keep this file as-is. If it already exists, no need to change.
create extension if not exists pgcrypto;
create extension if not exists postgis;

create table if not exists public.members (
  id uuid primary key default gen_random_uuid(),
  line_user_id text not null unique,
  display_name text,
  created_at timestamptz default now()
);

create table if not exists public.properties (
  id uuid primary key default gen_random_uuid(),
  code text,
  deed_no text,
  area_rai numeric,
  area_ngan numeric,
  area_wa numeric,
  lat double precision,
  lon double precision,
  price_total numeric,
  source text,
  status text default 'draft',
  owner_id uuid references public.members(id) on delete set null,
  created_at timestamptz default now()
);

create table if not exists public.deed_addresses (
  id uuid primary key default gen_random_uuid(),
  property_id uuid references public.properties(id) on delete cascade,
  province text,
  district text,
  subdistrict text,
  address text,
  created_at timestamptz default now()
);

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  kind text not null,
  data jsonb,
  property_id uuid references public.properties(id) on delete set null,
  member_id uuid references public.members(id) on delete set null,
  created_at timestamptz default now()
);

create table if not exists public.named_points (
  slug text primary key,
  name text not null,
  geom geometry(Point,4326) not null
);

insert into public.named_points(slug,name,geom)
values ('beach','Beach',ST_SetSRID(ST_Point(100.8736,12.6800),4326))
on conflict (slug) do nothing;

alter table public.properties enable row level security;
alter table public.deed_addresses enable row level security;
alter table public.events enable row level security;

create policy if not exists "properties_read_service" on public.properties
for select using (
  current_setting('request.jwt.claims',true)::jsonb ? 'role' and
  (current_setting('request.jwt.claims',true)::jsonb->>'role')='service_role'
);
create policy if not exists "properties_write_service" on public.properties
for all using (
  current_setting('request.jwt.claims',true)::jsonb ? 'role' and
  (current_setting('request.jwt.claims',true)::jsonb->>'role')='service_role'
) with check (true);

create policy if not exists "deed_read_service" on public.deed_addresses
for select using (
  current_setting('request.jwt.claims',true)::jsonb ? 'role' and
  (current_setting('request.jwt.claims',true)::jsonb->>'role')='service_role'
);
create policy if not exists "deed_write_service" on public.deed_addresses
for all using (
  current_setting('request.jwt.claims',true)::jsonb ? 'role' and
  (current_setting('request.jwt.claims',true)::jsonb->>'role')='service_role'
) with check (true);

create policy if not exists "events_read_service" on public.events
for select using (
  current_setting('request.jwt.claims',true)::jsonb ? 'role' and
  (current_setting('request.jwt.claims',true)::jsonb->>'role')='service_role'
);
create policy if not exists "events_write_service" on public.events
for all using (
  current_setting('request.jwt.claims',true)::jsonb ? 'role' and
  (current_setting('request.jwt.claims',true)::jsonb->>'role')='service_role'
) with check (true);