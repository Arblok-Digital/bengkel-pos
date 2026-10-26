-- 0008: produk (T2.2)
-- CRUD produk + barcode + harga jual. cost_price TIDAK diberikan ke role API
-- (kolom sensitif); nanti diisi lewat modul pembelian/RPC.
-- Stok awal belum di sini — menunggu stock_movements (T3.1).

-- units perlu unique (tenant_id, id) untuk FK komposit produk
alter table public.units
  add constraint units_tenant_id_id_key unique (tenant_id, id);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  sku text,
  barcode text,
  name text not null check (btrim(name) <> ''),
  category_id uuid,
  kind text not null default 'barang'
    check (kind in ('barang', 'jasa', 'paket')),
  base_unit_id uuid,
  track_stock boolean not null default true,
  cost_price bigint not null default 0 check (cost_price >= 0),
  sell_price bigint not null default 0 check (sell_price >= 0),
  min_stock numeric not null default 0 check (min_stock >= 0),
  image_url text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  unique (tenant_id, id),
  constraint products_category_same_tenant
    foreign key (tenant_id, category_id) references public.categories (tenant_id, id),
  constraint products_unit_same_tenant
    foreign key (tenant_id, base_unit_id) references public.units (tenant_id, id)
);

create unique index products_tenant_sku_key
  on public.products (tenant_id, sku)
  where sku is not null and btrim(sku) <> '';

create unique index products_tenant_barcode_key
  on public.products (tenant_id, barcode)
  where barcode is not null and btrim(barcode) <> '';

create index products_tenant_name_idx on public.products (tenant_id, name);
create index products_tenant_category_idx on public.products (tenant_id, category_id);
create index products_tenant_active_idx on public.products (tenant_id, active);

alter table public.products enable row level security;

revoke all on public.products from anon;
revoke all on public.products from authenticated;

-- Kolom aman boleh dibaca; cost_price sengaja TIDAK diberikan.
grant select (
  id, tenant_id, name, sku, barcode, category_id, kind, base_unit_id,
  track_stock, sell_price, min_stock, image_url, active, created_at, updated_at
) on public.products to authenticated;

-- Tulis tanpa cost_price (HPP diisi lewat modul pembelian nanti).
grant insert (
  id, tenant_id, name, sku, barcode, category_id, kind, base_unit_id,
  track_stock, sell_price, min_stock, image_url, active
) on public.products to authenticated;

grant update (
  name, sku, barcode, category_id, kind, base_unit_id,
  track_stock, sell_price, min_stock, image_url, active
) on public.products to authenticated;

grant delete on public.products to authenticated;

create policy products_select_member on public.products
  for select to authenticated
  using (public.is_member(tenant_id));

create policy products_insert_admin on public.products
  for insert to authenticated
  with check (public.has_role(tenant_id, array['owner', 'admin']));

create policy products_update_admin on public.products
  for update to authenticated
  using (public.has_role(tenant_id, array['owner', 'admin']))
  with check (public.has_role(tenant_id, array['owner', 'admin']));

create policy products_delete_admin on public.products
  for delete to authenticated
  using (public.has_role(tenant_id, array['owner', 'admin']));

create trigger products_updated_at before update on public.products
  for each row execute function public.set_updated_at();

create trigger products_created_by before insert on public.products
  for each row execute function public.set_created_by();

create trigger products_tenant_id_immutable before update on public.products
  for each row execute function public.prevent_tenant_change();
