-- 0025: kendaraan (T7.1)
-- vehicles: plat nomor unik per tenant, terikat customer. Riwayat servis
-- = work_orders (T7.2).

create table public.vehicles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  customer_id uuid not null,
  plate_no text not null check (btrim(plate_no) <> ''),
  brand text,
  model text,
  year integer check (year between 1900 and 2100),
  vin text,
  last_odometer numeric check (last_odometer >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  unique (tenant_id, id),
  constraint vehicle_customer_same_tenant
    foreign key (tenant_id, customer_id) references public.customers (tenant_id, id)
);
create unique index vehicle_tenant_plate_unique_idx
  on public.vehicles (tenant_id, upper(plate_no));

create index vehicle_tenant_customer_idx
  on public.vehicles (tenant_id, customer_id);
create index vehicle_tenant_active_idx
  on public.vehicles (tenant_id, active);

alter table public.vehicles enable row level security;

revoke all on public.vehicles from anon, authenticated;

grant select on public.vehicles to authenticated;
grant insert on public.vehicles to authenticated;
grant update on public.vehicles to authenticated;
grant delete on public.vehicles to authenticated;

create policy vehicle_select_member on public.vehicles
  for select to authenticated using (public.is_member(tenant_id));
create policy vehicle_insert_admin on public.vehicles
  for insert to authenticated
  with check (public.has_role(tenant_id, array['owner', 'admin']));
create policy vehicle_update_admin on public.vehicles
  for update to authenticated
  using (public.has_role(tenant_id, array['owner', 'admin']))
  with check (public.has_role(tenant_id, array['owner', 'admin']));
create policy vehicle_delete_admin on public.vehicles
  for delete to authenticated
  using (public.has_role(tenant_id, array['owner', 'admin']));

create trigger vehicle_updated_at before update on public.vehicles
  for each row execute function public.set_updated_at();
create trigger vehicle_created_by before insert on public.vehicles
  for each row execute function public.set_created_by();
create trigger vehicle_tenant_id_immutable before update on public.vehicles
  for each row execute function public.prevent_tenant_change();
