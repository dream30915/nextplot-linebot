-- properties
drop policy if exists "properties_read_service"  on public.properties;
drop policy if exists "properties_write_service" on public.properties;

create policy "properties_read_service" on public.properties
for select
using (
  current_setting('request.jwt.claims', true)::jsonb ? 'role'
  and (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'service_role'
);

create policy "properties_write_service" on public.properties
for all
using (
  current_setting('request.jwt.claims', true)::jsonb ? 'role'
  and (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'service_role'
)
with check (true);

-- deed_addresses
drop policy if exists "deed_read_service"  on public.deed_addresses;
drop policy if exists "deed_write_service" on public.deed_addresses;

create policy "deed_read_service" on public.deed_addresses
for select
using (
  current_setting('request.jwt.claims', true)::jsonb ? 'role'
  and (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'service_role'
);

create policy "deed_write_service" on public.deed_addresses
for all
using (
  current_setting('request.jwt.claims', true)::jsonb ? 'role'
  and (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'service_role'
)
with check (true);

-- events
drop policy if exists "events_read_service"  on public.events;
drop policy if exists "events_write_service" on public.events;

create policy "events_read_service" on public.events
for select
using (
  current_setting('request.jwt.claims', true)::jsonb ? 'role'
  and (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'service_role'
);

create policy "events_write_service" on public.events
for all
using (
  current_setting('request.jwt.claims', true)::jsonb ? 'role'
  and (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'service_role'
)
with check (true);