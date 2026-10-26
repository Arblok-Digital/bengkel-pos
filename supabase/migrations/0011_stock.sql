-- 0011: stok — stock_movements (append-only) + stock_levels (trigger) + view (T3.1)
-- Aturan: stok hanya berubah lewat insert stock_movements. stock_levels tidak
-- boleh ditulis langsung oleh role API.

alter table public.outlets
  add constraint outlets_tenant_id_id_key unique (tenant_id, id);

create table public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  product_id uuid not null,
  outlet_id uuid not null,
  qty_base numeric not null check (qty_base <> 0),
  type text not null check (type in (
    'purchase', 'sale', 'sale_return', 'adjustment',
    'opname', 'transfer_in', 'transfer_out', 'workorder_use'
  )),
  ref_type text,
  ref_id uuid,
  unit_cost bigint not null default 0 check (unit_cost >= 0),
  note text,
  created_at timestamptz not null default now(),
  created_by uuid,
  constraint stock_movements_product_same_tenant
    foreign key (tenant_id, product_id) references public.products (tenant_id, id),
  constraint stock_movements_outlet_same_tenant
    foreign key (tenant_id, outlet_id) references public.outlets (tenant_id, id)
);

create index stock_movements_product_idx
  on public.stock_movements (tenant_id, product_id, outlet_id, created_at);
create index stock_movements_tenant_date_idx
  on public.stock_movements (tenant_id, created_at);

create table public.stock_levels (
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  product_id uuid not null,
  outlet_id uuid not null,
  qty_base numeric not null default 0,
  updated_at timestamptz not null default now(),
  primary key (tenant_id, product_id, outlet_id),
  constraint stock_levels_product_same_tenant
    foreign key (tenant_id, product_id) references public.products (tenant_id, id) on delete cascade,
  constraint stock_levels_outlet_same_tenant
    foreign key (tenant_id, outlet_id) references public.outlets (tenant_id, id) on delete cascade
);

alter table public.stock_movements enable row level security;
alter table public.stock_levels enable row level security;

-- Role API hanya boleh membaca. Tulis stok hanya lewat trigger/RPC.
revoke all on public.stock_movements from anon, authenticated;
revoke all on public.stock_levels from anon, authenticated;
grant select on public.stock_movements to authenticated;
grant select on public.stock_levels to authenticated;

create policy stock_movements_select_member on public.stock_movements
  for select to authenticated using (public.is_member(tenant_id));

create policy stock_levels_select_member on public.stock_levels
  for select to authenticated using (public.is_member(tenant_id));

create trigger stock_movements_created_by before insert on public.stock_movements
  for each row execute function public.set_created_by();

-- Terapkan movement ke stock_levels
create function public.apply_stock_movement() returns trigger
  language plpgsql
  security definer
  set search_path = public
  as $$
  begin
    insert into public.stock_levels (tenant_id, product_id, outlet_id, qty_base)
    values (new.tenant_id, new.product_id, new.outlet_id, new.qty_base)
    on conflict (tenant_id, product_id, outlet_id)
    do update set
      qty_base = public.stock_levels.qty_base + excluded.qty_base,
      updated_at = now();
    return new;
  end;
  $$;

revoke execute on function public.apply_stock_movement() from public, anon, authenticated;

create trigger stock_movements_apply
  after insert on public.stock_movements
  for each row execute function public.apply_stock_movement();

-- Append-only: koreksi lewat movement balik, bukan ubah/hapus
create function public.stock_movements_append_only() returns trigger
  language plpgsql
  set search_path = public
  as $$
  begin
    raise exception 'stock_movements bersifat append-only (koreksi lewat movement balik)'
      using errcode = 'P0001';
  end;
  $$;

revoke execute on function public.stock_movements_append_only() from public, anon, authenticated;

create trigger stock_movements_append_only
  before update or delete on public.stock_movements
  for each row execute function public.stock_movements_append_only();

-- View stok per outlet (aman untuk kasir: tanpa cost_price)
create view public.stock_by_outlet
  with (security_invoker = true)
  as
  select
    sl.tenant_id,
    sl.outlet_id,
    o.name as outlet_name,
    sl.product_id,
    p.name as product_name,
    p.sku,
    sl.qty_base,
    p.min_stock,
    (p.track_stock and p.min_stock > 0 and sl.qty_base < p.min_stock) as is_low
  from public.stock_levels sl
  join public.outlets o
    on o.tenant_id = sl.tenant_id and o.id = sl.outlet_id
  join public.products p
    on p.tenant_id = sl.tenant_id and p.id = sl.product_id;

revoke all on public.stock_by_outlet from anon;
grant select on public.stock_by_outlet to authenticated;
