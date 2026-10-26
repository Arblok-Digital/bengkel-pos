-- 0010: pelanggan + pemasok (T2.4)
-- customers: tier harga (price_tiers) + limit kredit (integer rupiah)
-- suppliers: termin pembayaran (hari)

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  name text not null check (btrim(name) <> ''),
  phone text,
  address text,
  tier_id uuid,
  credit_limit bigint not null default 0 check (credit_limit >= 0),
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  unique (tenant_id, id),
  constraint customers_tier_same_tenant
    foreign key (tenant_id, tier_id) references public.price_tiers (tenant_id, id)
);

create index customers_tenant_name_idx on public.customers (tenant_id, name);
create index customers_tenant_phone_idx on public.customers (tenant_id, phone);

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  name text not null check (btrim(name) <> ''),
  phone text,
  address text,
  payment_terms_days integer not null default 0 check (payment_terms_days >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  unique (tenant_id, id)
);

create index suppliers_tenant_name_idx on public.suppliers (tenant_id, name);

alter table public.customers enable row level security;
alter table public.suppliers enable row level security;

revoke all on public.customers from anon;
revoke all on public.suppliers from anon;

create policy customers_select_member on public.customers
  for select to authenticated using (public.is_member(tenant_id));
create policy customers_insert_admin on public.customers
  for insert to authenticated
  with check (public.has_role(tenant_id, array['owner', 'admin']));
create policy customers_update_admin on public.customers
  for update to authenticated
  using (public.has_role(tenant_id, array['owner', 'admin']))
  with check (public.has_role(tenant_id, array['owner', 'admin']));
create policy customers_delete_admin on public.customers
  for delete to authenticated
  using (public.has_role(tenant_id, array['owner', 'admin']));

create policy suppliers_select_member on public.suppliers
  for select to authenticated using (public.is_member(tenant_id));
create policy suppliers_insert_admin on public.suppliers
  for insert to authenticated
  with check (public.has_role(tenant_id, array['owner', 'admin']));
create policy suppliers_update_admin on public.suppliers
  for update to authenticated
  using (public.has_role(tenant_id, array['owner', 'admin']))
  with check (public.has_role(tenant_id, array['owner', 'admin']));
create policy suppliers_delete_admin on public.suppliers
  for delete to authenticated
  using (public.has_role(tenant_id, array['owner', 'admin']));

create trigger customers_updated_at before update on public.customers
  for each row execute function public.set_updated_at();
create trigger suppliers_updated_at before update on public.suppliers
  for each row execute function public.set_updated_at();

create trigger customers_created_by before insert on public.customers
  for each row execute function public.set_created_by();
create trigger suppliers_created_by before insert on public.suppliers
  for each row execute function public.set_created_by();

create trigger customers_tenant_id_immutable before update on public.customers
  for each row execute function public.prevent_tenant_change();
create trigger suppliers_tenant_id_immutable before update on public.suppliers
  for each row execute function public.prevent_tenant_change();
